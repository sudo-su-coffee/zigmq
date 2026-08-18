#!/usr/bin/env python3
"""Preflight checks for a stable ZigMV release candidate.

This script validates release metadata and claim boundaries. It deliberately
never creates tags or GitHub releases.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--artifact-dir", type=pathlib.Path)
    args = parser.parse_args()
    root = pathlib.Path(args.root)
    failures: list[str] = []

    root_zig = root / "src" / "root.zig"
    changelog = root / "CHANGELOG.md"
    if not root_zig.exists() or f'pub const version = "{args.expected_version}";' not in root_zig.read_text():
        failures.append(f"src/root.zig does not declare {args.expected_version}")
    if not changelog.exists() or not re.search(rf"## \[{re.escape(args.expected_version)}\]", changelog.read_text()):
        failures.append(f"CHANGELOG.md has no {args.expected_version} heading")

    docs = "\n".join(
        path.read_text(errors="replace")
        for path in [root / "README.md", root / "CHANGELOG.md", root / "docs" / "ZIGMV_PROTOCOL.md"]
        if path.exists()
    ).lower()
    required_nonclaims = ("qos 2", "jetstream", "distributed replication", "exactly-once")
    for term in required_nonclaims:
        if term not in docs:
            failures.append(f"known limitation is not documented: {term}")

    if args.artifact_dir:
        sums = args.artifact_dir / "SHA256SUMS"
        if not sums.exists():
            failures.append(f"missing checksum manifest: {sums}")
        else:
            for line in sums.read_text().splitlines():
                fields = line.split(maxsplit=1)
                if len(fields) != 2:
                    failures.append(f"malformed checksum line: {line}")
                    continue
                expected, name = fields
                artifact = args.artifact_dir / name.lstrip("*")
                if not artifact.exists():
                    failures.append(f"checksum references missing artifact: {name}")
                    continue
                actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
                if actual != expected:
                    failures.append(f"checksum mismatch: {name}")

    if failures:
        print("STABLE_RELEASE_PREFLIGHT_FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"STABLE_RELEASE_PREFLIGHT_PASS version={args.expected_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
