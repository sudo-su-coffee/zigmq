#!/usr/bin/env python3
"""Controlled NATS-protocol comparison for zigmq and nats-server."""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import time


CRLF = b"\r\n"


class FramedSocket:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buffer = bytearray()

    def sendall(self, data: bytes) -> None:
        self.sock.sendall(data)

    def _fill(self) -> None:
        chunk = self.sock.recv(65536)
        if not chunk:
            raise RuntimeError("connection closed before expected data")
        self.buffer.extend(chunk)

    def read_until(self, marker: bytes) -> bytes:
        while True:
            index = self.buffer.find(marker)
            if index >= 0:
                end = index + len(marker)
                result = bytes(self.buffer[:end])
                del self.buffer[:end]
                return result
            self._fill()

    def read_line(self) -> bytes:
        return self.read_until(CRLF)[:-2]

    def read_exact(self, size: int) -> bytes:
        while len(self.buffer) < size:
            self._fill()
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def close(self) -> None:
        self.sock.close()


def connect_retry(port: int) -> socket.socket:
    for _ in range(100):
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=5)
            sock.settimeout(5)
            return sock
        except OSError:
            time.sleep(0.02)
    raise RuntimeError(f"could not connect to port {port}")


def handshake(sock: FramedSocket, verbose: bool) -> None:
    info = sock.read_line()
    if not info.startswith(b"INFO "):
        raise RuntimeError(f"expected INFO, got {info!r}")
    value = b"true" if verbose else b"false"
    sock.sendall(b"CONNECT {\"verbose\":" + value + b",\"protocol\":1}" + CRLF)
    if verbose and sock.read_line() != b"+OK":
        raise RuntimeError("CONNECT was not accepted")


def subscribe(port: int, sid: int, verbose: bool) -> FramedSocket:
    sock = FramedSocket(connect_retry(port))
    handshake(sock, verbose)
    sock.sendall(f"SUB bench {sid}\r\n".encode())
    if verbose and sock.read_line() != b"+OK":
        raise RuntimeError("SUB was not accepted")
    if not verbose:
        time.sleep(0.002)
    return sock


def publisher(port: int, verbose: bool) -> FramedSocket:
    sock = FramedSocket(connect_retry(port))
    handshake(sock, verbose)
    return sock


def receive_msg(sock: FramedSocket, expected_payload: bytes) -> None:
    header = sock.read_line()
    parts = header.split()
    if len(parts) != 4 or parts[0] != b"MSG":
        raise RuntimeError(f"unexpected delivery header: {header!r}")
    size = int(parts[3])
    payload = sock.read_exact(size)
    terminator = sock.read_exact(2)
    if terminator != CRLF or payload != expected_payload or size != len(expected_payload):
        raise RuntimeError("delivery payload mismatch")


def start_process(command: list[str], port: int) -> subprocess.Popen[bytes]:
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        probe = connect_retry(port)
        probe.close()
    except Exception:
        process.terminate()
        process.wait(timeout=5)
        raise
    return process


def run_case(name: str, command: list[str], port: int, messages: int, subscribers: int, payload: bytes, verbose: bool) -> dict[str, object]:
    print(f"starting {name}", flush=True)
    process = start_process(command, port)
    sub_sockets: list[FramedSocket] = []
    pub = None
    try:
        sub_sockets = [subscribe(port, index + 1, verbose) for index in range(subscribers)]
        print(f"{name} subscribers_ready", flush=True)
        pub = publisher(port, verbose)
        print(f"{name} publisher_ready", flush=True)
        start = time.perf_counter_ns()
        latencies_us: list[float] = []
        frame = f"PUB bench {len(payload)}\r\n".encode() + payload + CRLF
        for message_index in range(messages):
            message_start = time.perf_counter_ns()
            pub.sendall(frame)
            if verbose and pub.read_line() != b"+OK":
                raise RuntimeError("PUB was not acknowledged")
            for sub in sub_sockets:
                receive_msg(sub, payload)
            latencies_us.append((time.perf_counter_ns() - message_start) / 1000.0)
            if message_index == 0 or message_index + 1 == messages:
                print(f"{name} progress={message_index + 1}/{messages}", flush=True)
        elapsed = (time.perf_counter_ns() - start) / 1_000_000_000
        latencies_us.sort()
        return {
            "broker": name,
            "messages": messages,
            "subscribers": subscribers,
            "payload_bytes": len(payload),
            "broker_messages_per_sec": messages / elapsed,
            "deliveries_per_sec": messages * subscribers / elapsed,
            "latency_us_p50": latencies_us[len(latencies_us) // 2],
            "latency_us_p99": latencies_us[min(len(latencies_us) - 1, int(len(latencies_us) * 0.99))],
        }
    finally:
        for sock in sub_sockets:
            sock.close()
        if pub is not None:
            pub.close()
        process.terminate()
        process.wait(timeout=5)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zigmq", default="zig-out/bin/zigmq")
    parser.add_argument("--nats", default=os.path.expanduser("~/.local/nats/nats-server"))
    parser.add_argument("--messages", type=int, default=1000)
    parser.add_argument("--subscribers", type=int, default=1)
    parser.add_argument("--payload-size", type=int, default=128)
    parser.add_argument("--zigmq-port", type=int, default=4464)
    parser.add_argument("--nats-port", type=int, default=4465)
    parser.add_argument("--verbose", action="store_true", help="wait for +OK acknowledgments; default matches normal NATS clients")
    args = parser.parse_args()
    if args.payload_size < 0:
        raise SystemExit("payload size must be non-negative")
    payload = bytes((index % 251 for index in range(args.payload_size)))
    results = [
        run_case(
            "zigmq-nats-mode",
            [args.zigmq, "--protocol", "nats", "--port", str(args.zigmq_port)],
            args.zigmq_port,
            args.messages,
            args.subscribers,
            payload,
            args.verbose,
        ),
        run_case(
            "nats-server",
            [args.nats, "-p", str(args.nats_port)],
            args.nats_port,
            args.messages,
            args.subscribers,
            payload,
            args.verbose,
        ),
    ]
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
