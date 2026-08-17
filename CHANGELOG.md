# Changelog

All notable changes to zigmq are documented here.

## [0.6.0] - Unreleased

### Added

- Native authenticated ZigMV `STATS` command for process-local operational counters.
- Counters for publications, deliveries, durable redeliveries, ACKs, expirations, active clients, subscriptions, and pending durable messages.
- Bounded per-client publish-idempotency windows that return `ZMV/1 OK DUP <id>` without routing repeated numeric IDs; this is a foundation for exactly-once work and not an exactly-once guarantee.
- Integration coverage proving STATS framing and retry/ACK counter behavior.
- Unreleased 0.6.0 release notes and the complete beta-gate checklist through `1.0.0-beta.1`.

### Performance evidence

- Consolidated recorded benchmark data in the README and `docs/ZIGMV_BENCHMARK_0.5.0.md`.
- Historical local evidence includes 23,563.4 publish-ACK msg/s, 36,618.7 volatile stream-free publish-ACK msg/s, 6,294.2 local-stream publish-ACK msg/s, and 89,066.7 fan-out deliveries/s with 50 subscribers.
- The 100M msg/s run remains an offered-rate stress target and is not claimed as end-to-end achieved throughput.
- The native benchmark now synchronizes no-ACK runs through STATS before BYE and distinguishes socket-written, broker-accepted, delivered, lost, delivery ratio, duplicates, gaps, invalid frames, and backpressure.
- The latest recorded 0.6.0 1,000-message, 128-byte live run delivered 994/1,000 messages with a 99.4% ratio under at-most-once overload; the corresponding publish-ACK run delivered 1,000/1,000.

### Known limitations

- Native TLS/mTLS, authenticated edge links, bounded offline transfer, durable reconnect sessions, full NATS JetStream semantics, full MQTT 5.0 interoperability, MQTT QoS 2, and ZigMV `exact` remain blocked release gates.

See [`docs/ZIGMV_RELEASE_0.6.0.md`](docs/ZIGMV_RELEASE_0.6.0.md) and [`docs/ZIGMV_BETA_RELEASE_GATES.md`](docs/ZIGMV_BETA_RELEASE_GATES.md).

## [0.5.0] - Unreleased

### Added

- Native ZigMV authentication using `ZMV/1 AUTH <token>` with bounded pre-auth command handling.
- Comma-separated subject ACLs for native ZigMV publish and subscribe operations, using the canonical subject wildcard matcher.
- Per-client publish rate limiting with explicit `rate_limited` protocol errors.
- Server options for `--publish-allow`, `--subscribe-allow`, and `--publish-rate-limit`.
- Integration coverage for authentication, ACL denial, allowed subjects, and rate limiting.
- Native `scripts/benchmark_zigmv.py` target-rate stress harness with offered, accepted, delivered, loss, gap, duplicate, invalid-frame, and backpressure metrics.
- Bounded producer backpressure in client mailboxes so a full queue blocks the publishing path rather than silently allowing unbounded growth or immediately dropping the delivery.
- Bounded in-session durable redelivery with exponential retry backoff; unacknowledged deliveries are retried while the original client remains connected and are removed safely on disconnect.
- Native durable redelivery integration coverage in `scripts/zigmv_test.py`.

### Performance notes

- A 100,000,000 messages/sec offered-rate stress target was exercised on the development host. The test measured the actual host ceiling and exposed the difference between publisher acceptance and end-to-end delivery; it did not claim 100M messages/sec as achieved throughput.
- A controlled 35,000 messages/sec acknowledged workload completed with zero loss, gaps, duplicates, or invalid frames in the local validation run; detailed commands and results are recorded in [`docs/ZIGMV_BENCHMARK_0.5.0.md`](docs/ZIGMV_BENCHMARK_0.5.0.md).

### Documentation

- README usage now reflects ZigMV naming, implemented delivery profiles, the 0.4.0 baseline, the 0.5.0 security configuration, practical use cases, and the edge architecture flow.
- Added `docs/ZIGMV_EDGE_ARCHITECTURE.mmd` and its rendered PNG architecture diagram.
- Corrected protocol documentation to state that MQTT QoS 2, ZigMV `exact`, durable reconnect sessions, and full NATS JetStream parity are not yet implemented.
- Added [`docs/ZIGMV_BETA_RELEASE_GATES.md`](docs/ZIGMV_BETA_RELEASE_GATES.md), which consolidates the 0.5.0-to-1.0.0-beta implementation, benchmark, failure-test, compatibility, and release gates.
- Added recorded benchmark evidence to the README, including publish ACK, fan-out, stream-cost, realtime, and consumer-group results.

### Known limitations

- Native TLS/mTLS, authenticated remote edge links, bounded offline transfer, reconnect backoff, and full NATS/MQTT semantic compatibility remain pending for the complete 0.5.0 train.
- ACL and rate-limit enforcement currently protects the native ZigMV path; legacy compatibility listeners remain separate migration surfaces.

## [0.4.0] - 2026-08-17

### Added

- Native `ZMV/1` protocol foundation with canonical subject routing.
- `live` and `work` delivery profiles.
- Durable delivery IDs, local stream append, consumer ACK removal, and bounded expiry metadata.
- Retained `state` profile with immediate delivery to matching state subscribers.
- ZigMV smoke coverage for live, work, durable, ACK, and state behavior.
- Grouped 0.4.0 release notes and capability roadmap.

### Changed

- README and protocol documentation now describe 0.4.0 as the grouped foundation/durable/state train.
- The existing ZMP, custom, NATS, and MQTT surfaces remain available for compatibility.

### Known limitations

- Automatic retry/redelivery after disconnect or process restart is not yet complete; the current retry loop is limited to the connected client session.
- Persistent offline sessions, replicated streams, native TLS, clustering, and exactly-once delivery remain future release-train work.
- `exact` remains disabled until deduplication and crash-recovery guarantees are proven.

## [0.2.0-beta.1] - 2026-08-16

### Added

- Native ZMP/1 protocol foundation for cloud, IoT, and edge messaging.
- Adaptive Delivery Routing terminology and canonical delivery-profile model.
- `live`, `work`, `durable`, `state`, and `exact` profile definitions.
- Native ZMP parser, encoder, control commands, and protocol tests.
- ZMP publish/fan-out benchmark harness.
- `zigmq --version` output.
- Refreshed zigmq logo and simpler getting-started documentation.

### Changed

- README rewritten as an open-source project guide.
- Release documentation now states implemented behavior and beta limitations explicitly.
- Existing custom, NATS-compatible, and MQTT-compatible surfaces are documented as compatibility paths rather than the native protocol design.

### Known limitations

- Only the ZMP `live` profile is implemented in this beta.
- Native TLS, full MQTT 5.0 conformance, full NATS compatibility, durable consumer offsets, ACK/retry recovery, clustering, and exactly-once delivery are not yet implemented.

[0.2.0-beta.1]: https://github.com/sudo-su-coffee/zigmq/releases/tag/v0.2.0-beta.1
