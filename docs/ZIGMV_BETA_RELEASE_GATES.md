# ZigMV 0.5.0 to 1.0.0-beta release gates

## Purpose

This document defines the evidence required before each ZigMV grouped release train is called complete. A release gate is passed only when the implementation, failure behavior, metrics, documentation, and automated tests agree. A command parsing successfully is not sufficient evidence for a delivery guarantee.

## Current baseline

The current branch contains the merged 0.5.0 security and benchmark train plus a follow-up durable redelivery change. The native ZigMV path has authentication, subject ACLs, per-client publish rate limiting, bounded client mailboxes, live/work/durable/state profiles, local stream append, ACK handling, retained state, benchmark integrity counters, and connected-session durable redelivery with bounded exponential backoff.

The following are **not yet release claims**: MQTT 5.0 QoS 2, ZigMV `exact`, durable reconnect sessions, durable consumer cursors across restart, authenticated remote edge transfer, native TLS/mTLS, full NATS JetStream semantics, and full MQTT 5.0 interoperability.

## Grouped release trains

| Train | Primary implementation | Required evidence | Current state |
| --- | --- | --- | --- |
| `0.5.0` | Authentication, identities, ACLs, limits, connected-session durable retry, benchmark integrity | Auth/ACL/rate tests, retry test, bounded-queue test, release build, benchmark evidence | Foundation implemented; TLS, edge links, and full adapters remain open |
| `0.6.0` | Operations and hot-path performance | Metrics accuracy, health/readiness, graceful drain, routing index, batching, p99 latency, connection churn, memory gates | Planned |
| `0.7.0` | Exact-delivery and failure foundations | Producer/consumer deduplication, crash injection, duplicate ACK/publish, restart consistency | Planned; `exact` stays rejected |
| `0.8.0` | Protocol conformance and hardening | Fuzzing, hostile input, upgrade/rollback, adapter conformance, soak tests, security review | Planned |
| `1.0.0-beta.1` | Verified beta release | Signed artifacts, checksums, complete advertised-profile matrix, failure semantics, upgrade guide, rollback procedure | Blocked until all selected guarantees pass |

## Delivery correctness matrix

| Profile | Allowed claim before beta | Required tests before enabling stronger claim |
| --- | --- | --- |
| `live` | At-most-once to connected consumers; overload may lose messages | Offered vs accepted vs delivered counters, slow consumer, full mailbox, fan-out, p50/p95/p99 latency |
| `work` | One eligible consumer per group | Fairness, ordering per group, worker loss, reconnect, duplicate and claim behavior |
| `durable` | ACK-tracked delivery with bounded redelivery during a connected session | ACK timeout, redelivery, ACK stop, expiry, disk append, restart recovery, durable client identity, reconnect resume |
| `state` | Retained last value with expiry | Late subscriber, replacement, expiry, restart, size limit, deletion, reconnect |
| `exact` | No claim | Must prove idempotency window, deduplication, crash recovery, duplicate publish/ACK, replay, and failover |

## Required benchmark matrix

Every benchmark result must record the commit, Zig version, optimization mode, operating system, CPU, memory, payload size, publisher count, subscriber count, profile, ACK mode, duration, and drain timeout.

| Dimension | Required values |
| --- | --- |
| Payload | 0, 16, 32, 128, 1 KiB, 64 KiB |
| Publishers | 1, 4, 16, 64 |
| Subscribers | 1, 10, 50, 100 |
| Profiles | `live`, `work`, `durable`, `state` |
| Publish mode | No publisher ACK, publisher ACK, consumer ACK |
| Duration | 10 seconds smoke, 60 seconds sustained, 1 hour soak |
| Failure | Slow consumer, disconnect, restart, full queue, full disk, TCP reset |
| Metrics | Offered, accepted, queued, delivered, acknowledged, redelivered, expired, lost, duplicate, gap, out-of-order, backpressure, bytes/sec, CPU, memory, p50/p95/p99/max latency |

The benchmark must never report socket-write rate as end-to-end throughput. For lossless claims, `accepted == delivered == acknowledged` where the selected profile requires acknowledgement, with zero gaps, duplicates, invalid frames, and unexplained expiry.

## Current recorded benchmark evidence

These numbers are historical local-sandbox evidence and are not universal capacity guarantees.

| Workload | Result |
| --- | ---: |
| Publish ACK capacity | 23,563.4 msg/s |
| 50-subscriber fan-out source rate | 1,781.3 msg/s |
| 50-subscriber fan-out deliveries | 89,066.7 deliveries/s |
| Volatile publish ACK without stream | 36,618.7 msg/s |
| Publish ACK with local stream | 6,294.2 msg/s |
| Stream relative rate | 17.2% of no-stream rate |
| Realtime telemetry scenario | 20,424.8 msg/s in the recorded run |
| Realtime alert burst | 18,253.4 events/s in the recorded run |
| Realtime command-control | 2,731.1 commands/s in the recorded run |
| Realtime consumer group | 882.4 msg/s with three members |

The 100M messages/sec run remains an offered-rate stress target. It is not a verified delivery result. The benchmark must continue to publish both offered rate and verified end-to-end delivery rate.

## Security gates

The 0.5.0 security gate requires valid and invalid authentication, bounded pre-auth commands, publish ACL denial, subscribe ACL denial, allowed subjects, per-client rate limits, maximum frame and payload limits, subscription limits, client limits, secret-file permissions, redacted logs, and resource exhaustion tests. Native TLS/mTLS, identity-to-tenant mapping, credential rotation, and certificate failure tests are required before a production beta claim.

## Edge gates

The edge train requires an authenticated link envelope, export/import subject filters, sequence or cursor tracking, reconnect backoff, a bounded forwarding queue, offline behavior per profile, link lag, retries, drops, queue occupancy, and recovery metrics. A disconnected upstream must not make local memory grow without bound. The current architecture diagram is [`ZIGMV_EDGE_ARCHITECTURE.png`](ZIGMV_EDGE_ARCHITECTURE.png), but the remote edge-link implementation is not yet complete.

## Compatibility gates

Adapters must be tested semantically, not only for successful connection. The NATS matrix must cover Core publish/subscribe, wildcard subjects, request/reply, queue groups, and the explicitly supported JetStream subset. The MQTT matrix must cover CONNECT/CONNACK, QoS 0, QoS 1, retained messages, session expiry, message expiry, keepalive, shared subscriptions, reason codes, and an explicit negative test showing that unsupported QoS 2 behavior is rejected rather than silently downgraded.

## Final beta checklist

Before tagging `1.0.0-beta.1`, CI must build Debug and ReleaseSafe/ReleaseFast artifacts, run unit and integration tests, run the complete benchmark matrix, run a bounded soak test, execute failure injection, verify `--version`, generate checksums, validate all documentation links, confirm no stale ZMP-era claims remain, and publish a known-limitations section. Only profiles with complete evidence may be advertised as stable.

## Release evidence locations

- [`scripts/benchmark_zigmv.py`](../scripts/benchmark_zigmv.py) — native target-rate benchmark.
- [`docs/ZIGMV_BENCHMARK_0.5.0.md`](ZIGMV_BENCHMARK_0.5.0.md) — current benchmark evidence.
- [`docs/ZIGMV_PROTOCOL.md`](ZIGMV_PROTOCOL.md) — protocol and guarantee boundaries.
- [`docs/ZIGMV_ROADMAP.md`](ZIGMV_ROADMAP.md) — grouped release trains.
- [`benchmark_runs/`](../benchmark_runs/) — raw local benchmark artifacts.
