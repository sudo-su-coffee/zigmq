#!/usr/bin/env python3
import argparse
import signal
import socket
import subprocess
import time


def recv_until(sock: socket.socket, marker: bytes) -> bytes:
    data = b""
    while marker not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError(f"connection closed before {marker!r}: {data!r}")
        data += chunk
    return data


def connect(port: int) -> socket.socket:
    for _ in range(40):
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=2)
        except OSError:
            time.sleep(0.05)
    raise RuntimeError(f"server did not open port {port}")


def start_server(binary: str, port: int, *extra: str) -> subprocess.Popen:
    process = subprocess.Popen(
        [binary, "--host", "127.0.0.1", "--port", str(port), *extra],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return process


def stop_server(process: subprocess.Popen) -> None:
    process.send_signal(signal.SIGTERM)
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)
    if process.returncode != 0:
        output = process.stdout.read() if process.stdout else ""
        raise RuntimeError(f"server did not shut down cleanly: {process.returncode}\n{output}")


def test_custom(binary: str, port: int) -> None:
    process = start_server(binary, port)
    subscriber = publisher = None
    try:
        subscriber = connect(port)
        publisher = connect(port)
        assert b"+OK zigmq ready\r\n" in recv_until(subscriber, b"\r\n")
        assert b"+OK zigmq ready\r\n" in recv_until(publisher, b"\r\n")

        subscriber.sendall(b"SUB sensors.*\r\n")
        assert b"+OK SUB\r\n" in recv_until(subscriber, b"\r\n")
        publisher.sendall(b"PUB sensors.room1 21.5 C\r\n")
        assert b"+OK PUB\r\n" in recv_until(publisher, b"\r\n")
        delivered = recv_until(subscriber, b"\r\n21.5 C\r\n")
        assert b"MSG sensors.room1 6\r\n21.5 C\r\n" in delivered

        publisher.sendall(b"PING\r\n")
        assert b"PONG\r\n" in recv_until(publisher, b"\r\n")
        subscriber.sendall(b"UNSUB sensors.*\r\n")
        assert b"+OK UNSUB\r\n" in recv_until(subscriber, b"\r\n")
    finally:
        if subscriber:
            subscriber.close()
        if publisher:
            publisher.close()
        stop_server(process)


def test_auth(binary: str, port: int) -> None:
    process = start_server(binary, port, "--auth-token", "edge-secret")
    client = None
    try:
        client = connect(port)
        assert b"auth=required" in recv_until(client, b"\r\n")
        client.sendall(b"PING\r\n")
        assert b"authentication required" in recv_until(client, b"\r\n")
        client.sendall(b"AUTH edge-secret\r\n")
        assert b"+OK AUTH\r\n" in recv_until(client, b"\r\n")
        client.sendall(b"PING\r\n")
        assert b"PONG\r\n" in recv_until(client, b"\r\n")
    finally:
        if client:
            client.close()
        stop_server(process)


def test_nats(binary: str, port: int) -> None:
    process = start_server(binary, port, "--protocol", "nats")
    subscriber = publisher = None
    try:
        subscriber = connect(port)
        publisher = connect(port)
        assert b"INFO " in recv_until(subscriber, b"\r\n")
        assert b"INFO " in recv_until(publisher, b"\r\n")
        subscriber.sendall(b"CONNECT {\"verbose\":true}\r\n")
        assert b"+OK\r\n" in recv_until(subscriber, b"\r\n")
        subscriber.sendall(b"SUB sensors.* 1\r\n")
        assert b"+OK\r\n" in recv_until(subscriber, b"\r\n")
        publisher.sendall(b"CONNECT {\"verbose\":true}\r\n")
        assert b"+OK\r\n" in recv_until(publisher, b"\r\n")
        publisher.sendall(b"PUB sensors.room 5\r\nhello\r\n")
        assert b"+OK\r\n" in recv_until(publisher, b"\r\n")
        assert b"MSG sensors.room 1 5\r\nhello\r\n" in recv_until(subscriber, b"\r\nhello\r\n")
        publisher.sendall(b"PING\r\n")
        assert b"PONG\r\n" in recv_until(publisher, b"\r\n")
    finally:
        if subscriber:
            subscriber.close()
        if publisher:
            publisher.close()
        stop_server(process)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    args = parser.parse_args()
    test_custom(args.binary, 4422)
    test_auth(args.binary, 4423)
    test_nats(args.binary, 4424)
    print("E2E_OK")


if __name__ == "__main__":
    main()
