#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import socket
import subprocess
import tempfile
import time


def recv_until(sock: socket.socket, marker: bytes) -> None:
    data = bytearray()
    while marker not in data:
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError("connection closed")
        data.extend(chunk)


def connect(port: int) -> socket.socket:
    for _ in range(100):
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=3)
        except OSError:
            time.sleep(0.02)
    raise RuntimeError("broker did not start")


def run_case(binary: str, port: int, messages: int, payload: bytes, stream: bool) -> float:
    with tempfile.TemporaryDirectory() as directory:
        stream_path = os.path.join(directory, "events.log")
        command = [binary, "--host", "127.0.0.1", "--port", str(port)]
        if stream:
            command += ["--stream", stream_path]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        publisher = None
        try:
            publisher = connect(port)
            recv_until(publisher, b"\r\n")
            frame = b"PUB bench " + payload + b"\r\n"
            start = time.perf_counter()
            for _ in range(messages):
                publisher.sendall(frame)
                recv_until(publisher, b"+OK PUB\r\n")
            return messages / (time.perf_counter() - start)
        finally:
            if publisher is not None:
                publisher.close()
            process.terminate()
            process.wait(timeout=5)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--messages", type=int, default=1000)
    parser.add_argument("--payload-size", type=int, default=128)
    parser.add_argument("--port", type=int, default=4610)
    args = parser.parse_args()
    payload = b"x" * args.payload_size
    without_stream = run_case(args.binary, args.port, args.messages, payload, False)
    with_stream = run_case(args.binary, args.port + 1, args.messages, payload, True)
    print(f"messages={args.messages}")
    print(f"payload_bytes={args.payload_size}")
    print(f"without_stream_publish_ack_msg_per_sec={without_stream:.1f}")
    print(f"with_stream_publish_ack_msg_per_sec={with_stream:.1f}")
    print(f"stream_relative_rate_percent={with_stream / without_stream * 100:.1f}")


if __name__ == "__main__":
    main()
