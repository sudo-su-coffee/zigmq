#!/usr/bin/env python3
"""Verify the optional Prometheus metrics listener."""
import argparse
import http.client
import subprocess
import time


def main(binary: str, broker_port: int, metrics_port: int) -> None:
    process = subprocess.Popen(
        [binary, "--protocol", "zigmv", "--host", "127.0.0.1", "--port", str(broker_port), "--metrics-port", str(metrics_port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        time.sleep(0.5)
        connection = http.client.HTTPConnection("127.0.0.1", metrics_port, timeout=3)
        connection.request("GET", "/metrics")
        response = connection.getresponse()
        body = response.read().decode("utf-8")
        connection.close()
        if response.status != 200:
            raise RuntimeError(f"unexpected metrics status: {response.status}")
        for endpoint in ("/health", "/readyz"):
            connection = http.client.HTTPConnection("127.0.0.1", metrics_port, timeout=3)
            connection.request("GET", endpoint)
            health_response = connection.getresponse()
            health_body = health_response.read().decode("utf-8")
            connection.close()
            if health_response.status != 200 or health_body != "ok\n":
                raise RuntimeError(f"{endpoint} check failed: {health_response.status} {health_body!r}")
        if "text/plain" not in response.getheader("Content-Type", ""):
            raise RuntimeError("metrics response did not advertise text exposition")
        for metric in ("zigmv_build_info", "zigmv_clients", "zigmv_published_total", "zigmv_pending_durable"):
            if metric not in body:
                raise RuntimeError(f"missing metric {metric}")
        print("prometheus metrics test passed")
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--broker-port", type=int, default=4232)
    parser.add_argument("--metrics-port", type=int, default=9092)
    args = parser.parse_args()
    main(args.binary, args.broker_port, args.metrics_port)
