# ZMP: Zig Message Protocol

## Purpose

ZMP is one new lightweight protocol for cloud services, IoT devices, and edge gateways. It combines selected strengths of NATS and MQTT 5.0 without requiring clients to choose between two semantic systems. The protocol has one wire grammar, one canonical message envelope, one routing algorithm, and one delivery state machine.

ZMP is not Redis-compatible. `zigkv` owns Redis-compatible key-value, list, hash, and set behavior. zigmq owns transport, routing, delivery, optional streams, retained state, and edge messaging.

## Adaptive Delivery Routing

The central algorithm is **Adaptive Delivery Routing (ADR)**. Each publish is normalized, authorized, matched, and represented by one immutable envelope. The broker then chooses the minimum work required by the selected delivery profile:

```text
input frame
  -> normalize canonical subject
  -> authenticate and authorize
  -> resolve delivery profile
  -> match exact/wildcard/group subscriptions once
  -> construct one message envelope
  -> live route to ready consumers
  -> durable append only for durable profiles
  -> maintain per-consumer cursor/ACK/retry state
```

ADR is intended to avoid copying the message once for every protocol implementation or running an NATS-to-MQTT bridge inside the hot path. Protocol compatibility adapters can map existing clients into the same envelope later, but ZMP itself is the native unified protocol.

## Canonical message envelope

```text
Message {
    message_id
    subject
    payload
    headers/properties
    delivery_profile
    expiry
    retained/state flag
    reply_to
    correlation_id
    stream_sequence
}
```

The envelope is designed to represent both service traffic and device traffic. A request/reply service uses `reply_to` and `correlation_id`; a device uses expiry, retained state, session identity, and a delivery profile; a durable consumer uses `stream_sequence` and acknowledgement state.

## Delivery profiles

| Profile | Semantics | Primary use |
| --- | --- | --- |
| `live` | At-most-once, volatile, current subscribers only | Telemetry and low-latency events |
| `work` | One eligible consumer per group | Service workers and command processing |
| `durable` | At-least-once, stream-backed, ACK/retry/expiry | Important commands and notifications |
| `state` | Retained last value with expiry | Device and edge state |
| `exact` | Future deduplicated durable mode | Transactions requiring stronger guarantees |

The v0.2.0 implementation exposes the frame grammar and the `live` slice. It must reject profiles that are not implemented rather than pretending a publisher acknowledgement is the same as consumer acknowledgement.

## Wire grammar

The initial transport is TCP. Frames are line-oriented at the header level and use CRLF termination. Publish payloads are binary-safe and length-delimited.

```text
ZMP/1 COMMAND [arguments]\r\n
[payload bytes]\r\n
```

Initial commands:

| Command | Form | Purpose |
| --- | --- | --- |
| `HELLO` | `ZMP/1 HELLO` | Capability/readiness handshake |
| `PING` | `ZMP/1 PING` | Liveness check |
| `PONG` | `ZMP/1 PONG` | Liveness response |
| `SUB` | `ZMP/1 SUB <profile> <subject>` | Subscribe with one delivery profile |
| `UNSUB` | `ZMP/1 UNSUB <profile> <subject>` | Remove a subscription |
| `PUB` | `ZMP/1 PUB <profile> <id> <subject> <length>` | Publish a binary payload; use `-` as the id for live no-ack delivery |
| `ACK` | `ZMP/1 ACK <id>` | Acknowledge a durable delivery when supported |
| `BYE` | `ZMP/1 BYE` | Graceful disconnect |

Subjects are canonical dot-separated names. `*` matches one token and `>` matches the remaining suffix. MQTT slash-separated topics can be mapped at an external compatibility boundary, but the ZMP core uses one subject grammar.

## Examples

Live telemetry:

```text
ZMP/1 SUB live factory.line1.temperature\r\n
ZMP/1 OK SUB\r\n
```

Live publish with an application-visible publish acknowledgement:

```text
ZMP/1 PUB live 42 factory.line1.temperature 4\r\ndata\r\n
ZMP/1 OK PUB 42\r\n
```

Live publish without a publish acknowledgement, intended for high-rate telemetry:

```text
ZMP/1 PUB live - factory.line1.temperature 4\r\ndata\r\n
```

The `-` identifier removes only the publisher acknowledgement. It does not change the live profile into durable delivery and does not create consumer acknowledgement state.

A staged profile is rejected until its state machine is implemented:

```text
ZMP/1 PUB durable 43 factory.line1.command 5\r\nSTART\r\n
ZMP/1 ERR profile_not_implemented\r\n
```

## Compatibility direction

Existing NATS and MQTT listeners are compatibility surfaces, not separate implementations of the new algorithm. The long-term structure is:

```text
NATS adapter ─┐
MQTT adapter ─┼─> canonical ZMP envelope -> ADR -> routing/storage
ZMP client  ──┘
```

New clients should use ZMP when they control both ends. Existing MQTT 5.0 and NATS clients can be supported through thin adapters after the canonical semantics are stable.

## Correctness and safety rules

A broker must reject unknown profiles, malformed lengths, oversized subjects, oversized payloads, invalid wildcard placement, duplicate subscription identifiers, and unsupported properties. Delivery acknowledgements must only be returned for the guarantee actually provided. Backpressure must remain bounded per consumer, and durable state must not be claimed until restart, redelivery, expiry, and duplicate handling tests pass.
