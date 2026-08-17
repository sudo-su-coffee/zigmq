# ZigMV 0.6.0 — Unreleased development train

## Summary

ZigMV 0.6.0 is the observability and performance-focused grouped release train. It builds on the 0.5.0 security and connected-session durable-delivery foundation and makes broker behavior easier to inspect during benchmarks, integration testing, and edge development.

This document describes the current development branch. It is not a published release and does not claim full MQTT 5.0 or NATS JetStream compatibility.

## Added

| Capability | Description |
| --- | --- |
| Native `STATS` command | Authenticated ZigMV clients can request broker counters without opening a separate administration protocol. |
| Delivery counters | The broker tracks native ZigMV publications, deliveries, redeliveries, durable acknowledgements, and expirations. |
| Retry visibility | Connected-session durable redelivery is visible through the `redelivered` counter. |
| Benchmark evidence | README and the benchmark evidence document contain recorded publish, fan-out, stream-cost, realtime, and consumer-group measurements. |
| Release gates | The beta-gate document defines the required throughput, latency, recovery, security, compatibility, and edge evidence through `1.0.0-beta.1`. |

## STATS usage

After the native ZigMV handshake and authentication, send:

```text
ZMV/1 STATS\r\n
```

The broker returns a line such as:

```text
ZMV/1 STATS clients=3 subscriptions=2 pending=0 published=5 delivered=5 redelivered=1 acknowledged=2 expired=0\r\n
```

The counters are process-local and reset on restart. They are intended for benchmark integrity and local operations, not as a replacement for a production metrics endpoint.

## Validation

The following checks passed on the development branch:

- `zig build test`
- ReleaseFast build
- Native ZigMV smoke and durable-redelivery test
- Native ZigMV STATS counter assertion
- Authentication, ACL, and rate-limit integration test
- End-to-end, edge, stream, CLI, NATS, MQTT, and realtime scenarios
- Python syntax and whitespace validation

## Performance evidence

Recorded local artifacts include 23,563.4 publish-ACK messages/sec, 1,781.3 source messages/sec with 50-subscriber fan-out, 89,066.7 fan-out deliveries/sec, 36,618.7 volatile stream-free publish-ACK messages/sec, and 6,294.2 publish-ACK messages/sec with local stream append. These values are machine-specific regression evidence, not universal capacity guarantees.

The 100M messages/sec test remains an offered-rate stress target. It must not be described as achieved end-to-end throughput until a compiled multi-publisher workload demonstrates accepted, queued, delivered, and acknowledged counts with complete integrity.

## Remaining gates

The release is blocked from a production claim until routing optimization, batching or memory reuse, p99 latency histograms, durable restart and reconnect recovery, TLS/mTLS, authenticated edge links, bounded offline transfer, full adapter conformance, and failure-injection coverage are complete. MQTT QoS 2 and ZigMV `exact` remain disabled.

See [`ZIGMV_BETA_RELEASE_GATES.md`](ZIGMV_BETA_RELEASE_GATES.md) for the complete path to `1.0.0-beta.1`.
