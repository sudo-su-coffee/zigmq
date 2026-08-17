#!/usr/bin/env python3
"""Verify ZigMV durable session replay across client and broker restart."""
import argparse
import os
import socket
import subprocess
import tempfile
import time


def connect(port: int):
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    reader = sock.makefile("rb", buffering=64 * 1024)
    ready = reader.readline()
    if not ready.startswith(b"ZMV/1 READY"):
        raise RuntimeError(f"unexpected handshake: {ready!r}")
    return sock, reader


def line(reader):
    value = reader.readline()
    if not value:
        raise RuntimeError("connection closed")
    return value


def frame(reader):
    header = line(reader)
    parts = header.split()
    if len(parts) != 6 or parts[0] != b"ZMV/1" or parts[1] != b"MSG":
        raise RuntimeError(f"unexpected delivery header: {header!r}")
    size = int(parts[5])
    payload = reader.read(size + 2)
    if len(payload) != size + 2 or payload[-2:] != b"\r\n":
        raise RuntimeError(f"invalid delivery payload: {payload!r}")
    return parts, payload[:-2]


def start(binary: str, port: int, store: str):
    process = subprocess.Popen(
        [binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(port), "--session-store", store],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    time.sleep(0.5)
    return process


def stop(process):
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def main(binary: str, port: int):
    with tempfile.TemporaryDirectory(prefix="zigmv-session-") as directory:
        store = os.path.join(directory, "sessions.zms")
        process = start(binary, port, store)
        subscriber = publisher = None
        try:
            subscriber, subscriber_reader = connect(port)
            subscriber.sendall(b"ZMV/1 SESSION edge-gateway-7\r\n")
            if not line(subscriber_reader).startswith(b"ZMV/1 OK SESSION"):
                raise RuntimeError("session claim failed")
            subscriber.sendall(b"ZMV/1 SUB durable commands\r\n")
            if not line(subscriber_reader).startswith(b"ZMV/1 OK SUB"):
                raise RuntimeError("durable subscription failed")
            publisher, publisher_reader = connect(port)
            publisher.sendall(b"ZMV/1 PUB durable 77 commands 4\r\nOPEN\r\n")
            if line(publisher_reader) != b"ZMV/1 OK PUB 77\r\n":
                raise RuntimeError("durable publication failed")
            parts, payload = frame(subscriber_reader)
            delivery_id = parts[3]
            if delivery_id == b"0" or payload != b"OPEN":
                raise RuntimeError(f"invalid initial durable delivery: {parts!r} {payload!r}")
            subscriber.close()
            subscriber = None
            publisher.close()
            publisher = None
            stop(process)
            process = start(binary, port, store)
            subscriber, subscriber_reader = connect(port)
            subscriber.sendall(b"ZMV/1 SESSION edge-gateway-7\r\n")
            if not line(subscriber_reader).startswith(b"ZMV/1 OK SESSION"):
                raise RuntimeError("session rebind failed")
            parts, payload = frame(subscriber_reader)
            if parts[3] != delivery_id or payload != b"OPEN":
                raise RuntimeError(f"replayed delivery mismatch: {parts!r} {payload!r}")
            subscriber.sendall(b"ZMV/1 ACK " + parts[3] + b"\r\n")
            if not line(subscriber_reader).startswith(b"ZMV/1 OK ACK"):
                raise RuntimeError("replayed delivery ACK failed")
            print("persistent session recovery test passed")
        finally:
            if subscriber is not None:
                subscriber.close()
            if publisher is not None:
                publisher.close()
            stop(process)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=4231)
    args = parser.parse_args()
    main(args.binary, args.port)
