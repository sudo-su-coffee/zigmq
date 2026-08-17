# ZigMV comparison findings

## NATS

The official NATS overview describes subject-based messaging, low latency at high message rates, a small single binary, request/reply, queue-style load balancing, security, clustering, and edge-to-cloud use cases. Core NATS is the volatile path: messages are delivered only to subscribers connected at publication time and are at-most-once. JetStream adds streams, persistent storage, server-side consumers, sequence positions, explicit acknowledgements, replay, redelivery, and at-least-once delivery.

Sources:

- https://docs.nats.io/concepts/what-is-nats
- https://docs.nats.io/concepts/jetstream

## MQTT 5.0

The OASIS MQTT 5.0 standard defines a lightweight publish/subscribe transport for constrained IoT environments. Its delivery model includes QoS 0 at-most-once, QoS 1 at-least-once with possible duplicates, and QoS 2 exactly-once. It also defines retained messages, sessions and session expiry, message expiry, topic filters, shared subscriptions, PUBACK/PUBREC/PUBREL/PUBCOMP flows, keepalive, disconnect behavior, maximum packet size, authentication exchange, and a broad property/reason-code model.

Source:

- https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html

## Implication for ZigMV

ZigMV should make delivery guarantees explicit per profile and must not claim MQTT QoS 2 or exactly-once behavior until deduplication, crash recovery, retransmission, and duplicate tests are complete. Its live profile can correspond to a Core-NATS/MQTT QoS 0 path; durable can correspond to a JetStream/MQTT QoS 1-style at-least-once path once redelivery and durable consumer cursors are implemented; an eventual exact profile needs a complete deduplication protocol and failure evidence. Retained state, session expiry, message expiry, shared/work subscriptions, request/reply correlation, authentication, ACLs, keepalive, flow control, and compatibility adapters all need independent conformance tests.
