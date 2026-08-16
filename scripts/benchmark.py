#!/usr/bin/env python3
import argparse
import selectors
import socket
import subprocess
import time


def recv_until(sock: socket.socket, marker: bytes) -> bytes:
    data = b""
    while marker not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("connection closed")
        data += chunk
    return data


def connect(port: int) -> socket.socket:
    for _ in range(80):
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=3)
        except OSError:
            time.sleep(0.025)
    raise RuntimeError("server did not start")


def start_server(binary: str, port: int) -> subprocess.Popen:
    return subprocess.Popen(
        [binary, "--host", "127.0.0.1", "--port", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def stop_server(process: subprocess.Popen) -> None:
    process.terminate()
    process.wait(timeout=5)


def count_frames(sock: socket.socket, expected: bytes, count: int, timeout: float) -> int:
    received = 0
    buffer = b""
    deadline = time.monotonic() + timeout
    while received < count and time.monotonic() < deadline:
        remaining = max(0.01, deadline - time.monotonic())
        sock.settimeout(remaining)
        chunk = sock.recv(65536)
        if not chunk:
            break
        buffer += chunk
        found = buffer.count(expected)
        if found:
            received += found
            buffer = buffer[max(0, len(buffer) - len(expected) + 1) :]
    return received


def benchmark_publish_acks(binary: str, port: int, messages: int, payload: bytes) -> float:
    process = start_server(binary, port)
    publisher = None
    try:
        publisher = connect(port)
        recv_until(publisher, b"\r\n")
        command = b"PUB bench " + payload + b"\r\n"
        start = time.perf_counter()
        for _ in range(messages):
            publisher.sendall(command)
            recv_until(publisher, b"+OK PUB\r\n")
        elapsed = time.perf_counter() - start
        return messages / elapsed
    finally:
        if publisher:
            publisher.close()
        stop_server(process)


def benchmark_fanout(binary: str, port: int, messages: int, payload: bytes) -> float:
    process = start_server(binary, port)
    subscriber = publisher = None
    try:
        subscriber = connect(port)
        publisher = connect(port)
        recv_until(subscriber, b"\r\n")
        recv_until(publisher, b"\r\n")
        subscriber.sendall(b"SUB bench\r\n")
        recv_until(subscriber, b"+OK SUB\r\n")
        frame = b"MSG bench " + str(len(payload)).encode() + b"\r\n" + payload + b"\r\n"
        command = b"PUB bench " + payload + b"\r\n"
        start = time.perf_counter()
        for _ in range(messages):
            publisher.sendall(command)
            recv_until(publisher, b"+OK PUB\r\n")
            recv_until(subscriber, frame)
        elapsed = time.perf_counter() - start
        return messages / elapsed
    finally:
        if subscriber:
            subscriber.close()
        if publisher:
            publisher.close()
        stop_server(process)


def benchmark_clients(binary: str, port: int, clients: int) -> float:
    process = start_server(binary, port)
    sockets = []
    try:
        start = time.perf_counter()
        for _ in range(clients):
            sock = connect(port)
            recv_until(sock, b"\r\n")
            sockets.append(sock)
        elapsed = time.perf_counter() - start
        return clients / elapsed
    finally:
        for sock in sockets:
            sock.close()
        stop_server(process)


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark zigmq on the current machine")
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--messages", type=int, default=10000)
    parser.add_argument("--clients", type=int, default=100)
    args = parser.parse_args()
    payload = b"edge-payload"
    print(f"publish_ack_msg_per_sec={benchmark_publish_acks(args.binary, 4432, args.messages, payload):.1f}")
    print(f"fanout_msg_per_sec={benchmark_fanout(args.binary, 4433, min(args.messages, 5000), payload):.1f}")
    print(f"client_connects_per_sec={benchmark_clients(args.binary, 4434, args.clients):.1f}")


if __name__ == "__main__":
    main()
