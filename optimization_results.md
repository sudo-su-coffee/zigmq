# ZigMQ Optimization Results

## Scope

This iteration targets the two clearest hot paths in the compact edge broker: outbound client queue dequeue and NATS-compatible subscription routing. The implementation remains pure Zig and keeps the bounded queue policy, at-most-once delivery model, custom protocol, and separate ZigKV project boundary unchanged.

## Changes

| Area | Previous behavior | Current behavior | Complexity effect |
| --- | --- | --- | --- |
| Client output queue | `ArrayList.orderedRemove(0)` shifted every pending pointer after each write | Bounded head-index queue with occasional compaction | Dequeue changes from **O(n)** shifting to amortized **O(1)** |
| NATS exact subscriptions | Each publish scanned every connected client and every NATS subscription | Exact subjects use a hash-map index; only wildcard subscriptions are scanned | Exact publish routing changes from **O(all subscriptions)** to **O(matching exact subscribers)** |
| NATS unsubscribe | `orderedRemove(index)` shifted later subscriptions | `swapRemove(index)` removes by SID without preserving order | Removal changes from **O(n)** shifting to **O(1)** after SID lookup |
| Cleanup | Subscription index entries were not explicitly removed on disconnect | Exact and wildcard index references are removed during disconnect | Prevents stale references and makes lifecycle behavior explicit |

## Fair before/after run

Both sides of the comparison used the same `scripts/compare_nats.py` harness, Zig 0.15.2, ReleaseFast, localhost TCP, NATS framing, 1,000 messages, and 128-byte payloads. The before case was built from commit `05ff28a` immediately before this optimization; the after case was built from the current working tree.

| Subscribers | Before ZigMQ msg/s | After ZigMQ msg/s | Change | Before ZigMQ p50 µs | After ZigMQ p50 µs |
|---:|---:|---:|---:|---:|---:|
| 1 | 11,250 | 12,279 | **+9.1%** | 45.7 | 41.4 |
| 10 | 6,717 | 7,303 | **+8.7%** | 92.8 | 86.2 |
| 50 | 2,089 | 2,445 | **+17.0%** | 401.7 | 334.6 |

The NATS server control measurements varied between runs, so this report focuses on the ZigMQ before/after delta and does not claim that the NATS server changed. The existing comparison report remains the authoritative cross-broker matrix. The raw logs are committed as `benchmark_runs/optimization_nats_before.jsonl` and `benchmark_runs/optimization_nats_after.jsonl`.

## Additional current custom-protocol run

A ReleaseFast run after the queue change measured approximately **21,640 publish acknowledgments per second**, **14,921 one-subscriber fan-out messages per second**, **1,653 broker messages per second with 50 subscribers**, and **82,636 total deliveries per second**. The latest saved real-time scenario artifact also measured approximately **20,425 telemetry messages per second** and **18,253 alert events per second**. These numbers are host-specific and should be repeated on the target edge hardware.

## Interpretation

The gains are meaningful because they reduce work that occurs for every outbound message or every NATS publish. The exact-subject index is particularly useful when an edge workload has many idle subscriptions but each message targets one or a small number of subjects. The bounded head-index queue avoids repeatedly moving pending message pointers under slow or bursty consumers.

The index adds memory for subject keys, subscription references, and per-subject lists. Wildcard subscriptions still require matching scans, and fan-out still spends time formatting, allocating, queueing, and writing one frame per recipient. Therefore, the next likely bottlenecks are per-message heap allocation and socket write behavior rather than subject matching alone.

## Recommended next roadmap

| Priority | Idea | Why it matters | Edge-safe scope |
|---:|---|---|---|
| 1 | Per-client reusable frame buffer or small slab allocator | Reduces allocator calls for ACK and MSG frames | Keep message ownership explicit; retain queue bounds |
| 2 | Batch adjacent queued frames into one write | Reduces syscall overhead during bursts | Batch only up to a small byte limit and preserve frame order |
| 3 | Pre-tokenized subject representation | Avoids rescanning dots for wildcard matching | Store compact token offsets only for wildcard subscriptions |
| 4 | Expired-retained cleanup | Prevents long-running TTL workloads from accumulating dead map entries | Lazy cleanup on access plus a bounded periodic sweep |
| 5 | Stream durability modes | `sync=always` is safe but expensive | Add `sync=interval` or `sync=never` as explicit opt-in modes with documented loss windows |
| 6 | Worker-pool or event-loop experiment | One thread per client limits large connection counts | Keep as a separate benchmarked branch; do not replace the readable default prematurely |
| 7 | Per-subject consumer-group cursor | Current selection is deterministic but not durable | Add only if edge workloads need restartable group progress |

The project should not add clustering, replication, transactions, full JetStream, or the full MQTT binary protocol before the simpler allocation and write-path measurements are complete. Those features increase code size and operational complexity without directly improving the current localhost hot path.
