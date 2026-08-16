#!/usr/bin/env python3
"""Benchmark the initial fast ZMP path.

Start the broker separately, for example:
    zig build run -- --protocol zmp --port 4222
"""
import argparse
import socket
import threading
import time


def connect(host: str, port: int) -> socket.socket:
    sock = socket.create_connection((host, port), timeout=10)
    sock.settimeout(10)
    ready = sock.recv(256)
    if not ready.startswith(b"ZMP/1 READY"):
        raise RuntimeError(f"unexpected handshake: {ready!r}")
    return sock


def read_line(sock: socket.socket) -> bytes:
    data = bytearray()
    while not data.endswith(b"\r\n"):
        chunk = sock.recv(1)
        if not chunk:
            raise RuntimeError("connection closed while reading line")
        data.extend(chunk)
    return bytes(data)


def read_zmp_message(sock: socket.socket) -> bytes:
    header = read_line(sock).decode("ascii").strip()
    parts = header.split(" ")
    if len(parts) != 6 or parts[0] != "ZMP/1" or parts[1] != "MSG":
        raise RuntimeError(f"unexpected delivery: {header!r}")
    length = int(parts[5])
    payload = bytearray()
    while len(payload) < length + 2:
        payload.extend(sock.recv(length + 2 - len(payload)))
    if payload[-2:] != b"\r\n":
        raise RuntimeError("invalid payload terminator")
    return bytes(payload[:-2])


def subscribe_worker(host: str, port: int, subject: str, expected: int, result: list, index: int) -> None:
    sock = connect(host, port)
    try:
        sock.sendall(f"ZMP/1 SUB fast {subject}\r\n".encode())
        if not read_line(sock).startswith(b"ZMP/1 OK SUB"):
            raise RuntimeError("subscription failed")
        count = 0
        while count < expected:
            read_zmp_message(sock)
            count += 1
        result[index] = count
    finally:
        sock.close()


def benchmark(host: str, port: int, messages: int, subscribers: int, payload_size: int) -> None:
    subject = "bench.zmp"
    payload = b"x" * payload_size
    received = [0] * subscribers
    workers = [threading.Thread(target=subscribe_worker, args=(host, port, subject, messages, received, i)) for i in range(subscribers)]
    for worker in workers:
        worker.start()
    time.sleep(0.1)

    publisher = connect(host, port)
    try:
        publisher.sendall(f"ZMP/1 SUB fast bench.ack\r\n".encode())
        read_line(publisher)
        start = time.perf_counter()
        for message_id in range(messages):
            header = f"ZMP/1 PUB fast {message_id} {subject} {len(payload)}\r\n".encode()
            publisher.sendall(header + payload + b"\r\n")
            response = read_line(publisher)
            if not response.startswith(b"ZMP/1 OK PUB"):
                raise RuntimeError(f"publish failed: {response!r}")
        elapsed = time.perf_counter() - start
    finally:
        publisher.close()

    for worker in workers:
        worker.join(timeout=20)
    if any(count != messages for count in received):
        raise RuntimeError(f"fan-out incomplete: {received}")

    publish_rate = messages / elapsed if elapsed else 0.0
    delivery_rate = messages * subscribers / elapsed if elapsed else 0.0
    print(f"protocol=zmp mode=fast messages={messages} subscribers={subscribers} payload_bytes={payload_size}")
    print(f"publish_ack_rate={publish_rate:.2f} msg/s")
    print(f"delivery_rate={delivery_rate:.2f} msg/s")
    print(f"elapsed_seconds={elapsed:.6f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4222)
    parser.add_argument("--messages", type=int, default=10000)
    parser.add_argument("--subscribers", type=int, default=1)
    parser.add_argument("--payload-size", type=int, default=128)
    args = parser.parse_args()
    benchmark(args.host, args.port, args.messages, args.subscribers, args.payload_size)
