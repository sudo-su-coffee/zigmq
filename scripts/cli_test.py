#!/usr/bin/env python3
import os
import signal
import subprocess
import time


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINARY = os.path.join(ROOT, "zig-out", "bin", "zigmq")
PORT = "4443"


def main() -> None:
    server = subprocess.Popen(
        [BINARY, "server", "--port", PORT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subscriber = None
    try:
        for _ in range(50):
            try:
                subscriber = subprocess.Popen(
                    [BINARY, "sub", "cli.demo", "--port", PORT, "--raw"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                break
            except OSError:
                time.sleep(0.05)
        if subscriber is None:
            raise RuntimeError("could not start subscriber")

        ready = subscriber.stdout.readline().strip()
        if ready != "+OK SUB":
            raise RuntimeError(f"unexpected subscriber response: {ready!r}")

        published = subprocess.run(
            [BINARY, "pub", "cli.demo", "hello-cli", "--port", PORT],
            check=True,
            capture_output=True,
            text=True,
        )
        if "+OK PUB" not in published.stdout:
            raise RuntimeError(f"unexpected publisher response: {published.stdout!r}")

        received = subscriber.stdout.readline().strip()
        if received != "hello-cli":
            raise RuntimeError(f"unexpected subscriber payload: {received!r}")
        print("CLI_E2E_OK")
    finally:
        if subscriber is not None:
            subscriber.send_signal(signal.SIGTERM)
            subscriber.wait(timeout=3)
        server.send_signal(signal.SIGTERM)
        server.wait(timeout=3)


if __name__ == "__main__":
    main()
