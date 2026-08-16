# zigmq

**zigmq** is a compact, learning-focused TCP publish/subscribe broker written in Zig. It is designed for small edge devices and direct local deployments where a simple in-memory broker is more useful than a large messaging stack.

> zigmq is intentionally smaller than NATS. It is suitable for learning, experiments, and lightweight edge workloads. Use NATS when you need mature clustering, persistence, security, monitoring, and a broad client ecosystem.

## Features

| Capability | Behavior |
| --- | --- |
| Transport | TCP over IPv4 |
| Default address | `127.0.0.1:4222` |
| Custom commands | `SUB`, `UNSUB`, `PUB`, `AUTH`, `PING`, `PONG`, `HELP`, `QUIT` |
| Wildcards | `*` matches one subject token; `>` matches the remaining suffix |
| Delivery | In-memory at-most-once fan-out |
| Backpressure | 32 queued messages or 256 KiB per client, then slow clients are disconnected |
| Authentication | Optional shared token using `--auth-token` |
| NATS mode | Small subset: `INFO`, `CONNECT`, `PUB`, `SUB`, `UNSUB`, `MSG`, `PING`, `PONG` |
| Persistence | None |
| Zig version | 0.15.2 |

## Build and test

Install Zig 0.15.2, then run:

```sh
zig build test
zig build
python3 scripts/e2e_test.py --binary ./zig-out/bin/zigmq
```

The repository also runs these checks in GitHub Actions for pushes and pull requests targeting `main`.

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

Queue groups, headers, request/reply routing, JetStream, clustering, and the rest of the NATS protocol are not implemented. The custom protocol remains the simplest option for direct edge use.

## Limits and delivery model

The broker limits control lines to 1 KiB, topics to 256 bytes, payloads to 64 KiB, and each client queue to 32 messages or 256 KiB. Publishers enqueue copies of messages instead of writing directly to subscriber sockets, so a slow client does not hold the broker routing lock. When a client exceeds its queue bound, zigmq disconnects it rather than growing memory without limit.

Delivery is in-memory and at-most-once. There is no persistence, replay, acknowledgment, or retry queue. Restarting the process loses subscriptions and queued messages.

## Measured baseline

The repository includes `scripts/benchmark.py` for repeatable local measurements. On the development sandbox, with Zig 0.15.2, a Debug build, 12-byte payloads, and one subscriber, the broker measured approximately **17,500-18,500 publish acknowledgments per second** and **9,600-9,850 delivered fan-out messages per second**. A 100,000-message run completed successfully; that means 100,000 messages is a reasonable test volume, not that the broker supports 100,000 messages per second.

The one-thread-per-client design held **1,000 idle TCP clients** on the test host, with sequential connection establishment around 98 clients per second. This is not a target for 100,000 concurrent clients. For a small edge device, start with a design budget of roughly 1,000-5,000 messages per second and tens to hundreds of active clients until the actual hardware, payload size, subscriber count, socket limits, and network are benchmarked. The bounded queues protect memory by disconnecting slow consumers rather than allowing unbounded growth.

Run the local benchmark with:

```sh
python3 scripts/benchmark.py --binary ./zig-out/bin/zigmq --messages 10000 --clients 100
```

These figures are host-specific measurements, not performance guarantees. Larger payloads, multiple subscribers, authentication, TLS, storage, and constrained CPUs will reduce throughput.

## Project structure

| Path | Purpose |
| --- | --- |
| `src/root.zig` | Subject validation, wildcard matching, command parsing, and parser tests |
| `src/main.zig` | TCP listener, client queues, routing, authentication, shutdown, and NATS subset |
| `scripts/e2e_test.py` | Automated custom, authentication, wildcard, NATS, and shutdown tests |
| `scripts/benchmark.py` | Local throughput and client-capacity benchmark |
| `benchmark_results.md` | Recorded sandbox baseline and interpretation |
| `.github/workflows/ci.yml` | Zig 0.15.2 build and integration-test workflow |
| `build.zig` | Zig build graph and test steps |
| `build.zig.zon` | Package metadata with minimum Zig version pinned to 0.15.2 |

## License

MIT. See [LICENSE](LICENSE).
