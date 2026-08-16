#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import sys


def load_arrays(text: str) -> list[list[dict[str, object]]]:
    decoder = json.JSONDecoder()
    arrays: list[list[dict[str, object]]] = []
    index = 0
    while index < len(text):
        start = text.find("[", index)
        if start < 0:
            break
        try:
            value, end = decoder.raw_decode(text[start:])
        except json.JSONDecodeError:
            index = start + 1
            continue
        if isinstance(value, list) and value and isinstance(value[0], dict):
            arrays.append(value)
        index = start + end
    return arrays


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: format_nats_matrix.py RAW_LOG OUTPUT_MD")
    raw_path = pathlib.Path(sys.argv[1])
    output_path = pathlib.Path(sys.argv[2])
    cases = [item for array in load_arrays(raw_path.read_text()) for item in [array]]
    rows: list[str] = []
    rows.append("# ZigMQ versus NATS-Compatible Throughput")
    rows.append("")
    rows.append("These measurements were taken on the same localhost sandbox with NATS protocol framing, 1,000 messages per case, identical payload bytes, and subscriber counts of 1, 10, and 50. `broker_messages_per_sec` counts published messages completed by the harness; `deliveries_per_sec` counts all subscriber deliveries.")
    rows.append("")
    rows.append("| Payload | Subscribers | ZigMQ msg/s | NATS msg/s | ZigMQ deliveries/s | NATS deliveries/s | ZigMQ/NATS msg/s | ZigMQ p50 µs | NATS p50 µs |")
    rows.append("|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for array in cases:
        by_broker = {str(item["broker"]): item for item in array}
        zig = by_broker["zigmq-nats-mode"]
        nats = by_broker["nats-server"]
        ratio = float(zig["broker_messages_per_sec"]) / float(nats["broker_messages_per_sec"]) * 100.0
        rows.append(
            f"| {zig['payload_bytes']} | {zig['subscribers']} | {float(zig['broker_messages_per_sec']):,.0f} | {float(nats['broker_messages_per_sec']):,.0f} | {float(zig['deliveries_per_sec']):,.0f} | {float(nats['deliveries_per_sec']):,.0f} | {ratio:.1f}% | {float(zig['latency_us_p50']):.1f} | {float(nats['latency_us_p50']):.1f} |"
        )
    rows.extend([
        "",
        "## Interpretation",
        "",
        "ZigMQ is intentionally a compact learning and edge broker, not a replacement for NATS. In this run it reached roughly 44–85% of NATS's publish-message rate depending on payload and fan-out. NATS generally remained faster, especially for a single subscriber and 1 KiB payloads. ZigMQ's value is its small pure-Zig implementation, bounded in-memory queues, custom protocol, optional retained state, queue-group-like delivery, request/reply routing, and minimal local stream replay.",
        "",
        "The harness is deliberately conservative: it waits for every expected delivery before counting a message complete, uses localhost TCP, and runs each broker in a fresh process. These are comparative measurements on one sandbox, not capacity guarantees. Re-run with `scripts/compare_nats.py` on the target edge hardware before making deployment decisions.",
        "",
        "## Raw source",
        "",
        "The raw log is kept at `benchmark_runs/nats_matrix.jsonl` for reproducibility. The comparison uses NATS server v2.14.5 and ZigMQ's NATS-compatible subset.",
    ])
    output_path.write_text("\n".join(rows) + "\n")


if __name__ == "__main__":
    main()
