# ZigMV beta.1 to v1.0.0 Transition Review

**Review date:** 2026-08-18
**Candidate:** `zigmq 1.0.0-beta.1`
**PR:** [#36](https://github.com/sudo-su-coffee/zigmq/pull/36)
**Reviewed commit:** `95d6b28a71580434ce4364fdd7f98b6609d2f600`

## Executive assessment

The repository is **implementation-complete for the currently advertised ZigMV beta scope and CI-green on the reviewed PR commit**, but it is not yet defensibly ready for a stable `v1.0.0` tag. The remaining work is principally release evidence, explicit guarantee boundaries, and approval hygiene rather than another broad protocol rewrite.

The stable release must not claim MQTT 5.0 completeness, MQTT QoS 2, full NATS JetStream semantics, distributed durable replication, exactly-once delivery, or ZigMV `exact`. These remain non-claims unless new implementation and conformance evidence are deliberately added.

## Current evidence already present

| Area | Current evidence | Assessment |
| --- | --- | --- |
| Native ZigMV broker path | Unit, native smoke, and end-to-end tests | Present |
| Plain edge forwarding | LINK integration and broker bridge tests | Present |
| TLS/mTLS | Listener, certificate verification, and secure edge bridge tests | Present for the implemented transport scope |
| Authentication and ACLs | Security hardening tests, bounded pre-auth behavior, subject controls, rate limits | Present |
| Durable local behavior | Journal recovery and opt-in durable-session tests | Present locally; not distributed replication |
| Fuzz robustness | 250 deterministic seeded protocol-survival cases | Present, but not a statistical fuzzing campaign |
| Failure injection | Abrupt termination and torn-journal recovery | Present; disk-full and broader fault matrix remain |
| Cross-target builds | x86_64, ARM64 musl, ARMv7 musl | Passing on PR #36 |
| PR CI | Main test plus ARM64 and ARMv7 cross-target jobs | All passing on the reviewed commit |
| Artifacts | Release-safe binaries and SHA256SUMS | Present; final artifacts must be regenerated from the final tagged commit |
| Documentation links and metadata | Link checker, `--version`, release-gate checker, and diff check | Passing locally |

## Mandatory blockers before stable v1.0.0

### 1. Complete and freeze the release-gate policy

The project must decide which profiles and compatibility behaviors are actually advertised as stable. The evidence must be matched to those claims. At minimum, the final release notes should state stable support for the tested ZigMV profiles and explicitly mark MQTT QoS 2, full MQTT 5.0 interoperability, full JetStream, distributed replication, exactly-once delivery, and `exact` as unsupported.

This is a release-policy gate, not a request to implement every feature associated with MQTT or NATS.

### 2. Finish the operational performance matrix

The authoritative matrix requires metadata for each result: commit, Zig version, optimization mode, operating system, CPU, memory, payload, publishers, subscribers, profile, ACK mode, duration, and drain timeout. It also requires offered, accepted, queued, delivered, acknowledged, redelivered, expired, lost, duplicate, gap, out-of-order, backpressure, bytes/sec, CPU, memory, and p50/p95/p99/max latency.

The 100M messages/sec workload remains an offered-rate stress target, not a verified end-to-end delivery claim. Final results must separate offered rate from accepted and verified delivered rate, especially for bounded at-most-once overload workloads.

The required matrix includes payloads `0, 16, 32, 128, 1 KiB, 64 KiB`; publisher counts `1, 4, 16, 64`; subscriber counts `1, 10, 50, 100`; profiles `live, work, durable, state`; publisher-ACK and consumer-ACK modes; 10-second smoke, 60-second sustained, and 1-hour soak durations; and slow-consumer, disconnect, restart, full-queue, full-disk, and TCP-reset cases.

### 3. Run the hour-scale soak and preserve raw evidence

The current 10-second and prior 30-second bounded soaks are useful candidate evidence, but the authoritative gate calls for a one-hour soak. It must run on the final candidate commit, record the full delivery counters, remain bounded in memory, and distinguish lossless acknowledged modes from intentionally lossy at-most-once overload behavior.

Acceptance for a lossless acknowledged workload is `accepted == delivered == acknowledged`, with zero gaps, duplicates, invalid frames, and unexplained expiry.

### 4. Expand fault-injection coverage

The existing restart and torn-journal test is not enough for the final gate. Add or execute evidence for disk-full behavior and the broader matrix: disconnect, retry, duplicate-delivery handling, TCP reset, full queue, process restart, partial journal write, and recovery under bounded resources.

The expected behavior for each failure must be documented: reject, backpressure, expire, redeliver, reconnect, or fail closed. A disk-full condition must not silently convert a durable acceptance into an untracked success.

### 5. Close the security claim boundary

TLS/mTLS runtime validation is present. The remaining decision is whether credential rotation and identity-to-ACL mapping are advertised. If advertised, add deterministic tests for successful rotation, stale credential rejection, certificate/CA rotation behavior, identity-to-ACL enforcement, and failure without plaintext downgrade. If not advertised, document both as explicit non-claims in the stable security section and operations guide.

### 6. Complete release-document synchronization

The upgrade and rollback procedures, failure-semantics matrix, known limitations, benchmark interpretation, edge-link security behavior, and compatibility boundary must agree across `README.md`, `CHANGELOG.md`, `docs/ZIGMV_PROTOCOL.md`, `docs/ZIGMV_BETA_OPERATIONS.md`, `docs/ZIGMV_BETA_RELEASE_GATES.md`, and the release-readiness document.

Run the link checker and a stale-claim search after the final edits. The release notes must not describe planned or unsupported capabilities as implemented.

### 7. Rebuild final artifacts from one exact commit

After all code and documentation changes are merged, build Debug and ReleaseSafe/ReleaseFast artifacts for the supported targets, run the final checksums, verify the executable reports the intended stable version, and retain the raw manifests and CI URLs. Stable artifacts must be tied to the exact commit that passed CI; do not reuse beta.1 binaries.

### 8. Perform release approval and tag sequencing

The stable tag remains blocked until the selected gates above pass. The final sequence should be: merge PR #36, update the version to `1.0.0`, update changelog and known limitations, run the full release workflow on that exact commit, inspect all required job conclusions, generate final artifacts and checksums, obtain explicit release approval, create and push `v1.0.0`, and verify the GitHub release points at the tagged commit.

## Not required for v1.0.0 unless the scope changes

The following are not blockers when kept as explicit non-claims: MQTT QoS 2, full MQTT 5.0 interoperability, complete NATS JetStream semantics, distributed durable replication, exactly-once delivery, and ZigMV `exact`. Implementing those would be a separate post-1.0 protocol program and would require new compatibility, correctness, and failure evidence.

Likewise, a web management console is not required for the broker release. The broker must remain usable as a lightweight Zig executable on edge devices and remote servers.

## Final acceptance checklist

- [ ] Select and freeze stable advertised profiles and non-claims.
- [ ] Complete the required performance matrix with end-to-end counters and p50/p95/p99/max latency.
- [ ] Run and archive the one-hour soak on the final candidate commit.
- [ ] Add and pass disk-full and broader fault-matrix validation.
- [ ] Either test or explicitly disclaim credential rotation and identity-to-ACL mapping.
- [ ] Synchronize README, changelog, protocol, operations, gates, and readiness documents.
- [ ] Run documentation-link, stale-claim, metadata, and diff checks.
- [ ] Merge the PR and run final CI on the stable-version commit.
- [ ] Build final multi-target artifacts and regenerate SHA256SUMS.
- [ ] Obtain approval, create `v1.0.0`, and verify the release/tag/artifact alignment.

## Conclusion

The current candidate is best described as **CI-green beta.1 with implemented TLS/mTLS and authenticated edge-link foundations, awaiting final production evidence**. The remaining work is finite and well-defined. The highest-risk items are the one-hour soak, complete performance matrix, disk-full/fault evidence, and a clear decision on whether credential rotation and identity mapping are claims or non-claims.

The correct next milestone is not another minor version. It is a controlled release-evidence pass followed by a stable-tag decision.

## Authoritative repository references

- [`docs/ZIGMV_BETA_RELEASE_GATES.md`](ZIGMV_BETA_RELEASE_GATES.md)
- [`docs/V1_RELEASE_READINESS.md`](V1_RELEASE_READINESS.md)
- [`docs/ROADMAP_GAP_AUDIT.md`](ROADMAP_GAP_AUDIT.md)
- [`docs/ZIGMV_BETA_OPERATIONS.md`](ZIGMV_BETA_OPERATIONS.md)
- [`scripts/release_gate_check.py`](../scripts/release_gate_check.py)
- [`scripts/protocol_fuzz_test.py`](../scripts/protocol_fuzz_test.py)
- [`scripts/failure_injection_test.py`](../scripts/failure_injection_test.py)
- [`scripts/secure_edge_bridge_test.py`](../scripts/secure_edge_bridge_test.py)
