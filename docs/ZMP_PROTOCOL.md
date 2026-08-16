# ZMP: Zig Message Protocol

## Purpose

ZMP is zigmq’s lightweight unified protocol for cloud services, IoT devices, and edge gateways. It combines fast subject-based messaging, request/reply-oriented operations, consumer-style delivery modes, retained state, and explicit acknowledgement semantics in one compact protocol.

ZMP is intentionally separate from zigkv’s Redis-compatible data API. zigkv is the key-value and collection store; zigmq is the message transport, routing, delivery, and optional stream system. Existing NATS and MQTT listeners remain compatibility surfaces, but ZMP is the native protocol for new clients.

## Transport and framing

The initial transport is TCP. Frames are line-oriented at the header level and use CRLF termination. Publish payloads are binary-safe and length-delimited.

```text
ZMP/1 COMMAND [arguments]\r\n
[payload bytes]\r\n
```

The maximum subject is 256 bytes and the maximum payload is 64 KiB in the current implementation. A future binary frame can preserve the same logical fields while reducing parsing and allocation overhead.

## Commands

| Command | Form | Purpose |
| --- | --- | --- |
| `HELLO` | `ZMP/1 HELLO` | Capability or readiness handshake |
| `PING` | `ZMP/1 PING` | Liveness check |
| `PONG` | `ZMP/1 PONG` | Liveness response |
| `SUB` | `ZMP/1 SUB <mode> <subject>` | Subscribe to a subject or wildcard |
| `UNSUB` | `ZMP/1 UNSUB <mode> <subject>` | Remove a subscription |
| `PUB` | `ZMP/1 PUB <mode> <id> <subject> <length>` | Publish a binary payload |
| `ACK` | `ZMP/1 ACK <id>` | Acknowledge a message or publish identifier |
| `BYE` | `ZMP/1 BYE` | Graceful disconnect |

Subjects use dot-separated tokens in the native protocol. `*` matches one token and `>` matches the remaining suffix. The adapter layer may translate MQTT slash-separated filters into canonical ZMP subjects.

## Delivery modes

| Mode | Contract | Status |
| --- | --- | --- |
| `fast` | Volatile, low-latency, at-most-once delivery to current subscribers | Implemented in v0.2.0 |
| `acked` | At-least-once delivery backed by a durable stream, acknowledgement, expiry, and redelivery | Staged; requires durable consumer state |
| `exact` | Deduplicated durable delivery with crash-safe producer and consumer state | Future; not promised by v0.2.0 |

The protocol exposes these modes explicitly so applications do not confuse a fast live event with a durable command. A broker may reject `acked` or `exact` when the required storage mode is not enabled.

## Examples

Subscribe to live telemetry:

```text
ZMP/1 SUB fast factory.line1.temperature\r\n
ZMP/1 OK SUB\r\n
```

Publish a four-byte payload:

```text
ZMP/1 PUB fast 42 factory.line1.temperature 4\r\ndata\r\n
ZMP/1 OK PUB 42\r\n
```

Publish using the staged durable mode when a stream is enabled:

```text
ZMP/1 PUB acked 43 factory.line1.command 5\r\nSTART\r\n
ZMP/1 ACK 43\r\n
```

## Design boundary

ZMP owns connection state, authentication, authorization, routing, delivery, backpressure, optional persistence, replay, and metrics. Application services own business actions. A device command can be carried by ZMP, but zigmq must not decide whether an order, payment, ride, or trade is valid.

## Compatibility direction

The project should provide small compatibility adapters rather than duplicate broker engines:

```text
NATS client  ─┐
MQTT client  ─┼─> protocol adapter ─> shared zigmq routing/storage engine
ZMP client   ─┘
```

New applications should use ZMP when they control both ends and want one API. Existing devices and services can continue using MQTT or NATS while migrating gradually.
