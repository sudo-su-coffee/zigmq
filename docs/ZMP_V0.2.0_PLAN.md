# ZMP v0.2.0 Plan: One Unified Algorithm

## Product decision

ZMP v0.2.0 is the foundation of one new protocol, not a bundle of separate NATS and MQTT modes. It targets one compact client API for cloud services, IoT devices, and edge gateways. NATS and MQTT 5.0 are design influences and future compatibility targets; they are not duplicated internal broker implementations.

The implementation principle is **Adaptive Delivery Routing (ADR)**: normalize one publish into one canonical message envelope, match subscriptions once, and select live, work, durable, state, or exact behavior from the subscription/publish profile.

## Scope before further feature work

| Area | v0.2.0 decision |
| --- | --- |
| Native protocol | `ZMP/1` |
| Message model | One canonical envelope with subject, payload, profile, expiry, reply, correlation, and sequence fields |
| Routing | One exact/wildcard index with optional group selection |
| Profiles | Define `live`, `work`, `durable`, `state`, and `exact`; implement only `live` initially |
| Delivery truth | Never claim ACK/retry/exact semantics until the corresponding state machine exists |
| Persistence | Existing stream remains a low-level append/replay foundation, not yet durable consumer semantics |
| Compatibility | Existing NATS/MQTT listeners remain separate compatibility surfaces until thin adapters map into the envelope |
| zigkv boundary | No Redis commands, RESP server, or key-value semantics in zigmq |

## Implementation sequence

### Step 1: freeze the semantic model

Document the envelope, profile contracts, subject grammar, subscription state, message identifiers, expiry, and error behavior. Add parser tests that prove unknown profiles are rejected and that malformed frames cannot become valid messages.

### Step 2: implement ADR interfaces

Separate protocol parsing from broker decisions. Introduce explicit internal operations such as:

```text
publish(envelope)
subscribe(filter, profile, consumer_policy)
unsubscribe(subscription_id)
ack(consumer_id, message_id)
recover(consumer_id, cursor)
```

The first implementation can delegate to the current broker indexes, but protocol code must not directly encode NATS or MQTT-specific storage decisions.

### Step 3: complete the live profile

Support fast at-most-once delivery, wildcard routing, work-group selection, bounded queues, publisher responses, and clear metrics. Measure the publish path and fan-out path separately.

### Step 4: implement work and state profiles

Add fair one-of-N consumer selection, retained last-value state, expiry, and state delivery on subscription. Keep state bounded by topic count, payload bytes, tenant/account, and TTL.

### Step 5: implement durable profile

Add append records with checksums, stream sequence, consumer cursors, ACK deadlines, redelivery, expiry, restart recovery, duplicate handling, and explicit lag metrics. Only then expose `durable` as a successful profile.

### Step 6: add compatibility adapters

Map MQTT 5.0 QoS/session/retained concepts and NATS request/reply/queue concepts into the canonical envelope. Compatibility translation must happen at the edge of the broker, not in the ADR hot path.

## Benchmark and correctness gates

| Gate | Required evidence |
| --- | --- |
| Parser | Unit tests for every frame type, profile, invalid length, invalid subject, and unknown field |
| Live throughput | Publish ACK rate and delivery rate at 16/128/1024-byte payloads |
| Fan-out | 1/10/50/100 consumers with p50/p95/p99 latency |
| Work groups | No duplicate delivery within one group and fair distribution over a run |
| State | Retained value delivery, TTL expiry, replacement, and bounded memory |
| Durable | Restart recovery, ACK loss, retry, duplicate ACK, expiry, and cursor resume |
| Backpressure | Slow consumer cannot grow memory without a bound |
| Compatibility | Existing custom/NATS/MQTT tests remain green |
| CI | Zig 0.15.2 format, build, unit, and integration checks pass |

## Release sequence

| Version | Main outcome |
| --- | --- |
| `0.2.0` | ZMP grammar, ADR envelope foundation, live profile, tests, benchmark harness |
| `0.3.0` | Work/state profiles, TLS, authorization, rate limits, metrics |
| `0.4.0` | Durable profile with ACK/retry/recovery |
| `0.5.0` | MQTT 5.0 and NATS compatibility adapters mapped to the envelope |
| `0.6.0` | Edge links, reconnect sessions, offline synchronization |
| `0.7.0` | Binary framing, batching, event-driven I/O, memory optimization |
| `1.0.0` | Stable unified protocol and documented compatibility guarantees |

## Non-goals

This plan does not make zigmq a Redis replacement, a business workflow engine, or a claim that a new protocol automatically outperforms mature NATS or MQTT implementations. The advantage sought is a simpler unified semantic model that can serve services and devices with one lightweight native protocol and measurable behavior.
