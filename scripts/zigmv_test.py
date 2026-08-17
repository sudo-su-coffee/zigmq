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


def exact(reader, count: int) -> bytes:
    value = reader.read(count)
    if len(value) != count:
        raise RuntimeError(f"short payload: expected {count}, got {len(value)}")
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

        durable, durable_reader = connect("127.0.0.1", port)
        state, state_reader = connect("127.0.0.1", port)
        sockets.extend([(durable, durable_reader), (state, state_reader)])
        durable.sendall(b"ZMV/1 SUB durable jobs\r\n")
        state.sendall(b"ZMV/1 SUB state device.status\r\n")
        if not line(durable_reader).startswith(b"ZMV/1 OK SUB"):
            raise RuntimeError("durable subscription failed")
        if not line(state_reader).startswith(b"ZMV/1 OK SUB"):
            raise RuntimeError("state subscription failed")

        publisher.sendall(b"ZMV/1 PUB durable 2 jobs 5\r\nhello\r\n")
        if line(publisher_reader) != b"ZMV/1 OK PUB 2\r\n":
            raise RuntimeError("durable publish acknowledgement failed")
        durable_reader_socket = durable
        durable_reader_socket.settimeout(2)
        durable_message = line(durable_reader)
        if not durable_message.startswith(b"ZMV/1 MSG durable "):
            raise RuntimeError(f"durable delivery failed: {durable_message!r}")
        durable_id = durable_message.split()[3]
        if exact(durable_reader, 7) != b"hello\r\n":
            raise RuntimeError("durable payload framing failed")
        durable.sendall(b"ZMV/1 ACK " + durable_id + b"\r\n")
        if not line(durable_reader).startswith(b"ZMV/1 OK ACK"):
            raise RuntimeError("durable acknowledgement failed")

        publisher.sendall(b"ZMV/1 PUB durable 4 jobs 5\r\nhello\r\n")
        if line(publisher_reader) != b"ZMV/1 OK PUB 4\r\n":
            raise RuntimeError("retry publish acknowledgement failed")
        first_retry = line(durable_reader)
        if not first_retry.startswith(b"ZMV/1 MSG durable "):
            raise RuntimeError(f"initial retry delivery failed: {first_retry!r}")
        retry_id = first_retry.split()[3]
        if exact(durable_reader, 7) != b"hello\r\n":
            raise RuntimeError("initial retry payload framing failed")
        durable.settimeout(3)
        second_retry = line(durable_reader)
        if not second_retry.startswith(b"ZMV/1 MSG durable ") or second_retry.split()[3] != retry_id:
            raise RuntimeError(f"durable redelivery failed: {second_retry!r}")
        if exact(durable_reader, 7) != b"hello\r\n":
            raise RuntimeError("redelivery payload framing failed")
        durable.sendall(b"ZMV/1 ACK " + retry_id + b"\r\n")
        if not line(durable_reader).startswith(b"ZMV/1 OK ACK"):
            raise RuntimeError("redelivery acknowledgement failed")

        publisher.sendall(b"ZMV/1 PUB state 3 device.status 4\r\nokay\r\n")
        if line(publisher_reader) != b"ZMV/1 OK PUB 3\r\n":
            raise RuntimeError("state publish acknowledgement failed")
        state.settimeout(2)
        if not line(state_reader).startswith(b"ZMV/1 MSG state"):
            raise RuntimeError("state delivery failed")

        publisher.sendall(b"ZMV/1 STATS\r\n")
        stats = line(publisher_reader).decode("ascii").strip()
        if not stats.startswith("ZMV/1 STATS "):
            raise RuntimeError(f"stats response failed: {stats!r}")
        fields = dict(item.split("=", 1) for item in stats.split()[2:])
        for name in ("clients", "subscriptions", "pending", "published", "delivered", "redelivered", "acknowledged", "expired"):
            if name not in fields or not fields[name].isdigit():
                raise RuntimeError(f"invalid stats field {name}: {stats!r}")
        if int(fields["redelivered"]) < 1 or int(fields["acknowledged"]) < 2:
            raise RuntimeError(f"retry/ack stats were not recorded: {stats!r}")
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
