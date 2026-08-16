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
| Authentication | Optional shared token using `--auth-token`; constant-time comparison and bounded pre-auth commands |
| Safety limits | 1,024 clients, 1,024 subscriptions per client, 8 pre-auth commands per connection |
| Stream file security | Durable stream files are created and chmodded to owner-only `0600` permissions |
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
python3 scripts/security_hardening_test.py --binary ./zig-out/bin/zigmq
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

For deployments where the token should not appear in the process command line, store it in a protected file and use:

```sh
zig build run -- --auth-token-file ./data/zigmq.token
```

The file is trimmed for a final newline and loaded into memory only for the broker lifetime. Protect the file with owner-only permissions.

Clients must authenticate before using broker commands:

```text
AUTH edge-secret
+OK AUTH
```

The token is intentionally simple and is not a replacement for TLS or a full identity system. The direct `--auth-token` form can be visible to local users through process inspection; prefer `--auth-token-file` for local deployments. Token comparison avoids an early-exit equality check, invalid NATS authorization closes the connection, and unauthenticated connections are bounded to eight commands. Do not expose this mode directly to an untrusted network without placing it behind an encrypted transport or trusted network boundary.

## Security and operational guardrails

The current edge-hardening branch adds explicit resource bounds: a maximum of 1,024 connected clients, 1,024 custom subscriptions per client, 1,024 NATS subscriptions per client, and eight commands before authentication. A client that exceeds its subscription or pre-auth budget receives an error or is closed; a client that exceeds its delivery queue is disconnected. These are protection limits, not capacity guarantees, and they can be changed as compile-time constants in `src/root.zig` after hardware testing.

The optional stream file is opened with an exclusive advisory lock and owner-only `0600` permissions. This protects the stream from ordinary local users, but it does not encrypt the file. Use filesystem encryption or a protected service account when stream payloads are sensitive. TCP transport is still plaintext until a TLS layer is added.

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

The broker limits control lines to 1 KiB, topics to 256 bytes, payloads to 64 KiB, each client queue to 32 messages or 256 KiB, connected clients to 1,024, and subscriptions to 1,024 per client. Publishers enqueue copies of messages instead of writing directly to subscriber sockets, so a slow client does not hold the broker routing lock. When a client exceeds its queue bound, zigmq disconnects it rather than growing memory without limit.

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

The latest saved ReleaseFast run completed the telemetry scenario at approximately 20,425 messages per second, the alert burst at approximately 18,253 events per second, and evenly distributed the 30-job consumer-group check as 10/10/10. These are workload-harness measurements on one sandbox, not service-level guarantees.

## Throughput optimization

The broker maintains an exact-subject subscriber index and compact wildcard subscription lists for both custom and NATS subscriptions. Exact publishes use hash-map lookup instead of scanning every client. The client output queue uses a bounded head-index queue, making dequeue amortized **O(1)** instead of shifting every pending message with `orderedRemove(0)`. A per-publish generation marker prevents duplicate custom delivery when one client matches both exact and wildcard subscriptions.

The latest ReleaseFast NATS-compatible run with 128-byte payloads measured approximately **12,279**, **7,303**, and **2,445 broker messages per second** for 1, 10, and 50 subscribers, respectively. The corresponding NATS v2.14.5 measurements were approximately **19,078**, **11,543**, and **3,854 messages per second**. This is still an honest gap, but it is an improvement over the earlier 10,837, 6,735, and 2,230 ZigMQ measurements for the same topology. See `optimization_results.md` for the before/after table and methodology.

The older custom-protocol routing comparison remains in `performance_results.md`. Further gains will likely require reducing per-message allocation and write syscall overhead, not simply adding more subject scans or features.

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
| `scripts/benchmark_modes.py` | Durable-stream versus memory-only publish benchmark |
| `scripts/compare_nats.py` | Controlled NATS-compatible comparison harness |
| `scripts/nats_index_test.py` | Exact-index, wildcard, unsubscribe, and disconnect regression test |
| `scripts/security_hardening_test.py` | Authentication, connection, subscription, and stream-permission regression test |
| `scripts/format_nats_matrix.py` | Reproducible formatter for raw comparison logs |
| `comparison_results.md` | Captured ZigMQ versus NATS matrix and interpretation |
| `optimization_results.md` | Before/after queue and NATS-index measurements |
| `benchmark_results.md` | Recorded sandbox baseline and interpretation |
| `performance_results.md` | Main-versus-optimized throughput comparison |
| `.github/workflows/ci.yml` | Zig 0.15.2 build and integration-test workflow |
| `.github/workflows/release.yml` | Manual-only semantic-version release workflow |
| `.github/scripts/generate-release-notes.sh` | Categorized changelog and custom-note generator |
| `build.zig` | Zig build graph and test steps |
| `build.zig.zon` | Package metadata with minimum Zig version pinned to 0.15.2 |

## Manual releases

Releases are intentionally **manual-only**. Merging a pull request or pushing to `main` runs CI but does not create a tag or GitHub release.

To publish a release, open the repository’s **Actions** tab, select the **Release** workflow, choose **Run workflow**, and provide:

| Input | Example | Meaning |
| --- | --- | --- |
| `version` | `v0.2.0` | New semantic-version release tag; it must not already exist |
| `target` | `main` | Branch or commit to validate and release |
| `prerelease` | `false` | Whether GitHub should mark the release as a prerelease |
| `custom_notes` | Optional Markdown | Maintainer notes inserted at the top of the release notes |

The workflow checks the version format, refuses an existing tag, runs `zig build test`, builds ReleaseFast, categorizes commits since the previous tag into features, fixes, performance, documentation, maintenance, breaking changes, and other changes, and then creates the GitHub release from the generated notes. Conventional commit prefixes such as `feat:`, `fix:`, `perf:`, and `docs:` are recognized. A `!` marker or `BREAKING CHANGE` text is placed in the breaking-changes section. The workflow requires repository contents write permission, so only maintainers with appropriate Actions permissions can publish a release.

## License

MIT. See [LICENSE](LICENSE).
