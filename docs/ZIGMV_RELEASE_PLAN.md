# ZigMV release plan

## 0.3.0 — protocol foundation

The 0.3.0 release is an implementation release, not a promise that every delivery profile is complete.

| Area | 0.3.0 gate |
| --- | --- |
| Naming | `ZMV/1` handshake and capability response are defined |
| Core envelope | One canonical subject, message ID, payload, profile, expiry, reply, and correlation model |
| Live | Volatile at-most-once delivery, bounded queues, no-ack telemetry, publish acknowledgement option |
| Work | One-of-N group selection with deterministic group membership and disconnect recovery |
| Parser | Partial reads, binary payload lengths, malformed input, limits, and unsupported profiles tested |
| Security | Existing token/TLS path documented; subject authorization design frozen |
| Edge | Transfer envelope and bounded outbound-link design documented; implementation may remain staged |
| Compatibility | Existing NATS/MQTT surfaces remain separate compatibility paths and do not define ZigMV semantics |
| Benchmarks | Reproducible live and work benchmark matrix with recorded hardware and commit |

## 1.0.0-beta — production candidate

The 1.0.0-beta release requires evidence for every advertised guarantee.

| Area | 1.0.0-beta gate |
| --- | --- |
| Durable | Append-only log, checksum, restart recovery, retention, ACK, retry, expiry, and replay |
| State | Retained last-value state, expiry, reconnect behavior, size limits, and deletion |
| Exact | Durable producer/consumer deduplication, idempotency window, crash tests, and duplicate tests |
| Edge transfer | TLS/mTLS link, export/import filters, reconnect backoff, cursor transfer, bounded queue, lag metrics |
| Security | TLS, mTLS option, identity-to-ACL mapping, subject permissions, rate limits, credential rotation |
| Operations | Metrics, structured logs, health/readiness endpoints, resource and disk limits |
| Compatibility | Conformance tests for supported NATS and MQTT 5.0 adapter behavior |
| Reliability | Failure injection for process restart, disk-full, partial write, disconnect, retry, and duplicate delivery |
| Performance | p50/p95/p99 latency, throughput, memory per connection, fan-out, edge-link lag, and slow-consumer behavior |
| Documentation | Stable wire grammar, client examples, upgrade guide, failure semantics, and security model |

## Implementation order

The work must proceed in dependency order. First stabilize the envelope and parser, then implement `live`, then `work`, then durable storage and `durable`, then `state`, and finally `exact`. Edge transfer and compatibility adapters should use the same envelope and should not duplicate routing or persistence logic.

No release may enable a profile only because its command parses. A profile is enabled only after its state machine, failure behavior, metrics, resource limits, and tests are present.

## Release commands

The release workflow should build and test the selected main commit, verify the embedded version with `--version`, package the Linux binary and checksum, generate categorized notes, and mark `0.3.0` or `1.0.0-beta.1` appropriately. A release tag must point to the exact CI-tested commit.
