#!/usr/bin/env python3
"""Reason-key gate for reasons.proto (decision 14.44).

The framework's reason keys are the enums of ``io/angzarr/v1/reasons.proto``:
a key travels as its value's full name, its enum's prefix included, and every
enum reserves every retired key under its prefix, so none is answered or
reused again. This checks those spec-level rules on the compiled descriptor,
``buf build -o -#format=json`` of reasons.proto (``just check-reason-keys``
runs buf in its pinned container):

- the file declares exactly RouterReason, HostReason and CoordinatorReason;
- each enum's 0 is ``<PREFIX>UNSPECIFIED`` and its live keys are numbered
  densely from 1;
- every live key is ``<PREFIX><SCREAMING_SNAKE>``, and no key is in two enums;
- every enum reserves exactly RETIRED under its prefix, reserves no number
  (numbers are bookkeeping), and answers no retired key;
- the owners' keys pinned by decisions 14.45 to 14.48 are there.

Ported from angzarr-proto's ``tests/reasons.rs`` when the Rust crates moved to
angzarr-core; the generated-code assertions (``as_str_name`` and friends) stay
with the crate there.

Usage: check_reason_keys.py DESCRIPTOR.json   (``-`` reads stdin)

Exits 0 when every rule holds, 1 otherwise (one line per problem).
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any

REASONS_PROTO = "io/angzarr/v1/reasons.proto"

PREFIXES = {
    "RouterReason": "ROUTER_REASON_",
    "HostReason": "HOST_REASON_",
    "CoordinatorReason": "COORDINATOR_REASON_",
}

# The keys decisions 14.37, 14.39 and 14.42 retired, as they were answered:
# bare, before the prefix.
RETIRED = (
    # 14.37
    "MALFORMED_REFUSAL_FACT",
    "DUPLICATE_REGISTRATION",
    "NO_HANDLER_REGISTERED",
    # 14.39
    "DUPLICATE_UPCASTER_CHAIN",
    "DUPLICATE_COMMAND_HANDLER",
    # 14.42
    "MISSING_COMMAND_BOOK",
    "MISSING_COMMAND_PAGE",
    "MISSING_COMMAND_PAYLOAD",
    "MISSING_EVENT_BOOK_COVER",
    "EMPTY_POLICY_SOURCE",
    "POLICY_SOURCE_OUTSIDE_INPUT_DOMAIN",
    "REFUSAL_FACT_MISSING",
    "REFUSAL_WITHOUT_COMMAND",
    "REFUSAL_WITHOUT_EVENT",
    "REFUSAL_WITHOUT_REFUSED_COMMAND",
    "REFUSED_COMMAND_WITHOUT_ID",
    "REFUSAL_WITHOUT_TRIGGER_STREAM",
    "HOST_STATUS_UNDECODABLE",
    "NULL_ABI_POINTER",
)

# HostReason's keys, exactly, in number order.
HOST_KEYS = (
    "HOST_REASON_UPCASTER_WITH_COMPONENT",
    "HOST_REASON_NO_COMPONENTS_REGISTERED",
)

# Keys an owner's decision pinned; each must be live.
PINNED = (
    "ROUTER_REASON_DUPLICATE_COMPONENT",
    "COORDINATOR_REASON_PM_NO_INSTANCE",
    # 14.45
    "COORDINATOR_REASON_EXPECTED_SEQUENCE_STALE",
    # 14.46
    "COORDINATOR_REASON_RETRY_CAP_EXHAUSTED",
    # 14.47
    "COORDINATOR_REASON_EXPECTED_SEQUENCE_AHEAD",
    # 14.48, amended
    "COORDINATOR_REASON_POLICY_COMMAND_WITH_HANDLING",
    "COORDINATOR_REASON_EDITION_REMOVAL_FAILED",
    "COORDINATOR_REASON_POLICY_COMMAND_OTHER_IDENTITY",
    "COORDINATOR_REASON_POLICY_COMMAND_IS_FACT",
    "COORDINATOR_REASON_POLICY_COMMAND_FACT_ORIGIN",
)

SCREAMING_SNAKE = re.compile(r"^[A-Z0-9_]+$")


def check(descriptor: dict[str, Any]) -> list[str]:
    """Every rule broken by the descriptor set, one message each."""
    files = [f for f in descriptor.get("file", []) if f.get("name") == REASONS_PROTO]
    if len(files) != 1:
        return [f"{REASONS_PROTO}: not in the descriptor set exactly once ({len(files)} found)"]
    enums = files[0].get("enumType", [])
    problems: list[str] = []
    names = sorted(e.get("name", "") for e in enums)
    if names != sorted(PREFIXES):
        problems.append(f"enums are {names}, expected {sorted(PREFIXES)}")

    live_by_enum: dict[str, list[str]] = {}
    for e in enums:
        name = e.get("name", "")
        prefix = PREFIXES.get(name)
        if prefix is None:
            continue
        values = e.get("value", [])
        by_number = {v.get("number", 0): v.get("name", "") for v in values}
        if by_number.get(0) != f"{prefix}UNSPECIFIED":
            problems.append(f"{name}: 0 is {by_number.get(0)!r}, expected {prefix}UNSPECIFIED")
        live_numbers = sorted(n for n in by_number if n != 0)
        if live_numbers != list(range(1, len(live_numbers) + 1)):
            problems.append(f"{name}: live keys are not numbered densely from 1: {live_numbers}")
        live = [by_number[n] for n in live_numbers]
        live_by_enum[name] = live
        if not live:
            problems.append(f"{name}: no keys")
        for key in live:
            rest = key[len(prefix) :] if key.startswith(prefix) else ""
            if not rest:
                problems.append(f"{name}: {key} does not carry the prefix {prefix}")
            if not SCREAMING_SNAKE.match(key):
                problems.append(f"{name}: {key} is not SCREAMING_SNAKE")
            if rest in RETIRED:
                problems.append(f"{name}: {key} is retired")

        retired = {f"{prefix}{k}" for k in RETIRED}
        reserved = set(e.get("reservedName", []))
        for key in sorted(retired - reserved):
            problems.append(f"{name}: retired key {key} is not reserved")
        for key in sorted(reserved - retired):
            problems.append(f"{name}: {key} is reserved but not retired")
        if e.get("reservedRange"):
            problems.append(f"{name}: reserves numbers; numbers are bookkeeping")

    every = [k for keys in live_by_enum.values() for k in keys]
    for key in sorted({k for k in every if every.count(k) > 1}):
        problems.append(f"{key}: a key in two enums")
    if "HostReason" in live_by_enum and tuple(live_by_enum["HostReason"]) != HOST_KEYS:
        problems.append(f"HostReason: keys are {live_by_enum['HostReason']}, expected {list(HOST_KEYS)}")
    for key in PINNED:
        if key not in every:
            problems.append(f"{key}: a decision pins it, and it is not a live key")
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: check_reason_keys.py DESCRIPTOR.json  (- reads stdin)", file=sys.stderr)
        return 2
    src = sys.stdin if argv[1] == "-" else open(argv[1], encoding="utf-8")
    with src:
        descriptor = json.load(src)
    problems = check(descriptor)
    for p in problems:
        print(f"FAIL check-reason-keys: {p}", file=sys.stderr)
    if problems:
        return 1
    print(f"ok   check-reason-keys ({len(PREFIXES)} enums, every key prefixed, {len(RETIRED)} retired keys reserved)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
