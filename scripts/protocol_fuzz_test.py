#!/usr/bin/env python3
"""Seeded protocol mutation gate; this is deterministic robustness coverage, not a statistical fuzz claim."""
from __future__ import annotations

import argparse
import random
import socket
import subprocess
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=24650)
    parser.add_argument("--cases", type=int, default=250)
    args = parser.parse_args()
    broker = subprocess.Popen(
        [args.binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(args.port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(0.4)
        rng = random.Random(0x5A17)
        alphabet = b"ZMV/1 AUTH PUB SUB LINK STATS \\r\\n\\x00\\xff._->*0123456789"
        for index in range(args.cases):
            size = rng.randrange(0, 2048)
            if index % 5 == 0:
                payload = b"ZMV/1 PUB live 1 fuzz.topic 65535\\r\\n" + bytes(rng.randrange(256) for _ in range(min(size, 512)))
            else:
                payload = bytes(alphabet[rng.randrange(len(alphabet))] for _ in range(size))
            try:
                with socket.create_connection(("127.0.0.1", args.port), timeout=1) as sock:
                    sock.settimeout(1)
                    sock.recv(256)
                    sock.sendall(payload)
                    try:
                        sock.recv(4096)
                    except socket.timeout:
                        pass
            except OSError:
                pass
            if broker.poll() is not None:
                raise RuntimeError(f"broker exited at case {index}")
        print(f"PROTOCOL_FUZZ_SURVIVAL_PASS cases={args.cases}")
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
