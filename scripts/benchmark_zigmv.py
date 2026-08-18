#!/usr/bin/env python3
"""Sustained native ZigMV/1 benchmark with target-rate and integrity metrics."""
from __future__ import annotations

import argparse
import socket
import threading
import time


class Consumer:
    def __init__(self, sock: socket.socket, reader: object, expected: int | None) -> None:
        self.sock = sock
        self.reader = reader
        self.expected = expected
        self.delivered = 0
        self.gaps = 0
        self.duplicates = 0
        self.invalid = 0
        self.last_id = -1
        self.error: Exception | None = None

    def read_line(self) -> bytes:
        line = self.reader.readline()
        if not line:
            raise RuntimeError("connection closed while reading line")
        return line

    def run(self, stop: threading.Event) -> None:
        try:
            while not stop.is_set() and (self.expected is None or self.delivered < self.expected):
                header = self.read_line().decode("ascii").strip()
                parts = header.split(" ")
                if len(parts) != 6 or parts[0] != "ZMV/1" or parts[1] != "MSG":
                    self.invalid += 1
                    raise RuntimeError(f"unexpected delivery: {header!r}")
                message_id = int(parts[3])
                length = int(parts[5])
                payload = self.reader.read(length + 2)
                if len(payload) != length + 2 or payload[-2:] != b"\r\n":
                    self.invalid += 1
                    raise RuntimeError("invalid payload framing")
                if message_id == 0:
                    message_id = self.delivered
                if message_id <= self.last_id:
                    self.duplicates += 1
                elif message_id > self.last_id + 1 and self.last_id >= 0:
                    self.gaps += message_id - self.last_id - 1
                self.last_id = message_id
                self.delivered += 1
        except (OSError, TimeoutError, RuntimeError, ValueError) as error:
            if not stop.is_set():
                self.error = error


def connect(host: str, port: int) -> tuple[socket.socket, object]:
    sock = socket.create_connection((host, port), timeout=10)
    sock.settimeout(10)
    reader = sock.makefile("rb", buffering=256 * 1024)
    ready = reader.readline()
    if not ready.startswith(b"ZMV/1 READY"):
        reader.close()
        sock.close()
        raise RuntimeError(f"unexpected handshake: {ready!r}")
    return sock, reader


def run_benchmark(args: argparse.Namespace) -> int:
    subject = "bench.zigmv"
    payload = b"x" * args.payload_size
    subscriber, subscriber_reader = connect(args.host, args.port)
    subscriber.sendall(f"ZMV/1 SUB live {subject}\r\n".encode())
    if not subscriber_reader.readline().startswith(b"ZMV/1 OK SUB"):
        raise RuntimeError("subscription failed")

    expected = args.messages if args.messages > 0 else None
    consumer = Consumer(subscriber, subscriber_reader, expected)
    stop = threading.Event()
    consumer_thread = threading.Thread(target=consumer.run, args=(stop,), daemon=True)
    consumer_thread.start()

    publisher, publisher_reader = connect(args.host, args.port)
    publisher.sendall(b"ZMV/1 STATS\r\n")
    initial_stats_line = publisher_reader.readline().decode("ascii").strip()
    if not initial_stats_line.startswith("ZMV/1 STATS "):
        raise RuntimeError(f"initial benchmark synchronization failed: {initial_stats_line!r}")
    initial_stats = dict(item.split("=", 1) for item in initial_stats_line.split()[2:])
    baseline_published = int(initial_stats.get("published", "0"))
    offered = 0
    accepted = 0
    broker_accepted = 0
    backpressure_events = 0
    publisher_bye_sent = False
    start = time.perf_counter()
    deadline = start + args.duration if args.duration > 0 else None
    next_target = start
    try:
        while (args.messages <= 0 or offered < args.messages) and (deadline is None or time.perf_counter() < deadline):
            if args.target_mps > 0:
                next_target += 1.0 / args.target_mps
                delay = next_target - time.perf_counter()
                if delay > 0:
                    time.sleep(delay)
            message_id = str(offered) if args.ack_publishes else "-"
            frame = f"ZMV/1 PUB live {message_id} {subject} {len(payload)}\r\n".encode() + payload + b"\r\n"
            try:
                publisher.sendall(frame)
                offered += 1
                if args.ack_publishes:
                    response = publisher_reader.readline()
                    if not response.startswith(b"ZMV/1 OK PUB"):
                        raise RuntimeError(f"publish acknowledgement failed: {response!r}")
                accepted += 1
                if args.ack_publishes:
                    broker_accepted += 1
            except (socket.timeout, TimeoutError):
                backpressure_events += 1
                time.sleep(0.001)
            except OSError:
                backpressure_events += 1
                break
        if not args.ack_publishes:
            publisher.sendall(b"ZMV/1 STATS\r\n")
            stats_line = publisher_reader.readline().decode("ascii").strip()
            if not stats_line.startswith("ZMV/1 STATS "):
                raise RuntimeError(f"benchmark synchronization failed: {stats_line!r}")
            stats = dict(item.split("=", 1) for item in stats_line.split()[2:])
            broker_accepted = int(stats.get("published", "0")) - baseline_published
            if broker_accepted < accepted:
                raise RuntimeError(f"broker accepted fewer messages than socket writer: {broker_accepted} < {accepted}")
    finally:
        send_end = time.perf_counter()
        try:
            publisher.sendall(b"ZMV/1 BYE\r\n")
            publisher_bye_sent = True
        except (OSError, socket.timeout, TimeoutError):
            backpressure_events += 1
        try:
            publisher.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        publisher_reader.close()
        publisher.close()

    drain_deadline = time.perf_counter() + args.drain_timeout
    while consumer.delivered < broker_accepted and time.perf_counter() < drain_deadline and consumer.error is None:
        time.sleep(0.01)
    stop.set()
    try:
        subscriber.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    subscriber_reader.close()
    subscriber.close()
    consumer_thread.join(timeout=2)

    elapsed = max(send_end - start, 1e-9)
    drain_elapsed = max(time.perf_counter() - start, elapsed)
    lost = max(0, broker_accepted - consumer.delivered)
    integrity_ok = consumer.invalid == 0 and consumer.duplicates == 0 and consumer.gaps == 0
    if lost == 0 and integrity_ok:
        status = "PASS"
    elif args.allow_live_loss and not args.ack_publishes and integrity_ok:
        status = "PASS_LOSSY_LIVE"
    else:
        status = "FAIL"
    print(f"status={status}")
    print(f"protocol=zigmv profile=live payload_bytes={args.payload_size} target_mps={args.target_mps:.2f}")
    print(f"duration_seconds={elapsed:.6f} drain_seconds={drain_elapsed:.6f}")
    print(f"offered_messages={offered} socket_accepted_messages={accepted} broker_accepted_messages={broker_accepted} delivered_messages={consumer.delivered}")
    delivery_ratio = consumer.delivered / broker_accepted if broker_accepted else 1.0
    print(f"lost_messages={lost} delivery_ratio={delivery_ratio:.6f} gaps={consumer.gaps} duplicates={consumer.duplicates} invalid_frames={consumer.invalid}")
    print(f"accepted_msg_per_sec={accepted / elapsed:.2f} delivered_msg_per_sec={consumer.delivered / drain_elapsed:.2f}")
    print(f"backpressure_events={backpressure_events}")
    print(f"publisher_bye_sent={str(publisher_bye_sent).lower()}")
    if consumer.error is not None:
        print(f"consumer_error={consumer.error}")
    return 0 if status in ("PASS", "PASS_LOSSY_LIVE") else 2


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4222)
    parser.add_argument("--messages", type=int, default=0, help="finite message count; 0 means duration mode")
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--target-mps", type=float, default=0.0, help="offered target rate; 0 means send as fast as possible")
    parser.add_argument("--payload-size", type=int, default=128)
    parser.add_argument("--drain-timeout", type=float, default=10.0)
    parser.add_argument("--ack-publishes", action="store_true")
    parser.add_argument("--allow-live-loss", action="store_true", help="allow expected at-most-once live loss while still failing integrity errors")
    args = parser.parse_args()
    if args.messages < 0 or args.duration < 0 or args.target_mps < 0 or args.payload_size < 0:
        parser.error("numeric values must be non-negative")
    raise SystemExit(run_benchmark(args))
