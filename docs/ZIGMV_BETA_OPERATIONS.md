# ZigMV 1.0.0-beta.1 Operations Guide

## Upgrade procedure

Stop the old broker after draining publishers, back up the session journal and configuration, deploy the new binary, verify its checksum, and start with the same `--session-store` path. The journal recovery path ignores an incomplete tail and replays valid checksummed records. Validate `/health`, `/readyz`, `--version`, and a native `AUTH`/`SUB`/`PUB` exchange before reopening producers.

For a secure deployment, provide the server certificate, private key, CA bundle, and `--tls-require-client-cert`. Rotate certificates by staging a new CA bundle and certificate, restarting one edge broker at a time, validating a secure LINK handshake, and then retiring the old trust material. Do not copy private keys into the repository or artifact directory.

## Rollback procedure

If the new broker fails readiness or protocol smoke tests, stop it without deleting the journal, restore the previously verified binary, and restart with the backed-up configuration and journal. Do not run a journal compaction or destructive migration during an uncertain rollback. Confirm that the restored process can read the journal, accept authenticated clients, and expose health/readiness before resuming traffic.

If a certificate rotation fails, restore the previous certificate and CA bundle, restart the affected broker, and verify the peer LINK session before allowing traffic. A failed secure edge connection must remain disconnected rather than silently downgrade to plaintext.

## Failure semantics

| Profile | Delivery guarantee | Disconnect behavior | Restart behavior | Explicit limitation |
| --- | --- | --- | --- | --- |
| `live` | At-most-once | Messages not accepted by the bounded mailbox may be rejected or lost under overload | No replay guarantee | Use for telemetry where loss is acceptable. |
| `work` | One-of-N among active consumers | Unacknowledged work is not a distributed durable guarantee | No cluster-wide replay guarantee | Use durable mode for important commands. |
| `durable` | Bounded acknowledged connected-session retry | Unacknowledged deliveries retry while supported session state remains available | Journal recovery is supported; distributed consumer cursors are not claimed | Not full JetStream or MQTT QoS 1 interoperability. |
| `state` | Retained last value with expiry | A reconnecting subscriber receives the retained value when still valid | Local retained state only | Not a replicated configuration store. |
| `LINK` | Authenticated, filtered, bounded forwarding | Reconnect backoff and cursor handling prevent unbounded transfer; gaps are observable | Offline transfer remains bounded and scoped | No exactly-once or distributed replication claim. |

ZigMV `exact`, MQTT QoS 2, full MQTT 5.0 interoperability, full NATS JetStream semantics, and distributed replication remain explicitly unsupported in this beta candidate.
