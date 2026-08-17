#!/usr/bin/env python3
"""Deterministic hostile-input smoke gate for the native ZigMV listener."""
from __future__ import annotations

import argparse
import socket
import subprocess
import time


def exchange(port: int, payload: bytes) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(3)
        sock.recv(4096)
        sock.sendall(payload)
        try:
            return sock.recv(4096)
        except socket.timeout:
            return b""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=24610)
    args = parser.parse_args()
    broker = subprocess.Popen(
        [args.binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(args.port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(0.4)
        cases = [
            b"\x00\xff\x00\r\n",
            b"ZMV/999 UNKNOWN\r\n",
            b"ZMV/1 PUB live 1 topic 999999\r\n",
            b"ZMV/1 LINK AUTH\r\n",
            b"ZMV/1 AUTH\r\n",
            b"ZMV/1 SUB live "+b"a"*4096+b"\r\n",
        ]
        for case in cases:
            exchange(args.port, case)
            if broker.poll() is not None:
                raise RuntimeError(f"broker exited after hostile input: {case[:32]!r}")
        print("PROTOCOL_HOSTILE_INPUT_PASS")
        return 0
    finally:
        broker.terminate()
        try:
            broker.wait(timeout=3)
        except subprocess.TimeoutExpired:
            broker.kill()
            broker.wait(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
