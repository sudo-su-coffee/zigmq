# ZMP live-profile test plan

This plan defines the gates for the `0.2.0-beta.1` native ZMP `live` profile before adding `work`, `durable`, `state`, or `exact` delivery.

## Scope

The live profile is volatile and at-most-once. A connected subscriber should receive each accepted publish at most once while it has capacity. The broker may reject or disconnect a slow consumer according to its configured queue limits. The profile does not promise replay, offline delivery, acknowledgement recovery, or exactly-once behavior.

## Acceptance gates

The numbers below are starting engineering gates for a localhost ReleaseFast build, not universal product guarantees. They must be recorded with the CPU, operating system, Zig version, optimization mode, payload size, subscriber count, and commit.

| Gate | Target | Failure meaning |
| --- | ---: | --- |
| Unit and integration tests | 100% pass | Correctness regression |
| Publish acknowledgement rate | >= 25,000 msg/s for 128-byte payloads | Hot path needs optimization or target is too ambitious |
| One-subscriber delivery | >= 25,000 msg/s | Per-message framing or socket path is limiting throughput |
| Ten-subscriber fan-out | >= 100,000 deliveries/s | Routing or fan-out path is limiting throughput |
| p99 publish acknowledgement latency | <= 5 ms at 10,000 msg/s | Excessive queueing or scheduler overhead |
| Memory growth during steady live load | No unbounded growth | Queue or ownership leak |
| Slow-consumer behavior | Bounded queue and deterministic disconnect/error | Backpressure is unsafe |
| Reconnect behavior | New client can connect after disconnect | Resource cleanup regression |
| Invalid-frame handling | No crash, bounded error response | Parser or resource-safety defect |

If the current implementation does not meet the numeric targets, do not implement stronger profiles immediately. First capture the result, identify the bottleneck, and optimize the live path.

## Benchmark matrix

Run each row at least three times and report the median and the worst run. Use message counts large enough to exceed startup noise.

| Messages | Subscribers | Payload sizes |
| ---: | ---: | --- |
| 10,000 | 1 | 16, 128, 1,024 bytes |
| 10,000 | 10 | 16, 128, 1,024 bytes |
| 10,000 | 50 | 16, 128, 1,024 bytes |
| 100,000 | 1 | 128 bytes |
| 100,000 | 10 | 128 bytes |

Measure publish acknowledgements, total fan-out deliveries, elapsed time, p50/p95/p99 acknowledgement latency, connection setup time, and incomplete delivery counts.

## Correctness tests

The live profile must be tested with exact subjects, `*` wildcards, `>` wildcards, multiple subscribers, duplicate subscriptions, unsubscribe during traffic, malformed headers, oversized payload declarations, truncated payloads, invalid profiles, invalid subjects, and client disconnects during a publish.

## Resource and failure tests

Run the broker with a bounded queue and create a subscriber that does not read. Verify that the broker does not grow memory without limit and that the slow consumer receives a deterministic disconnect or error. Reconnect repeatedly while publishing and verify that the broker can continue accepting new clients.

Run invalid ZMP frames against a fresh process and verify that malformed input cannot terminate the broker process. Include incomplete CRLF frames, invalid lengths, invalid message IDs, unsupported profiles, and payloads above the configured maximum.

## Profile gate

Only after the live profile passes the correctness and resource tests should the next profiles be enabled. `work` requires deterministic one-of-N selection. `durable` requires append, acknowledgement, retry, expiry, and restart recovery. `state` requires retained values and expiry. `exact` requires durable deduplication and crash tests. Each profile must have independent tests and benchmarks; a passing live benchmark does not prove any stronger guarantee.
