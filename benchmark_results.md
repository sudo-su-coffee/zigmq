# zigmq benchmark results

The benchmark was run on the sandbox host using the current Debug build of zigmq with Zig 0.15.2 and the local Python benchmark script.

| Scenario | Result |
|---|---:|
| 10,000 publish acknowledgments | 18,470.4 messages/second |
| 5,000 custom fan-out deliveries | 9,843.4 messages/second |
| 100 sequential client connects | 94.5 connects/second |
| 100,000 publish acknowledgments | 17,511.1 messages/second |
| 5,000 fan-out deliveries during the 100,000-message run | 9,616.9 messages/second |
| 1,000 sequential client connects | 97.8 connects/second |

These are localhost sandbox measurements, not portable guarantees. The benchmark uses small 12-byte payloads and waits for acknowledgments or delivery for every message, so it measures application-level round-trip throughput rather than raw socket writes. The current one-thread-per-client model is appropriate for a small edge broker and can hold at least 1,000 idle test clients on this host, but sequential connection establishment is around 100 connects/second. The bounded queue intentionally disconnects a client that cannot consume messages fast enough.

The measurements show that 100,000 messages is a valid test volume, but not a claim that 100,000 messages/second is supported. The observed sustained range on this host is roughly 17,000-18,000 publish acknowledgments/second and 9,600-9,800 one-subscriber fan-out messages/second for the tested payload and access pattern. Real edge-device limits depend on CPU, RAM, kernel socket limits, payload size, number of subscribers, network bandwidth, and whether TLS or authentication is added.
