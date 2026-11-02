"""Unit tests for check_reason_keys.py (run: python3 -m unittest scripts/test_check_reason_keys.py)."""

from __future__ import annotations

import copy
import io
import json
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_reason_keys as crk  # noqa: E402


def _enum(name: str, keys: list[str], moved: tuple[str, ...] = ()) -> dict[str, Any]:
    """A key enum of `keys`, numbered from 1, then reserving `moved` by name
    and by the numbers after them."""
    prefix = crk.PREFIXES[name]
    values = [{"name": f"{prefix}UNSPECIFIED", "number": 0}]
    values += [{"name": k, "number": n, "options": {crk.REASON_OPTION: _option(k)}} for n, k in enumerate(keys, start=1)]
    enum: dict[str, Any] = {
        "name": name,
        "value": values,
        "reservedName": [f"{prefix}{k}" for k in crk.RETIRED] + list(moved),
    }
    if moved:
        enum["reservedRange"] = [{"start": len(keys) + 1, "end": len(keys) + len(moved)}]
    return enum


def _option(key: str) -> dict[str, Any]:
    """A conforming (reason) option for `key`: its pinned status, else
    INTERNAL; its pinned args, else `stream` first for a key that concerns
    one stream, then `domain`."""
    args = crk.PINNED_ARGS.get(key, (["stream"] if key in crk.STREAM_KEYS else []) + ["domain"])
    return {"args": args, "status": crk.PINNED_STATUS.get(key, "REASON_STATUS_INTERNAL")}


def _moved(path: str, prefix: str) -> tuple[str, ...]:
    return tuple(k for k, p in crk.MOVED.items() if p == path and k.startswith(prefix))


def _good() -> dict[str, Any]:
    router = [k for k in crk.PINNED if k.startswith("ROUTER_REASON_")]
    coordinator = [k for k in crk.PINNED if k.startswith("COORDINATOR_REASON_") and k not in crk.MOVED]
    coordinator += [k for k in crk.STREAM_KEYS if k not in coordinator]
    to_embedded = _moved(crk.EMBEDDED, "HOST_REASON_")
    to_distributed = _moved(crk.DISTRIBUTED, "COORDINATOR_REASON_")
    return {
        "file": [
            {"name": "sererr/v1/sererr.proto"},
            {
                "name": crk.CORE,
                "enumType": [
                    _enum("RouterReason", router),
                    _enum("HostReason", list(crk.HOST_KEYS[crk.CORE]), to_embedded),
                    _enum("CoordinatorReason", coordinator, to_distributed),
                    {"name": "ReasonStatus", "value": [{"name": "REASON_STATUS_UNSPECIFIED", "number": 0}]},
                ],
            },
            {"name": crk.EMBEDDED, "enumType": [_enum("HostReason", list(crk.HOST_KEYS[crk.EMBEDDED]))]},
            {"name": crk.DISTRIBUTED, "enumType": [_enum("CoordinatorReason", list(to_distributed))]},
        ]
    }


def _file(d: dict[str, Any], path: str = crk.CORE) -> dict[str, Any]:
    return next(f for f in d["file"] if f["name"] == path)


def _enum_of(d: dict[str, Any], name: str, path: str = crk.CORE) -> dict[str, Any]:
    return next(e for e in _file(d, path)["enumType"] if e["name"] == name)


def _value(d: dict[str, Any], key: str) -> dict[str, Any]:
    return next(
        v for f in d["file"] for e in f.get("enumType", []) for v in e["value"] if v["name"] == key
    )


def _catalog(d: dict[str, Any], path: str = crk.CORE) -> str:
    """A conforming catalog of `path` in `d`: one message per live key, each using its first arg."""
    lines = ["# English for the keys.", ""]
    for e in _file(d, path)["enumType"]:
        for v in e["value"][1:]:
            args = v.get("options", {}).get(crk.REASON_OPTION, {}).get("args", [])
            body = f"a {{ ${args[0]} }} failed" if args else "it failed"
            lines.append(f"{v['name']} = {body}")
    return "\n".join(lines) + "\n"


class CheckReasonKeysTest(unittest.TestCase):
    def assertProblem(self, d: dict[str, Any], fragment: str) -> None:
        problems = crk.check(d)
        self.assertTrue(any(fragment in p for p in problems), problems)

    def test_conforming_descriptor_passes(self) -> None:
        self.assertEqual(crk.check(_good()), [])

    def test_missing_file(self) -> None:
        self.assertProblem({"file": [{"name": "other.proto"}]}, "not in the descriptor set exactly once")
        for path in crk.REASON_FILES:
            with self.subTest(path=path):
                d = _good()
                d["file"].remove(_file(d, path))
                self.assertProblem(d, f"{path}: not in the descriptor set exactly once (0 found)")

    def test_an_extra_or_missing_enum(self) -> None:
        d = _good()
        _file(d)["enumType"].append({"name": "OtherReason", "value": []})
        self.assertProblem(d, "enums are")
        d = _good()
        _file(d)["enumType"].pop(0)
        self.assertProblem(d, "enums are")
        d = _good()
        _file(d, crk.EMBEDDED)["enumType"].append(_enum("RouterReason", ["ROUTER_REASON_STRAY"]))
        self.assertProblem(d, f"{crk.EMBEDDED}: enums are")

    def test_core_declares_its_statuses_beside_its_keys(self) -> None:
        d = _good()
        _file(d)["enumType"] = [e for e in _file(d)["enumType"] if e["name"] != "ReasonStatus"]
        self.assertProblem(d, f"{crk.CORE}: enums are")
        d = _good()
        _file(d, crk.EMBEDDED)["enumType"].append({"name": "ReasonStatus", "value": []})
        self.assertProblem(d, f"{crk.EMBEDDED}: enums are")

    def test_zero_must_be_unspecified(self) -> None:
        d = _good()
        _enum_of(d, "HostReason")["value"][0]["name"] = "HOST_REASON_NONE"
        self.assertProblem(d, "HostReason: 0 is 'HOST_REASON_NONE'")

    def test_numbers_are_dense(self) -> None:
        d = _good()
        _enum_of(d, "RouterReason")["value"].append({"name": "ROUTER_REASON_GAP", "number": 99})
        self.assertProblem(d, "RouterReason: live keys are not numbered densely from 1")

    def test_a_moved_keys_reserved_number_fills_its_place(self) -> None:
        # Core's HostReason: four live keys, then the seven moved numbers.
        e = _enum_of(_good(), "HostReason")
        self.assertEqual(e["reservedRange"], [{"start": 5, "end": 11}])
        d = _good()
        _enum_of(d, "HostReason")["reservedRange"] = [{"start": 6, "end": 12}]
        self.assertProblem(d, "HostReason: live keys are not numbered densely from 1")

    def test_an_enum_with_no_keys(self) -> None:
        d = _good()
        e = _enum_of(d, "RouterReason")
        e["value"] = e["value"][:1]
        self.assertProblem(d, "RouterReason: no keys")

    def test_a_key_without_its_prefix(self) -> None:
        d = _good()
        _enum_of(d, "RouterReason")["value"].append({"name": "HOST_REASON_STRAY", "number": 2})
        self.assertProblem(d, "RouterReason: HOST_REASON_STRAY does not carry the prefix ROUTER_REASON_")

    def test_the_prefix_alone_is_not_a_key(self) -> None:
        d = _good()
        _enum_of(d, "RouterReason")["value"].append({"name": "ROUTER_REASON_", "number": 2})
        self.assertProblem(d, "does not carry the prefix")

    def test_a_key_not_screaming_snake(self) -> None:
        d = _good()
        _enum_of(d, "RouterReason")["value"].append({"name": "ROUTER_REASON_lower", "number": 2})
        self.assertProblem(d, "ROUTER_REASON_lower is not SCREAMING_SNAKE")

    def test_a_retired_key_answered_again(self) -> None:
        d = _good()
        _enum_of(d, "RouterReason")["value"].append({"name": "ROUTER_REASON_NULL_ABI_POINTER", "number": 2})
        self.assertProblem(d, "RouterReason: ROUTER_REASON_NULL_ABI_POINTER is retired")

    def test_a_retired_key_not_reserved(self) -> None:
        d = _good()
        _enum_of(d, "CoordinatorReason")["reservedName"].remove("COORDINATOR_REASON_EMPTY_POLICY_SOURCE")
        self.assertProblem(d, "CoordinatorReason: retired key COORDINATOR_REASON_EMPTY_POLICY_SOURCE is not reserved")

    def test_reserved_under_the_wrong_prefix(self) -> None:
        d = _good()
        names = _enum_of(d, "HostReason")["reservedName"]
        names[names.index("HOST_REASON_NULL_ABI_POINTER")] = "NULL_ABI_POINTER"
        self.assertProblem(d, "HostReason: NULL_ABI_POINTER is reserved but not retired")
        self.assertProblem(d, "HostReason: retired key HOST_REASON_NULL_ABI_POINTER is not reserved")

    def test_reserved_numbers(self) -> None:
        d = _good()
        _enum_of(d, "RouterReason")["reservedRange"] = [{"start": 16, "end": 16}]
        self.assertProblem(d, "RouterReason: reserves 1 numbers, for 0 moved keys")
        d = _good()
        _enum_of(d, "HostReason", crk.EMBEDDED)["reservedRange"] = [{"start": 8, "end": 8}]
        self.assertProblem(d, "HostReason: reserves 1 numbers, for 0 moved keys")

    def test_a_moved_key_not_reserved_in_core(self) -> None:
        d = _good()
        _enum_of(d, "HostReason")["reservedName"].remove("HOST_REASON_PROBE_INPUT")
        self.assertProblem(d, "HostReason: moved key HOST_REASON_PROBE_INPUT is not reserved")

    def test_a_moved_key_reserved_outside_core(self) -> None:
        d = _good()
        _enum_of(d, "HostReason", crk.EMBEDDED)["reservedName"].append("HOST_REASON_PROBE_INPUT")
        self.assertProblem(d, "HostReason: HOST_REASON_PROBE_INPUT is reserved but not retired")

    def test_a_moved_key_answered_in_core(self) -> None:
        d = _good()
        values = _enum_of(d, "CoordinatorReason")["value"]
        values.append({"name": "COORDINATOR_REASON_COMMANDS_NOT_SERVED", "number": len(values) + 3})
        self.assertProblem(d, f"CoordinatorReason: COORDINATOR_REASON_COMMANDS_NOT_SERVED moved to {crk.DISTRIBUTED}")

    def test_a_moved_key_missing_from_its_transport(self) -> None:
        d = _good()
        e = _enum_of(d, "CoordinatorReason", crk.DISTRIBUTED)
        e["value"] = [v for v in e["value"] if v["name"] != "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE"]
        self.assertProblem(d, f"COORDINATOR_REASON_PAYLOAD_UNAVAILABLE: moved to {crk.DISTRIBUTED}, and not a live key there")

    def test_a_key_in_two_enums(self) -> None:
        d = _good()
        # A key with the wrong prefix lands in two enums only through a
        # second, already-reported error; the duplicate is reported too.
        _enum_of(d, "CoordinatorReason")["value"].append(
            {"name": "ROUTER_REASON_DUPLICATE_COMPONENT", "number": len(_enum_of(d, "CoordinatorReason")["value"])}
        )
        self.assertProblem(d, "ROUTER_REASON_DUPLICATE_COMPONENT: a key in two enums")

    def test_host_keys_are_exactly_these(self) -> None:
        for path in crk.HOST_KEYS:
            with self.subTest(path=path):
                d = _good()
                values = _enum_of(d, "HostReason", path)["value"]
                values.insert(1, {"name": "HOST_REASON_EXTRA", "number": len(values)})
                self.assertProblem(d, f"{path}: HostReason: keys are")

    def test_a_key_in_two_files(self) -> None:
        # The string travels, not the package: one key in two files' enums.
        d = _good()
        values = _enum_of(d, "HostReason", crk.EMBEDDED)["value"]
        values.append({"name": "HOST_REASON_UPCASTER_WITH_COMPONENT", "number": len(values)})
        self.assertProblem(d, "HOST_REASON_UPCASTER_WITH_COMPONENT: a key in two enums")

    def test_every_pinned_key_is_live(self) -> None:
        for key in crk.PINNED:
            with self.subTest(key=key):
                d = _good()
                for e in (e for f in d["file"] for e in f.get("enumType", [])):
                    kept = [v for v in e["value"] if v["name"] != key]
                    if len(kept) != len(e["value"]):
                        # Keep the numbering dense: renumber what remains.
                        e["value"] = [{"name": v["name"], "number": n} for n, v in enumerate(kept)]
                        e.pop("reservedRange", None)
                        e["reservedName"] = [n for n in e["reservedName"] if n not in crk.MOVED]
                problems = crk.check(d)
                self.assertIn(f"{key}: a decision pins it, and it is not a live key", problems)

    def test_decision_14_49_pins_its_four_keys(self) -> None:
        # The limits and conditions any coordinator (and, the step limit,
        # any router) may enforce: each a live key of its owner's enum.
        for key in (
            "COORDINATOR_REASON_POLICY_COMMAND_UNKNOWN_DOMAIN",
            "COORDINATOR_REASON_HANDLER_UNAVAILABLE",
            "COORDINATOR_REASON_CHAIN_TOO_DEEP",
            "ROUTER_REASON_TOO_MANY_STEPS",
        ):
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)

    def test_decision_14_51_pins_its_retryable_keys(self) -> None:
        # Every retryable failure carries a key, for when the retry fails.
        for key in (
            "COORDINATOR_REASON_STORE_CONFLICT",
            "COORDINATOR_REASON_STORE_UNAVAILABLE",
            "COORDINATOR_REASON_UPCASTER_UNAVAILABLE",
            "COORDINATOR_REASON_COMPONENT_NOT_REGISTERED",
            "COORDINATOR_REASON_COMMANDS_NOT_SERVED",
            "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE",
        ):
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)

    def test_decision_14_62_pins_the_hosts_child_keys(self) -> None:
        # The host's own failures with a child, keyed by the spec.
        for key in (
            "HOST_REASON_HANDSHAKE_TIMEOUT",
            "HOST_REASON_HANDSHAKE_CLOSED",
            "HOST_REASON_CHILD_NOT_SERVING",
            "HOST_REASON_CHILD_EXIT_STATUS",
            "HOST_REASON_CHILD_NOT_EXITED",
            "HOST_REASON_PROBE_INPUT",
        ):
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)
                self.assertIn(key, crk.HOST_KEYS[crk.EMBEDDED])

    def test_decision_14_64_moves_the_child_and_distribution_keys(self) -> None:
        # The child's keys to the local-process transport; the keys only a
        # distributed coordinator raises to the distributed one.
        self.assertEqual(
            sorted(k for k, p in crk.MOVED.items() if p == crk.EMBEDDED), sorted(crk.HOST_KEYS[crk.EMBEDDED])
        )
        self.assertEqual(
            sorted(k for k, p in crk.MOVED.items() if p == crk.DISTRIBUTED),
            [
                "COORDINATOR_REASON_COMMANDS_NOT_SERVED",
                "COORDINATOR_REASON_COMPONENT_NOT_REGISTERED",
                "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE",
            ],
        )
        self.assertNotIn("HOST_REASON_PROJECTOR_NO_INPUT_DOMAIN", crk.MOVED)

    def test_the_good_descriptor_is_not_mutated(self) -> None:
        d = _good()
        before = copy.deepcopy(d)
        crk.check(d)
        self.assertEqual(d, before)

    def test_every_live_key_declares_its_args(self) -> None:
        d = _good()
        del _value(d, "HOST_REASON_HANDSHAKE_MALFORMED")["options"]
        self.assertProblem(d, "HOST_REASON_HANDSHAKE_MALFORMED: declares no args (its (reason) option is missing)")

    def test_an_empty_option_declares_no_args(self) -> None:
        d = _good()
        _value(d, "HOST_REASON_HANDSHAKE_MALFORMED")["options"] = {
            crk.REASON_OPTION: {"status": "REASON_STATUS_INTERNAL"}
        }
        self.assertEqual(crk.check(d), [])
        self.assertEqual(crk.declared_args(d)["HOST_REASON_HANDSHAKE_MALFORMED"], [])

    def test_declared_args_are_read_per_key(self) -> None:
        d = _good()
        _value(d, "ROUTER_REASON_TOO_MANY_STEPS")["options"] = {crk.REASON_OPTION: {"args": ["limit"]}}
        declared = crk.declared_args(d)
        self.assertEqual(declared["ROUTER_REASON_TOO_MANY_STEPS"], ["limit"])
        self.assertNotIn("ROUTER_REASON_UNSPECIFIED", declared)

    def test_every_live_key_declares_its_status(self) -> None:
        # Decision 14.65: a key's gRPC status is declared on its option.
        for status in (None, "REASON_STATUS_UNSPECIFIED"):
            with self.subTest(status=status):
                d = _good()
                option = _value(d, "HOST_REASON_HANDSHAKE_MALFORMED")["options"][crk.REASON_OPTION]
                option.pop("status")
                if status is not None:
                    option["status"] = status
                self.assertProblem(d, "HOST_REASON_HANDSHAKE_MALFORMED: declares no status")

    def test_an_empty_option_declares_no_status(self) -> None:
        d = _good()
        _value(d, "HOST_REASON_HANDSHAKE_MALFORMED")["options"] = {crk.REASON_OPTION: {}}
        self.assertProblem(d, "HOST_REASON_HANDSHAKE_MALFORMED: declares no status")

    def test_declared_statuses_are_read_per_key(self) -> None:
        d = _good()
        _value(d, "ROUTER_REASON_TOO_MANY_STEPS")["options"][crk.REASON_OPTION]["status"] = "REASON_STATUS_READINESS"
        statuses = crk.declared_statuses(d)
        self.assertEqual(statuses["ROUTER_REASON_TOO_MANY_STEPS"], "REASON_STATUS_READINESS")
        self.assertEqual(statuses["HOST_REASON_HANDSHAKE_MALFORMED"], "REASON_STATUS_INTERNAL")
        self.assertNotIn("ROUTER_REASON_UNSPECIFIED", statuses)

    def test_decision_11_names_the_keys_that_concern_one_stream(self) -> None:
        self.assertEqual(
            sorted(crk.STREAM_KEYS),
            [
                "COORDINATOR_REASON_CONFLICT_OVERLAP",
                "COORDINATOR_REASON_CONFLICT_UNRESOLVED",
                "COORDINATOR_REASON_EDITION_NOT_FORKED",
                "COORDINATOR_REASON_EDITION_REMOVAL_FAILED",
                "COORDINATOR_REASON_EVENTS_NOT_ITS_STREAM",
                "COORDINATOR_REASON_EXPECTED_SEQUENCE_AHEAD",
                "COORDINATOR_REASON_EXPECTED_SEQUENCE_STALE",
                "COORDINATOR_REASON_HANDLER_UNAVAILABLE",
                "COORDINATOR_REASON_PM_NO_INSTANCE",
                "COORDINATOR_REASON_RETRY_CAP_EXHAUSTED",
                "COORDINATOR_REASON_RULES_VERSION_MISMATCH",
                "COORDINATOR_REASON_STORE_CONFLICT",
            ],
        )

    def test_a_key_that_concerns_one_stream_declares_stream(self) -> None:
        for key in crk.STREAM_KEYS:
            with self.subTest(key=key):
                d = _good()
                _value(d, key)["options"][crk.REASON_OPTION]["args"] = ["domain"]
                self.assertProblem(d, f"{key}: concerns one stream and declares no stream arg")

    def test_decision_14_65_pins_its_keys_their_statuses_and_args(self) -> None:
        pinned = {
            "COORDINATOR_REASON_EVENTS_NOT_ITS_STREAM": ("REASON_STATUS_INTERNAL", ["stream", "event_stream"]),
            "COORDINATOR_REASON_EDITION_NOT_FORKED": ("REASON_STATUS_FAILED_PRECONDITION", ["stream", "edition"]),
        }
        for key, (status, args) in pinned.items():
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)
                self.assertEqual(crk.PINNED_STATUS[key], status)
                self.assertEqual(crk.PINNED_ARGS[key], args)
                d = _good()
                _value(d, key)["options"][crk.REASON_OPTION]["status"] = "REASON_STATUS_ABORTED"
                self.assertProblem(d, f"{key}: status is REASON_STATUS_ABORTED, and a decision pins {status}")
                d = _good()
                _value(d, key)["options"][crk.REASON_OPTION]["args"] = ["stream"]
                self.assertProblem(d, f"{key}: args are ['stream'], and a decision pins {args}")

    def test_an_arg_named_twice(self) -> None:
        d = _good()
        _value(d, "ROUTER_REASON_TOO_MANY_STEPS")["options"] = {crk.REASON_OPTION: {"args": ["limit", "limit"]}}
        self.assertProblem(d, "ROUTER_REASON_TOO_MANY_STEPS: arg limit declared twice")

    def test_an_arg_not_snake_case(self) -> None:
        for bad in ("Limit", "cause.ext_err_txt", "step-limit", "", "_limit", "9lives", "limit_", "step__limit"):
            with self.subTest(arg=bad):
                d = _good()
                _value(d, "ROUTER_REASON_TOO_MANY_STEPS")["options"] = {crk.REASON_OPTION: {"args": [bad]}}
                self.assertProblem(d, f"ROUTER_REASON_TOO_MANY_STEPS: arg {bad!r} is not snake_case")

    def test_a_conforming_catalog_passes(self) -> None:
        d = _good()
        for path in crk.REASON_FILES:
            with self.subTest(path=path):
                self.assertEqual(crk.check_catalog(d, _catalog(d, path), path), [])

    def test_each_catalog_holds_only_its_files_keys(self) -> None:
        d = _good()
        text = _catalog(d, crk.EMBEDDED)
        problems = crk.check_catalog(d, text)
        self.assertIn("HOST_REASON_HANDSHAKE_MALFORMED: a message for no live key", problems)
        self.assertIn("ROUTER_REASON_TOO_MANY_STEPS: no message in the catalog", problems)

    def test_a_key_with_no_message(self) -> None:
        d = _good()
        text = "\n".join(
            l for l in _catalog(d, crk.EMBEDDED).splitlines() if not l.startswith("HOST_REASON_HANDSHAKE_MALFORMED ")
        )
        self.assertIn(
            "HOST_REASON_HANDSHAKE_MALFORMED: no message in the catalog", crk.check_catalog(d, text, crk.EMBEDDED)
        )

    def test_a_message_for_no_live_key(self) -> None:
        d = _good()
        for stray in ("ROUTER_REASON_UNSPECIFIED", "ROUTER_REASON_NULL_ABI_POINTER", "angzarr-embedded-stale"):
            with self.subTest(stray=stray):
                text = _catalog(d) + f"{stray} = stray\n"
                self.assertIn(f"{stray}: a message for no live key", crk.check_catalog(d, text))

    def test_a_message_twice(self) -> None:
        d = _good()
        text = _catalog(d) + "ROUTER_REASON_TOO_MANY_STEPS = again\n"
        self.assertIn("ROUTER_REASON_TOO_MANY_STEPS: two messages", crk.check_catalog(d, text))

    def test_a_message_naming_an_undeclared_arg(self) -> None:
        d = _good()
        text = _catalog(d) + "\n"
        text = text.replace(
            "ROUTER_REASON_TOO_MANY_STEPS = a { $domain } failed",
            "ROUTER_REASON_TOO_MANY_STEPS = stream { $stream } ran { $count ->\n    [one] a step\n   *[other] { $count } steps\n  }",
        )
        problems = crk.check_catalog(d, text)
        self.assertIn("ROUTER_REASON_TOO_MANY_STEPS: names count, stream, which it does not declare", problems)

    def test_a_message_naming_its_cause(self) -> None:
        d = _good()
        _value(d, "COORDINATOR_REASON_STORE_UNAVAILABLE")["options"] = {crk.REASON_OPTION: {"args": ["cause"]}}
        text = _catalog(d).replace(
            "COORDINATOR_REASON_STORE_UNAVAILABLE = a { $cause } failed",
            "COORDINATOR_REASON_STORE_UNAVAILABLE = failed: { $cause }",
        )
        problems = crk.check_catalog(d, text)
        self.assertEqual(
            problems, ["COORDINATOR_REASON_STORE_UNAVAILABLE: names its cause, which renders as its own key"]
        )

    def test_a_catalog_line_that_is_no_message(self) -> None:
        d = _good()
        text = _catalog(d) + "not a message\n"
        self.assertTrue(any("line" in p and "not a message" in p for p in crk.check_catalog(d, text)))

    def test_a_continuation_with_no_message_above_it(self) -> None:
        for text in ("  { $x }\n", "# a comment\n  { $x }\n", "KEY_A = a\nnot a message\n  { $x }\n"):
            with self.subTest(text=text):
                messages, problems = crk.parse_catalog(text)
                self.assertTrue(any("not a message" in p and "$x" in p for p in problems), problems)
                self.assertNotIn("x", messages.get("KEY_A", set()))

    def test_continuation_and_comment_lines(self) -> None:
        text = "# a comment\n## a group\n\nKEY_A = one { $a ->\n    [one] x\n   *[other] { $b }\n  }\nKEY_B = two\n"
        self.assertEqual(crk.parse_catalog(text), ({"KEY_A": {"a", "b"}, "KEY_B": set()}, []))

    def test_the_real_catalogs_against_the_real_protos(self) -> None:
        # The catalog shipped beside each reasons.proto conforms to the keys
        # that build into this test's descriptor shape: every message is a
        # well-formed entry, which is all this test can know without buf.
        root = Path(__file__).resolve().parent.parent / "proto"
        expect = {
            crk.CORE: "HOST_REASON_PROJECTOR_NO_INPUT_DOMAIN",
            crk.EMBEDDED: "HOST_REASON_HANDSHAKE_MALFORMED",
            crk.DISTRIBUTED: "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE",
        }
        for path, key in expect.items():
            with self.subTest(path=path):
                text = (root / crk.catalog_path(path)).read_text(encoding="utf-8")
                messages, problems = crk.parse_catalog(text)
                self.assertEqual(problems, [])
                self.assertIn(key, messages)
        core, _ = crk.parse_catalog((root / crk.catalog_path(crk.CORE)).read_text(encoding="utf-8"))
        self.assertFalse(set(core) & set(crk.MOVED), "core's catalog keeps no moved key")

    def test_main_exit_codes(self) -> None:
        import tempfile

        bad = _good()
        _enum_of(bad, "RouterReason")["reservedRange"] = [{"start": 16, "end": 16}]
        for descriptor, catalogs, code in (
            (_good(), True, 0),
            (bad, True, 1),
            (_good(), False, 1),
        ):
            with self.subTest(code=code, catalogs=catalogs):
                out, err = io.StringIO(), io.StringIO()
                sys.stdin = io.StringIO(json.dumps(descriptor))
                with tempfile.TemporaryDirectory() as root:
                    if catalogs:
                        for path in crk.REASON_FILES:
                            target = Path(root) / crk.catalog_path(path)
                            target.parent.mkdir(parents=True, exist_ok=True)
                            target.write_text(_catalog(descriptor, path), encoding="utf-8")
                    try:
                        with redirect_stdout(out), redirect_stderr(err):
                            self.assertEqual(crk.main(["check_reason_keys.py", "-", root]), code)
                    finally:
                        sys.stdin = sys.__stdin__
                if code:
                    self.assertIn("FAIL check-reason-keys", err.getvalue())
                else:
                    self.assertIn("ok   check-reason-keys", out.getvalue())
                if not catalogs:
                    self.assertIn("reasons.en-US.ftl: no catalog", err.getvalue())
        with redirect_stderr(io.StringIO()):
            self.assertEqual(crk.main(["check_reason_keys.py"]), 2)
            self.assertEqual(crk.main(["check_reason_keys.py", "-"]), 2)


if __name__ == "__main__":
    unittest.main()
