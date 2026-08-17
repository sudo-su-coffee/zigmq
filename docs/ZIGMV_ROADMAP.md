# ZigMV grouped release roadmap

## Release model

ZigMV will use **grouped release trains** rather than publishing a separate version for every small milestone. Related internal milestones will be implemented together, reviewed in one pull request, tested together, and published as one public release.

The internal milestone numbers remain useful for planning, but they do not automatically become public tags. A release is created only when the entire capability bundle and all of its gates pass.

> **One release train = one capability bundle, one primary implementation PR, one complete CI cycle, and one public release tag.**

If a train becomes too large to review safely, it may use preparatory commits or dependent PRs, but the final release remains blocked until the complete bundle is integrated and tested on `main`.

## Grouped release trains

| Public release | Internal milestones grouped together | Capability bundle | Release gate |
| --- | --- | --- | --- |
| `0.4.0` | Previous `0.3.x`, `0.4.x`, and `0.5.x` work | ZMV/1 foundation, live telemetry, work groups, durable append, consumer cursors, ACK/retry/replay, retained state, expiry, and persistent sessions | End-to-end profile matrix, restart recovery, queue/backpressure, replay, retention, and benchmark gates |
| `0.5.0` | Previous `0.6.x`, `0.7.x`, and `0.8.x` work | TLS/mTLS, identities, subject ACLs, rate limits, authenticated edge links, reconnect/offline transfer, NATS/MQTT compatibility adapters, and migration tools | Security matrix, certificate tests, edge-link recovery, compatibility clients, and resource-limit tests |
| `0.6.0` | Previous `0.9.x` and `0.10.x` work | Metrics, health/readiness, structured logs, administration, graceful shutdown, routing optimization, batching, event-loop improvements, memory reuse, and resource isolation | Observability accuracy, secret redaction, graceful drain, p99 latency, fan-out, connection churn, and memory gates |
| `0.7.0` | Previous `0.11.x` and `0.12.x` work | Exact-delivery foundations, producer/consumer deduplication, crash recovery, cluster routing, replicated metadata, stream replication, and failover foundations | Duplicate publish/ACK tests, failure injection, node loss, leader changes, partition behavior, and recovery consistency |
| `0.8.0` | Previous `0.13.x`, `0.14.x`, and `0.15.x` work | Protocol conformance, fuzzing, hostile-input hardening, production upgrades, migration tools, compatibility policy, performance freeze, and release-candidate stabilization | Full conformance matrix, fuzz/soak tests, security review, upgrade/rollback tests, SLO evidence, and known-defect closure |
| `1.0.0-beta.1` | Final beta gate | Complete verified ZigMV beta with only the profiles whose guarantees are proven | Signed artifacts, checksums, upgrade guide, rollback procedure, security checklist, documented failure semantics, and release approval |

## Execution order

The implementation still proceeds in dependency order, even though public releases are grouped:

```text
ZMV/1 foundation
    -> live
    -> work
    -> durable
    -> state
    -> security
    -> edge transfer
    -> compatibility
    -> operations and scaling
    -> exact delivery
    -> clustering and failover
    -> conformance and release hardening
    -> 1.0.0-beta
```

The current release baseline is **`0.4.0`**, containing the ZMV/1 foundation, `live`, `work`, durable append, delivery IDs, ACK handling, retained state, and expiry behavior. The active public target is **`0.5.0`**, which is being implemented as one security and edge-transfer train rather than a sequence of small tags.

## Public PR policy

For each grouped train, create one primary PR titled for the public release, such as `feat: prepare ZigMV 0.4.0`. The PR must contain the implementation, tests, benchmark updates, documentation, migration notes, and release notes for the entire bundle. CI must compile the release build, run unit and integration tests, execute the bounded benchmark suite, and verify that unsupported profiles fail explicitly.

The PR may be updated repeatedly while bugs and performance issues are fixed. It must not be merged merely because an early subset works. The merge gate is the complete train, not the first passing commit.

## Versioning policy

A grouped release increments the minor version when the complete bundle adds a coherent user-visible capability. Patch versions such as `0.4.1` and `0.4.2` are reserved for compatible bug fixes, security fixes, documentation corrections, and performance improvements that do not change the protocol contract.

A beta release is not created just because the code compiles. The `1.0.0-beta.1` tag requires evidence for every advertised delivery profile, including behavior after disconnect, restart, duplicate publish, duplicate acknowledgement, expired message, full queue, full disk, and unavailable edge link. Unsupported behavior must produce an explicit protocol error rather than silent data loss.

## Current status

| Area | Status |
| --- | --- |
| Detailed roadmap grouped into public trains | Complete and documented |
| ZMV/1 foundation | Merged and CI-tested |
| `live` profile | Merged and CI-tested |
| `work` profile | Merged and CI-tested |
| Durable/state broker profiles | Implemented foundation in `0.4.0`; retry/recovery guarantees remain bounded |
| `0.5.0` authentication and resource security | Partially implemented: native ZigMV AUTH, subject ACLs, subscription limits, and per-client publish rate limits |
| `0.5.0` edge transfer and compatibility | Pending: TLS/mTLS, authenticated edge links, reconnect/offline transfer, and NATS/MQTT adapters |
| 1.0.0-beta | Blocked until all grouped release gates pass |
