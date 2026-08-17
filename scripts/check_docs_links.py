#!/usr/bin/env python3
"""Validate relative Markdown links resolve inside the repository."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
errors: list[str] = []
for path in ROOT.rglob("*.md"):
    if ".git" in path.parts or "zig-out" in path.parts:
        continue
    for target in LINK.findall(path.read_text(encoding="utf-8")):
        target = target.split("#", 1)[0].strip()
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        candidate = (path.parent / target).resolve()
        if not candidate.exists():
            errors.append(f"{path.relative_to(ROOT)} -> {target}")
if errors:
    print("DOC_LINKS_FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
print("DOC_LINKS_PASS")
