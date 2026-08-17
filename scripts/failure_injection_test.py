#!/usr/bin/env python3
"""Deterministic restart and torn-journal failure-injection gate."""
from __future__ import annotations

import argparse
import os
import signal
import socket
import subprocess
import tempfile
import time


def wait_ready(port: int) -> None:
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5) as sock:
                sock.settimeout(1)
                greeting = sock.recv(256)
                if b"ZMV/1 READY" in greeting:
                    return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("broker did not become ready")


def start(binary: str, port: int, store: str) -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        [binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(port), "--session-store", store],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=24640)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="zigmv-failure-") as directory:
        store = os.path.join(directory, "sessions.zms")
        first = start(args.binary, args.port, store)
        try:
            wait_ready(args.port)
            with socket.create_connection(("127.0.0.1", args.port), timeout=2) as sock:
                sock.sendall(b"ZMV/1 AUTH disabled\r\n")
                sock.recv(256)
        finally:
            first.send_signal(signal.SIGKILL)
            first.wait(timeout=5)
        with open(store, "ab") as journal:
            journal.write(b"ZMV-TRUNCATED-TAIL")
            journal.flush()
            os.fsync(journal.fileno())
        second = start(args.binary, args.port, store)
        try:
            wait_ready(args.port)
            with socket.create_connection(("127.0.0.1", args.port), timeout=2) as sock:
                sock.settimeout(2)
                greeting = sock.recv(256)
                if b"ZMV/1 READY" not in greeting:
                    raise RuntimeError(f"unexpected post-recovery greeting: {greeting!r}")
                sock.sendall(b"ZMV/1 STATS\r\n")
                response = sock.recv(4096)
                if b"STATS" not in response and b"OK" not in response:
                    raise RuntimeError(f"unexpected post-recovery response: {response!r}")
            print("FAILURE_INJECTION_RECOVERY_PASS")
            return 0
        finally:
            second.terminate()
            try:
                second.wait(timeout=5)
            except subprocess.TimeoutExpired:
                second.kill()
                second.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
