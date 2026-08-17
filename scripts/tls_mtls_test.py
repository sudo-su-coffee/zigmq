#!/usr/bin/env python3
"""Runtime TLS/mTLS gate for ZigMV's native listener."""
from __future__ import annotations

import argparse
import socket
import ssl
import subprocess
import time
from pathlib import Path


def wait_port(port: int) -> None:
    for _ in range(50):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError("broker did not listen")


def make_context(ca: Path, cert: Path | None, key: Path | None) -> ssl.SSLContext:
    context = ssl.create_default_context(cafile=str(ca))
    if cert and key:
        context.load_cert_chain(str(cert), str(key))
    context.check_hostname = False
    return context


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--ca", type=Path, required=True)
    parser.add_argument("--server-cert", type=Path, required=True)
    parser.add_argument("--server-key", type=Path, required=True)
    parser.add_argument("--client-cert", type=Path, required=True)
    parser.add_argument("--client-key", type=Path, required=True)
    parser.add_argument("--port", type=int, default=24440)
    args = parser.parse_args()

    command = [
        args.binary,
        "server",
        "--host",
        "127.0.0.1",
        "--port",
        str(args.port),
        "--protocol",
        "zigmv",
        "--auth-token",
        "probe-token",
        "--tls-cert",
        str(args.server_cert),
        "--tls-key",
        str(args.server_key),
        "--tls-client-ca",
        str(args.ca),
        "--tls-require-client-cert",
    ]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        wait_port(args.port)
        no_client = make_context(args.ca, None, None)
        try:
            with socket.create_connection(("127.0.0.1", args.port), timeout=2) as raw:
                with no_client.wrap_socket(raw, server_hostname="127.0.0.1") as conn:
                    conn.settimeout(2)
                    conn.sendall(b"ZMV/1 AUTH probe-token\\r\\n")
                    response = conn.recv(256)
                    if response:
                        raise AssertionError(f"mTLS accepted unauthenticated application traffic: {response!r}")
        except (ssl.SSLError, ConnectionError, OSError):
            pass

        client = make_context(args.ca, args.client_cert, args.client_key)
        with socket.create_connection(("127.0.0.1", args.port), timeout=3) as raw:
            with client.wrap_socket(raw, server_hostname="127.0.0.1") as conn:
                conn.settimeout(3)
                ready = conn.recv(256)
                assert b"ZMV/1 READY auth=required" in ready, ready
                conn.sendall(b"ZMV/1 AUTH probe-token\r\n")
                assert b"ZMV/1 OK AUTH" in conn.recv(256)
                conn.sendall(b"ZMV/1 SUB live tls.sensor\r\n")
                assert b"ZMV/1 OK SUB" in conn.recv(256)
        print("TLS_MTLS_RUNTIME_PASS")
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
