# ZigMV 0.5.0 benchmark and validation evidence

## Environment

The measurements below were collected in the repository sandbox using Zig `0.15.2`, a local ReleaseFast build, localhost TCP connections, and the current working tree. They are reproducibility evidence for this change, not universal capacity guarantees.

## Native ZigMV integrity benchmark

Command:

```sh
zig build -Doptimize=ReleaseFast
./zig-out/bin/zigmq --protocol zigmv --host 127.0.0.1 --port 6820
python3 scripts/benchmark_zigmv.py --messages 16 --payload-size 128 --drain-timeout 5 --port 6820
python3 scripts/benchmark_zigmv.py --messages 16 --payload-size 128 --drain-timeout 5 --ack-publishes --port 6820
```

Both modes passed with zero loss and zero integrity errors.

| Mode | Offered | Accepted | Delivered | Lost | Duplicates | Gaps | Invalid frames |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Live, no publish ACK | 16 | 16 | 16 | 0 | 0 | 0 | 0 |
| Live, publish ACK | 16 | 16 | 16 | 0 | 0 | 0 | 0 |

The small-batch rates are diagnostic only because the drain window and TCP setup dominate the elapsed time. Sustained throughput must be measured with the target-rate mode and a larger message count.

## Native 100M offered-rate stress target

Command:

```sh
python3 scripts/benchmark_zigmv.py \
  --duration 1 \
  --target-mps 100000000 \
  --payload-size 32 \
  --drain-timeout 10
```

Observed result on the development host:

| Metric | Result |
| --- | ---: |
| Offered target | 100,000,000 msg/s |
| Offered and socket-accepted | 128,275 |
| Delivered | 104,950 |
| Lost before the drain deadline | 23,325 |
| Accepted rate | 126,458.87 msg/s |
| Delivered rate over the full drain window | 9,524.66 msg/s |
| Gaps, duplicates, invalid frames | 0, 0, 0 |

This is a valid overload and integrity result, not evidence that ZigMV achieved 100M messages/sec. The target is intentionally much higher than the local host can sustain so the benchmark exposes the difference between offered load and end-to-end delivery.

## Controlled acknowledged target

Command:

```sh
python3 scripts/benchmark_zigmv.py \
  --duration 3 \
  --target-mps 35000 \
  --payload-size 32 \
  --ack-publishes \
  --drain-timeout 25
```

Observed result:

| Metric | Result |
| --- | ---: |
| Target | 35,000 msg/s |
| Accepted and delivered | 42,487 messages |
| Measured acknowledged rate | 14,162.23 msg/s |
| Lost, gaps, duplicates, invalid frames | 0, 0, 0, 0 |

The acknowledged rate is limited by the Python benchmark client and per-message ACK round trips. A production throughput comparison requires a compiled benchmark client or batched ACK protocol.

## Feature and compatibility validation

| Test | Result |
| --- | --- |
| `zig build test` | Passed |
| ReleaseFast build | Passed |
| `scripts/zigmv_test.py` | `zigmv smoke test passed` |
| `scripts/e2e_test.py` | `E2E_OK` |
| `scripts/edge_features_test.py` | `EDGE_FEATURES_OK` |
| `scripts/stream_test.py` | `STREAM_OK` |
| `scripts/cli_test.py` | `CLI_E2E_OK` |
| `scripts/python_ffi_test.py` | `PYTHON_FFI_OK` |
| `scripts/nats_index_test.py` | `NATS_INDEX_OK` |
| `scripts/mqtt_compat_test.py` | `MQTT_COMPAT_OK` |
| `scripts/security_hardening_test.py` | `SECURITY_HARDENING_OK` |
| `scripts/realtime_scenarios.py` | `REALTIME_SCENARIOS_OK` |

## Remaining performance gates

The next performance work should replace the Python publisher with a compiled multi-publisher client, add latency histograms, expose queue occupancy and blocked-publisher time, benchmark payload sizes from 0 bytes to 64 KiB, and compare 1, 10, 50, and 100 subscribers. The broker must report accepted, queued, delivered, lost, duplicate, and retry counts separately before a throughput claim is considered release evidence.
