#!/usr/bin/env python3
"""Smoke-test the native ZigMV/1 foundation."""
import argparse
import socket
import subprocess
import time


def connect(host: str, port: int):
    sock = socket.create_connection((host, port), timeout=5)
    reader = sock.makefile("rb", buffering=64 * 1024)
    ready = reader.readline()
    if not ready.startswith(b"ZMV/1 READY"):
        raise RuntimeError(f"unexpected handshake: {ready!r}")
    return sock, reader


def line(reader) -> bytes:
    value = reader.readline()
    if not value:
        raise RuntimeError("connection closed")
    return value


def main(binary: str, port: int) -> None:
    process = subprocess.Popen(
        [binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    sockets = []
    try:
        time.sleep(0.5)
        work_a, reader_a = connect("127.0.0.1", port)
        work_b, reader_b = connect("127.0.0.1", port)
        publisher, publisher_reader = connect("127.0.0.1", port)
        sockets.extend([(work_a, reader_a), (work_b, reader_b), (publisher, publisher_reader)])

        work_a.sendall(b"ZMV/1 SUB work jobs worker\r\n")
        work_b.sendall(b"ZMV/1 SUB work jobs worker\r\n")
        if not line(reader_a).startswith(b"ZMV/1 OK SUB"):
            raise RuntimeError("worker A subscription failed")
        if not line(reader_b).startswith(b"ZMV/1 OK SUB"):
            raise RuntimeError("worker B subscription failed")

        publisher.sendall(b"ZMV/1 PUB work 1 jobs 5\r\nhello\r\n")
        if line(publisher_reader) != b"ZMV/1 OK PUB 1\r\n":
            raise RuntimeError("work publish acknowledgement failed")
        deliveries = []
        for reader in (reader_a, reader_b):
            reader_socket = work_a if reader is reader_a else work_b
            reader_socket.settimeout(0.5)
            try:
                deliveries.append(line(reader))
            except (socket.timeout, TimeoutError):
                deliveries.append(None)
        actual = [item for item in deliveries if item is not None]
        if len(actual) != 1 or not actual[0].startswith(b"ZMV/1 MSG work"):
            raise RuntimeError(f"work delivery was not one-of-N: {deliveries!r}")

        live, live_reader = connect("127.0.0.1", port)
        sockets.append((live, live_reader))
        live.sendall(b"ZMV/1 SUB live telemetry\r\n")
        if not line(live_reader).startswith(b"ZMV/1 OK SUB"):
            raise RuntimeError("live subscription failed")
        publisher.sendall(b"ZMV/1 PUB live - telemetry 4\r\nping\r\n")
        live.settimeout(2)
        if not line(live_reader).startswith(b"ZMV/1 MSG live"):
            raise RuntimeError("live no-ack delivery failed")

        publisher.sendall(b"ZMV/1 PUB durable 2 jobs 5\r\nhello\r\n")
        if not line(publisher_reader).startswith(b"ZMV/1 ERR mode_not_implemented"):
            raise RuntimeError("durable profile was not rejected explicitly")
        print("zigmv smoke test passed")
    finally:
        for sock, reader in sockets:
            reader.close()
            sock.close()
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--port", type=int, default=4230)
    args = parser.parse_args()
    main(args.binary, args.port)
