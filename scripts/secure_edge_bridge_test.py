#!/usr/bin/env python3
from __future__ import annotations

import argparse
import socket
import ssl
import subprocess
import time
from pathlib import Path


def context(ca: Path, cert: Path, key: Path) -> ssl.SSLContext:
    ctx = ssl.create_default_context(cafile=str(ca))
    ctx.load_cert_chain(str(cert), str(key))
    ctx.check_hostname = False
    return ctx


def connect(ctx: ssl.SSLContext, port: int) -> ssl.SSLSocket:
    for _ in range(60):
        try:
            raw = socket.create_connection(("127.0.0.1", port), timeout=1)
            return ctx.wrap_socket(raw, server_hostname="127.0.0.1")
        except OSError:
            time.sleep(0.1)
    raise RuntimeError(f"port {port} unavailable")


def read_until(sock: ssl.SSLSocket, marker: bytes) -> bytes:
    data = b""
    while marker not in data:
        data += sock.recv(4096)
        if not data:
            raise RuntimeError(f"connection closed before {marker!r}: {data!r}")
    return data


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--binary", required=True)
    p.add_argument("--ca", type=Path, required=True)
    p.add_argument("--cert", type=Path, required=True)
    p.add_argument("--key", type=Path, required=True)
    p.add_argument("--port-a", type=int, default=24450)
    p.add_argument("--port-b", type=int, default=24451)
    args = p.parse_args()
    base = [args.binary, "server", "--host", "127.0.0.1", "--protocol", "zigmv", "--auth-token", "edge-secret", "--tls-cert", str(args.cert), "--tls-key", str(args.key), "--tls-client-ca", str(args.ca), "--tls-require-client-cert"]
    b = subprocess.Popen(base + ["--port", str(args.port_b)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    a = subprocess.Popen(base + ["--port", str(args.port_a), "--edge-link-host", "127.0.0.1", "--edge-link-port", str(args.port_b), "--edge-link-identity", "edge-a", "--edge-link-filter", "telemetry.>"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    subscriber = None
    publisher = None
    try:
        ctx = context(args.ca, args.cert, args.key)
        subscriber = connect(ctx, args.port_b)
        assert b"ZMV/1 READY" in read_until(subscriber, b"\r\n")
        subscriber.sendall(b"ZMV/1 AUTH edge-secret\r\n")
        assert b"OK AUTH" in read_until(subscriber, b"\r\n")
        subscriber.sendall(b"ZMV/1 SUB live telemetry.>\r\n")
        assert b"OK SUB" in read_until(subscriber, b"\r\n")
        publisher = connect(ctx, args.port_a)
        assert b"ZMV/1 READY" in read_until(publisher, b"\r\n")
        publisher.sendall(b"ZMV/1 AUTH edge-secret\r\n")
        assert b"OK AUTH" in read_until(publisher, b"\r\n")
        # Allow the outbound TLS LINK worker to complete its authenticated peer handshake.
        time.sleep(1.0)
        publisher.sendall(b"ZMV/1 PUB live 1 telemetry.secure 12\r\nhello-secure\r\n")
        assert b"OK PUB" in read_until(publisher, b"\r\n")
        delivered = read_until(subscriber, b"hello-secure")
        assert b"hello-secure" in delivered
        print("SECURE_EDGE_BRIDGE_PASS")
        return 0
    finally:
        for sock in (subscriber, publisher):
            if sock:
                sock.close()
        for proc in (a, b):
            proc.terminate()
        for proc in (a, b):
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


if __name__ == "__main__":
    raise SystemExit(main())
