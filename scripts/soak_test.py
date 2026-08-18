#!/usr/bin/env python3
"""Run a bounded sustained ZigMV benchmark for release evidence."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--duration", type=float, default=60.0)
    parser.add_argument("--port", type=int, default=4260)
    parser.add_argument("--output", default="benchmark_runs/zigmv_soak.txt")
    args = parser.parse_args()
    if args.duration <= 0:
        parser.error("--duration must be positive")
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    broker = subprocess.Popen(
        [args.binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(args.port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        time.sleep(0.5)
        command = [
            sys.executable,
            os.path.join(os.path.dirname(__file__), "benchmark_zigmv.py"),
            "--port", str(args.port),
            "--duration", str(args.duration),
            "--payload-size", "128",
            "--drain-timeout", "15",
            "--ack-publishes",
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        with open(args.output, "w", encoding="utf-8") as output:
            output.write(result.stdout)
            if result.stderr:
                output.write("\n--- benchmark stderr ---\n")
                output.write(result.stderr)
        print(f"soak_returncode={result.returncode} output={args.output}")
        return result.returncode
    finally:
        broker.terminate()
        try:
            broker.wait(timeout=3)
        except subprocess.TimeoutExpired:
            broker.kill()
            broker.wait(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
