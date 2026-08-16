# ZMP live benchmark — 2026-08-16

## Environment

The test used the published `v0.2.0-beta.1` Linux x86_64 ReleaseFast binary, Zig 0.15.2 build provenance, localhost TCP, and the repository benchmark client. Each case used 1,000 messages and was run against a fresh broker process.

## Results

| Subscribers | Payload | Messages | Publish ACK rate | Fan-out delivery rate | Result |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 16 bytes | 1,000 | 4,742.53 msg/s | 4,742.53 deliveries/s | Complete |
| 1 | 128 bytes | 1,000 | 4,864.09 msg/s | 4,864.09 deliveries/s | Complete |
| 1 | 1,024 bytes | 1,000 | 4,432.33 msg/s | 4,432.33 deliveries/s | Complete |
| 10 | 16 bytes | 1,000 | 353.66 msg/s | 3,536.63 deliveries/s | Complete |
| 10 | 128 bytes | 1,000 | 347.31 msg/s | 3,473.09 deliveries/s | Complete |
| 10 | 1,024 bytes | 1,000 | 350.64 msg/s | 3,506.44 deliveries/s | Complete |

A longer 10,000-message run completed for one subscriber at approximately 6,200–6,500 publish acknowledgements per second. At ten subscribers, the 10,000-message run reached the bounded queue and disconnected clients rather than completing. This is expected protection behavior for the current small queue, but it means the benchmark cannot yet claim sustained high-volume fan-out.

## Gate decision

The current live path does not meet the provisional engineering gates in [`ZMP_LIVE_TEST_PLAN.md`](ZMP_LIVE_TEST_PLAN.md): it is below the 25,000 publish-acknowledgement-per-second target, below the 100,000 ten-subscriber fan-out target, and has no p99 latency measurement yet. The benchmark client also performs a request/acknowledgement round trip for every publish, so a separate pipelined benchmark is needed before drawing a final wire-throughput conclusion.

The correct next step is **live-path optimization and better measurement**, not implementation of `work`, `durable`, `state`, or `exact`. The current beta remains functionally valid for small edge workloads, but the stronger profiles should wait until the live path has a stable performance baseline and a complete backpressure test.
