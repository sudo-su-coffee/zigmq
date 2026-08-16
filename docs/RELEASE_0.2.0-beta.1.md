# zigmq 0.2.0-beta.1

**Status:** beta pre-release

**Tag:** `v0.2.0-beta.1`

**Protocol:** ZMP/1

**Language:** Zig 0.15.2

## What is new

This release introduces the first native slice of **ZMP (Zig Message Protocol)**. ZMP is a new unified protocol inspired by NATS and MQTT 5.0, designed to provide one lightweight message model for cloud services, IoT devices, and edge gateways.

The protocol uses **Adaptive Delivery Routing (ADR)**: one canonical message envelope, one subject space, one authorization/routing path, and explicit delivery profiles. The current beta implements the `live` profile for bounded, low-latency, at-most-once delivery.

The release also adds a native ZMP parser and encoder, ZMP-framed subscriber delivery, protocol unit tests, a reproducible publish/fan-out benchmark, a `--version` command, a refreshed project logo, and simpler user documentation.

## Quick start

```sh
git clone https://github.com/sudo-su-coffee/zigmq.git
cd zigmq
zig build -Doptimize=ReleaseFast
./zig-out/bin/zigmq --version
./zig-out/bin/zigmq --protocol zmp --port 4222
```

## Current ZMP example

```text
ZMP/1 SUB live sensors.room1.temperature\r\n
ZMP/1 PUB live 1 sensors.room1.temperature 4\r\n
21.5\r\n
```

## Compatibility

The custom, NATS-compatible, and MQTT-compatible listeners remain available. They are compatibility surfaces and are not claims of complete NATS or MQTT 5.0 conformance. New applications that control both client and server can begin with ZMP/1.

## Known limitations

The beta does not yet provide native TLS, full MQTT 5.0 conformance, full NATS compatibility, persistent MQTT sessions, durable ZMP consumer offsets, ACK/retry redelivery, retained ZMP state, replicated streams, clustering, or exactly-once delivery. The `work`, `durable`, `state`, and `exact` profiles are specified but rejected until their complete correctness and recovery tests exist.

The existing local stream is an append-only replay foundation. It does not provide replication, compaction, transactions, or a distributed consumer protocol.

## Validation

The release candidate must pass:

```sh
zig build test
python3 scripts/e2e_test.py --binary ./zig-out/bin/zigmq
python3 scripts/edge_features_test.py --binary ./zig-out/bin/zigmq
python3 scripts/stream_test.py --binary ./zig-out/bin/zigmq
python3 scripts/cli_test.py --binary ./zig-out/bin/zigmq
python3 scripts/python_ffi_test.py
python3 scripts/security_hardening_test.py --binary ./zig-out/bin/zigmq
```

Benchmark live ZMP traffic with:

```sh
python3 scripts/benchmark_zmp.py --messages 10000 --subscribers 10 --payload-size 128
```

Record the environment with every benchmark result. Throughput and latency depend on hardware, operating system, payload size, subscriber count, optimization mode, and network topology.

## Upgrade guidance

This is a new beta protocol release. Existing custom, NATS-compatible, and MQTT-compatible clients should continue using their current protocol listeners. ZMP clients should treat the `live` profile as the only stable profile in this release and should not depend on future `work`, `durable`, `state`, or `exact` behavior.

## Next steps

The next releases will implement work-group selection, retained state, native TLS and authorization, durable ACK/retry recovery, compatibility adapters mapped into the canonical envelope, edge links, and eventually event-driven I/O and binary framing.
