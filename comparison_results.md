# ZigMQ versus NATS-Compatible Throughput

These measurements were taken on the same localhost sandbox with NATS protocol framing, 1,000 messages per case, identical payload bytes, and subscriber counts of 1, 10, and 50. `broker_messages_per_sec` counts published messages completed by the harness; `deliveries_per_sec` counts all subscriber deliveries.

| Payload | Subscribers | ZigMQ msg/s | NATS msg/s | ZigMQ deliveries/s | NATS deliveries/s | ZigMQ/NATS msg/s | ZigMQ p50 µs | NATS p50 µs |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1 | 11,121 | 26,278 | 11,121 | 26,278 | 42.3% | 48.7 | 38.0 |
| 16 | 10 | 6,432 | 9,804 | 64,324 | 98,043 | 65.6% | 109.6 | 101.9 |
| 16 | 50 | 2,155 | 2,740 | 107,767 | 137,022 | 78.6% | 402.2 | 359.4 |
| 128 | 1 | 10,837 | 21,402 | 10,837 | 21,402 | 50.6% | 54.7 | 45.2 |
| 128 | 10 | 6,735 | 7,955 | 67,346 | 79,553 | 84.7% | 105.4 | 125.7 |
| 128 | 50 | 2,230 | 2,874 | 111,510 | 143,712 | 77.6% | 388.0 | 342.0 |
| 1024 | 1 | 10,002 | 21,587 | 10,002 | 21,587 | 46.3% | 52.8 | 46.4 |
| 1024 | 10 | 6,178 | 9,788 | 61,782 | 97,884 | 63.1% | 115.8 | 101.0 |
| 1024 | 50 | 2,020 | 2,861 | 101,012 | 143,035 | 70.6% | 439.6 | 346.5 |

## Interpretation

ZigMQ is intentionally a compact learning and edge broker, not a replacement for NATS. In this run it reached roughly 42–85% of NATS's publish-message rate depending on payload and fan-out. NATS generally remained faster, especially for a single subscriber and 1 KiB payloads. ZigMQ's value is its small pure-Zig implementation, bounded in-memory queues, custom protocol, optional retained state, queue-group-like delivery, request/reply routing, and minimal local stream replay.

The harness is deliberately conservative: it waits for every expected delivery before counting a message complete, uses localhost TCP, and runs each broker in a fresh process. These are comparative measurements on one sandbox, not capacity guarantees. Re-run with `scripts/compare_nats.py` on the target edge hardware before making deployment decisions.

## Raw source

The raw log is kept at `benchmark_runs/nats_matrix.jsonl` for reproducibility. The comparison uses NATS server v2.14.5 and ZigMQ's NATS-compatible subset.
