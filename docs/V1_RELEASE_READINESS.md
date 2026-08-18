# ZigMV 1.0.0-beta.1 Release Readiness

## Candidate

The current candidate is `zigmq 1.0.0-beta.1`, built with Zig 0.15.2. The repository now contains a shared plain/TLS transport adapter, live TLS listener handshakes, certificate-based client authentication, outbound TLS edge-link sessions, and automated runtime gates.

## Verified locally

| Gate | Result | Evidence |
| --- | --- | --- |
| Zig unit tests | Pass | `zig build test` |
| ReleaseSafe native build | Pass | `zig build -Doptimize=ReleaseSafe` |
| ReleaseFast native build | Pass | `zig build -Doptimize=ReleaseFast` |
| ARM64 musl ReleaseSafe/ReleaseFast | Pass | cross-target build run |
| ARMv7 musl ReleaseSafe/ReleaseFast | Pass | cross-target build run |
| Native ZigMV smoke and end-to-end | Pass | `scripts/zigmv_test.py`, `scripts/e2e_test.py` |
| Security hardening | Pass | `scripts/security_hardening_test.py` |
| Persistent session recovery | Pass | `scripts/session_recovery_test.py` |
| Plain broker edge LINK | Pass | `scripts/edge_link_integration_test.py`, `scripts/edge_broker_bridge_test.py` |
| TLS/mTLS listener | Pass | `scripts/tls_mtls_test.py` |
| TLS/mTLS secure edge bridge | Pass | `scripts/secure_edge_bridge_test.py` |
| MQTT compatibility smoke | Pass | `scripts/mqtt_compat_test.py` |
| NATS index compatibility regression | Pass | `scripts/nats_index_test.py` |
| 10-second bounded soak | Pass | `benchmark_runs/1.0.0-beta.1/soak.json` |
| Metadata checker | Pass | `scripts/release_gate_check.py --expected-version 1.0.0-beta.1` |
| Diff consistency | Pass | `git diff --check` |

The soak run delivered 98,557 of 98,557 messages with zero gaps, duplicates, invalid frames, or loss at the selected workload. The acknowledged benchmark modes recorded approximately 26,634.2 publish-ACK messages per second without local stream persistence and 6,043.7 with local stream persistence on the development host. These numbers are machine-specific evidence, not universal capacity guarantees.

## Remaining release conditions

The public release gate still requires the complete benchmark matrix, longer soak duration, fuzzing and failure-injection evidence, documentation-link validation, artifact checksums, and CI execution on the final commit. The current matrix also correctly exposes that at-most-once no-ACK overload can lose messages or fail its synchronization deadline; those workloads must remain labeled as offered-rate or lossy stress results and must not be advertised as lossless delivery.

The beta candidate does not claim full MQTT 5.0 interoperability, full NATS JetStream semantics, MQTT QoS 2 parity, distributed replication, or exactly-once delivery. A final stable `v1.0.0` tag must not be created until the project’s selected compatibility and reliability claims have corresponding passing evidence.
