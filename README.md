# zigmq / ZigMV

<p align="center">
  <img src="assets/zigmq-logo.svg" alt="zigmq logo" width="180">
</p>

<p align="center"><strong>One lightweight message protocol for services, IoT, and edge systems.</strong></p>

<p align="center">
  <a href="https://github.com/sudo-su-coffee/zigmq/actions/workflows/ci.yml"><img src="https://github.com/sudo-su-coffee/zigmq/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/sudo-su-coffee/zigmq/releases"><img src="https://img.shields.io/github/v/release/sudo-su-coffee/zigmq?include_prereleases" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/sudo-su-coffee/zigmq" alt="License"></a>
</p>

**zigmq** is a small TCP message broker written in Zig. The `0.2.0-beta.1` release introduces **ZMP (Zig Message Protocol)**, a new unified protocol inspired by the useful parts of NATS and MQTT 5.0.

ZMP is one protocol and one message model. It is designed for backend services, sensors, gateways, and edge applications without requiring separate protocol clients in the native path. Existing custom, NATS-compatible, and MQTT-compatible listeners remain available for migration and interoperability.

> This is a beta release. The current native ZMP implementation provides the `live` profile. Durable delivery, retained state, work groups, and stronger recovery are specified and staged for later releases.

## Why zigmq?

| Need | zigmq approach |
| --- | --- |
| Cloud service events | Fast publish/subscribe and request/reply patterns |
| IoT and edge devices | Small protocol, bounded resources, reconnect-friendly design |
| Work distribution | Consumer-group profile planned in the same message model |
| Durable messages | Optional local stream and planned ACK/retry state machine |
| Simple deployment | One small binary, no external runtime dependency |
| Existing clients | Custom, NATS-compatible, and MQTT-compatible surfaces |
| Product boundary | Messaging only; `zigkv` remains the Redis-compatible data store |

## Install

### Download a beta binary

Open the [0.2.0-beta.1 release](https://github.com/sudo-su-coffee/zigmq/releases/tag/v0.2.0-beta.1) and download the archive for your platform when available.

### Build from source

Install [Zig 0.15.2](https://ziglang.org/download/) and clone the repository:

```sh
git clone https://github.com/sudo-su-coffee/zigmq.git
cd zigmq
zig build -Doptimize=ReleaseFast
```

The binary is created at `zig-out/bin/zigmq`.

## Quick start

Start the default custom-protocol server:

```sh
zig build run
```

The default listener is `127.0.0.1:4222`. To expose it on another address:

```sh
zig build run -- --host 0.0.0.0 --port 4222
```

Check the build version and help:

```sh
zig build run -- --version
zig build run -- --help
```

The server prints `zigmq 0.2.0-beta.1` for the version command.

## Native ZMP

Start the native unified protocol:

```sh
zig build run -- --protocol zmp --port 4222
```

ZMP uses one canonical subject space and explicit delivery profiles:

| Profile | Current status | Intended use |
| --- | --- | --- |
| `live` | Implemented | Low-latency, volatile, at-most-once delivery |
| `work` | Planned | One-of-N consumer-group delivery |
| `durable` | Planned | ACK, retry, expiry, and restart recovery |
| `state` | Planned | Retained last-value device state |
| `exact` | Planned | Deduplicated durable delivery after crash testing |

Subscribe and publish with the current `live` profile:

```text
ZMP/1 SUB live sensors.room1.temperature\r\n
ZMP/1 OK SUB\r\n

ZMP/1 PUB live 1 sensors.room1.temperature 4\r\n
21.5\r\n
ZMP/1 OK PUB 1\r\n
```

ZMP is specified in [`docs/ZMP_PROTOCOL.md`](docs/ZMP_PROTOCOL.md). The routing design is called **Adaptive Delivery Routing (ADR)**: normalize one message, authorize it, match subscriptions once, then apply the selected delivery profile without a NATS-to-MQTT bridge in the hot path.

## Existing protocol surfaces

The existing listeners are useful when integrating current applications:

| Protocol | Start command | Intended clients |
| --- | --- | --- |
| Custom | `zig build run -- --protocol custom` | zigmq examples and simple scripts |
| NATS-compatible | `zig build run -- --protocol nats` | Small NATS-style service clients |
| MQTT-compatible | `zig build run -- --protocol mqtt --port 1883` | MQTT device and gateway clients |
| ZMP | `zig build run -- --protocol zmp` | New unified cloud/IoT/edge clients |

The compatibility listeners are intentionally smaller than full NATS or MQTT 5.0 implementations. ZMP is the new native protocol direction; compatibility support is maintained separately so it does not make the core message path unnecessarily complex.

## Custom protocol example

```text
SUB sensors.*\r\n
+OK SUB\r\n
PUB sensors.room1 21.5 C\r\n
+OK PUB\r\n
MSG sensors.room1 6\r\n
21.5 C\r\n
PING\r\n
PONG\r\n
```

The custom protocol uses `*` for one subject token and `>` for the remaining suffix. It also supports retained values, consumer groups, request/reply, authentication, and explicit stream replay.

## Durable local stream

Enable the optional append-only local stream:

```sh
zig build run -- --stream ./data/events.zmq
```

The stream is a local append-only log. It is useful for replay and experimentation, but the beta release does not claim replicated storage, consumer offsets, compaction, transactions, or exactly-once delivery.

## Authentication and limits

For a small trusted deployment, use a token file:

```sh
zig build run -- --auth-token-file ./data/zigmq.token
```

The beta has bounded resources to protect small edge systems: 1,024 clients, 1,024 subscriptions per client, eight unauthenticated commands, and bounded per-client queues. The current TCP transport is plaintext; put it behind a protected network or TLS-terminating proxy until native TLS is added.

## Tests

Run the Zig unit tests:

```sh
zig build test
```

Run the repository integration checks:

```sh
python3 scripts/e2e_test.py --binary ./zig-out/bin/zigmq
python3 scripts/edge_features_test.py --binary ./zig-out/bin/zigmq
python3 scripts/stream_test.py --binary ./zig-out/bin/zigmq
python3 scripts/cli_test.py --binary ./zig-out/bin/zigmq
python3 scripts/python_ffi_test.py
python3 scripts/security_hardening_test.py --binary ./zig-out/bin/zigmq
```

## Benchmarks

Start a ZMP-compatible server and measure live publish acknowledgements and fan-out delivery:

```sh
zig build run -- --protocol zigmv --port 4222
python3 scripts/benchmark_zmp.py --messages 10000 --subscribers 10 --payload-size 128 --pipeline 1 --ack-publishes
```

That command measures acknowledged publish throughput. For NATS-like one-way live telemetry, omit publisher acknowledgements:

```sh
python3 scripts/benchmark_zmp.py --messages 10000 --subscribers 10 --payload-size 128 --pipeline 1
```

Use `--ack-publishes` when you want the acknowledged comparison. Run the matrix with payload sizes of 16, 128, and 1,024 bytes and subscriber counts of 1, 10, and 50. Record the commit, Zig version, optimization mode, CPU, memory, operating system, publish mode, publish rate, delivery rate, and latency. Benchmark numbers are machine-specific and are not performance guarantees.

## Try ZigMV

Start the native unified protocol listener:

```sh
zig build run -- --protocol zigmv --host 127.0.0.1 --port 4222
```

A live subscription and no-ack telemetry publish look like this:

```text
ZMV/1 SUB live sensors.room1.temperature
ZMV/1 PUB live - sensors.room1.temperature 4
21.5
```

A work group uses one shared group name. Each message is delivered to one eligible worker:

```text
ZMV/1 SUB work jobs.created workers
ZMV/1 PUB work 42 jobs.created 5
hello
```

The `0.4.0` ZigMV train enables `live`, `work`, `durable`, and `state`. `exact` remains disabled until deduplication and crash-recovery guarantees are complete.

## ZigMV direction

The next protocol generation is **ZigMV**: one lightweight message protocol and one Adaptive Delivery and Transfer algorithm for cloud services, IoT devices, and edge gateways. It combines NATS-like low-latency subjects, request/reply, and work sharing with MQTT-like device sessions, retained state, expiry, and stronger delivery profiles. It is a new protocol, not two protocol implementations joined by a bridge.

The `0.4.0` release combines the ZMV/1 foundation, `live`, `work`, durable delivery, ACK handling, durable stream append, retained state, expiry metadata, and the first persistent delivery state. Later trains will add security/edge compatibility, operations/scaling, exact delivery/clustering, and final hardening before `1.0.0-beta`.

The project boundaries remain intentional. `zigkv` owns Redis-compatible data structures; `nammapush-rs` owns notification delivery and provider fallback; zigmq/ZigMV owns transport, routing, delivery state, and edge messaging.

Read the design first: [`docs/ZIGMV_PROTOCOL.md`](docs/ZIGMV_PROTOCOL.md).

## Documentation

| Document | Purpose |
| --- | --- |
| [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md) | Short installation and first-message guide |
| [`docs/ZMP_PROTOCOL.md`](docs/ZMP_PROTOCOL.md) | ZMP beta wire format and semantics |
| [`docs/ZIGMV_PROTOCOL.md`](docs/ZIGMV_PROTOCOL.md) | ZigMV protocol, ADT algorithm, transfer model, and release gates |
| [`docs/ZMP_V0.2.0_PLAN.md`](docs/ZMP_V0.2.0_PLAN.md) | ZMP beta roadmap and staged delivery profiles |
| [`docs/ZIGMV_RELEASE_PLAN.md`](docs/ZIGMV_RELEASE_PLAN.md) | ZigMV 0.3.0 and 1.0.0-beta release gates |
| [`docs/ZIGMV_ROADMAP.md`](docs/ZIGMV_ROADMAP.md) | Grouped release trains from 0.4.0 to 1.0.0-beta |
| [`docs/ZMP_LIVE_TEST_PLAN.md`](docs/ZMP_LIVE_TEST_PLAN.md) | Live-profile acceptance gates and test matrix |
| [`docs/ZMP_LIVE_BENCHMARK_2026-08-16.md`](docs/ZMP_LIVE_BENCHMARK_2026-08-16.md) | Recorded beta benchmark results and gate decision |
| [`docs/RELEASE_0.2.0-beta.1.md`](docs/RELEASE_0.2.0-beta.1.md) | Previous beta release notes and known limitations |
| [`docs/RELEASE_0.4.0.md`](docs/RELEASE_0.4.0.md) | Grouped 0.4.0 ZigMV release notes and guarantees |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Contribution and test workflow |

## Project structure

```text
src/main.zig       broker, listeners, and CLI
src/root.zig       shared limits, parser helpers, and version
src/zmp.zig        ZMP parser, encoder, and compatibility tests
src/zigmv_state.zig ACK, retry, and deduplication state primitives
scripts/            integration tests and benchmarks
docs/               protocol, release, and user documentation
assets/             project branding
```

## Contributing

Create a branch, make a focused change, run `zig build test`, run the relevant integration tests, and include benchmark evidence for performance changes. Please do not claim a delivery guarantee until restart, backpressure, duplicate, expiry, and failure behavior are tested.

```sh
git checkout -b feat/your-change
zig build test
git diff --check
git commit -m "feat: describe the change"
```

## License

See [`LICENSE`](LICENSE).
