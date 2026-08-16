#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import socket
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor

CRLF = b"\r\n"


class Client:
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
        result = bytes(self.buffer[:index])
        del self.buffer[: index + 2]
        return result

    def exact(self, size: int) -> bytes:
        while len(self.buffer) < size:
            self.fill()
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def message(self) -> tuple[bytes, bytes | None, bytes]:
        fields = self.line().split()
        if len(fields) not in (3, 4) or fields[0] != b"MSG":
            raise RuntimeError(f"unexpected message frame: {fields!r}")
        topic = fields[1]
        reply = fields[2] if len(fields) == 4 else None
        size = int(fields[-1])
        payload = self.exact(size)
        if self.exact(2) != CRLF:
            raise RuntimeError("message payload missing CRLF")
        return topic, reply, payload


def connect(port: int) -> Client:
    for _ in range(100):
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=3)
            client = Client(sock)
            if client.line() != b"+OK zigmq ready":
                raise RuntimeError("unexpected broker greeting")
            return client
        except OSError:
            time.sleep(0.02)
    raise RuntimeError(f"broker did not open port {port}")


def command(client: Client, text: str, expected: bytes = b"+OK") -> None:
    client.sock.sendall(text.encode() + CRLF)
    response = client.line()
    if not response.startswith(expected):
        raise RuntimeError(f"command {text!r}: expected {expected!r}, got {response!r}")


def start(binary: str, port: int) -> subprocess.Popen[bytes]:
    process = subprocess.Popen(
        [binary, "--host", "127.0.0.1", "--port", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    probe = connect(port)
    probe.sock.close()
    return process


def stop(process: subprocess.Popen[bytes]) -> None:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
    if process.returncode != 0:
        raise RuntimeError(f"broker exited with status {process.returncode}")


def collect(client: Client, count: int, output: list[tuple[bytes, bytes | None, bytes]], error: list[BaseException]) -> None:
    try:
        for _ in range(count):
            output.append(client.message())
    except BaseException as exc:  # propagate worker failures to the main test
        error.append(exc)


def telemetry(binary: str, port: int) -> dict[str, object]:
    process = start(binary, port)
    subscriber = connect(port)
    devices: list[Client] = []
    received: list[tuple[bytes, bytes | None, bytes]] = []
    errors: list[BaseException] = []
    try:
        command(subscriber, "SUB telemetry.>")
        devices = [connect(port) for _ in range(100)]
        reader = threading.Thread(target=collect, args=(subscriber, 1000, received, errors), daemon=True)
        reader.start()
        payload = (b"temperature=21.5;humidity=47.0;device=zigmq-edge;" * 4)[:128]
        started = time.perf_counter()

        def device_publish(index: int) -> None:
            client = devices[index]
            for sample in range(10):
                client.sock.sendall(f"PUB telemetry.device{index} {payload.decode()}".encode() + CRLF)
                response = client.line()
                if not response.startswith(b"+OK PUB"):
                    raise RuntimeError(f"telemetry publish was not acknowledged: {response!r}")

        with ThreadPoolExecutor(max_workers=100) as pool:
            list(pool.map(device_publish, range(100)))
        reader.join(timeout=10)
        elapsed = time.perf_counter() - started
        if reader.is_alive() or errors or len(received) != 1000:
            raise RuntimeError("telemetry subscriber did not receive all readings")
        return {"scenario": "telemetry", "messages": 1000, "devices": 100, "hz_per_device": 10, "elapsed_s": elapsed, "messages_per_sec": 1000 / elapsed}
    finally:
        subscriber.sock.close()
        for client in devices:
            client.sock.close()
        stop(process)


def command_control(binary: str, port: int) -> dict[str, object]:
    process = start(binary, port)
    subscribers = [connect(port) for _ in range(100)]
    received: list[list[tuple[bytes, bytes | None, bytes]]] = [[] for _ in subscribers]
    errors: list[BaseException] = []
    try:
        for index, client in enumerate(subscribers):
            command(client, f"SUB command.device{index}")
        threads = [threading.Thread(target=collect, args=(client, 1, received[index], errors), daemon=True) for index, client in enumerate(subscribers)]
        for thread in threads:
            thread.start()
        publisher = connect(port)
        started = time.perf_counter()
        for index in range(100):
            command(publisher, f"PUB command.device{index} reboot")
        for thread in threads:
            thread.join(timeout=5)
        elapsed = time.perf_counter() - started
        if any(len(items) != 1 for items in received) or errors:
            raise RuntimeError("command/control delivery mismatch")
        return {"scenario": "command_control", "devices": 100, "commands": 100, "elapsed_s": elapsed, "commands_per_sec": 100 / elapsed}
    finally:
        for client in subscribers:
            client.sock.close()
        if "publisher" in locals():
            publisher.sock.close()
        stop(process)


def alert_burst(binary: str, port: int) -> dict[str, object]:
    process = start(binary, port)
    subscriber = connect(port)
    received: list[tuple[bytes, bytes | None, bytes]] = []
    errors: list[BaseException] = []
    try:
        command(subscriber, "SUB alerts.>")
        reader = threading.Thread(target=collect, args=(subscriber, 1000, received, errors), daemon=True)
        reader.start()
        publisher = connect(port)
        started = time.perf_counter()
        for index in range(1000):
            command(publisher, f"PUB alerts.event{index} burst")
        reader.join(timeout=10)
        elapsed = time.perf_counter() - started
        if reader.is_alive() or errors or len(received) != 1000:
            raise RuntimeError("alert burst was not fully delivered")
        return {"scenario": "alert_burst", "events": 1000, "elapsed_s": elapsed, "events_per_sec": 1000 / elapsed}
    finally:
        subscriber.sock.close()
        if "publisher" in locals():
            publisher.sock.close()
        stop(process)


def request_reply_timeout(binary: str, port: int) -> dict[str, object]:
    process = start(binary, port)
    service = requestor = None
    try:
        service = connect(port)
        command(service, "SUB rpc.request")
        requestor = connect(port)
        command(requestor, "SUB rpc.reply")
        command(requestor, "REQ rpc.request rpc.reply ping")
        topic, reply, payload = service.message()
        if topic != b"rpc.request" or reply != b"rpc.reply" or payload != b"ping":
            raise RuntimeError("request frame mismatch")
        command(service, "PUB rpc.reply pong")
        topic, _, payload = requestor.message()
        if topic != b"rpc.reply" or payload != b"pong":
            raise RuntimeError("reply frame mismatch")
        command(requestor, "REQ rpc.missing rpc.reply no-service")
        requestor.sock.settimeout(0.25)
        try:
            requestor.message()
        except (socket.timeout, TimeoutError):
            pass
        else:
            raise RuntimeError("missing service unexpectedly replied")
        return {"scenario": "request_reply_timeout", "completed_request_reply": True, "missing_service_timeout_s": 0.25}
    finally:
        if service:
            service.sock.close()
        if requestor:
            requestor.sock.close()
        stop(process)


def retained_reconnect(binary: str, port: int) -> dict[str, object]:
    process = start(binary, port)
    publisher = subscriber = None
    try:
        publisher = connect(port)
        command(publisher, "RETAIN state.device1 5000 online")
        publisher.sock.close()
        publisher = None
        subscriber = connect(port)
        command(subscriber, "SUB state.device1")
        topic, reply, payload = subscriber.message()
        if topic != b"state.device1" or reply is not None or payload != b"online":
            raise RuntimeError("retained state mismatch after reconnect")
        return {"scenario": "retained_reconnect", "topic": "state.device1", "payload": "online", "ttl_ms": 5000}
    finally:
        if publisher:
            publisher.sock.close()
        if subscriber:
            subscriber.sock.close()
        stop(process)


def consumer_group(binary: str, port: int) -> dict[str, object]:
    process = start(binary, port)
    subscribers = [connect(port) for _ in range(3)]
    received: list[list[tuple[bytes, bytes | None, bytes]]] = [[] for _ in subscribers]
    errors: list[BaseException] = []
    try:
        for client in subscribers:
            command(client, "SUB jobs.work workers")
        threads = [threading.Thread(target=collect, args=(client, 10, received[index], errors), daemon=True) for index, client in enumerate(subscribers)]
        for thread in threads:
            thread.start()
        publisher = connect(port)
        started = time.perf_counter()
        for index in range(30):
            command(publisher, f"PUB jobs.work job-{index}")
        for thread in threads:
            thread.join(timeout=5)
        elapsed = time.perf_counter() - started
        if errors or any(len(items) != 10 for items in received):
            raise RuntimeError(f"consumer group did not balance 30 jobs: {[len(items) for items in received]}")
        payloads = [item[2] for items in received for item in items]
        if len(set(payloads)) != 30:
            raise RuntimeError("consumer group duplicated or dropped jobs")
        return {"scenario": "consumer_group", "members": 3, "messages": 30, "per_member": [len(items) for items in received], "elapsed_s": elapsed, "messages_per_sec": 30 / elapsed}
    finally:
        for client in subscribers:
            client.sock.close()
        if "publisher" in locals():
            publisher.sock.close()
        stop(process)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--port", type=int, default=4480)
    args = parser.parse_args()
    scenarios = [telemetry, command_control, alert_burst, request_reply_timeout, retained_reconnect, consumer_group]
    results = [scenario(args.binary, args.port + index) for index, scenario in enumerate(scenarios)]
    print(json.dumps(results, indent=2))
    print("REALTIME_SCENARIOS_OK")


if __name__ == "__main__":
    main()
