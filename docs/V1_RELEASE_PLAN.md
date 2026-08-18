# ZigMV v1.0.0 Completion Plan

This is the final four-plan sequence for moving the current `1.0.0-beta.1` candidate to a defensible stable `v1.0.0` release. The plans are ordered and cumulative; a later plan must not silently override an earlier gate.

## Plan 1 — Stabilize the baseline and CI

The repository baseline is the merged `main` candidate with native ZigMV, authenticated edge LINK sessions, TLS/mTLS transport, journal recovery, bounded queues, release metadata, and the three stacked PR layers merged. The plan is complete only when the active release-candidate PR is CI-green, the working tree is understood, and the candidate version is consistent across source, changelog, release workflow, and documentation.

**Acceptance:** main test, ARM64, ARMv7, metadata, link, stale-claim, and diff checks pass on the exact candidate commit.

## Plan 2 — Close reliability, security, and evidence gates

Run the complete acknowledged benchmark matrix with payload, profile, subscriber, ACK, duration, CPU, RSS, latency, queue-pressure, and end-to-end delivery metadata. Complete the one-hour acknowledged soak. Run disk-full, torn-journal, disconnect, TCP-reset, slow-consumer, full-queue, restart, retry, and duplicate-delivery tests. Decide whether credential rotation and identity-to-ACL mapping are stable claims; otherwise retain them as explicit non-claims.

**Acceptance:** acknowledged workloads have zero unexplained loss, gaps, duplicates, invalid frames, or out-of-order deliveries; bounded lossy live workloads are labeled as such; every failure case has documented expected behavior.

## Plan 3 — Synchronize claims, documentation, and packaging

Align README, changelog, protocol, operations, docs-site, release notes, known limitations, benchmark interpretation, and release workflow. Keep MQTT QoS 2, full MQTT 5.0 interoperability, complete NATS JetStream semantics, distributed replication, exactly-once delivery, and ZigMV `exact` explicitly unsupported. Build ReleaseSafe/ReleaseFast artifacts for supported targets and generate SHA256SUMS from the exact candidate commit.

**Acceptance:** documentation-link, stale-claim, stable-release-preflight, version, checksum, and reproducibility checks pass; artifacts report the candidate version and are tied to one commit.

## Plan 4 — Final candidate and release decision

Run the final local suite and the final CI workflow on the exact release commit. Merge the release-candidate PR, update version metadata from `1.0.0-beta.1` to `1.0.0`, update release notes, regenerate artifacts and checksums, obtain explicit approval, create `v1.0.0`, and verify GitHub release/tag/artifact alignment.

**Acceptance:** every selected release gate is green, the stable tag references the CI-tested commit, artifacts reference the same commit, and the release notes contain no unsupported claims.

## Current status

Plans 1 and 3 are substantially implemented locally. The disk-full and fault-matrix gates, six-payload acknowledged matrix, 60-second sustained soak, artifact builds, checksums, release preflight, docs-site synchronization, and CI workflow integration are present. The one-hour soak remains time-based and is running separately. The complete operational matrix and final stable-version/tag sequence remain the last release decisions, not reasons to implement unsupported protocol features.
