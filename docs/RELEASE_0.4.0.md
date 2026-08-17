# zigmq 0.4.0

## Summary

`0.4.0` is the first grouped ZigMV release train. It combines the ZMV/1 foundation with live telemetry, work groups, durable delivery primitives, ACK handling, retained state, expiry metadata, and the initial persistent delivery state.

## Included capabilities

| Capability | Status |
| --- | --- |
| `ZMV/1` handshake and canonical subject routing | Available |
| `live` delivery | Volatile at-most-once delivery to connected consumers |
| `work` delivery | One eligible consumer per work group |
| `durable` delivery | Durable append, delivery IDs, consumer ACK removal, and bounded expiry metadata |
| `state` delivery | Retained last-value state and immediate delivery to state subscribers |
| No-ack telemetry | Available with the `-` publish identifier |
| `exact` delivery | Not enabled; deduplication and crash guarantees are not complete |

## Quick start

Start the broker with the native ZigMV listener:

```sh
zig build run -- --protocol zigmv --host 127.0.0.1 --port 4222
```

Subscribe to state and publish a state value:

```text
ZMV/1 SUB state device.status
ZMV/1 PUB state 1 device.status 4
okay
```

Subscribe to durable delivery and acknowledge the resulting delivery ID:

```text
ZMV/1 SUB durable jobs.created
ZMV/1 PUB durable 2 jobs.created 5
hello

ZMV/1 MSG durable <delivery-id> jobs.created 5
hello
ZMV/1 ACK <delivery-id>
```

Use `live` with `-` when the publisher does not need a broker response for each telemetry message:

```text
ZMV/1 SUB live sensors.temperature
ZMV/1 PUB live - sensors.temperature 4
21.5
```

## Guarantees and limitations

Durable delivery in this release appends the message to the configured local stream when one is enabled, assigns a broker delivery ID, sends a durable message to matching ZigMV consumers, and removes the pending delivery after a valid ACK from the receiving client. Expiry metadata is bounded by the configured delivery window.

This release does not yet claim complete offline persistent sessions, automatic redelivery after process restart, replicated streams, exactly-once delivery, native TLS, or clustered failover. Those capabilities remain in later grouped release trains and are blocked by their respective tests and review gates.

## Verification

The release workflow must compile the ReleaseFast Linux binary, run the complete Zig test suite, run the ZigMV smoke test for live/work/durable/state behavior, validate `zigmq --version`, package the binary, and publish a SHA-256 checksum.

## Upgrade guidance

The existing custom, NATS, MQTT, and ZMP listeners remain available. Applications adopting ZigMV should use `ZMV/1` and explicitly choose a delivery profile. Existing ZMP clients should continue to use `--protocol zmp` until they are migrated and tested against ZigMV.
