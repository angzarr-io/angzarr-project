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
- the owners' keys pinned by decisions 14.45 to 14.49 are there;
- every live key declares its args on its ``(io.angzarr.v1.reason)``
  option, ``{}`` for none, each name snake_case and declared once
  (decision 14.60);

and, given the en-US catalog beside the proto (``reasons.en-US.ftl``,
decision 14.60), that it holds one message per live key and no other, each
naming only args its key declares, and never its ``cause``, which renders as
a key of its own.

Ported from angzarr-proto's ``tests/reasons.rs`` when the Rust crates moved to
angzarr-core; the generated-code assertions (``as_str_name`` and friends) stay
with the crate there.

Usage: check_reason_keys.py DESCRIPTOR.json CATALOG.ftl   (``-`` reads the
descriptor from stdin)

Exits 0 when every rule holds, 1 otherwise (one line per problem).
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any

REASONS_PROTO = "io/angzarr/v1/reasons.proto"

# The en-US catalog of the keys, from the repository root.
CATALOG = "proto/io/angzarr/v1/reasons.en-US.ftl"

# How buf's JSON descriptor names the (io.angzarr.v1.reason) option.
REASON_OPTION = "[io.angzarr.v1.reason]"

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
    "HOST_REASON_DESCRIPTOR_RULES_VERSION_MISMATCH",
    "HOST_REASON_PROJECTOR_NO_INPUT_DOMAIN",
    "HOST_REASON_HANDSHAKE_MALFORMED",
    "HOST_REASON_HANDSHAKE_TIMEOUT",
    "HOST_REASON_HANDSHAKE_CLOSED",
    "HOST_REASON_CHILD_NOT_SERVING",
    "HOST_REASON_CHILD_EXIT_STATUS",
    "HOST_REASON_CHILD_NOT_EXITED",
    "HOST_REASON_PROBE_INPUT",
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
    # 14.49
    "COORDINATOR_REASON_POLICY_COMMAND_UNKNOWN_DOMAIN",
    "COORDINATOR_REASON_HANDLER_UNAVAILABLE",
    "COORDINATOR_REASON_CHAIN_TOO_DEEP",
    "ROUTER_REASON_TOO_MANY_STEPS",
    # 14.51
    "COORDINATOR_REASON_STORE_CONFLICT",
    "COORDINATOR_REASON_STORE_UNAVAILABLE",
    "COORDINATOR_REASON_UPCASTER_UNAVAILABLE",
    "COORDINATOR_REASON_COMPONENT_NOT_REGISTERED",
    "COORDINATOR_REASON_COMMANDS_NOT_SERVED",
    "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE",
    # 14.55
    "HOST_REASON_PROJECTOR_NO_INPUT_DOMAIN",
    # 14.56
    "COORDINATOR_REASON_RULES_VERSION_MISMATCH",
    # 14.59
    "HOST_REASON_HANDSHAKE_MALFORMED",
    # 14.62
    "HOST_REASON_HANDSHAKE_TIMEOUT",
    "HOST_REASON_HANDSHAKE_CLOSED",
    "HOST_REASON_CHILD_NOT_SERVING",
    "HOST_REASON_CHILD_EXIT_STATUS",
    "HOST_REASON_CHILD_NOT_EXITED",
    "HOST_REASON_PROBE_INPUT",
)

SCREAMING_SNAKE = re.compile(r"^[A-Z0-9_]+$")
SNAKE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")


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
    problems.extend(_arg_problems(enums))
    return problems


def _live_values(enums: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every value but the zeros of the enums this checks."""
    return [v for e in enums if e.get("name") in PREFIXES for v in e.get("value", []) if v.get("number", 0) != 0]


def _arg_problems(enums: list[dict[str, Any]]) -> list[str]:
    """Each live key's (reason) option: present, its args snake_case, each once."""
    problems: list[str] = []
    for value in _live_values(enums):
        key = value.get("name", "")
        option = value.get("options", {}).get(REASON_OPTION)
        if option is None:
            problems.append(f"{key}: declares no args (its (reason) option is missing)")
            continue
        args = option.get("args", [])
        for arg in args:
            if not SNAKE.match(arg):
                problems.append(f"{key}: arg {arg!r} is not snake_case")
        for arg in sorted({a for a in args if args.count(a) > 1}):
            problems.append(f"{key}: arg {arg} declared twice")
    return problems


def _reasons_enums(descriptor: dict[str, Any]) -> list[dict[str, Any]]:
    """reasons.proto's enums: the first such file's (check reports a second)."""
    for f in descriptor.get("file", []):
        if f.get("name") == REASONS_PROTO:
            return f.get("enumType", [])
    return []


def declared_args(descriptor: dict[str, Any]) -> dict[str, list[str]]:
    """Each live key's declared args, by key: what its (reason) option names."""
    return {
        v.get("name", ""): list(v.get("options", {}).get(REASON_OPTION, {}).get("args", []))
        for v in _live_values(_reasons_enums(descriptor))
    }


MESSAGE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*) =(?: (.*))?$")
VARIABLE = re.compile(r"\$([A-Za-z][A-Za-z0-9_-]*)")


def parse_catalog(text: str) -> tuple[dict[str, set[str]], list[str]]:
    """The catalog's messages, each id with the variables it names, and its
    problems: a message twice, a line that is no comment, message or
    continuation. The subset of Fluent a catalog of messages uses."""
    messages: dict[str, set[str]] = {}
    problems: list[str] = []
    current: str | None = None
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            current = None
            continue
        if line.startswith(" ") and current is not None:
            messages[current] |= set(VARIABLE.findall(line))
            continue
        match = MESSAGE.match(line)
        if match is None:
            problems.append(f"line {number}: not a message, comment or continuation: {line!r}")
            current = None
            continue
        current = match.group(1)
        if current in messages:
            problems.append(f"{current}: two messages")
        messages[current] = set(VARIABLE.findall(match.group(2) or ""))
    return messages, problems


def check_catalog(descriptor: dict[str, Any], text: str) -> list[str]:
    """Every rule the catalog `text` breaks against the descriptor's keys."""
    declared = declared_args(descriptor)
    messages, problems = parse_catalog(text)
    for key in declared:
        if key not in messages:
            problems.append(f"{key}: no message in the catalog")
    for key, variables in sorted(messages.items()):
        if key not in declared:
            problems.append(f"{key}: a message for no live key")
            continue
        if "cause" in variables:
            problems.append(f"{key}: names its cause, which renders as its own key")
        undeclared = sorted(variables - set(declared[key]))
        if undeclared:
            problems.append(f"{key}: names {', '.join(undeclared)}, which it does not declare")
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: check_reason_keys.py DESCRIPTOR.json CATALOG.ftl  (- reads stdin)", file=sys.stderr)
        return 2
    src = sys.stdin if argv[1] == "-" else open(argv[1], encoding="utf-8")
    with src:
        descriptor = json.load(src)
    with open(argv[2], encoding="utf-8") as ftl:
        catalog = ftl.read()
    problems = check(descriptor) + check_catalog(descriptor, catalog)
    for p in problems:
        print(f"FAIL check-reason-keys: {p}", file=sys.stderr)
    if problems:
        return 1
    print(
        f"ok   check-reason-keys ({len(PREFIXES)} enums, every key prefixed and its args declared, "
        f"{len(RETIRED)} retired keys reserved, {len(declared_args(descriptor))} messages in the catalog)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
