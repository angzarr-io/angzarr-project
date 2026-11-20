#!/usr/bin/env python3
"""Reason-key gate for the framework's reasons.proto files (decisions 14.44
and 14.64).

The framework's reason keys are the enums of three files, one per layer
(decisions 14.64 and 14.104): core's ``io/angzarr/v1/reasons.proto``
(AngzarrReason, ``ANGZARR_REASON_*``), the local-process transport's
``io/angzarr/transport/embedded/v1/reasons.proto`` (EmbeddedReason,
``EMBEDDED_REASON_*``) and the distributed transport's
``io/angzarr/transport/distributed/v1/reasons.proto`` (DistributedReason,
``DISTRIBUTED_REASON_*``). A key travels as its value's full name, its enum's
prefix included; which component raises it is in its comment, never its
string. Only live keys are checked: a removed key leaves nothing
behind (no reserved name or number), and the live keys stay numbered
densely. This checks those spec-level rules on the compiled descriptor,
``buf build -o -#format=json`` of the three files (``just check-reason-keys``
runs buf in its pinned container):

- each file declares exactly its enum (REASON_FILES);
- each key enum's 0 is ``<PREFIX>UNSPECIFIED``, and its live keys are
  numbered densely from 1;
- every live key is ``<PREFIX><SCREAMING_SNAKE>``, the prefix not alone, and
  no key is in two enums, in any file: a key's string is what travels;
- EmbeddedReason holds exactly its keys, in number order (EXACT_KEYS);
- the keys an owner's decision pins (PINNED) are live;
- every live key declares its args on its ``(io.angzarr.v1.reason)``
  option, each name snake_case and declared once (decision 14.60), and
  exactly one surface: its gRPC status (``grpc_status``, a google.rpc.Code,
  never ``OK``; decisions 14.65 and 14.104) or ``readiness``, a
  readiness refusal that travels as no status;
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
    CORE: ("AngzarrReason",),
    EMBEDDED: ("EmbeddedReason",),
    DISTRIBUTED: ("DistributedReason",),
}

# Each file's en-US catalog sits beside it, under this name.
CATALOG_NAME = "reasons.en-US.ftl"

# How buf's JSON descriptor names the (io.angzarr.v1.reason) option, and
# the option's two surfaces, one of which each live key declares.
REASON_OPTION = "[io.angzarr.v1.reason]"
GRPC_STATUS = "grpcStatus"
READINESS_SURFACE = "readiness"

# Each enum's prefix: its layer (decision 14.104), never a role.
PREFIXES = {
    "AngzarrReason": "ANGZARR_REASON_",
    "EmbeddedReason": "EMBEDDED_REASON_",
    "DistributedReason": "DISTRIBUTED_REASON_",
}

# The enums whose keys a decision pins exactly, in number order: whatever
# runs a child's (decision 14.62).
EXACT_KEYS = {
    (EMBEDDED, "EmbeddedReason"): (
        "EMBEDDED_REASON_CHILD_NOT_SERVING",
        "EMBEDDED_REASON_CHILD_EXIT_STATUS",
        "EMBEDDED_REASON_CHILD_NOT_EXITED",
        "EMBEDDED_REASON_PROBE_INPUT",
    ),
}

# Keys an owner's decision pinned; each must be live.
PINNED = (
    "ANGZARR_REASON_DUPLICATE_COMPONENT",
    "ANGZARR_REASON_PM_NO_INSTANCE",
    # 14.46
    "ANGZARR_REASON_RETRY_CAP_EXHAUSTED",
    # 14.48, amended
    "ANGZARR_REASON_EDITION_REMOVAL_FAILED",
    # 14.49
    "ANGZARR_REASON_POLICY_COMMAND_UNKNOWN_DOMAIN",
    "ANGZARR_REASON_HANDLER_UNAVAILABLE",
    "ANGZARR_REASON_CHAIN_TOO_DEEP",
    # 14.51
    "ANGZARR_REASON_STORE_UNAVAILABLE",
    "ANGZARR_REASON_UPCASTER_UNAVAILABLE",
    "DISTRIBUTED_REASON_COMPONENT_NOT_REGISTERED",
    "DISTRIBUTED_REASON_COMMANDS_NOT_SERVED",
    "DISTRIBUTED_REASON_PAYLOAD_UNAVAILABLE",
    # 14.56
    "ANGZARR_REASON_RULES_VERSION_MISMATCH",
    # 14.62
    "EMBEDDED_REASON_CHILD_NOT_SERVING",
    "EMBEDDED_REASON_CHILD_EXIT_STATUS",
    "EMBEDDED_REASON_CHILD_NOT_EXITED",
    "EMBEDDED_REASON_PROBE_INPUT",
    # the component host's, once pinned exactly as core's HostReason
    # (merged into AngzarrReason by 14.104)
    "ANGZARR_REASON_UPCASTER_WITH_COMPONENT",
    "ANGZARR_REASON_NO_COMPONENTS_REGISTERED",
    # 14.65
    "ANGZARR_REASON_EDITION_NOT_FORKED",
    "ANGZARR_REASON_UPCASTER_UNKNOWN_DOMAIN",
    "ANGZARR_REASON_UPCASTER_OTHER_DOMAIN",
    "ANGZARR_REASON_REMOTE_SOURCE",
    # 14.71
    "ANGZARR_REASON_POLICY_TARGETS_ITS_TRIGGER",
)

# The coordinator's keys that concern one stream, each declaring a `stream`
# arg, the stream's text (decision 14.65, from the owner's ruling on
# decision 11 of the 2026-10-31 run).
STREAM_KEYS = (
    "ANGZARR_REASON_PM_NO_INSTANCE",
    "ANGZARR_REASON_RETRY_CAP_EXHAUSTED",
    "ANGZARR_REASON_EDITION_REMOVAL_FAILED",
    "ANGZARR_REASON_HANDLER_UNAVAILABLE",
    "ANGZARR_REASON_RULES_VERSION_MISMATCH",
    "ANGZARR_REASON_EDITION_NOT_FORKED",
    "ANGZARR_REASON_POLICY_TARGETS_ITS_TRIGGER",
    "ANGZARR_REASON_FACT_DEAD_LETTERED",
    "ANGZARR_REASON_STATE_TYPE_MISMATCH",
    "ANGZARR_REASON_SYNC_PROJECTION_FAILED",
)

# The statuses and args a decision pins (14.65).
PINNED_STATUS = {
    "ANGZARR_REASON_EDITION_NOT_FORKED": "FAILED_PRECONDITION",
    "ANGZARR_REASON_POLICY_TARGETS_ITS_TRIGGER": "INTERNAL",
}
PINNED_ARGS = {
    "ANGZARR_REASON_EDITION_NOT_FORKED": ["stream", "edition"],
    "ANGZARR_REASON_POLICY_TARGETS_ITS_TRIGGER": ["stream", "command_type"],
}

# google.rpc.Code's zero, a status no live key travels with; and what
# declared_statuses answers for a key whose surface is readiness, which
# travels as no status (no google.rpc.Code value is named so).
NO_STATUS = "OK"
READINESS = "READINESS"

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
        expected = sorted(REASON_FILES[path])
        if names != expected:
            problems.append(f"{path}: enums are {names}, expected {expected}")
        for e in enums:
            if e.get("name", "") in REASON_FILES[path]:
                live[(path, e["name"])] = _check_enum(e, problems)
    every = [k for keys in live.values() for k in keys]
    for key in sorted({k for k in every if every.count(k) > 1}):
        problems.append(f"{key}: a key in two enums")
    for (path, enum), keys in EXACT_KEYS.items():
        found = live.get((path, enum))
        if found is not None and tuple(found) != keys:
            problems.append(f"{path}: {enum}: keys are {found}, expected {list(keys)}")
    for key in PINNED:
        if key not in every:
            problems.append(f"{key}: a decision pins it, and it is not a live key")
    for enums in files.values():
        problems.extend(_arg_problems(enums))
    return problems


def _check_enum(e: dict[str, Any], problems: list[str]) -> list[str]:
    """One key enum: its zero, numbering and prefix. Returns its live keys,
    in number order; appends what it breaks to `problems`."""
    name = e.get("name", "")
    prefix = PREFIXES[name]
    by_number = {v.get("number", 0): v.get("name", "") for v in e.get("value", [])}
    if by_number.get(0) != f"{prefix}UNSPECIFIED":
        problems.append(f"{name}: 0 is {by_number.get(0)!r}, expected {prefix}UNSPECIFIED")
    numbers = sorted(n for n in by_number if n != 0)
    if numbers != list(range(1, len(numbers) + 1)):
        problems.append(f"{name}: live keys are not numbered densely from 1: {numbers}")
    live = [by_number[n] for n in numbers]
    if not live:
        problems.append(f"{name}: no keys")
    for key in live:
        rest = key[len(prefix) :] if key.startswith(prefix) else ""
        if not rest:
            problems.append(f"{name}: {key} does not carry the prefix {prefix}")
        if not SCREAMING_SNAKE.match(key):
            problems.append(f"{name}: {key} is not SCREAMING_SNAKE")
    return live


def _live_values(enums: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every value but the zeros of the enums this checks."""
    return [v for e in enums if e.get("name") in PREFIXES for v in e.get("value", []) if v.get("number", 0) != 0]


def _arg_problems(enums: list[dict[str, Any]]) -> list[str]:
    """Each live key's (reason) option: present, its args snake_case, each
    once, a key of one stream's naming `stream`, and exactly one surface, a
    gRPC status or readiness; what a decision pins, as pinned."""
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
        has_status = GRPC_STATUS in option
        has_readiness = READINESS_SURFACE in option
        if has_status and has_readiness:
            problems.append(f"{key}: declares two surfaces (its (reason) option's grpc_status and readiness)")
        elif not has_status and not has_readiness:
            problems.append(f"{key}: declares no surface (its (reason) option's grpc_status or readiness)")
        elif has_status and option[GRPC_STATUS] == NO_STATUS:
            problems.append(f"{key}: declares no status (its (reason) option's grpc_status is {NO_STATUS})")
        status = _surface(option)
        if key in PINNED_STATUS and status != PINNED_STATUS[key]:
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


def _surface(option: dict[str, Any]) -> str:
    """The surface a (reason) option declares: its grpc_status's name (a
    google.rpc.Code value's), READINESS for a readiness key (when it declares
    no status beside it), or NO_STATUS when it declares neither."""
    if GRPC_STATUS in option:
        return str(option[GRPC_STATUS])
    if READINESS_SURFACE in option:
        return READINESS
    return NO_STATUS


def declared_statuses(descriptor: dict[str, Any]) -> dict[str, str]:
    """Each live key's declared surface, by key, across every reasons.proto:
    its grpc_status's name (a google.rpc.Code value's), READINESS for a key
    whose surface is readiness, NO_STATUS for one that declares neither."""
    return {
        v.get("name", ""): _surface(v.get("options", {}).get(REASON_OPTION, {}))
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
        f"ok   check-reason-keys ({len(REASON_FILES)} files, every key prefixed and its args and surface declared, "
        f"{len(declared_args(descriptor))} messages in the catalogs)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
