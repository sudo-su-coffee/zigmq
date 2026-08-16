# ZigMQ Capacity, Architecture, Security, and Optimization Review

## Executive assessment

ZigMQ is working as a **small, understandable edge broker**, not as a general replacement for NATS. Its useful operating range is determined by the number of subscribers per subject, payload size, whether durable streaming is enabled, client hardware, and the number of slow consumers. The current measurements support a practical design budget of approximately **1,000–5,000 custom messages per second on small edge hardware without durable streaming**, with lower rates when every publish must be synchronously flushed to disk. The development sandbox can exceed that budget, but those numbers must not be presented as universal capacity guarantees.

The important distinction is between a **published message**, a **subscriber delivery**, and a complete **application task**. One `PUB` command is one broker message. With 50 subscribers, one publish creates 50 deliveries. A workload reporting 1,763 broker messages/s at 50 subscribers is also producing approximately 88,180 subscriber deliveries/s. If an application task requires request/reply, durable disk sync, a downstream database, or a second network hop, its end-to-end task rate will be lower than the broker’s raw publish rate.

## How one message moves through the broker

The current custom-protocol path is deliberately compact:

```text
TCP accept
   -> one client thread
      -> bounded line reader
         -> parser and subject validation
            -> broker mutex
               -> exact-subject hash lookup
               -> wildcard matching fallback
               -> consumer-group bucket selection
               -> optional stream append and fsync
               -> allocate one frame per recipient
               -> bounded per-client queue
                  -> writer thread
                     -> socket write
                        -> frame memory freed
```

The reader thread does not write subscriber data directly to subscriber sockets. It creates an owned frame and enqueues it. This prevents one slow client from holding the routing lock, but it also means each recipient currently pays for a frame allocation and a queue operation. The writer thread owns the actual socket write and disconnects a client when its queue exceeds **32 messages or 256 KiB**.

The exact-subject indexes make ordinary routing much cheaper than scanning all clients. Wildcard subscriptions still require subject matching. Consumer groups now use a hash-keyed `(pattern, group)` bucket with a round-robin cursor, avoiding the previous repeated scans of every group member for every publish.

Durable streaming is intentionally synchronous. The broker appends a 22-byte record header, topic, and payload while holding the broker lock, then calls `file.sync()` before continuing. This provides a clear durability boundary, but it serializes publishers behind filesystem latency.

## Measured capacity envelope

The following results are ReleaseFast localhost measurements from the development sandbox. They are useful for comparing code paths, not for promising a production service level.

| Workload | Configuration | Measured result | Interpretation |
| --- | --- | ---: | --- |
| Publish acknowledgments | Custom protocol, 10,000 messages, small payload | **24,342 msg/s** | Raw publisher/ACK path without fan-out |
| One-subscriber fan-out | Custom protocol, 10,000 messages | **14,291 msg/s** | One delivery drained for every publish |
| Fan-out, 1 subscriber | 1,000 messages | **8,952 broker msg/s** | Approximately 8,952 deliveries/s |
| Fan-out, 10 subscribers | 1,000 messages | **5,096 broker msg/s** | Approximately 50,958 deliveries/s |
| Fan-out, 50 subscribers | 1,000 messages | **1,764 broker msg/s** | Approximately 88,181 deliveries/s |
| Sequential client connects | 100 clients | **98.4 connects/s** | Thread and TCP setup cost, not steady-state capacity |
| Telemetry simulation | 100 devices, 10 readings each | **20,425 messages/s** | Harness result; 1,000 total messages |
| Alert burst simulation | 1,000 events | **18,253 events/s** | Harness result; one wildcard consumer |
| Durable stream, disabled | 1,000 messages, 128-byte payload | **36,619 publish ACK/s** | Storage disabled |
| Durable stream, enabled | Same workload and payload | **6,294 publish ACK/s** | Approximately **17.2%** of the non-stream rate |

The two custom fan-out figures are from different harnesses. `benchmark.py` uses a single subscriber and a small payload, whereas `benchmark_fanout.py` uses a per-case process and explicit subscriber draining. The difference is normal for microbenchmarks; compare like-for-like runs only.

## NATS comparison

The controlled NATS-compatible matrix used the same protocol framing, 1,000 messages, payload sizes of 16, 128, and 1,024 bytes, and 1, 10, and 50 subscribers. ZigMQ reached approximately **42.3–84.7% of NATS’s publish-message rate** in that captured matrix. The single-subscriber 128-byte case was approximately 10,837 ZigMQ messages/s versus 21,402 NATS messages/s before the latest queue and routing optimization. The post-optimization representative run measured approximately 12,279, 7,303, and 2,445 ZigMQ broker messages/s for 1, 10, and 50 subscribers.

The honest conclusion is that NATS remains faster and substantially more mature. ZigMQ’s value is its compact pure-Zig implementation, inspectable algorithms, bounded memory behavior, optional local replay, and header-free Python bridge. The project should use NATS when clustering, broad client compatibility, TLS, observability, replication, or mature operational tooling are primary requirements.

## What “tasks per second” means for edge applications

| Application pattern | Broker interpretation | Conservative starting budget |
| --- | --- | ---: |
| 100 devices at 10 Hz, one telemetry consumer | 1,000 publishes/s and 1,000 deliveries/s | Comfortable on the measured development path; verify on target hardware |
| 100 devices at 10 Hz, 10 consumers | 1,000 publishes/s and 10,000 deliveries/s | Usually feasible without stream sync; validate CPU and socket pressure |
| 100 devices at 10 Hz, 50 consumers | 1,000 publishes/s and 50,000 deliveries/s | Close to the measured fan-out envelope; test carefully |
| 1,000 alert burst, one consumer | 1,000 publishes and 1,000 deliveries | Supported by the tested workload simulation |
| Durable audit events | One synchronous filesystem flush per publish | Expect a large rate reduction; measure the actual storage |
| 100,000 messages/s | 100,000 broker publishes every second | Not a current ZigMQ target; requires a different event-loop, batching, and storage architecture |

A useful sizing formula is:

> `required delivery rate = publish rate × average matching subscribers`

For example, 2,000 telemetry publishes/s with 20 matching consumers requires roughly 40,000 frame deliveries/s before accounting for request/reply, retained delivery, group routing, network retransmission, or application work.

## Memory and concurrency limits

The current hardening constants are intentionally explicit:

| Limit | Current value | Why it exists |
| --- | ---: | --- |
| Control line | 1 KiB | Bounds parser and command memory |
| Topic | 256 bytes | Bounds subject indexes and validation |
| Payload | 64 KiB | Bounds input and frame allocation |
| Per-client queue | 32 messages or 256 KiB | Disconnects slow consumers instead of growing without limit |
| Connected clients | 1,024 | Prevents unlimited thread and client-state growth |
| Custom subscriptions/client | 1,024 | Prevents subscription-index abuse |
| NATS subscriptions/client | 1,024 | Prevents SID/index abuse |
| Commands before authentication | 8 | Limits unauthenticated connection holding and probing |

The queue bound is per client. If all 1,024 client queues were simultaneously full, the payload budget alone could reach approximately **256 MiB**, before frame headers, allocators, client objects, subscription memory, thread stacks, kernel socket buffers, and the broker process itself. Therefore, `max_clients = 1024` is a protection ceiling, not a recommendation for a small device. A realistic starting deployment should usually configure an operating-system service limit and run only tens to hundreds of active clients until memory and CPU are measured.

The one-thread-per-client design is easy to learn and works well at small scale. It is not appropriate to infer support for 100,000 concurrent clients from a 1,000-idle-client experiment. Thread stacks, scheduler overhead, file descriptors, and join/resource management become the limiting factors well before the subject algorithm does.

## Security status

### Improvements implemented in the edge-hardening branch

| Control | Current behavior | Security value |
| --- | --- | --- |
| Authentication comparison | Shared tokens use a fixed-length byte comparison that does not exit on the first differing byte | Reduces simple timing leakage compared with ordinary early-exit equality |
| Secret handling | `--auth-token-file` loads a trimmed token from a file and wipes the owned buffer on shutdown | Avoids exposing the secret in the process command line |
| Invalid NATS authorization | Failed NATS `CONNECT` authorization closes the connection | Reduces repeated probing on one connection |
| Pre-auth budget | Only eight non-auth commands are accepted before the connection is closed | Limits unauthenticated resource holding and command probing |
| Client admission | Maximum of 1,024 connected clients | Bounds thread and client-state growth |
| Subscription admission | Maximum of 1,024 subscriptions per client in each protocol mode | Bounds index and allocation growth |
| Stream permissions | Stream creation requests owner-only `0600` mode and applies `chmod` | Protects ordinary local access to the append-only file |
| Stream coordination | Exclusive advisory file lock | Prevents cooperating processes from sharing one stream accidentally |

### Security limitations that remain

The token is still a **single shared secret**, not an identity system. It has no per-client permissions, rotation, expiry, revocation, audit trail, or subject-level authorization. TCP is plaintext, and the stream file is not encrypted. Anyone able to read the process memory can access the token while the broker is running. There is no IP-based connection rate limiter, idle handshake timeout, per-client publish quota, or TLS implementation in the current compact broker.

The most important production safety step is to keep ZigMQ on loopback or a private network, use `--auth-token-file` with a protected service account, and place it behind an encrypted transport boundary until TLS is implemented and reviewed. The next pure-Zig security milestone should be TLS or a carefully scoped transport-security layer, not a larger feature set.

## Highest-value optimization roadmap

| Priority | Improvement | Expected benefit | Main trade-off |
| ---: | --- | --- | --- |
| P0 | Keep exact-subject, queue, and group indexes | Removes repeated scans and queue shifting | More index memory and lifecycle code |
| P0 | Add per-client publish and connection rate limits | Reduces abuse and protects edge CPU | Requires counters and a time window |
| P1 | Reuse frame buffers or add a small bounded slab allocator | Reduces per-recipient heap allocation | More ownership complexity |
| P1 | Batch adjacent queued frames into bounded writes | Reduces socket syscalls | Slightly higher latency and more complex queue framing |
| P1 | Add `--stream-sync always|interval|none` | Makes durability/performance trade-off explicit | `interval` and `none` allow a crash-loss window |
| P2 | Add a handshake/idle timeout | Prevents half-open clients from occupying threads | Requires timeout or polling behavior |
| P2 | Pre-tokenize wildcard subjects | Reduces repeated dot scanning | More stored metadata and invalidation logic |
| P2 | Lazy expired-retained cleanup | Prevents long-lived TTL maps from accumulating dead entries | Periodic cleanup work |
| P3 | Event loop or worker-pool experiment | Improves large-connection efficiency | Larger code and less direct learning value |
| P3 | TLS, per-client identity, and subject ACLs | Makes wider deployments safer | Considerably more security-critical code |

The next performance experiment should measure allocation count and write syscall count before implementing a large redesign. The next security experiment should add per-client rate limits and an idle handshake timeout. Both are smaller and safer than attempting clustering or full JetStream semantics.

## Evidence files

The detailed raw evidence is stored in [`comparison_results.md`](comparison_results.md), [`optimization_results.md`](optimization_results.md), [`benchmark_runs/nats_matrix.jsonl`](benchmark_runs/nats_matrix.jsonl), [`benchmark_runs/optimization_nats_before.jsonl`](benchmark_runs/optimization_nats_before.jsonl), [`benchmark_runs/optimization_nats_after.jsonl`](benchmark_runs/optimization_nats_after.jsonl), [`benchmark_runs/hardening_capacity.txt`](benchmark_runs/hardening_capacity.txt), [`benchmark_runs/hardening_fanout.txt`](benchmark_runs/hardening_fanout.txt), [`benchmark_runs/hardening_stream_cost.txt`](benchmark_runs/hardening_stream_cost.txt), and [`benchmark_runs/hardening_realtime_results.json`](benchmark_runs/hardening_realtime_results.json). The security behavior is exercised by [`scripts/security_hardening_test.py`](scripts/security_hardening_test.py).

## References

[1]: README.md#limits-and-delivery-model
[2]: comparison_results.md
[3]: optimization_results.md
[4]: benchmark_runs/realtime_results.json
[5]: scripts/security_hardening_test.py
