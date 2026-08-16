#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import socket
import subprocess
import tempfile
import time


class Reader:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buffer = bytearray()

    def fill(self) -> None:
        chunk = self.sock.recv(4096)
        if not chunk:
            raise RuntimeError("connection closed")
        self.buffer.extend(chunk)

    def line(self) -> bytes:
        while b"\r\n" not in self.buffer:
            self.fill()
        index = self.buffer.index(b"\r\n")
        result = bytes(self.buffer[:index])
        del self.buffer[: index + 2]
        return result

    def exact(self, size: int) -> bytes:
        while len(self.buffer) < size:
            self.fill()
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result


def connect(port: int) -> Reader:
    for _ in range(100):
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=2)
            reader = Reader(sock)
            reader.line()
            return reader
        except OSError:
            time.sleep(0.02)
    raise RuntimeError("server did not start")


def command(reader: Reader, command_text: bytes, expected: bytes) -> None:
    reader.sock.sendall(command_text + b"\r\n")
    response = reader.line()
    if not response.startswith(expected):
        raise RuntimeError(f"expected {expected!r}, got {response!r}")


def read_message(reader: Reader) -> tuple[bytes, bytes]:
    header = reader.line().split()
    if header[0] != b"MSG":
        raise RuntimeError(f"unexpected frame {header!r}")
    size = int(header[-1])
    payload = reader.exact(size)
    if reader.exact(2) != b"\r\n":
        raise RuntimeError("bad frame terminator")
    return header[1], payload


def start(binary: str, port: int, stream_path: str) -> subprocess.Popen[bytes]:
    process = subprocess.Popen([binary, "--port", str(port), "--stream", stream_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    connect(port).sock.close()
    return process


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--port", type=int, default=4471)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="zigmq-stream-") as directory:
        stream_path = os.path.join(directory, "events.zmq")
        process = start(args.binary, args.port, stream_path)
        try:
            publisher = connect(args.port)
            for index in range(1, 6):
                command(publisher, f"PUB telemetry.room event-{index}".encode(), b"+OK PUB")
            replay = connect(args.port)
            command(replay, b"REPLAY 1 telemetry.>", b"+OK REPLAY")
            for index in range(1, 6):
                topic, payload = read_message(replay)
                assert topic == b"telemetry.room" and payload == f"event-{index}".encode()
            publisher.sock.close()
            replay.sock.close()
        finally:
            process.terminate()
            process.wait(timeout=5)

        process = start(args.binary, args.port, stream_path)
        try:
            publisher = connect(args.port)
            command(publisher, b"PUB telemetry.room event-6", b"+OK PUB")
            replay = connect(args.port)
            command(replay, b"REPLAY 6 telemetry.>", b"+OK REPLAY")
            topic, payload = read_message(replay)
            assert topic == b"telemetry.room" and payload == b"event-6"
            publisher.sock.close()
            replay.sock.close()
        finally:
            process.terminate()
            process.wait(timeout=5)
    print("STREAM_OK")


if __name__ == "__main__":
    main()
