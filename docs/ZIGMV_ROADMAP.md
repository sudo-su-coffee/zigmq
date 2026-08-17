# ZigMV release roadmap

## Purpose

ZigMV will be developed through small, testable minor releases. Each release must implement one coherent capability, document its guarantees, add regression and failure tests, and pass the repository CI before the next release begins. Version numbers are milestones, not promises that a feature is complete merely because its command parses.

The roadmap intentionally separates the fast NATS-like path from stronger MQTT-like device and delivery semantics while keeping one ZigMV envelope, one subject space, and one Adaptive Delivery and Transfer algorithm.

## Release sequence

| Release | Main objective | Required tests and gates |
| --- | --- | --- |
| `0.3.0` | Stabilize `ZMV/1`, canonical envelopes, live delivery, no-ack telemetry, and work groups | Wire/parser tests, one-of-N tests, malformed-frame tests, bounded-queue tests, live benchmark baseline |
| `0.4.0` | Add durable append, stream sequence, consumer cursors, ACK, retry, and replay | Restart recovery, ACK removal, retry deadline, expiry, partial-record recovery, replay tests |
| `0.5.0` | Add retained state, last-value delivery, expiry, and persistent sessions | State replacement, TTL expiry, reconnect recovery, session limits, retained-size tests |
| `0.6.0` | Add TLS/mTLS, identities, subject ACLs, rate limits, and credential rotation | Handshake failures, ACL matrix, certificate identity tests, brute-force and resource-limit tests |
| `0.7.0` | Add authenticated edge links, export/import filters, reconnect, and bounded offline transfer | Link reconnect, cursor transfer, offline queue limits, duplicate link message tests |
| `0.8.0` | Add NATS and MQTT 5.0 compatibility adapters at the boundary | Client interoperability, subject/topic translation, request/reply mapping, QoS mapping tests |
| `0.9.0` | Add metrics, health/readiness, structured logs, admin inspection, and safe shutdown | Metric accuracy, secret redaction, readiness transitions, graceful drain, admin authorization |
| `0.10.0` | Improve routing scale, event-loop behavior, batching, memory reuse, and resource isolation | p50/p95/p99 latency, fan-out, connection churn, memory-per-client, slow-consumer tests |
| `0.11.0` | Add exact-delivery foundations: producer IDs, consumer IDs, deduplication windows, idempotent ACK | Duplicate publish, duplicate ACK, crash between append and ACK, dedup-window expiry |
| `0.12.0` | Add cluster routing, replicated metadata, leader/follower stream foundations, and failover | Node loss, leader change, partition behavior, duplicate forwarding, recovery consistency |
| `0.13.0` | Add protocol conformance, fuzzing, hostile-input hardening, and benchmark automation | Fuzz parser, frame limits, malformed lengths, long-running soak, reproducible benchmark artifacts |
| `0.14.0` | Add production upgrades, migrations, configuration validation, compatibility policy, and operator tooling | Rolling upgrade, old-client compatibility, config errors, disk-full, restore and rollback tests |
| `0.15.0` | Release candidate: freeze wire behavior, complete security review, stabilize performance, and close known defects | Full conformance matrix, failure injection, security checklist, performance SLOs, release-candidate review |
| `1.0.0-beta.1` | Publish the first complete ZigMV beta with documented guarantees | All advertised profiles enabled only with passing evidence; signed artifacts, checksums, upgrade guide, and rollback procedure |

## Profile gates

The profiles are enabled in dependency order:

```text
live -> work -> durable -> state -> exact
```

`live` is volatile at-most-once delivery for connected consumers. `work` selects one eligible member of a group. `durable` requires persistent records, consumer cursors, ACK, retry, expiry, and restart recovery. `state` requires retained last-value state and expiry. `exact` requires crash-safe producer and consumer deduplication; it must not be enabled because a message ID exists alone.

## Release policy

Each minor release must have a dedicated release note, migration note when wire behavior changes, benchmark record, and CI workflow result. A release tag must point to the exact commit that passed the release workflow. If a performance or reliability gate fails, the next release remains blocked while the issue is fixed or the target is revised using recorded measurements.

The 1.0.0-beta release is allowed only when the project can state, for every enabled profile, what happens on disconnect, process restart, duplicate publish, duplicate acknowledgement, expired message, full queue, full disk, and unavailable edge link. Unsupported behavior must produce an explicit protocol error rather than silent data loss.

## Current position

The repository has the `ZMV/1` foundation, `live`, and the first `work` group path merged and CI-tested. The next implementation milestone is `0.4.0`: broker-integrated durable records, consumer cursors, ACK, retry, replay, and restart recovery. Until that milestone is complete, `durable`, `state`, and `exact` remain disabled.
