#!/usr/bin/env python3
from __future__ import annotations

import argparse
import signal
import socket
import subprocess
import time

CRLF = b"\r\n"


class Framed:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buffer = bytearray()

    def fill(self) -> None:
        chunk = self.sock.recv(65536)
        if not chunk:
            raise RuntimeError("connection closed")
        self.buffer.extend(chunk)

    def line(self) -> bytes:
        while CRLF not in self.buffer:
            self.fill()
        index = self.buffer.index(CRLF)
        line = bytes(self.buffer[:index])
        del self.buffer[: index + 2]
        return line

    def message(self) -> tuple[bytes, bytes]:
        fields = self.line().split()
        if len(fields) != 4 or fields[0] != b"MSG":
            raise RuntimeError(f"unexpected frame {fields!r}")
        size = int(fields[3])
        while len(self.buffer) < size + 2:
            self.fill()
        payload = bytes(self.buffer[:size])
        del self.buffer[: size + 2]
        return fields[1], payload


def connect(port: int) -> Framed:
    for _ in range(100):
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=3)
            client = Framed(sock)
            if not client.line().startswith(b"INFO "):
                raise RuntimeError("missing INFO")
            sock.sendall(b'CONNECT {"verbose":true,"protocol":1}\r\n')
            if client.line() != b"+OK":
                raise RuntimeError("CONNECT failed")
            return client
        except OSError:
            time.sleep(0.02)
    raise RuntimeError("broker did not start")


def command(client: Framed, text: bytes) -> None:
    client.sock.sendall(text + CRLF)
    if client.line() != b"+OK":
        raise RuntimeError(f"command failed: {text!r}")


def publish(client: Framed, subject: bytes, payload: bytes) -> None:
    client.sock.sendall(b"PUB " + subject + b" " + str(len(payload)).encode() + CRLF + payload + CRLF)
    if client.line() != b"+OK":
        raise RuntimeError("publish was not acknowledged")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--port", type=int, default=4520)
    args = parser.parse_args()
    process = subprocess.Popen([args.binary, "--protocol", "nats", "--host", "127.0.0.1", "--port", str(args.port)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    clients: list[Framed] = []
    try:
        exact_one = connect(args.port)
        exact_two = connect(args.port)
        wildcard = connect(args.port)
        publisher = connect(args.port)
        clients = [exact_one, exact_two, wildcard, publisher]
        command(exact_one, b"SUB bench 1")
        command(exact_two, b"SUB bench 2")
        command(wildcard, b"SUB bench.> 3")

        publish(publisher, b"bench", b"one")
        assert exact_one.message() == (b"bench", b"one")
        assert exact_two.message() == (b"bench", b"one")
        wildcard.sock.settimeout(0.2)
        try:
            wildcard.message()
        except (socket.timeout, TimeoutError):
            pass
        else:
            raise RuntimeError("wildcard subscription received a non-matching exact subject")
        wildcard.sock.settimeout(3)

        command(exact_one, b"UNSUB 1")
        publish(publisher, b"bench", b"two")
        assert exact_two.message() == (b"bench", b"two")
        exact_one.sock.settimeout(0.2)
        try:
            exact_one.message()
        except (socket.timeout, TimeoutError):
            pass
        else:
            raise RuntimeError("unsubscribed exact subscription received a message")
        exact_one.sock.settimeout(3)

        publish(publisher, b"bench.room", b"wild")
        assert wildcard.message() == (b"bench.room", b"wild")
        exact_two.sock.close()
        exact_two = None  # type: ignore[assignment]
        time.sleep(0.1)
        publish(publisher, b"bench", b"three")
        print("NATS_INDEX_OK")
    finally:
        for client in clients:
            try:
                client.sock.close()
            except OSError:
                pass
        process.send_signal(signal.SIGTERM)
        process.wait(timeout=5)
        if process.returncode != 0:
            output = process.stderr.read() if process.stderr else ""
            raise RuntimeError(f"broker exited with {process.returncode}: {output}")


if __name__ == "__main__":
    main()
