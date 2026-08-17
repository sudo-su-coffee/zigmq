# Changelog

All notable changes to zigmq are documented here.

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

- Automatic retry/redelivery after disconnect or process restart is not yet complete.
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
