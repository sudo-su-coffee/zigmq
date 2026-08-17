#!/usr/bin/env python3
"""Validate repository-local prerequisites for a ZigMV beta release."""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--expected-version", required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.root)
    failures: list[str] = []

    root_zig = root / "src/root.zig"
    if not root_zig.exists() or f'pub const version = "{args.expected_version}";' not in root_zig.read_text():
        failures.append(f"version metadata does not match {args.expected_version}")

    docs_config = root / "docs-site/docs.json"
    if docs_config.exists():
        try:
            config = json.loads(docs_config.read_text())
            for group in config.get("navigation", {}).get("groups", []):
                for page in group.get("pages", []):
                    page_path = root / "docs-site" / f"{page}.mdx"
                    if not page_path.exists():
                        failures.append(f"missing documentation page: {page_path}")
        except json.JSONDecodeError as error:
            failures.append(f"invalid docs-site/docs.json: {error}")
    else:
        failures.append("missing docs-site/docs.json")

    required = [
        "src/main.zig",
        "src/metrics.zig",
        "src/zigmv_persist.zig",
        "scripts/benchmark_zigmv.py",
        "scripts/benchmark_matrix.py",
        "docs/ZIGMV_BETA_RELEASE_GATES.md",
    ]
    for relative in required:
        if not (root / relative).exists():
            failures.append(f"missing release artifact: {relative}")

    gates = root / "docs/ZIGMV_BETA_RELEASE_GATES.md"
    if gates.exists():
        text = gates.read_text()
        if "100M messages/sec" not in text:
            failures.append("benchmark gate does not document the offered-rate boundary")
        if "Only profiles with complete evidence" not in text:
            failures.append("beta gate does not require complete profile evidence")

    changelog = root / "CHANGELOG.md"
    if changelog.exists() and not re.search(rf"## \[{re.escape(args.expected_version)}\]", changelog.read_text()):
        failures.append(f"CHANGELOG.md has no heading for {args.expected_version}")

    if failures:
        print("RELEASE_GATE_FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"RELEASE_GATE_PASS version={args.expected_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
