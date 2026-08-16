# zigmq performance optimization results

All measurements used Zig 0.15.2, a ReleaseFast build, localhost TCP, and the existing benchmark scripts.

| Workload | Clean main baseline | Indexed-routing branch | Change |
| --- | ---: | ---: | ---: |
| 10,000 publish acknowledgments | 18,729 msg/s repeat baseline | 23,222 msg/s | +24.0% |
| 10,000 one-subscriber fan-out | 11,977 msg/s repeat baseline | 14,173 msg/s | +18.3% |
| 50 subscribers, 1,000 messages | 1,722.9 broker msg/s | 1,785.3 broker msg/s | +3.6% |
| 50 subscribers, total deliveries | 86,144.9 deliveries/s | 89,265.7 deliveries/s | +3.6% |
| Sequential client connects | 98.0 connects/s | 96.2-98.4 connects/s | Within variance |

The branch changes the broker's publish path from scanning every connected client and every subscription to an exact-subject index plus a compact wildcard list. A per-publish generation marker prevents duplicate delivery when one client matches both an exact and wildcard subscription. The indexed path preserves the existing at-most-once delivery semantics and does not change the public command protocol.

The benchmark is application-level and waits for each publish acknowledgment and subscriber delivery. It is not a raw socket maximum. Results will vary with payload size, subscriber count, CPU, kernel limits, and network conditions.
