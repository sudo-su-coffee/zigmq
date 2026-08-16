# zigmq

**zigmq** is a lightweight, learning-focused and edge-oriented TCP publish/subscribe broker written in Zig. It provides a deliberately small line protocol so the core ideas of networking, concurrency, topic routing, and fan-out remain easy to inspect.

> zigmq is not intended to replace NATS in production. Use NATS when you need mature security, persistence, clustering, monitoring, and a large client ecosystem.

## Current MVP

The broker accepts multiple TCP clients and starts one thread per connection. A client can subscribe to a topic, publish a line-oriented payload, unsubscribe, check liveness, request help, or disconnect. Every connected subscriber of a topic receives a copy of each published message.

| Capability | MVP behavior |
| --- | --- |
| Transport | TCP over IPv4 |
| Default address | `127.0.0.1:4222` |
| Commands | `SUB`, `UNSUB`, `PUB`, `PING`, `PONG`, `HELP`, `QUIT` |
| Delivery | At-most-once in-memory fan-out |
| Persistence | None |
| Authentication | None |
| Topic characters | Letters, numbers, `.`, `-`, `_` |
| Maximum topic length | 256 bytes |
| Maximum payload length | 64 KiB |
| Zig version | 0.15.2 |

## Build

Install Zig 0.15.2, then run:

```sh
zig build
zig build test
```

The executable is written to `zig-out/bin/zigmq`.

## Run

Start the broker with the defaults:

```sh
zig build run
```

Or select an address and port:

```sh
zig build run -- --host 0.0.0.0 --port 4222
```

The server prints a startup message and waits for TCP clients.

## Protocol

Each command is terminated by `CRLF` or `LF`. The payload of `PUB` is the remainder of the line after the topic, so the current MVP is intended for text payloads without embedded newlines.

```text
SUB sensors.room1
+OK SUB

PUB sensors.room1 21.5 C
+OK PUB

MSG sensors.room1 8
21.5 C

UNSUB sensors.room1
+OK UNSUB

PING
PONG
```

A new client receives:

```text
+OK zigmq ready
```

`HELP` returns the supported commands. `QUIT` returns `+OK BYE` and closes the connection. Invalid commands receive an `-ERR` response. Duplicate subscriptions are harmless and return a positive acknowledgment.

## Quick manual test

With the server running, open two terminals. In terminal one, connect and subscribe:

```sh
telnet 127.0.0.1 4222
SUB demo
```

In terminal two, connect and publish:

```sh
telnet 127.0.0.1 4222
PUB demo hello from zigmq
```

The first terminal receives a `MSG demo ...` frame containing the payload.

## Project structure

| Path | Purpose |
| --- | --- |
| `src/root.zig` | Command types, validation, parser, and parser tests |
| `src/main.zig` | TCP listener, client threads, topic registry, fan-out, and CLI |
| `build.zig` | Zig build graph and test steps |
| `build.zig.zon` | Package metadata with minimum Zig version pinned to 0.15.2 |

## Deliberate non-goals for this MVP

This first version does not implement authentication, TLS, persistence, wildcard topics, request/reply, queue groups, clustering, backpressure queues, or the complete NATS wire protocol. Those features should be added only after the small core is understood and covered by integration tests.

## Roadmap

The next useful steps are to add socket-level integration tests, wildcard topic matching, configurable limits, graceful shutdown, metrics, and an optional NATS-compatible protocol mode. The NATS-compatible mode should be treated as a separate milestone because existing NATS clients expect a richer protocol than this learning protocol.

## License

MIT. See [LICENSE](LICENSE).
