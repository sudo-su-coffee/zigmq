# Contributing to zigmq

Thank you for helping improve zigmq. The project is written in Zig and aims to stay small, understandable, and useful on cloud, IoT, and edge systems.

## Before changing code

Read the [README](README.md), the [ZigMV protocol specification](docs/ZIGMV_PROTOCOL.md), the [ZigMV roadmap](docs/ZIGMV_ROADMAP.md), and the [benchmark evidence](docs/ZIGMV_BENCHMARK_0.5.0.md). Keep `zigkv` separate: zigmq is a message broker, not a Redis-compatible data store.

## Development workflow

```sh
git checkout -b feat/your-change
zig build test
git diff --check
```

Run the relevant integration tests before opening a pull request:

```sh
python3 scripts/e2e_test.py --binary ./zig-out/bin/zigmq
python3 scripts/edge_features_test.py --binary ./zig-out/bin/zigmq
python3 scripts/stream_test.py --binary ./zig-out/bin/zigmq
python3 scripts/cli_test.py --binary ./zig-out/bin/zigmq
python3 scripts/security_hardening_test.py --binary ./zig-out/bin/zigmq
```

Performance changes must include a reproducible benchmark command and environment details. Do not report a throughput number without recording the commit, Zig version, optimization mode, payload size, subscriber count, and machine details.

## Protocol changes

ZigMV changes must update the wire specification, parser tests, error behavior, and README usage examples. A new delivery guarantee must not be advertised until it has tests for backpressure, disconnects, restart recovery, duplicates, expiry, and acknowledgement behavior.

Compatibility changes must preserve the existing custom, NATS-compatible, and MQTT-compatible surfaces unless the pull request explicitly documents a breaking change.

## Pull requests

Use a focused conventional commit such as `feat:`, `fix:`, `perf:`, `docs:`, or `test:`. Explain the behavior change, test commands, benchmark evidence when relevant, and any known limitation. Keep generated or unrelated changes out of the pull request.

CI runs the Zig build and repository tests. A pull request should be green before merge.
