# Edge stress findings

The latest checked-out broker binary passed the existing edge-focused suites on localhost:

| Scenario | Result |
| --- | --- |
| Telemetry | 1,000 messages from 100 devices at 10 Hz; 19,789.6 messages/sec measured. |
| Command/control | 100 devices and 100 commands; 3,585.2 commands/sec measured. |
| Alert burst | 1,000 events; 17,735.8 events/sec measured. |
| Request/reply timeout | Completed request/reply and missing-service timeout behavior passed. |
| Retained reconnect | Retained `state.device1` value was recovered with 5,000 ms TTL. |
| Consumer group | 30 messages across 3 members, exactly 10 per member; 906.6 messages/sec measured. |
| Edge feature suite | Passed. |
| Security hardening suite | Passed. |

These are localhost functional/stress baselines, not long-duration soak measurements and not a multi-device physical edge benchmark. The highest-value remaining edge measurements are RSS/CPU/file-descriptor tracking, queue occupancy under disconnected upstream conditions, restart recovery under power-loss-style termination, payload-size sweeps, and sustained multi-hour soak runs.
