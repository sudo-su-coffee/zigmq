#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import signal
import socket
import stat
import subprocess
import tempfile
import time


class LineSocket:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buffer = bytearray()

    def line(self) -> bytes:
        while b"\r\n" not in self.buffer:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("connection closed before CRLF frame")
            self.buffer.extend(chunk)
        index = self.buffer.index(b"\r\n")
        line = bytes(self.buffer[:index])
        del self.buffer[: index + 2]
        return line

    def wait_closed(self) -> None:
        self.sock.settimeout(1)
        while True:
            chunk = self.sock.recv(65536)
            if not chunk:
                return

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass


def start(binary: str, port: int, *extra: str) -> subprocess.Popen[str]:
    process = subprocess.Popen(
        [binary, "--host", "127.0.0.1", "--port", str(port), *extra],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    for _ in range(100):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.1).close()
            return process
        except OSError:
            time.sleep(0.02)
    process.kill()
    raise RuntimeError("broker did not start")


def connect_custom(port: int) -> LineSocket:
    for _ in range(100):
        try:
            client = LineSocket(socket.create_connection(("127.0.0.1", port), timeout=2))
            client.line()
            return client
        except OSError:
            time.sleep(0.02)
    raise RuntimeError("custom connection failed")


def stop(process: subprocess.Popen[str]) -> None:
    process.send_signal(signal.SIGTERM)
    process.wait(timeout=5)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/zigmq")
    parser.add_argument("--port", type=int, default=4540)
    args = parser.parse_args()

    process = start(args.binary, args.port, "--auth-token", "secret")
    clients: list[LineSocket] = []
    try:
        unauthenticated = connect_custom(args.port)
        clients.append(unauthenticated)
        for _ in range(8):
            unauthenticated.sock.sendall(b"PING\r\n")
            assert unauthenticated.line() == b"-ERR authentication required"
        unauthenticated.sock.sendall(b"PING\r\n")
        unauthenticated.wait_closed()
        unauthenticated.close()

        authenticated = connect_custom(args.port)
        clients.append(authenticated)
        authenticated.sock.sendall(b"AUTH secret\r\n")
        assert authenticated.line() == b"+OK AUTH"
        for index in range(1024):
            authenticated.sock.sendall(f"SUB limit.{index}\r\n".encode())
            assert authenticated.line() == b"+OK SUB"
        authenticated.sock.sendall(b"SUB limit.too-many\r\n")
        assert authenticated.line() == b"-ERR subscription limit reached"
        authenticated.sock.sendall(b"PING\r\n")
        assert authenticated.line() == b"PONG"
        authenticated.close()

    except Exception:
        for client in clients:
            client.close()
        stop(process)
        raise
    finally:
        for client in clients:
            client.close()
        stop(process)

    nats_process = start(args.binary, args.port + 1, "--protocol", "nats", "--auth-token", "secret")
    nats_client: LineSocket | None = None
    try:
        nats_client = LineSocket(socket.create_connection(("127.0.0.1", args.port + 1), timeout=2))
        assert nats_client.line().startswith(b"INFO ")
        nats_client.sock.sendall(b'CONNECT {"auth_token":"wrong"}\r\n')
        nats_client.wait_closed()
    finally:
        if nats_client is not None:
            nats_client.close()
        stop(nats_process)

    with tempfile.TemporaryDirectory() as directory:
        stream_path = os.path.join(directory, "events.log")
        stream_process = start(args.binary, args.port + 2, "--stream", stream_path)
        stop(stream_process)
        mode = stat.S_IMODE(os.stat(stream_path).st_mode)
        assert mode == 0o600, oct(mode)

        token_path = os.path.join(directory, "token.txt")
        with open(token_path, "w", encoding="utf-8") as token_file:
            token_file.write("secret\n")
        file_process = start(args.binary, args.port + 3, "--auth-token-file", token_path)
        file_client = connect_custom(args.port + 3)
        try:
            file_client.sock.sendall(b"AUTH secret\r\n")
            assert file_client.line() == b"+OK AUTH"
        finally:
            file_client.close()
            stop(file_process)

    zigmv_process = start(
        args.binary,
        args.port + 4,
        "--protocol",
        "zigmv",
        "--auth-token",
        "secret",
        "--publish-allow",
        "telemetry.*",
        "--subscribe-allow",
        "telemetry.*",
        "--publish-rate-limit",
        "1",
    )
    zigmv_clients: list[LineSocket] = []
    try:
        unauthenticated_zigmv = LineSocket(socket.create_connection(("127.0.0.1", args.port + 4), timeout=2))
        zigmv_clients.append(unauthenticated_zigmv)
        assert unauthenticated_zigmv.line() == b"ZMV/1 READY auth=required"
        unauthenticated_zigmv.sock.sendall(b"ZMV/1 PING\r\n")
        assert unauthenticated_zigmv.line() == b"ZMV/1 ERR authentication_required"
        unauthenticated_zigmv.close()

        zigmv = LineSocket(socket.create_connection(("127.0.0.1", args.port + 4), timeout=2))
        zigmv_clients.append(zigmv)
        assert zigmv.line() == b"ZMV/1 READY auth=required"
        zigmv.sock.sendall(b"ZMV/1 AUTH secret\r\n")
        assert zigmv.line() == b"ZMV/1 OK AUTH"
        zigmv.sock.sendall(b"ZMV/1 SUB live private.device\r\n")
        assert zigmv.line() == b"ZMV/1 ERR subscribe_denied"
        zigmv.sock.sendall(b"ZMV/1 SUB live telemetry.device\r\n")
        assert zigmv.line() == b"ZMV/1 OK SUB"
        zigmv.sock.sendall(b"ZMV/1 UNSUB live telemetry.device\r\n")
        assert zigmv.line() == b"ZMV/1 OK UNSUB"
        zigmv.sock.sendall(b"ZMV/1 PUB live 1 private.device 0\r\n\r\n")
        assert zigmv.line() == b"ZMV/1 ERR publish_denied"
        zigmv.sock.sendall(b"ZMV/1 PUB live 2 telemetry.device 0\r\n\r\n")
        assert zigmv.line() == b"ZMV/1 OK PUB 2"
        zigmv.sock.sendall(b"ZMV/1 PUB live 3 telemetry.device 0\r\n\r\n")
        assert zigmv.line() == b"ZMV/1 ERR rate_limited"
    finally:
        for client in zigmv_clients:
            client.close()
        stop(zigmv_process)

    print("SECURITY_HARDENING_OK")


if __name__ == "__main__":
    main()
