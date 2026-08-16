# Getting started with zigmq

This guide gets a local `0.2.0-beta.1` build running in a few minutes.

## Requirements

Install Zig 0.15.2 and Python 3 for the repository integration tests.

## Build

```sh
git clone https://github.com/sudo-su-coffee/zigmq.git
cd zigmq
zig build -Doptimize=ReleaseFast
```

Check the binary:

```sh
./zig-out/bin/zigmq --version
```

Expected output:

```text
zigmq 0.2.0-beta.1
```

## Start a server

The simplest server uses the custom protocol:

```sh
./zig-out/bin/zigmq
```

It listens on `127.0.0.1:4222`.

For the native protocol:

```sh
./zig-out/bin/zigmq --protocol zmp --port 4222
```

## Send a first message

The custom protocol is line-oriented. Connect with any TCP client, for example:

```sh
nc 127.0.0.1 4222
```

Then type:

```text
SUB demo.>\r\n
PUB demo.hello hello-from-zigmq\r\n
```

The subscriber receives a `MSG` frame. Use `PING` to check that the connection is alive.

## Use native ZMP

A ZMP client subscribes with a delivery profile and publishes a length-delimited payload:

```text
ZMP/1 SUB live demo.>\r\n
ZMP/1 PUB live 1 demo.hello 16\r\n
hello-from-zigmq\r\n
```

Only the `live` profile is implemented in the beta. `work`, `durable`, `state`, and `exact` are defined in the protocol plan but are rejected until their complete state machines are ready.

## Enable a local stream

```sh
./zig-out/bin/zigmq --stream ./data/events.zmq
```

The stream is useful for local replay experiments. It is not replicated storage.

## Run tests

```sh
zig build test
python3 scripts/e2e_test.py --binary ./zig-out/bin/zigmq
python3 scripts/security_hardening_test.py --binary ./zig-out/bin/zigmq
```

For the full test list and benchmark matrix, see the [README](../README.md).
