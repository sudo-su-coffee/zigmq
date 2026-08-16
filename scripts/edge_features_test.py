#!/usr/bin/env python3
from __future__ import annotations

import argparse
import select
import socket
import subprocess
import time


class BufferedSocket:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buffer = bytearray()

    def sendall(self, data: bytes) -> None:
        self.sock.sendall(data)

    def fill(self) -> None:
        chunk = self.sock.recv(4096)
        if not chunk:
            raise RuntimeError("connection closed")
        self.buffer.extend(chunk)

    def read_until(self, marker: bytes) -> bytes:
        while True:
            index = self.buffer.find(marker)
            if index >= 0:
                end = index + len(marker)
                result = bytes(self.buffer[:end])
                del self.buffer[:end]
                return result
            self.fill()

    def read_line(self) -> bytes:
        return self.read_until(b"\r\n")[:-2]

    def read_exact(self, size: int) -> bytes:
        while len(self.buffer) < size:
            self.fill()
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def settimeout(self, timeout: float) -> None:
        self.sock.settimeout(timeout)

    def fileno(self) -> int:
        return self.sock.fileno()

    def close(self) -> None:
        self.sock.close()


def connect(port: int) -> BufferedSocket:
    for _ in range(100):
        try:
            sock = BufferedSocket(socket.create_connection(("127.0.0.1", port), timeout=2))
            sock.read_line()
            return sock
        except OSError:
            time.sleep(0.02)
    raise RuntimeError("server did not start")


def read_message(sock: BufferedSocket) -> tuple[bytes, bytes]:
    header = sock.read_line().split()
    if header[0] != b"MSG":
        raise RuntimeError(f"expected MSG, got {header!r}")
    topic = header[1]
    size = int(header[-1])
    payload = sock.read_exact(size)
    if sock.read_exact(2) != b"\r\n":
        raise RuntimeError("invalid message terminator")
    return topic, payload


def command(sock: BufferedSocket, text: bytes, expected: bytes) -> None:
    sock.sendall(text + b"\r\n")
    response = sock.read_line()
    if not response.startswith(expected):
        raise RuntimeError(f"expected {expected!r}, got {response!r}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--port", type=int, default=4470)
    args = parser.parse_args()
    server = subprocess.Popen([args.binary, "--port", str(args.port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sockets: list[BufferedSocket] = []
    try:
        publisher = connect(args.port)
        sockets.append(publisher)
        command(publisher, b"RETAIN sensors.state 1000 ready", b"+OK RETAIN")

        retained = connect(args.port)
        sockets.append(retained)
        command(retained, b"SUB sensors.>", b"+OK SUB")
        topic, payload = read_message(retained)
        assert topic == b"sensors.state" and payload == b"ready"

        group_a = connect(args.port)
        group_b = connect(args.port)
        sockets.extend([group_a, group_b])
        command(group_a, b"SUB jobs.created workers", b"+OK SUB")
        command(group_b, b"SUB jobs.created workers", b"+OK SUB")
        for index in range(20):
            command(publisher, f"PUB jobs.created job-{index}".encode(), b"+OK PUB")
        deliveries = [0, 0]
        deadline = time.monotonic() + 3.0
        while sum(deliveries) < 20 and time.monotonic() < deadline:
            buffered = [group for group in (group_a, group_b) if group.buffer]
            if buffered:
                ready_groups = buffered
            else:
                remaining = max(0.01, deadline - time.monotonic())
                ready_raw, _, _ = select.select([group_a.sock, group_b.sock], [], [], remaining)
                if not ready_raw:
                    break
                ready_groups = [group for group in (group_a, group_b) if group.sock in ready_raw]
            for group in ready_groups:
                slot = 0 if group is group_a else 1
                topic, payload = read_message(group)
                assert topic == b"jobs.created" and payload.startswith(b"job-")
                deliveries[slot] += 1
        assert sum(deliveries) == 20 and all(count > 0 for count in deliveries), deliveries

        responder = connect(args.port)
        requester = connect(args.port)
        sockets.extend([responder, requester])
        command(responder, b"SUB service.check workers", b"+OK SUB")
        command(requester, b"SUB reply.1", b"+OK SUB")
        requester.sendall(b"REQ service.check reply.1 ping\r\n")
        assert requester.read_line().startswith(b"+OK REQ")
        topic, payload = read_message(responder)
        assert topic == b"service.check" and payload == b"ping"
        command(responder, b"PUB reply.1 pong", b"+OK PUB")
        topic, payload = read_message(requester)
        assert topic == b"reply.1" and payload == b"pong"
        print("EDGE_FEATURES_OK")
    finally:
        for sock in sockets:
            sock.close()
        server.terminate()
        server.wait(timeout=5)


if __name__ == "__main__":
    main()
