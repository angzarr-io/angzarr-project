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


# The fixture's keys beyond the checker's tables: the distributed
# transport's coordinator keys, core's AngzarrReason key, and a core
# coordinator key whose surface is readiness.
DISTRIBUTED_KEYS = (
    "COORDINATOR_REASON_COMPONENT_NOT_REGISTERED",
    "COORDINATOR_REASON_COMMANDS_NOT_SERVED",
    "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE",
)
ANGZARR_KEY = "ANGZARR_REASON_COMMAND_REFUSED"
READINESS_KEY = "COORDINATOR_REASON_MISSING_RULES_VERSION"


def _enum(name: str, keys: list[str]) -> dict[str, Any]:
    """A key enum of `keys`, numbered densely from 1."""
    prefix = crk.PREFIXES[name]
    values = [{"name": f"{prefix}UNSPECIFIED", "number": 0}]
    values += [{"name": k, "number": n, "options": {crk.REASON_OPTION: _option(k)}} for n, k in enumerate(keys, start=1)]
    return {"name": name, "value": values}


def _option(key: str) -> dict[str, Any]:
    """A conforming (reason) option for `key`: its pinned args, else
    `stream` first for a key that concerns one stream, then `domain`; and
    readiness for READINESS_KEY, else its pinned status, else INTERNAL."""
    args = crk.PINNED_ARGS.get(key, (["stream"] if key in crk.STREAM_KEYS else []) + ["domain"])
    if key == READINESS_KEY:
        return {"args": args, crk.READINESS_SURFACE: {}}
    return {"args": args, crk.GRPC_STATUS: crk.PINNED_STATUS.get(key, "REASON_STATUS_INTERNAL")}


def _good() -> dict[str, Any]:
    router = [k for k in crk.PINNED if k.startswith("ROUTER_REASON_")]
    coordinator = [k for k in crk.PINNED if k.startswith("COORDINATOR_REASON_") and k not in DISTRIBUTED_KEYS]
    coordinator += [k for k in crk.STREAM_KEYS if k not in coordinator] + [READINESS_KEY]
    return {
        "file": [
            {"name": "sererr/v1/sererr.proto"},
            {
                "name": crk.CORE,
                "enumType": [
                    _enum("AngzarrReason", [ANGZARR_KEY]),
                    _enum("RouterReason", router),
                    _enum("HostReason", list(crk.HOST_KEYS[crk.CORE])),
                    _enum("CoordinatorReason", coordinator),
                    {"name": "ReasonStatus", "value": [{"name": "REASON_STATUS_UNSPECIFIED", "number": 0}]},
                ],
            },
            {"name": crk.EMBEDDED, "enumType": [_enum("HostReason", list(crk.HOST_KEYS[crk.EMBEDDED]))]},
            {"name": crk.DISTRIBUTED, "enumType": [_enum("CoordinatorReason", list(DISTRIBUTED_KEYS))]},
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
            "COORDINATOR_REASON_STORE_UNAVAILABLE",
            "COORDINATOR_REASON_UPCASTER_UNAVAILABLE",
            "COORDINATOR_REASON_COMPONENT_NOT_REGISTERED",
            "COORDINATOR_REASON_COMMANDS_NOT_SERVED",
            "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE",
        ):
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)

    def test_decision_14_62_pins_the_hosts_child_keys(self) -> None:
        # The host's own failures with a child, keyed by the spec, in the
        # local-process transport's HostReason.
        for key in (
            "HOST_REASON_CHILD_NOT_SERVING",
            "HOST_REASON_CHILD_EXIT_STATUS",
            "HOST_REASON_CHILD_NOT_EXITED",
            "HOST_REASON_PROBE_INPUT",
        ):
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)
                self.assertIn(key, crk.HOST_KEYS[crk.EMBEDDED])

    def test_core_declares_angzarr_reason(self) -> None:
        self.assertEqual(crk.REASON_FILES[crk.CORE][0], "AngzarrReason")
        self.assertEqual(crk.PREFIXES["AngzarrReason"], "ANGZARR_REASON_")
        d = _good()
        _file(d)["enumType"] = [e for e in _file(d)["enumType"] if e["name"] != "AngzarrReason"]
        self.assertProblem(d, f"{crk.CORE}: enums are")
        d = _good()
        _enum_of(d, "AngzarrReason")["value"][0]["name"] = "ANGZARR_REASON_NONE"
        self.assertProblem(d, "AngzarrReason: 0 is 'ANGZARR_REASON_NONE', expected ANGZARR_REASON_UNSPECIFIED")
        self.assertIn(ANGZARR_KEY, crk.declared_args(_good(), crk.CORE))

    def test_the_good_descriptor_is_not_mutated(self) -> None:
        d = _good()
        before = copy.deepcopy(d)
        crk.check(d)
        self.assertEqual(d, before)

    def test_every_live_key_declares_its_args(self) -> None:
        d = _good()
        del _value(d, "HOST_REASON_PROBE_INPUT")["options"]
        self.assertProblem(d, "HOST_REASON_PROBE_INPUT: declares no args (its (reason) option is missing)")

    def test_an_option_without_args_declares_none(self) -> None:
        d = _good()
        _value(d, "HOST_REASON_PROBE_INPUT")["options"] = {crk.REASON_OPTION: {crk.GRPC_STATUS: "REASON_STATUS_INTERNAL"}}
        self.assertEqual(crk.check(d), [])
        self.assertEqual(crk.declared_args(d)["HOST_REASON_PROBE_INPUT"], [])

    def test_declared_args_are_read_per_key(self) -> None:
        d = _good()
        _value(d, "ROUTER_REASON_TOO_MANY_STEPS")["options"] = {crk.REASON_OPTION: {"args": ["limit"]}}
        declared = crk.declared_args(d)
        self.assertEqual(declared["ROUTER_REASON_TOO_MANY_STEPS"], ["limit"])
        self.assertNotIn("ROUTER_REASON_UNSPECIFIED", declared)

    def test_a_readiness_key_passes(self) -> None:
        d = _good()
        self.assertEqual(_value(d, READINESS_KEY)["options"][crk.REASON_OPTION], {"args": ["domain"], "readiness": {}})
        self.assertEqual(crk.check(d), [])

    def test_every_live_key_declares_one_surface(self) -> None:
        # Decision 14.65: a key's surface, its gRPC status or readiness, is
        # declared on its option; neither is a problem, and so are both.
        for key in ("HOST_REASON_PROBE_INPUT", READINESS_KEY):
            with self.subTest(key=key, surfaces="neither"):
                d = _good()
                option = _value(d, key)["options"][crk.REASON_OPTION]
                option.pop(crk.GRPC_STATUS, None)
                option.pop(crk.READINESS_SURFACE, None)
                self.assertProblem(d, f"{key}: declares no surface")
            with self.subTest(key=key, surfaces="both"):
                d = _good()
                option = _value(d, key)["options"][crk.REASON_OPTION]
                option[crk.GRPC_STATUS] = "REASON_STATUS_INTERNAL"
                option[crk.READINESS_SURFACE] = {}
                self.assertProblem(d, f"{key}: declares two surfaces")

    def test_an_unspecified_status_is_no_status(self) -> None:
        d = _good()
        _value(d, "HOST_REASON_PROBE_INPUT")["options"][crk.REASON_OPTION][crk.GRPC_STATUS] = "REASON_STATUS_UNSPECIFIED"
        self.assertProblem(d, "HOST_REASON_PROBE_INPUT: declares no status")

    def test_an_empty_option_declares_no_surface(self) -> None:
        d = _good()
        _value(d, "HOST_REASON_PROBE_INPUT")["options"] = {crk.REASON_OPTION: {}}
        self.assertProblem(d, "HOST_REASON_PROBE_INPUT: declares no surface")

    def test_declared_statuses_are_read_per_key(self) -> None:
        d = _good()
        _value(d, "ROUTER_REASON_TOO_MANY_STEPS")["options"][crk.REASON_OPTION][crk.GRPC_STATUS] = "REASON_STATUS_ABORTED"
        _value(d, "HOST_REASON_PROBE_INPUT")["options"] = {crk.REASON_OPTION: {}}
        statuses = crk.declared_statuses(d)
        self.assertEqual(statuses["ROUTER_REASON_TOO_MANY_STEPS"], "REASON_STATUS_ABORTED")
        self.assertEqual(statuses["HOST_REASON_CHILD_NOT_SERVING"], "REASON_STATUS_INTERNAL")
        self.assertEqual(statuses[READINESS_KEY], crk.READINESS)
        self.assertEqual(statuses["HOST_REASON_PROBE_INPUT"], crk.NO_STATUS)
        self.assertNotIn("ROUTER_REASON_UNSPECIFIED", statuses)

    def test_decision_11_names_the_keys_that_concern_one_stream(self) -> None:
        self.assertEqual(
            sorted(crk.STREAM_KEYS),
            [
                "COORDINATOR_REASON_EDITION_NOT_FORKED",
                "COORDINATOR_REASON_EDITION_REMOVAL_FAILED",
                "COORDINATOR_REASON_FACT_DEAD_LETTERED",
                "COORDINATOR_REASON_HANDLER_UNAVAILABLE",
                "COORDINATOR_REASON_PM_NO_INSTANCE",
                "COORDINATOR_REASON_POLICY_TARGETS_ITS_TRIGGER",
                "COORDINATOR_REASON_RETRY_CAP_EXHAUSTED",
                "COORDINATOR_REASON_RULES_VERSION_MISMATCH",
                "COORDINATOR_REASON_STATE_TYPE_MISMATCH",
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
            "COORDINATOR_REASON_EDITION_NOT_FORKED": ("REASON_STATUS_FAILED_PRECONDITION", ["stream", "edition"]),
            "COORDINATOR_REASON_POLICY_TARGETS_ITS_TRIGGER": ("REASON_STATUS_INTERNAL", ["stream", "command_type"]),
        }
        self.assertEqual(sorted(crk.PINNED_STATUS), sorted(pinned))
        self.assertEqual(sorted(crk.PINNED_ARGS), sorted(pinned))
        for key, (status, args) in pinned.items():
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)
                self.assertEqual(crk.PINNED_STATUS[key], status)
                self.assertEqual(crk.PINNED_ARGS[key], args)
                d = _good()
                _value(d, key)["options"][crk.REASON_OPTION][crk.GRPC_STATUS] = "REASON_STATUS_ABORTED"
                self.assertProblem(d, f"{key}: status is REASON_STATUS_ABORTED, and a decision pins {status}")
                d = _good()
                option = _value(d, key)["options"][crk.REASON_OPTION]
                del option[crk.GRPC_STATUS]
                option[crk.READINESS_SURFACE] = {}
                self.assertProblem(d, f"{key}: status is {crk.READINESS}, and a decision pins {status}")
                d = _good()
                _value(d, key)["options"][crk.REASON_OPTION]["args"] = ["stream"]
                self.assertProblem(d, f"{key}: args are ['stream'], and a decision pins {args}")

    def test_decision_14_65_keys_the_hosts_misconfigurations(self) -> None:
        # One validator, the spec's keys (the owner's ruling on decision 21
        # of the 2026-10-31 run): the gaps it found are keys of their own.
        for key in (
            "HOST_REASON_UPCASTER_UNKNOWN_DOMAIN",
            "HOST_REASON_UPCASTER_OTHER_DOMAIN",
            "HOST_REASON_REMOTE_SOURCE",
        ):
            with self.subTest(key=key):
                self.assertIn(key, crk.PINNED)
                self.assertIn(key, crk.HOST_KEYS[crk.CORE])

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
        self.assertIn("HOST_REASON_PROBE_INPUT: a message for no live key", problems)
        self.assertIn("ROUTER_REASON_TOO_MANY_STEPS: no message in the catalog", problems)

    def test_a_key_with_no_message(self) -> None:
        d = _good()
        text = "\n".join(
            l for l in _catalog(d, crk.EMBEDDED).splitlines() if not l.startswith("HOST_REASON_PROBE_INPUT ")
        )
        self.assertIn(
            "HOST_REASON_PROBE_INPUT: no message in the catalog", crk.check_catalog(d, text, crk.EMBEDDED)
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
            crk.CORE: ANGZARR_KEY,
            crk.EMBEDDED: "HOST_REASON_PROBE_INPUT",
            crk.DISTRIBUTED: "COORDINATOR_REASON_PAYLOAD_UNAVAILABLE",
        }
        for path, key in expect.items():
            with self.subTest(path=path):
                text = (root / crk.catalog_path(path)).read_text(encoding="utf-8")
                messages, problems = crk.parse_catalog(text)
                self.assertEqual(problems, [])
                self.assertIn(key, messages)
        core, _ = crk.parse_catalog((root / crk.catalog_path(crk.CORE)).read_text(encoding="utf-8"))
        transports = set(crk.HOST_KEYS[crk.EMBEDDED]) | set(DISTRIBUTED_KEYS)
        self.assertFalse(set(core) & transports, "core's catalog holds no transport's key")

    def test_main_exit_codes(self) -> None:
        import tempfile

        bad = _good()
        _enum_of(bad, "RouterReason")["value"][-1]["number"] = 99
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
