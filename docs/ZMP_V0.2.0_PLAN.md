# ZMP v0.2.0 Release Plan

## Release objective

Release the first usable slice of ZMP as a lightweight unified protocol for cloud services, IoT devices, and edge gateways. The release must be honest about what is implemented: fast volatile delivery is the primary capability, while durable acknowledgement and exactly-once behavior remain staged behind explicit roadmap gates.

## Scope for v0.2.0

| Area | v0.2.0 target |
| --- | --- |
| Wire protocol | `ZMP/1` CRLF headers and length-delimited payloads |
| Commands | `HELLO`, `PING`, `PONG`, `SUB`, `UNSUB`, `PUB`, `ACK`, `BYE` |
| Routing | Exact subjects, `*`, and `>` wildcard subscriptions |
| Delivery | `fast` mode with bounded per-client queues |
| Safety | Subject and payload limits, malformed-frame rejection |
| Integration | `--protocol zmp` server mode |
| Tests | Parser, encoder, malformed input, end-to-end publish/subscribe |
| Benchmarks | Publish acknowledgements, fan-out, connection churn, payload-size matrix |
| Documentation | Protocol specification, examples, limits, benchmark methodology |

## Explicitly outside v0.2.0

The release must not claim complete MQTT 5.0, complete NATS compatibility, QoS 1/2, persistent MQTT sessions, exactly-once delivery, TLS, multi-node replication, or production-grade clustered failover. These are planned capabilities with separate acceptance criteria.

## Implementation phases

### Phase A: protocol correctness

Keep the grammar small and deterministic. Reject unknown commands, invalid delivery modes, missing fields, invalid numeric identifiers, oversized subjects, oversized payloads, and mismatched payload lengths. Keep parser tests independent of sockets.

### Phase B: fast broker path

Route ZMP subscriptions through the existing bounded queue and subject index. Avoid creating a second routing implementation. Preserve the current slow-consumer policy and report queue overflow through a protocol error or disconnect.

### Phase C: durable acknowledged path

Reuse the append-only stream for `acked` messages, but add consumer sequence state, acknowledgement deadlines, redelivery, expiry, and crash recovery before calling it at-least-once. A stream append by itself is not a complete acknowledgement protocol.

### Phase D: device and edge features

Add session identifiers, session expiry, retained last-value state, Will messages, reconnect recovery, receive limits, and optional outbound edge links. Keep device state bounded by account, client, topic, byte, and expiry limits.

### Phase E: compatibility adapters

Add small mappings for MQTT 5.0 clients and NATS clients. Both adapters must call the same internal publish, subscribe, acknowledgement, and storage interfaces. Do not fork the routing or persistence engine.

## Benchmark matrix

All benchmark runs must record the commit, Zig version, optimization mode, CPU, RAM, OS, payload size, number of publishers, subscribers, fan-out factor, persistence mode, and authentication mode.

| Benchmark | Variables | Measurements |
| --- | --- | --- |
| Publish acknowledgement | 1, 10, 100 concurrent publishers; 16/128/1024-byte payloads | messages/sec, p50/p95/p99 latency, errors |
| Fan-out | 1/10/50/100 subscribers | deliveries/sec, broker CPU, per-client queue depth |
| Connection churn | 100/1,000/5,000 connects and disconnects | connects/sec, memory, failed handshakes |
| Wildcard routing | exact, one-level, multi-level, mixed filters | routing latency and CPU |
| Slow consumer | one blocked subscriber with active publishers | memory bound, dropped/disconnected clients, publish latency |
| Durable append | stream disabled/enabled | throughput, append latency, fsync latency |
| Recovery | restart during publish and replay | recovered sequence, lost messages, duplicate messages |
| Edge profile | small payloads, intermittent reconnects, limited subscribers | reconnect time, retained state recovery, memory |

The benchmark must distinguish **publish acknowledgements** from **delivered messages**. A successful publisher response alone does not prove that all subscribers received a message.

## Suggested acceptance gates

| Gate | Requirement |
| --- | --- |
| Build | `zig build` succeeds with Zig 0.15.2 |
| Unit tests | ZMP parser/encoder and existing tests pass |
| Protocol safety | Malformed frames never crash the broker or allocate unbounded memory |
| Fast throughput | Baseline is reported on the same host and workload before optimization claims |
| Backpressure | Slow clients cannot grow memory without bound |
| Recovery | Durable mode is not advertised until restart and replay tests pass |
| Compatibility | Existing custom, NATS, MQTT, and CLI tests remain green |
| Documentation | Every implemented command and limitation is documented |
| Release | Version, changelog, benchmark output, and known limitations are published |

## Version sequence after v0.2.0

| Version | Focus |
| --- | --- |
| `0.2.0` | ZMP grammar, fast mode, protocol tests, initial benchmark harness |
| `0.3.0` | TLS, subject ACLs, rate limits, better observability |
| `0.4.0` | Durable `acked` mode, consumer offsets, redelivery, expiry |
| `0.5.0` | Sessions, retained state improvements, reconnect recovery, MQTT 5 mapping |
| `0.6.0` | Request/reply correlation, shared consumer groups, edge links |
| `0.7.0` | Binary framing, batching, event-driven I/O, memory-per-connection reduction |
| `1.0.0` | Stable protocol, compatibility guarantees, operational and recovery hardening |

## Release checklist

Before tagging v0.2.0, run formatting, unit tests, build tests, existing integration tests, the ZMP end-to-end test, and the benchmark matrix. Save machine-readable benchmark results under `benchmark_runs/` and summarize the environment and limitations in the README. Do not compare results with NATS or MQTT without matching payloads, subscriber counts, completion rules, and persistence settings.
