#!/usr/bin/env python3
"""Bounded fault matrix for local ZigMV reliability evidence."""
from __future__ import annotations

import argparse
import socket
import struct
import subprocess
import time


def connect(port: int) -> tuple[socket.socket, object]:
    sock = socket.create_connection(("127.0.0.1", port), timeout=2)
    sock.settimeout(2)
    reader = sock.makefile("rb", buffering=64 * 1024)
    if not reader.readline().startswith(b"ZMV/1 READY"):
        raise RuntimeError("broker did not send READY")
    return sock, reader


def wait_ready(binary: str, port: int) -> subprocess.Popen[bytes]:
    process = subprocess.Popen([binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    deadline = time.time() + 6
    while time.time() < deadline:
        try:
            sock, reader = connect(port)
            reader.close()
            sock.close()
            return process
        except OSError:
            time.sleep(0.05)
    process.kill()
    process.wait()
    raise RuntimeError("broker did not become ready")


def broker_alive(process: subprocess.Popen[bytes]) -> bool:
    return process.poll() is None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=24660)
    args = parser.parse_args()
    cases: list[str] = []

    process = wait_ready(args.binary, args.port)
    try:
        sub, sub_reader = connect(args.port)
        sub.sendall(b"ZMV/1 SUB live fault.matrix\r\n")
        if not sub_reader.readline().startswith(b"ZMV/1 OK SUB"):
            raise RuntimeError("subscription setup failed")
        pub, pub_reader = connect(args.port)
        pub.sendall(b"ZMV/1 PUB live 1 fault.matrix 5\r\nhello\r\n")
        if not pub_reader.readline().startswith(b"ZMV/1 OK PUB"):
            raise RuntimeError("publish setup failed")
        sub.close()
        sub_reader.close()
        pub.close()
        pub_reader.close()
        if not broker_alive(process):
            raise RuntimeError("broker exited after consumer disconnect")
        cases.append("disconnect")

        reset, reset_reader = connect(args.port)
        reset.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        reset.close()
        reset_reader.close()
        if not broker_alive(process):
            raise RuntimeError("broker exited after TCP reset")
        cases.append("tcp_reset")

        slow, slow_reader = connect(args.port)
        slow.sendall(b"ZMV/1 SUB live fault.slow\r\n")
        if not slow_reader.readline().startswith(b"ZMV/1 OK SUB"):
            raise RuntimeError("slow subscription setup failed")
        writer, writer_reader = connect(args.port)
        writer.settimeout(0.1)
        payload = b"x" * 4096
        backpressure = False
        for message_id in range(1, 4097):
            frame = f"ZMV/1 PUB live {message_id} fault.slow {len(payload)}\r\n".encode() + payload + b"\r\n"
            try:
                writer.sendall(frame)
            except (OSError, socket.timeout, TimeoutError):
                backpressure = True
                break
        if not broker_alive(process):
            raise RuntimeError("broker exited under slow-consumer pressure")
        cases.append("slow_consumer_backpressure" if backpressure else "slow_consumer_bounded")
        slow.close()
        slow_reader.close()
        writer.close()
        writer_reader.close()
        print("FAULT_MATRIX_PASS cases=" + ",".join(cases))
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
