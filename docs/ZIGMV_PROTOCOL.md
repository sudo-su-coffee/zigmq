# ZigMV Protocol

## Status

ZigMV is the planned native protocol for zigmq. It is a new unified protocol inspired by the useful parts of NATS and MQTT 5.0, but it is not a wire-compatible copy of either protocol and it is not Redis-compatible.

`zigkv` remains the Redis-compatible data store. `nammapush-rs` remains a notification-delivery service. ZigMV owns transport, routing, delivery state, edge transfer, and optional persistence.

## Product idea

> **One compact protocol for cloud services, IoT devices, and edge gateways, with a fast live path and optional stronger delivery guarantees without requiring separate client libraries or protocol bridges.**

ZigMV uses one canonical message envelope, one subject namespace, one authorization model, and one adaptive delivery algorithm. A cloud worker and a constrained sensor use the same logical operations even when their delivery guarantees are different.

## Adaptive Delivery and Transfer (ADT)

The core algorithm is **Adaptive Delivery and Transfer (ADT)**. It processes each publish once and selects the minimum state required by the requested profile.

```text
receive frame
  -> authenticate connection
  -> validate and normalize subject
  -> authorize publish
  -> resolve delivery profile
  -> match exact, wildcard, and group subscriptions once
  -> create one canonical envelope
  -> choose memory-only or durable transfer path
  -> enqueue to bounded consumer mailboxes
  -> update cursor, ACK, retry, state, or deduplication state as required
```

ADT is designed for edge links. A local edge broker can accept messages while disconnected, retain only the profiles configured for offline operation, and forward selected subjects to a remote broker after reconnect. The edge link must be bounded and must never allow an unavailable upstream broker to exhaust local memory.

## Canonical envelope

```text
Envelope {
    protocol_version
    message_id
    origin_id
    subject
    payload
    headers
    delivery_profile
    expiry_time
    reply_to
    correlation_id
    retained_state
    stream_sequence
    attempt
}
```

The envelope is independent of the client library. A service request uses `reply_to` and `correlation_id`; telemetry uses `live`; a command uses `work` or `durable`; a device state update uses `state`; a transaction may eventually use `exact`.

## Subjects

ZigMV uses canonical dot-separated subjects:

```text
site.factory.line1.temperature
site.factory.line1.robot.command
```

`*` matches one subject token. `>` matches the remaining suffix. MQTT slash-separated topic filters and NATS subjects can be translated by optional compatibility adapters, but the ZigMV core has one subject grammar.

## Delivery profiles

| Profile | Guarantee | Intended use | Required state |
| --- | --- | --- | --- |
| `live` | Volatile at-most-once to connected consumers | Telemetry and low-latency events | Bounded memory mailbox |
| `work` | One eligible consumer per group | Jobs, commands, service workers | Group cursor and ownership |
| `durable` | ACK-tracked delivery with bounded in-session redelivery, expiry, and local replay; disconnect persistence is not yet enabled | Important commands and notifications | Append log, pending delivery map, and retry timer |
| `state` | Last-value retained state with expiry | Device status and edge state | Subject state index and TTL |
| `exact` | Deduplicated durable delivery | Only after crash guarantees are proven | Durable producer and consumer deduplication |

A server must reject a profile that is not implemented. A publisher acknowledgement only confirms acceptance by the broker; it must never be described as consumer acknowledgement. The current durable retry loop redelivers unacknowledged messages while the original client session remains connected; pending entries are discarded on disconnect until durable client identity and session resume are implemented.

## Wire format

The initial transport is TCP. The header is ASCII and CRLF terminated. The payload is binary-safe and length-delimited.

```text
ZMV/1 COMMAND [arguments]\r\n
[payload bytes]\r\n
```

The protocol supports an optional no-ack live publish form for telemetry:

```text
ZMV/1 PUB live - site.factory.line1.temperature 4\r\ndata\r\n
```

An application-visible publish acknowledgement uses a message identifier:

```text
ZMV/1 PUB live 42 site.factory.line1.temperature 4\r\ndata\r\n
ZMV/1 OK PUB 42\r\n
```

The `-` identifier removes only the publisher response. It does not add persistence or consumer acknowledgement.

## Core commands

| Command | Form | Meaning |
| --- | --- | --- |
| `HELLO` | `ZMV/1 HELLO` | Negotiate capability and readiness |
| `PING` | `ZMV/1 PING` | Keepalive |
| `SUB` | `ZMV/1 SUB <profile> <subject> [group]` | Subscribe to a profile and subject |
| `UNSUB` | `ZMV/1 UNSUB <profile> <subject> [group]` | Remove a subscription |
| `PUB` | `ZMV/1 PUB <profile> <id> <subject> <length>` | Publish a binary payload |
| `ACK` | `ZMV/1 ACK <message_id>` | Confirm a durable consumer delivery |
| `CLAIM` | `ZMV/1 CLAIM <group> <message_id>` | Claim a work item when supported |
| `RESUME` | `ZMV/1 RESUME <consumer> <sequence>` | Resume a durable consumer |
| `BYE` | `ZMV/1 BYE` | Graceful disconnect |

## Transfer model

A ZigMV edge deployment has local and remote transfer paths:

```text
sensor / service
      |
      v
  local ZigMV broker
      |  live: immediate local routing
      |  work: one local worker
      |  durable/state: local disk as configured
      v
  bounded authenticated edge link
      |
      v
  regional or cloud ZigMV broker
```

The edge link uses subject export/import filters, TLS or mTLS, connection identity, reconnect backoff, sequence or cursor tracking, and a bounded forwarding queue. It must support offline operation for configured profiles and must expose link lag, dropped messages, retries, and reconnect metrics.

## Security model

ZigMV separates transport encryption, authentication, authorization, and resource protection. The required production model includes TLS, optional mTLS, account or tenant identity, publish and subscribe ACLs, maximum frame and payload sizes, connection limits, subscription limits, rate limits, bounded mailboxes, credential rotation, and audit-safe structured logs.

## Compatibility

NATS and MQTT 5.0 compatibility are optional boundary adapters. They are not separate internal brokers and must translate into the canonical envelope before routing. New applications that control both ends should use ZigMV directly. Existing devices and services can migrate through adapters without forcing the ADT core to duplicate routing or storage logic.

ZigMV `live` is intentionally comparable to Core NATS or MQTT QoS 0. ZigMV `durable` is currently a bounded, connected-session analogue of an MQTT QoS 1 or JetStream-style acknowledged consumer, but it is not full MQTT QoS 1 interoperability because reconnect sessions and durable consumer cursors are incomplete. MQTT QoS 2 and ZigMV `exact` are not implemented: the required PUBREC/PUBREL/PUBCOMP or equivalent deduplication, crash recovery, and duplicate-suppression state machine is still a later release gate.

## Release boundaries

### 0.4.0

The grouped 0.4.0 implementation release stabilizes the ZigMV name and `ZMV/1` handshake, implements `live`, `work`, `durable`, and `state`, adds native end-to-end tests, ACK handling, durable stream append, retained-state delivery, expiry checks, and bounded in-session durable redelivery. `exact` remains explicitly rejected until deduplication, durable client identity, reconnect resume, and crash guarantees are complete.

### 1.0.0-beta

The 1.0.0-beta milestone requires durable append and recovery, `durable` ACK/retry/expiry, `state` retention and expiry, edge-link reconnect and bounded transfer, TLS and subject ACLs, compatibility tests, crash/failure tests, benchmark baselines, and documented guarantees. `exact` should not be enabled merely because the frame exists; it requires evidence from crash, retry, duplicate, and restart tests.

## Non-goals

ZigMV does not replace `zigkv`, does not provide arbitrary Redis commands, does not hide business logic inside the broker, and does not claim exactly-once semantics before the complete deduplication and recovery state machine is implemented.
