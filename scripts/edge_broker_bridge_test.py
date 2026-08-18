#!/usr/bin/env python3
"""Verify publication transfer between two ZigMV broker instances."""
from __future__ import annotations

import argparse
import socket
import subprocess
import time


def connect(port: int) -> socket.socket:
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    sock.settimeout(5)
    return sock


def read_until(sock: socket.socket, marker: bytes) -> bytes:
    data = bytearray()
    while marker not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("connection closed before expected marker")
        data.extend(chunk)
        if len(data) > 1024 * 1024:
            raise RuntimeError("test response exceeded bound")
    return bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--a-port", type=int, default=44230)
    parser.add_argument("--b-port", type=int, default=44231)
    args = parser.parse_args()
    common = ["--protocol", "zigmv", "--host", "127.0.0.1", "--auth-token", "edge-secret"]
    broker_a = subprocess.Popen([args.binary, *common, "--port", str(args.a_port)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    broker_b = subprocess.Popen(
        [args.binary, *common, "--port", str(args.b_port), "--edge-link-host", "127.0.0.1", "--edge-link-port", str(args.a_port), "--edge-link-identity", "broker-b", "--edge-link-filter", "telemetry.>"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(0.5)
        subscriber = connect(args.b_port)
        publisher = connect(args.a_port)
        try:
            read_until(subscriber, b"ZMV/1 READY")
            subscriber.sendall(b"ZMV/1 AUTH edge-secret\r\n")
            read_until(subscriber, b"ZMV/1 OK AUTH")
            subscriber.sendall(b"ZMV/1 SUB live telemetry.>\r\n")
            read_until(subscriber, b"ZMV/1 OK SUB")
            read_until(publisher, b"ZMV/1 READY")
            publisher.sendall(b"ZMV/1 AUTH edge-secret\r\n")
            read_until(publisher, b"ZMV/1 OK AUTH")
            time.sleep(1.0)
            publisher.sendall(b"ZMV/1 PUB live 1 telemetry.site 5\r\nhello\r\n")
            read_until(publisher, b"ZMV/1 OK PUB 1")
            delivery = read_until(subscriber, b"hello\r\n")
            expected = b"ZMV/1 MSG live 0 telemetry.site 5\r\nhello\r\n"
            if expected not in delivery:
                raise RuntimeError(f"bridge delivery mismatch: {delivery!r}")
            print("EDGE_BROKER_BRIDGE_PASS")
            return 0
        finally:
            subscriber.close()
            publisher.close()
    finally:
        for process in (broker_b, broker_a):
            process.terminate()
        for process in (broker_b, broker_a):
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        failures = []
        for name, process in (("A", broker_a), ("B", broker_b)):
            stderr = process.stderr.read().decode("utf-8", "replace") if process.stderr else ""
            if process.returncode not in (0, -15):
                failures.append(f"broker {name} exited {process.returncode}: {stderr}")
            elif stderr:
                print(f"broker {name} stderr: {stderr}")
        if failures:
            raise RuntimeError("; ".join(failures))


if __name__ == "__main__":
    raise SystemExit(main())
