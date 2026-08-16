#!/usr/bin/env python3
from __future__ import annotations

import argparse
import socket
import subprocess
import time


def encode_remaining_length(value: int) -> bytes:
    output = bytearray()
    while True:
        encoded = value % 128
        value //= 128
        if value:
            encoded |= 128
        output.append(encoded)
        if not value:
            return bytes(output)


def utf8(value: str) -> bytes:
    encoded = value.encode()
    return len(encoded).to_bytes(2, "big") + encoded


def packet(first: int, body: bytes = b"") -> bytes:
    return bytes([first]) + encode_remaining_length(len(body)) + body


def connect_packet(client_id: str, username: str | None = None, password: str | None = None) -> bytes:
    flags = 0x02
    body = bytearray(b"\x00\x04MQTT\x04")
    if username is not None:
        flags |= 0x80
    if password is not None:
        flags |= 0x40
    body.append(flags)
    body.extend((60).to_bytes(2, "big"))
    body.extend(utf8(client_id))
    if username is not None:
        body.extend(utf8(username))
    if password is not None:
        body.extend(utf8(password))
    return packet(0x10, bytes(body))


def read_exact(sock: socket.socket, length: int) -> bytes:
    data = bytearray()
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise RuntimeError("connection closed while reading MQTT packet")
        data.extend(chunk)
    return bytes(data)


def read_packet(sock: socket.socket) -> tuple[int, bytes]:
    first = read_exact(sock, 1)[0]
    multiplier = 1
    remaining = 0
    for _ in range(4):
        encoded = read_exact(sock, 1)[0]
        remaining += (encoded & 127) * multiplier
        if not encoded & 128:
            return first, read_exact(sock, remaining)
        multiplier *= 128
    raise RuntimeError("invalid remaining length")


def publish_packet(topic: str, payload: bytes, retain: bool = False) -> bytes:
    first = 0x31 if retain else 0x30
    return packet(first, utf8(topic) + payload)


def start(binary: str, port: int, *extra: str) -> subprocess.Popen[str]:
    process = subprocess.Popen(
        [binary, "--protocol", "mqtt", "--port", str(port), *extra],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    for _ in range(100):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.1).close()
            return process
        except OSError:
            time.sleep(0.02)
    stderr = process.stderr.read() if process.stderr else ""
    process.terminate()
    raise RuntimeError(f"MQTT broker did not start: {stderr}")


def stop(process: subprocess.Popen[str]) -> None:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def connect(port: int, client_id: str, username: str | None = None, password: str | None = None) -> socket.socket:
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    sock.sendall(connect_packet(client_id, username, password))
    first, body = read_packet(sock)
    assert first == 0x20 and body == b"\x00\x00", (first, body)
    return sock


def decode_publish(body: bytes) -> tuple[str, bytes]:
    length = int.from_bytes(body[:2], "big")
    topic = body[2 : 2 + length].decode()
    return topic, body[2 + length :]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--port", type=int, default=4632)
    args = parser.parse_args()

    process = start(args.binary, args.port)
    subscriber = publisher = None
    try:
        subscriber = connect(args.port, "ui-subscriber")
        subscriber.sendall(packet(0x82, b"\x00\x01" + utf8("sensors/+/temperature") + b"\x00"))
        first, body = read_packet(subscriber)
        assert first == 0x90 and body == b"\x00\x01\x00", (first, body)

        publisher = connect(args.port, "ui-publisher")
        publisher.sendall(publish_packet("sensors/room/temperature", b"21.5"))
        first, body = read_packet(subscriber)
        assert first == 0x30, hex(first)
        assert decode_publish(body) == ("sensors/room/temperature", b"21.5")

        subscriber.sendall(packet(0xC0))
        assert read_packet(subscriber) == (0xD0, b"")

        publisher.sendall(publish_packet("state/device-7", b"online", retain=True))
        time.sleep(0.1)
        subscriber.sendall(packet(0x82, b"\x00\x02" + utf8("state/#") + b"\x00"))
        assert read_packet(subscriber) == (0x90, b"\x00\x02\x00")
        first, body = read_packet(subscriber)
        assert first == 0x31
        assert decode_publish(body) == ("state/device-7", b"online")

        subscriber.sendall(packet(0xA2, b"\x00\x03" + utf8("state/#")))
        assert read_packet(subscriber) == (0xB0, b"\x00\x03")
        subscriber.settimeout(0.25)
        publisher.sendall(publish_packet("state/device-7", b"offline"))
        try:
            subscriber.recv(1)
            raise AssertionError("unsubscribed MQTT client received a message")
        except socket.timeout:
            pass
    finally:
        for sock in (subscriber, publisher):
            if sock is not None:
                sock.close()
        stop(process)

    auth_process = start(args.binary, args.port + 1, "--auth-token", "secret")
    good = bad = None
    try:
        good = connect(args.port + 1, "auth-good", "zigmq", "secret")
        bad = socket.create_connection(("127.0.0.1", args.port + 1), timeout=3)
        bad.sendall(connect_packet("auth-bad", "zigmq", "wrong"))
        assert read_packet(bad) == (0x20, b"\x00\x04")
    finally:
        for sock in (good, bad):
            if sock is not None:
                sock.close()
        stop(auth_process)

    print("MQTT_COMPAT_OK")


if __name__ == "__main__":
    main()
