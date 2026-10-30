#!/usr/bin/env python3
"""Reason-key catalog gate (decisions 14.37 and 14.42).

Checks catalog/reasons.toml: every key is SCREAMING_SNAKE, its owner is
`router`, `host` or `coordinator`, its status a gRPC status name or
READINESS, its args snake_case names; no key is both active and retired;
and no retired key is named in the given directories' .feature and .proto
files.

Usage: check_reasons.py CATALOG DIR [DIR ...]
Exits 0 when all hold, 1 otherwise (one line per problem).
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

KEY_RE = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*$")
ARG_RE = re.compile(r"^[a-z][a-z0-9_]*$")
OWNERS = {"router", "host", "coordinator"}
STATUSES = {
    "READINESS", "CANCELLED", "UNKNOWN", "INVALID_ARGUMENT", "DEADLINE_EXCEEDED",
    "NOT_FOUND", "ALREADY_EXISTS", "PERMISSION_DENIED", "RESOURCE_EXHAUSTED",
    "FAILED_PRECONDITION", "ABORTED", "OUT_OF_RANGE", "UNIMPLEMENTED",
    "INTERNAL", "UNAVAILABLE", "DATA_LOSS", "UNAUTHENTICATED",
}


def problems(catalog: dict, dirs: list[Path]) -> list[str]:
    out: list[str] = []
    keys = catalog.get("keys", {})
    for key, entry in keys.items():
        if not KEY_RE.match(key):
            out.append(f"{key}: not SCREAMING_SNAKE")
        if entry.get("owner") not in OWNERS:
            out.append(f"{key}: owner must be one of {sorted(OWNERS)}")
        if entry.get("status") not in STATUSES:
            out.append(f"{key}: unknown status {entry.get('status')!r}")
        for arg in entry.get("args", None) or []:
            if not ARG_RE.match(arg):
                out.append(f"{key}: arg {arg!r} is not snake_case")
        if "args" not in entry:
            out.append(f"{key}: no args list")
    retired = {k for ks in catalog.get("retired", {}).values() for k in ks}
    for key in sorted(retired & set(keys)):
        out.append(f"{key}: both active and retired")
    pattern = re.compile(r"\b(" + "|".join(sorted(retired)) + r")\b") if retired else None
    for d in dirs:
        for path in sorted(list(d.rglob("*.feature")) + list(d.rglob("*.proto"))):
            for n, line in enumerate(path.read_text().splitlines(), 1):
                if pattern and (m := pattern.search(line)):
                    out.append(f"{path}:{n}: names retired key {m.group(1)}")
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    catalog = tomllib.loads(Path(argv[0]).read_text())
    found = problems(catalog, [Path(d) for d in argv[1:]])
    for p in found:
        print(p)
    if not found:
        print(f"check-reasons: {len(catalog.get('keys', {}))} key(s) OK")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
