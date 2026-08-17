# ZigMV Roadmap and 1.0.0-beta Gap Audit

## Executive result

The roadmap does **not** require publishing every internal number from `0.3.0` through `0.15.0`. Those numbers are planning milestones grouped into public release trains. The planned public sequence is `0.4.0`, `0.5.0`, `0.6.0`, `0.7.0`, `0.8.0`, and then `1.0.0-beta.1`.

The current repository is at the **`1.0.0-beta.1` candidate metadata level**, with a batched candidate commit and passing local core, TLS/mTLS, edge, compatibility-smoke, deterministic hostile-input, deterministic fuzz-survival, failure-injection recovery, longer soak, cross-target, artifact-checksum, and release-metadata checks. It is not yet equivalent to a final stable `v1.0.0` release because the authoritative gates still require complete CI evidence and several stronger claims are intentionally not advertised.

## Version count and grouping

| Category | Versions | Meaning | Current interpretation |
| --- | --- | --- | --- |
| Internal foundation | `0.3.0` | Protocol foundation | Implemented through later grouped trains. |
| Public train | `0.4.0` | ZMV/1 foundation, live/work, durable append, ACKs, state, expiry | Implemented baseline. |
| Public train | `0.5.0` | Authentication, ACLs, limits, durable retry, edge and compatibility foundations | Implemented in parts; the current candidate adds live secure transport and integrated links. |
| Public train | `0.6.0` | Metrics, health, operations, performance and resource controls | Implemented baseline and retained as historical development notes. |
| Public train | `0.7.0` | Exact-delivery and replication/failover foundations | Partial foundations only; full distributed claims are not advertised. |
| Public train | `0.8.0` | Conformance, fuzzing, hardening, upgrade/rollback and stabilization | Partially covered by current validators; full conformance and failure evidence remain gates. |
| Internal hardening | `0.9.0`–`0.15.0` | Performance, protocol hardening, conformance, security review, soak, SLO and release-candidate work | These are not separate required public tags; their gates must be satisfied or explicitly scoped before beta approval. |
| Beta release | `1.0.0-beta.1` | Verified candidate with signed/reproducible artifacts and documented guarantees | Candidate prepared; final CI and remaining evidence are still required. |

Therefore, there are **six public release stages including the beta** after the foundation (`0.4.0`, `0.5.0`, `0.6.0`, `0.7.0`, `0.8.0`, and `1.0.0-beta.1`), not thirteen mandatory public versions.

## Completed in the current candidate

The code now includes native `live`, `work`, `durable`, and `state` profiles; bounded queues; ACK and duplicate-ID handling; checksummed journal persistence and compaction; metrics, health/readiness, tenant and subject controls; authenticated inbound and outbound LINK sessions; cursor and loop handling; a shared plain/TLS transport; live TLS/mTLS listener support; certificate rejection and acceptance tests; secure two-broker edge forwarding; MQTT and NATS compatibility smoke gates; hostile-input resilience; CI workflow gates; Linux x86_64, ARM64, and ARMv7 ReleaseSafe artifacts; checksums; and beta metadata.

## Remaining work before a defensible beta approval

| Gate | What is still needed | Current state |
| --- | --- | --- |
| CI/CD | Run the updated workflow on the exact candidate commit and retain the result | Workflow updated; local equivalent passes, remote CI result still required. |
| Benchmark matrix | Complete payload/profile/ACK/fan-out matrix with hardware, latency and memory fields | Bounded acknowledged modes and soak evidence exist; the matrix contains known no-ACK overload failures and needs a policy-compliant final run/report. |
| Soak | Longer-duration soak than the local 10-second run | 30-second bounded soak passes with zero loss at the selected workload; an hour-scale soak remains for the strongest gate. |
| Fuzzing | Actual fuzz/property campaign, not only deterministic hostile-input cases | Deterministic seeded survival gate passes for 250 cases; this is robustness evidence, not a statistical fuzz campaign. |
| Failure injection | Restart, partial journal write, disk-full, disconnect, retry and duplicate-delivery scenarios | Deterministic abrupt-termination plus torn-journal restart gate passes; disk-full and broader fault matrix remain. |
| Compatibility | Full supported-scope MQTT 5.0 and NATS semantic matrix | MQTT and NATS smoke/index tests pass; full MQTT 5.0 and JetStream parity are not implemented and must remain non-claims unless the scope is explicitly narrowed. |
| Security | Credential rotation and identity-to-ACL mapping evidence | Token, ACL, rate, TLS and mTLS gates pass; rotation and identity mapping need explicit coverage or documented non-claims. |
| Operations | p50/p95/p99 latency, memory-per-connection, edge lag and slow-consumer evidence | Throughput and bounded queue evidence exist; the complete operational performance matrix is incomplete. |
| Documentation | Upgrade guide, rollback procedure, stable failure-semantics matrix, and link validation | Readiness and changelog documents exist; these final release documents and link checks need completion. |
| Stable tag | Exact CI-tested commit, release approval, final artifacts and tag | Must remain blocked until the above selected gates pass. |

## Code changes needed next

The remaining implementation is primarily **validation infrastructure and release evidence**, not another large protocol rewrite. The immediate remaining tasks are to complete the policy-compliant benchmark matrix with metadata and classification of at-most-once overload versus lossless ACK workloads; add disk-full and broader fault cases; run an hour-scale soak and CI on the candidate commit; add credential rotation and identity-to-ACL tests if those features are advertised; and complete the missing release documents and link checks. Unsupported MQTT QoS 2, full NATS JetStream, distributed replication, and exactly-once delivery must remain explicit non-claims rather than being marked complete by documentation alone.

## Release decision

The candidate is **beta-preparation ready**, not yet stable-`v1.0.0` ready. The planned public version count is not the blocker. The blocker is evidence completeness: CI on the candidate commit, complete benchmark policy, longer soak, fuzzing, failure injection, documentation checks, and release approval. No stable `v1.0.0` tag should be created before those checks pass.
