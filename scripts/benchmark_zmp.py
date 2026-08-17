#!/usr/bin/env python3
"""Benchmark the initial fast ZMP path.

Start the broker separately, for example:
    zig build run -- --protocol zmp --port 4222
"""
import argparse
import socket
import threading
import time


def connect(host: str, port: int) -> tuple[socket.socket, object]:
    sock = socket.create_connection((host, port), timeout=10)
    sock.settimeout(10)
    reader = sock.makefile("rb", buffering=64 * 1024)
    ready = reader.readline()
    if not ready.startswith(b"ZMP/1 READY"):
        reader.close()
        sock.close()
        raise RuntimeError(f"unexpected handshake: {ready!r}")
    return sock, reader


def read_line(reader: object) -> bytes:
    line = reader.readline()
    if not line:
        raise RuntimeError("connection closed while reading line")
    return line


def read_zmp_message(reader: object) -> bytes:
    header = read_line(reader).decode("ascii").strip()
    parts = header.split(" ")
    if len(parts) != 6 or parts[0] != "ZMP/1" or parts[1] != "MSG":
        raise RuntimeError(f"unexpected delivery: {header!r}")
    length = int(parts[5])
    payload = bytearray()
    while len(payload) < length + 2:
        chunk = reader.read(length + 2 - len(payload))
        if not chunk:
            raise RuntimeError("connection closed while reading payload")
        payload.extend(chunk)
    if payload[-2:] != b"\r\n":
        raise RuntimeError("invalid payload terminator")
    return bytes(payload[:-2])


def subscribe_worker(host: str, port: int, subject: str, expected: int, result: list, ready: list, index: int) -> None:
    sock, reader = connect(host, port)
    try:
        sock.sendall(f"ZMP/1 SUB live {subject}\r\n".encode())
        if not read_line(reader).startswith(b"ZMP/1 OK SUB"):
            raise RuntimeError("subscription failed")
        ready[index] = True
        count = 0
        while count < expected:
            read_zmp_message(reader)
            count += 1
        result[index] = count
    finally:
        reader.close()
        sock.close()


def benchmark(host: str, port: int, messages: int, subscribers: int, payload_size: int, pipeline: int, acknowledge: bool) -> None:
    subject = "bench.zmp"
    payload = b"x" * payload_size
    received = [0] * subscribers
    ready = [False] * subscribers
    workers = [threading.Thread(target=subscribe_worker, args=(host, port, subject, messages, received, ready, i)) for i in range(subscribers)]
    for worker in workers:
        worker.start()
    deadline = time.monotonic() + 10
    while not all(ready):
        if time.monotonic() >= deadline:
            raise RuntimeError(f"subscription setup incomplete: {ready}")
        time.sleep(0.01)

    publisher, publisher_reader = connect(host, port)
    try:
        publisher.sendall(f"ZMP/1 SUB live bench.ack\r\n".encode())
        read_line(publisher_reader)
        start = time.perf_counter()
        sent = 0
        while sent < messages:
            batch = min(pipeline, messages - sent)
            for message_id in range(sent, sent + batch):
                message_id = str(message_id) if acknowledge else "-"
                header = f"ZMP/1 PUB live {message_id} {subject} {len(payload)}\r\n".encode()
                publisher.sendall(header + payload + b"\r\n")
            if acknowledge:
                for _ in range(batch):
                    response = read_line(publisher_reader)
                    if not response.startswith(b"ZMP/1 OK PUB"):
                        raise RuntimeError(f"publish failed: {response!r}")
            sent += batch
        elapsed = time.perf_counter() - start
    finally:
        publisher_reader.close()
        publisher.close()

    for worker in workers:
        worker.join(timeout=20)
    if any(count != messages for count in received):
        raise RuntimeError(f"fan-out incomplete: {received}")

    publish_rate = messages / elapsed if elapsed else 0.0
    delivery_rate = messages * subscribers / elapsed if elapsed else 0.0
    ack_mode = "ack" if acknowledge else "no-ack"
    print(f"protocol=zmp profile=live messages={messages} subscribers={subscribers} payload_bytes={payload_size} pipeline={pipeline} publish_mode={ack_mode}")
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
    parser.add_argument("--pipeline", type=int, default=1, help="Publishes sent before reading acknowledgements; keep at or below the broker queue limit")
    parser.add_argument("--ack-publishes", action="store_true", help="Request a ZMP publish acknowledgement for every message")
    args = parser.parse_args()
    if args.pipeline < 1:
        parser.error("--pipeline must be positive")
    benchmark(args.host, args.port, args.messages, args.subscribers, args.payload_size, args.pipeline, args.ack_publishes)
