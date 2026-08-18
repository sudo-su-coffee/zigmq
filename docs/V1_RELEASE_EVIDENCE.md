# ZigMV v1.0.0 Release Evidence Record

**Candidate:** `zigmq 1.0.0-beta.1`
**Local evidence commit:** `0e21c2b` plus uncommitted validation harness/evidence files
**Toolchain:** Zig 0.15.2

## Completed evidence in the current local pass

| Gate | Result | Evidence |
| --- | --- | --- |
| Unit tests | Pass | `zig build test` |
| Documentation links | Pass | `python3 scripts/check_docs_links.py` |
| Beta metadata | Pass | `scripts/release_gate_check.py --expected-version 1.0.0-beta.1` |
| Stable preflight structure | Pass for beta metadata | `scripts/stable_release_preflight.py --expected-version 1.0.0-beta.1` |
| Disk-full durable failure | Pass | `DISK_FULL_FAIL_CLOSED_PASS` |
| Torn-journal recovery | Pass | `FAILURE_INJECTION_RECOVERY_PASS` |
| Deterministic protocol fuzz survival | Pass for the existing seeded gate | 250-case CI/local gate |
| Acknowledged benchmark matrix | Pass | Six payload sizes, 100 messages each, zero failures; metadata includes commit, Zig version, optimization, OS, CPU, child CPU time, and maximum RSS |
| Sustained 60-second soak | Pass | 440,966 offered, accepted, and delivered; zero loss, gaps, duplicates, or invalid frames; approximately 7,349 delivered messages/sec |
| Fault matrix | Pass | Disconnect, TCP reset, and slow-consumer boundedness/backpressure cases |
| Candidate artifacts | Built | x86_64 ReleaseSafe/ReleaseFast, ARM64 ReleaseSafe, ARMv7 ReleaseSafe, with `SHA256SUMS` |
| Artifact version | Pass | Candidate binaries report `zigmq 1.0.0-beta.1` |

## One-hour soak

A one-hour acknowledged soak is running separately under `scripts/soak_test.py` with output at `benchmark_runs/1.0.0-beta.1/soak-1h.json`. It must complete before the strongest stable-release reliability claim is approved. Until that file contains a successful result, the one-hour gate remains open.

## Stable non-claims

The stable release must continue to state that MQTT QoS 2, full MQTT 5.0 interoperability, complete NATS JetStream semantics, distributed durable replication, exactly-once delivery, and ZigMV `exact` are unsupported. Credential rotation and identity-to-ACL mapping must either receive dedicated evidence or remain explicit non-claims.

## Final external sequence

After the one-hour soak completes and the final candidate files are committed, run CI on the exact release commit, merge the remaining documentation/CI PR if still open, update version metadata to `1.0.0`, regenerate final artifacts and checksums, run the stable preflight, obtain release approval, create `v1.0.0`, and verify tag, release, binaries, and checksums all reference the same commit.
