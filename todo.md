# ZigMV Native 1.0.0-Beta Workstream

## Portability and builds

- [ ] Define supported Linux targets for x86_64, aarch64, and armv7 and add reproducible Zig build commands.
- [ ] Verify ReleaseSafe and ReleaseFast builds on the supported target matrix.
- [ ] Document Raspberry Pi deployment, system service limits, storage, and upgrade/rollback procedure.

## Edge resource behavior

- [ ] Make client, subscription, payload, mailbox, durable backlog, and journal limits explicit and configurable.
- [ ] Add low-memory admission behavior and metrics for rejected clients, queue pressure, dropped live messages, and backpressure.
- [ ] Add payload-size and topic-length validation tests across profiles.

## Security

- [ ] Define secure-by-default bind/authentication behavior for local and remote deployments.
- [ ] Add TLS/mTLS transport integration or clearly gate it before beta release.
- [ ] Verify ACL, tenant isolation, credential rotation, and management endpoint exposure rules.

## Reliability and edge links

- [ ] Integrate durable-session recovery with restart and power-loss-style failure tests.
- [ ] Integrate cursor-aware edge forwarding with reconnect, duplicate, gap, and bounded offline behavior.
- [ ] Add journal compaction/checkpoint behavior and disk-full handling.

## AI and application events

- [ ] Keep application payloads opaque bytes with content type, schema ID, correlation ID, reply subject, and trace metadata.
- [ ] Add documented patterns for telemetry, commands, inference requests, inference results, and model/version events.
- [ ] Do not place model inference or heavyweight serialization in the broker hot path.

## Performance and validation

- [ ] Run payload-size, publisher/subscriber, profile, fan-out, reconnect, and sustained soak benchmark matrices.
- [ ] Record accepted, delivered, acknowledged, redelivered, loss, duplicate, gap, latency, CPU, RSS, and queue pressure metrics.
- [ ] Add cross-target smoke tests and release artifact checksum verification.

## Release

- [ ] Synchronize version metadata, changelog, README, Mintlify docs, release notes, and beta gate checker.
- [ ] Run the complete CI, security, recovery, benchmark, soak, and packaging workflow.
- [ ] Create a 1.0.0-beta tag only when all advertised gates pass; otherwise publish an accurately labeled development release.
