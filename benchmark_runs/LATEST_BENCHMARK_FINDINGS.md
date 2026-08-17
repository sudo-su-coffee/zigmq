# Latest ZigMV benchmark findings

The checked-out branch `feat/zigmv-delivery-semantics` at commit `81e52ef` was tested with the existing `zig-out/bin/zigmq` binary, which reports `zigmq 0.6.0`. A local Zig compiler was unavailable, so the binary was not rebuilt locally; the same branch's GitHub CI had passed the Zig 0.15.2 build and test workflow.

| Case | Broker accepted | Delivered | Ratio | Accepted msg/s | Delivered msg/s | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Live, 1,000 messages, 128-byte payload | 1,000 | 995 | 99.5% | 22,098.25 | 98.92 over the 10-second drain deadline | PASS_LOSSY_LIVE |
| Publish-ACK, 1,000 messages, 128-byte payload | 1,000 | 1,000 | 100% | 11,899.03 | 11,876.33 | PASS |
| Publish-ACK, 5,000 messages, 128-byte payload | 5,000 | 5,000 | 100% | 13,848.10 | 12,762.98 | PASS |

The live result is at-most-once behavior under the benchmark drain deadline, not a broker failure: there were no gaps, duplicates, or invalid frames. The acknowledged results are the stronger integrity evidence. These are local single-publisher/single-consumer measurements, not a 100M messages/sec claim and not a multi-publisher or fan-out capacity result.

The latest branch should use native ZMV framing for the data plane. Protobuf or a similar schema format should be reserved for control-plane and SDK payloads unless a later benchmark proves a binary envelope is needed for selected application payloads.
