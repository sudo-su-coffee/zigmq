#!/usr/bin/env python3
import argparse
import socket
import subprocess
import time


def recv_until(sock: socket.socket, marker: bytes) -> bytes:
    data = b""
    while marker not in data:
        chunk = sock.recv(65536)
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--subscribers", type=int, default=10)
    parser.add_argument("--messages", type=int, default=1000)
    parser.add_argument("--port", type=int, default=4452)
    args = parser.parse_args()

    process = subprocess.Popen(
        [args.binary, "--port", str(args.port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subscribers = []
    publisher = None
    try:
        for _ in range(args.subscribers):
            subscriber = connect(args.port)
            recv_until(subscriber, b"\r\n")
            subscriber.sendall(b"SUB bench\r\n")
            recv_until(subscriber, b"+OK SUB\r\n")
            subscribers.append(subscriber)
        publisher = connect(args.port)
        recv_until(publisher, b"\r\n")
        payload = b"payload"
        command = b"PUB bench " + payload + b"\r\n"
        frame = b"MSG bench 7\r\npayload\r\n"
        start = time.perf_counter()
        for _ in range(args.messages):
            publisher.sendall(command)
            recv_until(publisher, b"+OK PUB\r\n")
            for subscriber in subscribers:
                recv_until(subscriber, frame)
        elapsed = time.perf_counter() - start
        total_deliveries = args.messages * args.subscribers
        print(f"subscribers={args.subscribers}")
        print(f"messages={args.messages}")
        print(f"broker_messages_per_sec={args.messages / elapsed:.1f}")
        print(f"deliveries_per_sec={total_deliveries / elapsed:.1f}")
    finally:
        for subscriber in subscribers:
            subscriber.close()
        if publisher:
            publisher.close()
        process.terminate()
        process.wait(timeout=5)


if __name__ == "__main__":
    main()
