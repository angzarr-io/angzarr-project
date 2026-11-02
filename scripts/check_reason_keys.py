#!/usr/bin/env python3
"""Reason-key gate for the framework's reasons.proto files (decisions 14.44
and 14.64).

The framework's reason keys are the enums of three files, one per package
whose code raises them (decision 14.64): core's
``io/angzarr/v1/reasons.proto`` (RouterReason, HostReason, CoordinatorReason),
the local-process transport's ``io/angzarr/transport/embedded/v1/reasons.proto``
(HostReason) and the distributed transport's
``io/angzarr/transport/distributed/v1/reasons.proto`` (CoordinatorReason). A
key travels as its value's full name, its enum's prefix included, and every
enum reserves every retired key under its prefix, so none is answered or
reused again. This checks those spec-level rules on the compiled descriptor,
``buf build -o -#format=json`` of the three files (``just check-reason-keys``
runs buf in its pinned container):

- each file declares exactly its enums (REASON_FILES), and core's its
  statuses' (STATUS_ENUMS);
- each enum's 0 is ``<PREFIX>UNSPECIFIED``, and its live keys with the
  numbers it reserves are numbered densely from 1;
- every live key is ``<PREFIX><SCREAMING_SNAKE>``, and no key is in two
  enums, in any file: a key's string is what travels;
- every enum reserves exactly RETIRED under its prefix and, in core's file,
  the names of the keys MOVED from it to a transport; each key
  RETIRED_NUMBERED, by its name in its own file's enum; a number only for a
  moved key or a key retired by number; and answers no retired key;
- every MOVED key is live in its transport's file, and the two HostReasons
  hold exactly their keys (HOST_KEYS);
- the owners' keys pinned by decisions 14.45 to 14.49 are there;
- every live key declares its args on its ``(io.angzarr.v1.reason)``
  option, each name snake_case and declared once (decision 14.60), and its
  gRPC status, never ``REASON_STATUS_UNSPECIFIED`` (decision 14.65);
- every key that concerns one stream (STREAM_KEYS) declares a ``stream``
  arg (decision 14.65), and the keys a decision pins with a status and
  args (PINNED_STATUS, PINNED_ARGS) declare exactly those;

and, given the proto root, that the en-US catalog beside each file
(``reasons.en-US.ftl``, decisions 14.60 and 14.64) holds one message per
live key of that file and no other, each naming only args its key declares,
and never its ``cause``, which renders as a key of its own.

Ported from angzarr-proto's ``tests/reasons.rs`` when the Rust crates moved to
angzarr-core; the generated-code assertions (``as_str_name`` and friends) stay
with the crates there.

Usage: check_reason_keys.py DESCRIPTOR.json PROTO_ROOT   (``-`` reads the
descriptor from stdin)

Exits 0 when every rule holds, 1 otherwise (one line per problem).
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any

# Each reasons.proto, by its path under the proto root, and the enums it
# declares (decision 14.64): core's, then each transport's.
CORE = "io/angzarr/v1/reasons.proto"
EMBEDDED = "io/angzarr/transport/embedded/v1/reasons.proto"
DISTRIBUTED = "io/angzarr/transport/distributed/v1/reasons.proto"
REASON_FILES = {
    CORE: ("RouterReason", "HostReason", "CoordinatorReason"),
    EMBEDDED: ("HostReason",),
    DISTRIBUTED: ("CoordinatorReason",),
}

# The enums a reasons.proto declares beside its key enums: core's statuses
# (decision 14.65), which no key enum's rules apply to.
STATUS_ENUMS = {CORE: ("ReasonStatus",)}

# Each file's en-US catalog sits beside it, under this name.
CATALOG_NAME = "reasons.en-US.ftl"

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

# The keys retired after the prefix (decision 14.44), each answered under its
# full name and a number: its own file's enum reserves both, and no enum
# answers it again.
RETIRED_NUMBERED = {
    # 14.69: a policy emits the facts its destination declares.
    "COORDINATOR_REASON_POLICY_COMMAND_IS_FACT": CORE,
}

# The keys decision 14.64 moved from core's file to a transport's, each
# string unchanged, by the file it now lives in. Core's enum reserves each
# one's name and number.
MOVED = {
    "HOST_REASON_HANDSHAKE_MALFORMED": EMBEDDED,
    "HOST_REASON_HANDSHAKE_TIMEOUT": EMBEDDED,
    "HOST_REASON_HANDSHAKE_CLOSED": EMBEDDED,
    "HOST_REASON_CHILD_NOT_SERVING": EMBEDDED,
    "HOST_REASON_CHILD_EXIT_STATUS": EMBEDDED,
    "HOST_REASON_CHILD_NOT_EXITED": EMBEDDED,
    "HOST_REASON_PROBE_INPUT": EMBEDDED,
    "COORDINATOR_REASON_COMPONENT_NOT_REGISTERED": DISTRIBUTED,
    "COORDINATOR_REASON_COMMANDS_NOT_SERVED": DISTRIBUTED,
    "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE": DISTRIBUTED,
}

# Each HostReason's keys, exactly, in number order: core's component host's
# configuration and composition keys, and whatever runs a child's.
HOST_KEYS = {
    CORE: (
        "HOST_REASON_UPCASTER_WITH_COMPONENT",
        "HOST_REASON_NO_COMPONENTS_REGISTERED",
        "HOST_REASON_DESCRIPTOR_RULES_VERSION_MISMATCH",
        "HOST_REASON_PROJECTOR_NO_INPUT_DOMAIN",
        "HOST_REASON_UPCASTER_UNKNOWN_DOMAIN",
        "HOST_REASON_UPCASTER_OTHER_DOMAIN",
        "HOST_REASON_RESOLUTION_UNSUPPORTED",
        "HOST_REASON_REMOTE_SOURCE",
        "HOST_REASON_STATE_TYPE_MISMATCH",
    ),
    EMBEDDED: (
        "HOST_REASON_HANDSHAKE_MALFORMED",
        "HOST_REASON_HANDSHAKE_TIMEOUT",
        "HOST_REASON_HANDSHAKE_CLOSED",
        "HOST_REASON_CHILD_NOT_SERVING",
        "HOST_REASON_CHILD_EXIT_STATUS",
        "HOST_REASON_CHILD_NOT_EXITED",
        "HOST_REASON_PROBE_INPUT",
    ),
}

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
    # 14.65
    "COORDINATOR_REASON_EVENTS_NOT_ITS_STREAM",
    "COORDINATOR_REASON_EDITION_NOT_FORKED",
    "HOST_REASON_UPCASTER_UNKNOWN_DOMAIN",
    "HOST_REASON_UPCASTER_OTHER_DOMAIN",
    "HOST_REASON_RESOLUTION_UNSUPPORTED",
    "HOST_REASON_REMOTE_SOURCE",
    "HOST_REASON_STATE_TYPE_MISMATCH",
    "COORDINATOR_REASON_STATE_RESOLUTIONS_INVALID",
    # 14.71
    "COORDINATOR_REASON_POLICY_TARGETS_ITS_TRIGGER",
)

# The coordinator's keys that concern one stream, each declaring a `stream`
# arg, the stream's text (decision 14.65, from the owner's ruling on
# decision 11 of the 2026-10-31 run).
STREAM_KEYS = (
    "COORDINATOR_REASON_CONFLICT_UNRESOLVED",
    "COORDINATOR_REASON_CONFLICT_OVERLAP",
    "COORDINATOR_REASON_PM_NO_INSTANCE",
    "COORDINATOR_REASON_EXPECTED_SEQUENCE_STALE",
    "COORDINATOR_REASON_RETRY_CAP_EXHAUSTED",
    "COORDINATOR_REASON_EXPECTED_SEQUENCE_AHEAD",
    "COORDINATOR_REASON_EDITION_REMOVAL_FAILED",
    "COORDINATOR_REASON_HANDLER_UNAVAILABLE",
    "COORDINATOR_REASON_STORE_CONFLICT",
    "COORDINATOR_REASON_RULES_VERSION_MISMATCH",
    "COORDINATOR_REASON_EVENTS_NOT_ITS_STREAM",
    "COORDINATOR_REASON_EDITION_NOT_FORKED",
    "COORDINATOR_REASON_POLICY_TARGETS_ITS_TRIGGER",
)

# The statuses and args a decision pins (14.65).
PINNED_STATUS = {
    "COORDINATOR_REASON_EVENTS_NOT_ITS_STREAM": "REASON_STATUS_INTERNAL",
    "COORDINATOR_REASON_EDITION_NOT_FORKED": "REASON_STATUS_FAILED_PRECONDITION",
    "COORDINATOR_REASON_POLICY_TARGETS_ITS_TRIGGER": "REASON_STATUS_INTERNAL",
}
PINNED_ARGS = {
    "COORDINATOR_REASON_EVENTS_NOT_ITS_STREAM": ["stream", "event_stream"],
    "COORDINATOR_REASON_EDITION_NOT_FORKED": ["stream", "edition"],
    "COORDINATOR_REASON_POLICY_TARGETS_ITS_TRIGGER": ["stream", "command_type"],
}

# A status option left unset, which no live key may.
NO_STATUS = "REASON_STATUS_UNSPECIFIED"

SCREAMING_SNAKE = re.compile(r"^[A-Z0-9_]+$")
SNAKE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")


def _files(descriptor: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    """Each reasons.proto the descriptor set holds, by path: its enums."""
    found: dict[str, list[dict[str, Any]]] = {}
    for f in descriptor.get("file", []):
        name = f.get("name")
        if name in REASON_FILES and name not in found:
            found[name] = f.get("enumType", [])
    return found


def check(descriptor: dict[str, Any]) -> list[str]:
    """Every rule broken by the descriptor set, one message each."""
    problems: list[str] = []
    for path in REASON_FILES:
        count = sum(1 for f in descriptor.get("file", []) if f.get("name") == path)
        if count != 1:
            problems.append(f"{path}: not in the descriptor set exactly once ({count} found)")
    files = _files(descriptor)
    live: dict[tuple[str, str], list[str]] = {}
    for path, enums in files.items():
        names = sorted(e.get("name", "") for e in enums)
        expected = sorted(REASON_FILES[path] + STATUS_ENUMS.get(path, ()))
        if names != expected:
            problems.append(f"{path}: enums are {names}, expected {expected}")
        for e in enums:
            if e.get("name", "") in REASON_FILES[path]:
                live[(path, e["name"])] = _check_enum(path, e, problems)
    every = [k for keys in live.values() for k in keys]
    for key in sorted({k for k in every if every.count(k) > 1}):
        problems.append(f"{key}: a key in two enums")
    for path, keys in HOST_KEYS.items():
        found = live.get((path, "HostReason"))
        if found is not None and tuple(found) != keys:
            problems.append(f"{path}: HostReason: keys are {found}, expected {list(keys)}")
    for key, path in MOVED.items():
        if path in files and key not in [k for (p, _), ks in live.items() if p == path for k in ks]:
            problems.append(f"{key}: moved to {path}, and not a live key there")
    for key in PINNED:
        if key not in every:
            problems.append(f"{key}: a decision pins it, and it is not a live key")
    for enums in files.values():
        problems.extend(_arg_problems(enums))
    return problems


def _check_enum(path: str, e: dict[str, Any], problems: list[str]) -> list[str]:
    """One key enum of `path`: its numbering, prefix and reservations. Returns
    its live keys, in number order; appends what it breaks to `problems`."""
    name = e.get("name", "")
    prefix = PREFIXES[name]
    by_number = {v.get("number", 0): v.get("name", "") for v in e.get("value", [])}
    if by_number.get(0) != f"{prefix}UNSPECIFIED":
        problems.append(f"{name}: 0 is {by_number.get(0)!r}, expected {prefix}UNSPECIFIED")
    reserved_numbers = [
        n for r in e.get("reservedRange", []) for n in range(r.get("start", 0), r.get("end", 0) + 1)
    ]
    live_numbers = sorted(n for n in by_number if n != 0)
    numbers = sorted(live_numbers + reserved_numbers)
    if numbers != list(range(1, len(numbers) + 1)):
        problems.append(f"{name}: live keys are not numbered densely from 1: {numbers}")
    live = [by_number[n] for n in live_numbers]
    if not live:
        problems.append(f"{name}: no keys")
    for key in live:
        rest = key[len(prefix) :] if key.startswith(prefix) else ""
        if not rest:
            problems.append(f"{name}: {key} does not carry the prefix {prefix}")
        if not SCREAMING_SNAKE.match(key):
            problems.append(f"{name}: {key} is not SCREAMING_SNAKE")
        if rest in RETIRED or key in RETIRED_NUMBERED:
            problems.append(f"{name}: {key} is retired")
        if path == CORE and key in MOVED:
            problems.append(f"{name}: {key} moved to {MOVED[key]}")
    retired = {f"{prefix}{k}" for k in RETIRED}
    moved = {k for k in MOVED if k.startswith(prefix)} if path == CORE else set()
    numbered = {k for k, p in RETIRED_NUMBERED.items() if p == path and k.startswith(prefix)}
    retired |= numbered
    reserved = set(e.get("reservedName", []))
    for key in sorted(retired - reserved):
        problems.append(f"{name}: retired key {key} is not reserved")
    for key in sorted(moved - reserved):
        problems.append(f"{name}: moved key {key} is not reserved")
    for key in sorted(reserved - retired - moved):
        problems.append(f"{name}: {key} is reserved but not retired")
    if len(reserved_numbers) != len(moved) + len(numbered):
        problems.append(
            f"{name}: reserves {len(reserved_numbers)} numbers, for {len(moved)} moved keys"
            f" and {len(numbered)} key{'' if len(numbered) == 1 else 's'} retired by number;"
            " numbers are bookkeeping"
        )
    return live


def _live_values(enums: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every value but the zeros of the enums this checks."""
    return [v for e in enums if e.get("name") in PREFIXES for v in e.get("value", []) if v.get("number", 0) != 0]


def _arg_problems(enums: list[dict[str, Any]]) -> list[str]:
    """Each live key's (reason) option: present, its args snake_case, each
    once, a key of one stream's naming `stream`, and its status declared;
    what a decision pins, as pinned."""
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
        if key in STREAM_KEYS and "stream" not in args:
            problems.append(f"{key}: concerns one stream and declares no stream arg")
        if key in PINNED_ARGS and args != PINNED_ARGS[key]:
            problems.append(f"{key}: args are {args}, and a decision pins {PINNED_ARGS[key]}")
        status = option.get("status", NO_STATUS)
        if status == NO_STATUS:
            problems.append(f"{key}: declares no status (its (reason) option's status)")
        elif key in PINNED_STATUS and status != PINNED_STATUS[key]:
            problems.append(f"{key}: status is {status}, and a decision pins {PINNED_STATUS[key]}")
    return problems


def declared_args(descriptor: dict[str, Any], path: str | None = None) -> dict[str, list[str]]:
    """Each live key's declared args, by key: what its (reason) option names;
    of the one file `path`, or of every reasons.proto."""
    return {
        v.get("name", ""): list(v.get("options", {}).get(REASON_OPTION, {}).get("args", []))
        for p, enums in _files(descriptor).items()
        if path in (None, p)
        for v in _live_values(enums)
    }


def declared_statuses(descriptor: dict[str, Any]) -> dict[str, str]:
    """Each live key's declared status, by key, as its (reason) option names
    it (a ReasonStatus value's name), across every reasons.proto."""
    return {
        v.get("name", ""): v.get("options", {}).get(REASON_OPTION, {}).get("status", NO_STATUS)
        for enums in _files(descriptor).values()
        for v in _live_values(enums)
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


def check_catalog(descriptor: dict[str, Any], text: str, path: str = CORE) -> list[str]:
    """Every rule the catalog `text` breaks against the keys of the file
    `path`, whose catalog it is."""
    declared = declared_args(descriptor, path)
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


def catalog_path(path: str) -> str:
    """The catalog beside the reasons.proto at `path`, under the proto root."""
    return f"{path.rsplit('/', 1)[0]}/{CATALOG_NAME}"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: check_reason_keys.py DESCRIPTOR.json PROTO_ROOT  (- reads stdin)", file=sys.stderr)
        return 2
    src = sys.stdin if argv[1] == "-" else open(argv[1], encoding="utf-8")
    with src:
        descriptor = json.load(src)
    problems = check(descriptor)
    for path in REASON_FILES:
        try:
            with open(f"{argv[2]}/{catalog_path(path)}", encoding="utf-8") as ftl:
                catalog = ftl.read()
        except FileNotFoundError:
            problems.append(f"{catalog_path(path)}: no catalog")
            continue
        problems.extend(f"{catalog_path(path)}: {p}" for p in check_catalog(descriptor, catalog, path))
    for p in problems:
        print(f"FAIL check-reason-keys: {p}", file=sys.stderr)
    if problems:
        return 1
    print(
        f"ok   check-reason-keys ({len(REASON_FILES)} files, every key prefixed and its args and status declared, "
        f"{len(RETIRED)} retired keys reserved, {len(MOVED)} moved keys reserved, "
        f"{len(declared_args(descriptor))} messages in the catalogs)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
