#!/usr/bin/env python3
"""Exercise durable stream writes under a bounded file-size limit.

This test deliberately uses RLIMIT_FSIZE rather than filling the host disk. It
verifies that a durable publish cannot be reported as successful after the
stream write reaches the configured limit. It does not claim to simulate every
filesystem-specific ENOSPC behavior.
"""
from __future__ import annotations

import argparse
import os
import resource
import socket
import subprocess
import tempfile
import time


def child_limits() -> None:
    limit = 4096
    resource.setrlimit(resource.RLIMIT_FSIZE, (limit, limit))


def connect(port: int) -> tuple[socket.socket, object]:
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    sock.settimeout(3)
    reader = sock.makefile("rb", buffering=64 * 1024)
    greeting = reader.readline()
    if not greeting.startswith(b"ZMV/1 READY"):
        raise RuntimeError(f"unexpected greeting: {greeting!r}")
    return sock, reader


def wait_ready(port: int) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            sock, reader = connect(port)
            reader.close()
            sock.close()
            return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("broker did not become ready")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=24646)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="zigmv-disk-full-") as directory:
        stream = os.path.join(directory, "stream.zmv")
        process = subprocess.Popen(
            [args.binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(args.port), "--stream", stream],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            preexec_fn=child_limits,
        )
        publisher = None
        publisher_reader = None
        try:
            wait_ready(args.port)
            publisher, publisher_reader = connect(args.port)
            payload = b"x" * 2048
            saw_rejection = False
            for message_id in range(1, 8):
                try:
                    publisher.sendall(f"ZMV/1 PUB durable {message_id} disk.full {len(payload)}\\r\\n".encode() + payload + b"\\r\\n")
                    response = publisher_reader.readline()
                except (OSError, socket.timeout, TimeoutError):
                    saw_rejection = True
                    break
                if not response.startswith(b"ZMV/1 OK PUB"):
                    saw_rejection = True
                    break
            if not saw_rejection:
                raise RuntimeError("all durable publishes were acknowledged despite the bounded stream limit")
            print("DISK_FULL_FAIL_CLOSED_PASS")
            return 0
        finally:
            if publisher_reader is not None:
                publisher_reader.close()
            if publisher is not None:
                publisher.close()
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
