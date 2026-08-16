# zigmq

**zigmq** is a compact, learning-focused TCP publish/subscribe broker written entirely in Zig 0.15.2. It is designed for small edge devices and direct local deployments where a simple in-memory broker is more useful than a large messaging stack.

> zigmq is intentionally smaller than NATS. It is suitable for learning, experiments, and lightweight edge workloads. Use NATS when you need mature clustering, persistence, security, monitoring, and a broad client ecosystem.

## Features

| Capability | Behavior |
| --- | --- |
| Transport | TCP over IPv4 |
| Default address | `127.0.0.1:4222` |
| Custom commands | `SUB`, `UNSUB`, `PUB`, `RETAIN`, `REQ`, `REPLAY`, `AUTH`, `PING`, `PONG`, `HELP`, `QUIT` |
| Wildcards | `*` matches one subject token; `>` matches the remaining suffix |
| Retained state | One retained value per topic with optional millisecond TTL; delivered on a matching future `SUB` |
| Consumer groups | `SUB <subject> <group>` delivers each matching publish to one member of the group |
| Request/reply | `REQ <topic> <reply_subject> <payload>` preserves the reply subject in the `MSG` frame |
| Durable stream | Optional append-only local stream enabled with `--stream <path>` |
| Delivery | In-memory at-most-once fan-out; stream replay is explicit and local |
| Backpressure | 32 queued messages or 256 KiB per client, then slow clients are disconnected |
| Authentication | Optional shared token using `--auth-token` |
| NATS mode | Small subset: `INFO`, `CONNECT`, `PUB`, `SUB`, `UNSUB`, `MSG`, `PING`, `PONG` |
| CLI | Pure-Zig `server`, `pub`, `sub`, `ping`, `shell`, and `bench pub` commands |
| Embedding | `libzigmq_core.so` exports subject helpers, hashing, and frame encoding for the Python ctypes bridge |
| Dependencies | Pure Zig broker and library; no C files or headers |
| Zig version | 0.15.2 |

## Build and test

Install Zig 0.15.2, then run:

```sh
zig build test
zig build
python3 scripts/e2e_test.py --binary ./zig-out/bin/zigmq
python3 scripts/edge_features_test.py --binary ./zig-out/bin/zigmq
python3 scripts/stream_test.py --binary ./zig-out/bin/zigmq
python3 scripts/cli_test.py --binary ./zig-out/bin/zigmq
python3 scripts/python_ffi_test.py
```

The repository also runs the build, unit tests, and integration checks in GitHub Actions for pushes and pull requests targeting `main`.

## Run the custom protocol

```sh
zig build run
```

The server listens on `127.0.0.1:4222` by default. Configure the address and port with:

```sh
zig build run -- --host 0.0.0.0 --port 4222
```

A client receives `+OK zigmq ready` when authentication is disabled. Commands are line-oriented and terminate with `CRLF` or `LF`.

```text
SUB sensors.*
+OK SUB

PUB sensors.room1 21.5 C
+OK PUB

MSG sensors.room1 6
21.5 C

PING
PONG
```

A `*` wildcard matches exactly one dot-separated token. A `>` wildcard matches the remaining suffix and must be the final token. Publishing never accepts wildcards.

## Retained messages and TTL

`RETAIN` stores the latest value for a topic. The broker can deliver that value immediately after a later subscriber successfully subscribes to a matching subject.

```text
RETAIN state.device-7 5000 online
+OK RETAIN

SUB state.device-7
+OK SUB
MSG state.device-7 6
online
```

The TTL is expressed in milliseconds. A TTL of `0` means no expiration for the lifetime of the process. Retained values are memory-only and are not restored from the durable stream after a restart.

## Consumer groups

Add a group name to `SUB` when a workload needs one-of-N delivery rather than full fan-out:

```text
SUB jobs.image workers
+OK SUB
```

If three clients subscribe to `jobs.image workers`, each publish is delivered to one eligible member. Group subscriptions are separate from ordinary fan-out subscriptions. The selection is intentionally compact and deterministic for the current process; it is not a durable consumer offset or a clustered queue-group protocol.

## Request/reply

`REQ` publishes a message while carrying the reply subject in the delivered frame. The requestor should also subscribe to its reply subject:

```text
SUB rpc.reply.123
+OK SUB

REQ rpc.request rpc.reply.123 resize-image
+OK REQ
```

A service receives:

```text
MSG rpc.request rpc.reply.123 13
resize-image
```

The service can then publish to `rpc.reply.123`. Timeouts, retries, and request correlation are intentionally left to the client application.

## Durable local streams and replay

Enable the optional append-only stream with:

```sh
zig build run -- --stream ./data/events.zmq
```

Every custom-protocol publish and request is appended to the stream. The stream is a local binary log with a fixed **22-byte little-endian header** followed by topic and payload bytes:

| Header bytes | Field | Type |
| ---: | --- | --- |
| 0–7 | Sequence | `u64` |
| 8–15 | Timestamp in milliseconds | `u64` |
| 16–17 | Topic length | `u16` |
| 18–21 | Payload length | `u32` |

The sequence is recovered on startup by scanning existing records. Replay is explicit and does not alter live subscriptions:

```text
REPLAY 100 telemetry.>
+OK REPLAY
MSG telemetry.device-7 12
battery=82%
```

Replay requires the broker to have been started with `--stream`. The stream is intentionally minimal: there are no consumer offsets, compaction, replication, transactions, or retention policies beyond what the filesystem provides.

## Optional authentication

For a small trusted edge deployment, enable a shared token:

```sh
zig build run -- --auth-token edge-secret
```

Clients must authenticate before using broker commands:

```text
AUTH edge-secret
+OK AUTH
```

The token is intentionally simple and is not a replacement for TLS or a full identity system. Do not expose this mode directly to an untrusted network without placing it behind an encrypted transport or trusted network boundary.

## Graceful shutdown

The server handles `SIGINT` and `SIGTERM`. It stops accepting new clients, wakes active connections, joins client threads, releases queued messages, and exits cleanly. This makes it suitable for a small service manager or container lifecycle.

## NATS-compatible subset

Run the compact NATS mode with:

```sh
zig build run -- --protocol nats
```

The server sends an `INFO` frame and accepts a deliberately small subset of the NATS client protocol: `CONNECT`, `PUB`, `SUB`, `UNSUB`, `MSG`, `PING`, and `PONG`. NATS payloads use the normal byte-count form, for example:

```text
SUB sensors.* 1\r\n
PUB sensors.room1 5\r\n
hello\r\n
MSG sensors.room1 1 5\r\n
hello\r\n
```

The custom protocol remains the simplest option for retained messages, consumer groups, request/reply, and durable local replay. The NATS-compatible mode does not claim to implement queue groups, headers, JetStream, clustering, or the rest of the NATS protocol. See the [NATS protocol documentation](https://docs.nats.io/reference/reference-protocols/nats-protocol) for the full protocol surface.

## Limits and delivery model

The broker limits control lines to 1 KiB, topics to 256 bytes, payloads to 64 KiB, and each client queue to 32 messages or 256 KiB. Publishers enqueue copies of messages instead of writing directly to subscriber sockets, so a slow client does not hold the broker routing lock. When a client exceeds its queue bound, zigmq disconnects it rather than growing memory without limit.

Live delivery is at-most-once and memory-only. The optional stream is an append-only local record of custom publishes and requests, and replay is an explicit operation. There is no replication, acknowledgment protocol, retry queue, or clustered failover. Restarting without `--stream` loses subscriptions, retained values, and queued messages; starting with `--stream` restores only stream sequence state and makes prior records replayable.

## Measured baseline

The repository includes `scripts/benchmark.py` for repeatable local measurements. On the development sandbox, with Zig 0.15.2, a Debug build, 12-byte payloads, and one subscriber, the broker measured approximately **17,500–18,500 publish acknowledgments per second** and **9,600–9,850 delivered fan-out messages per second**. A 100,000-message run completed successfully; that means 100,000 messages is a reasonable test volume, not that the broker supports 100,000 messages per second.

The one-thread-per-client design held **1,000 idle TCP clients** on the test host, with sequential connection establishment around 98 clients per second. This is not a target for 100,000 concurrent clients. For a small edge device, start with a design budget of roughly 1,000–5,000 messages per second and tens to hundreds of active clients until the actual hardware, payload size, subscriber count, socket limits, and network are benchmarked. The bounded queues protect memory by disconnecting slow consumers rather than allowing unbounded growth.

Run the local benchmark with:

```sh
python3 scripts/benchmark.py --binary ./zig-out/bin/zigmq --messages 10000 --clients 100
```

These figures are host-specific measurements, not performance guarantees. Larger payloads, multiple subscribers, authentication, TLS, storage, and constrained CPUs will reduce throughput.

## Honest NATS comparison

`scripts/compare_nats.py` runs the same publish-and-drain workload against ZigMQ's NATS-compatible mode and NATS server v2.14.5. It uses the same localhost TCP topology, payload bytes, message count, subscriber count, and delivery completion rule for both brokers.

The captured matrix used 1,000 messages, payload sizes of 16, 128, and 1,024 bytes, and 1, 10, and 50 subscribers. ZigMQ reached approximately **42–85% of NATS's publish-message rate** across those cases. NATS was faster overall, especially with one subscriber and larger payloads, while ZigMQ remained competitive in the 10-subscriber 128-byte case. The detailed table and raw log are in [`comparison_results.md`](comparison_results.md) and `benchmark_runs/nats_matrix.jsonl`.

These are comparative localhost measurements, not guarantees. The project goal is not to beat NATS. The comparison makes the trade-off visible: NATS provides a mature, highly optimized ecosystem; zigmq provides a small pure-Zig implementation that is easy to read, modify, embed, and benchmark on edge hardware.

Run a single comparison case with:

```sh
python3 scripts/compare_nats.py --zigmq ./zig-out/bin/zigmq --messages 1000 --subscribers 10 --payload-size 128
```

## Real-time workload simulations

The repository includes `scripts/realtime_scenarios.py`, which verifies six practical edge patterns against the custom protocol:

| Scenario | Workload or assertion |
| --- | --- |
| Telemetry | 100 device connections, 10 readings each, 128-byte readings, 1,000 total messages |
| Command/control | 100 device subscriptions and one command for each device |
| Alert burst | 1,000 alert events drained by a wildcard subscriber |
| Request/reply timeout | A successful service exchange plus a missing-service timeout |
| Retained reconnect | State retained before disconnect and received after a new subscription |
| Consumer group | 30 jobs divided across three `workers` members without duplication |

Run the scenarios with:

```sh
python3 scripts/realtime_scenarios.py --binary ./zig-out/bin/zigmq
```

The latest saved ReleaseFast run completed the telemetry scenario at approximately 11,944 messages per second, the alert burst at approximately 14,372 events per second, and evenly distributed the 30-job consumer-group check as 10/10/10. These are workload-harness measurements on one sandbox, not service-level guarantees.

## Throughput optimization

The broker maintains an exact-subject subscriber index and a compact wildcard subscription list. Publishing now looks up exact subscribers directly instead of scanning every connected client and every subscription. A per-publish generation marker also prevents duplicate delivery when the same client matches both an exact and wildcard subscription.

On the same ReleaseFast localhost benchmark, the indexed routing branch measured approximately **23,200 publish acknowledgments per second** and **14,100 one-subscriber fan-out messages per second**, compared with a clean-main repeat baseline of approximately **18,700** and **12,000**, respectively. With 50 subscribers and 1,000 messages, broker throughput improved from approximately **1,723** to **1,785 messages per second** while total deliveries improved from approximately **86,145** to **89,266 deliveries per second**. See `performance_results.md` for the exact runs.

For multi-subscriber testing, run:

```sh
python3 scripts/benchmark_fanout.py --binary ./zig-out/bin/zigmq --subscribers 50 --messages 1000
```

## Project structure

| Path | Purpose |
| --- | --- |
| `src/root.zig` | Subject validation, wildcard matching, command parsing, and parser tests |
| `src/main.zig` | TCP listener, client queues, routing, retained state, groups, streams, authentication, shutdown, and NATS subset |
| `src/client.zig` | Reusable pure-Zig TCP client used by the CLI |
| `src/cli.zig` | Pure-Zig command-line operations for server, pub, sub, ping, shell, and benchmarks |
| `src/lib.zig` | Shared-library exports for embedding and Python ctypes |
| `python/zigmq/__init__.py` | Header-free Python ctypes bridge to `libzigmq_core.so` |
| `scripts/e2e_test.py` | Automated custom, authentication, wildcard, NATS, and shutdown tests |
| `scripts/edge_features_test.py` | Retained messages, consumer groups, and request/reply integration test |
| `scripts/stream_test.py` | Durable stream append, restart sequence recovery, and replay test |
| `scripts/realtime_scenarios.py` | Telemetry, control, burst, RPC, retained reconnect, and group simulations |
| `scripts/benchmark.py` | Local throughput and client-capacity benchmark |
| `scripts/benchmark_fanout.py` | Multi-subscriber routing benchmark |
| `scripts/compare_nats.py` | Controlled NATS-compatible comparison harness |
| `scripts/format_nats_matrix.py` | Reproducible formatter for raw comparison logs |
| `comparison_results.md` | Captured ZigMQ versus NATS matrix and interpretation |
| `benchmark_results.md` | Recorded sandbox baseline and interpretation |
| `performance_results.md` | Main-versus-optimized throughput comparison |
| `.github/workflows/ci.yml` | Zig 0.15.2 build and integration-test workflow |
| `build.zig` | Zig build graph and test steps |
| `build.zig.zon` | Package metadata with minimum Zig version pinned to 0.15.2 |

## License

MIT. See [LICENSE](LICENSE).
