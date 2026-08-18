#!/usr/bin/env python3
"""Exercise the broker-integrated ZMV LINK lifecycle."""
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
            raise RuntimeError("connection closed before expected response")
        data.extend(chunk)
        if len(data) > 1024 * 1024:
            raise RuntimeError("response exceeded test bound")
    return bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=44229)
    args = parser.parse_args()

    process = subprocess.Popen(
        [args.binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(args.port), "--auth-token", "edge-secret"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(0.2)
        subscriber = connect(args.port)
        link_peer = connect(args.port)
        try:
            read_until(subscriber, b"ZMV/1 READY")
            read_until(link_peer, b"ZMV/1 READY")
            subscriber.sendall(b"ZMV/1 AUTH edge-secret\r\n")
            read_until(subscriber, b"ZMV/1 OK AUTH")
            subscriber.sendall(b"ZMV/1 SUB live telemetry.>\r\n")
            read_until(subscriber, b"ZMV/1 OK SUB")

            link_peer.sendall(b"ZMV/1 LINK AUTH edge-a edge-secret telemetry.>\r\n")
            read_until(link_peer, b"ZMV/1 OK LINK AUTH edge-a")
            link_peer.sendall(b"ZMV/1 LINK 1 live telemetry.site 5\r\nhello\r\n")
            ack = read_until(link_peer, b"ZMV/1 LINK ACK 1 OK")
            if b"ZMV/1 LINK ACK 1 OK" not in ack:
                raise RuntimeError(f"missing link acknowledgement: {ack!r}")
            delivery = read_until(subscriber, b"hello\r\n")
            if b"ZMV/1 MSG live 0 telemetry.site 5\r\nhello\r\n" not in delivery:
                raise RuntimeError(f"unexpected subscriber delivery: {delivery!r}")

            link_peer.sendall(b"ZMV/1 LINK 1 live telemetry.site 5\r\nhello\r\n")
            duplicate = read_until(link_peer, b"ZMV/1 LINK ACK 1 DUP")
            if b"ZMV/1 LINK ACK 1 DUP" not in duplicate:
                raise RuntimeError(f"missing duplicate acknowledgement: {duplicate!r}")
            print("EDGE_LINK_INTEGRATION_PASS")
            return 0
        finally:
            subscriber.close()
            link_peer.close()
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        if process.returncode not in (0, -15):
            stderr = process.stderr.read().decode("utf-8", "replace") if process.stderr else ""
            raise RuntimeError(f"broker exited with {process.returncode}: {stderr}")


if __name__ == "__main__":
    raise SystemExit(main())
