#!/usr/bin/env python3
"""Run a bounded ZigMV benchmark matrix and preserve machine-readable results."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time


PAYLOADS = (0, 16, 128, 1024)
PUBLISHERS = (1,)
PROFILES = ("live",)


def run_case(binary: str, port: int, messages: int, payload_size: int, ack: bool) -> dict[str, object]:
    log_path = f"/tmp/zigmv-matrix-{port}.log"
    process = subprocess.Popen(
        [binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        time.sleep(0.5)
        command = [
            sys.executable,
            os.path.join(os.path.dirname(__file__), "benchmark_zigmv.py"),
            "--port",
            str(port),
            "--messages",
            str(messages),
            "--payload-size",
            str(payload_size),
            "--drain-timeout",
            "10",
        ]
        if ack:
            command.append("--ack-publishes")
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        result: dict[str, object] = {
            "payload_bytes": payload_size,
            "messages": messages,
            "ack_publishes": ack,
            "returncode": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }
        return result
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        with open(log_path, "w", encoding="utf-8") as log:
            if process.stdout is not None:
                log.write(process.stdout.read())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--messages", type=int, default=1000)
    parser.add_argument("--output", default="benchmark_runs/zigmv_matrix.json")
    parser.add_argument("--port", type=int, default=4250)
    parser.add_argument("--ack-only", action="store_true", help="run only acknowledged lossless cases")
    args = parser.parse_args()
    if args.messages <= 0:
        parser.error("--messages must be positive")
    results = []
    case_port = args.port
    for payload_size in PAYLOADS:
        for ack in ((True,) if args.ack_only else (False, True)):
            result = run_case(args.binary, case_port, args.messages, payload_size, ack)
            result["port"] = case_port
            results.append(result)
            case_port += 1
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as output:
        json.dump({"protocol": "zigmv", "results": results}, output, indent=2)
        output.write("\n")
    failures = [result for result in results if result["returncode"] != 0]
    policy = "lossless_acknowledged" if args.ack_only else "mixed_lossless_and_at_most_once_stress"
    print(f"cases={len(results)} failures={len(failures)} policy={policy} output={args.output}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
