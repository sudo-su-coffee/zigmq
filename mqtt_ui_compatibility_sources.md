# MQTT UI compatibility research notes

## Redis-compatible UI

Redis documents RESP as the wire protocol used by Redis clients. Clients send commands as RESP arrays of bulk strings, and servers reply with RESP types. RESP2 is the standard baseline; RESP3 extends it. Redis uses TCP for the client protocol. Source: https://redis.io/docs/latest/develop/reference/protocol-spec/

Redis Insight describes itself as a GUI/CLI for Redis deployments, with data browsing, CRUD, CLI, streams, Pub/Sub, and diagnostics. Direct RedisInsight compatibility therefore depends on ZigKV speaking the RESP command and reply dialects expected by the UI. Source: https://redis.io/insight/

ZigKV's repository README states that it has a RESP parser, works with `redis-cli`, implements RESP2, and is Redis-compatible. This makes RedisInsight a plausible direct integration target, subject to testing the UI's command coverage and data-type expectations.

## MQTT-compatible UI

The OASIS MQTT 3.1.1 specification defines MQTT as a client/server publish/subscribe transport over an ordered, lossless byte stream. It defines MQTT Control Packets including CONNECT, CONNACK, PUBLISH, PUBACK, SUBSCRIBE, SUBACK, UNSUBSCRIBE, UNSUBACK, PINGREQ, PINGRESP, and DISCONNECT. It also defines QoS 0/1/2, topic filters, sessions, retained behavior, and optional WebSocket transport. Source: https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html

MQTTX presents itself as an MQTT 5.0 desktop, CLI, and Web client for connecting to MQTT brokers, publishing, and subscribing. Source: https://mqttx.app/

MQTT Explorer presents a hierarchical MQTT topic view with topic activity, publish/subscribe operations, retained-topic operations, filtering, and plotting. Source: http://mqtt-explorer.com/

ZigMQ currently has a custom text protocol and a small NATS-compatible subset. Those are not MQTT Control Packets, so MQTTX and MQTT Explorer cannot connect directly to the current custom or NATS listener. A standard MQTT listener or a separate pure-Zig MQTT bridge is required.

## Recommended compatibility boundary

Use a dedicated `--protocol mqtt` listener, defaulting to TCP port 1883, while retaining custom mode and NATS mode. Start with MQTT 3.1.1 QoS 0: CONNECT/CONNACK, PUBLISH, SUBSCRIBE/SUBACK, UNSUBSCRIBE/UNSUBACK, PINGREQ/PINGRESP, and DISCONNECT. Map MQTT topics to ZigMQ subjects, translate retained state, and reject QoS 1/2 until packet identifiers and acknowledgments are implemented correctly. Add MQTT-over-WebSocket and TLS only after the plain MQTT TCP path is tested.
