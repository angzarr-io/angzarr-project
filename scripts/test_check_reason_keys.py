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


def _enum(name: str, keys: list[str]) -> dict[str, Any]:
    prefix = crk.PREFIXES[name]
    values = [{"name": f"{prefix}UNSPECIFIED", "number": 0}]
    values += [
        {"name": k, "number": n, "options": {crk.REASON_OPTION: {"args": ["domain"]}}}
        for n, k in enumerate(keys, start=1)
    ]
    return {
        "name": name,
        "value": values,
        "reservedName": [f"{prefix}{k}" for k in crk.RETIRED],
    }


def _good() -> dict[str, Any]:
    router = [k for k in crk.PINNED if k.startswith("ROUTER_REASON_")]
    coordinator = [k for k in crk.PINNED if k.startswith("COORDINATOR_REASON_")]
    return {
        "file": [
            {"name": "sererr/v1/sererr.proto"},
            {
                "name": crk.REASONS_PROTO,
                "enumType": [
                    _enum("RouterReason", router),
                    _enum("HostReason", list(crk.HOST_KEYS)),
                    _enum("CoordinatorReason", coordinator),
                ],
            },
        ]
    }


def _enum_of(d: dict[str, Any], name: str) -> dict[str, Any]:
    return next(e for e in d["file"][1]["enumType"] if e["name"] == name)


def _value(d: dict[str, Any], key: str) -> dict[str, Any]:
    return next(v for e in d["file"][1]["enumType"] for v in e["value"] if v["name"] == key)


def _catalog(d: dict[str, Any]) -> str:
    """A conforming catalog of `d`: one message per live key, each using its first arg."""
    lines = ["# English for the keys.", ""]
    for e in d["file"][1]["enumType"]:
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

    def test_an_extra_or_missing_enum(self) -> None:
        d = _good()
        d["file"][1]["enumType"].append({"name": "OtherReason", "value": []})
        self.assertProblem(d, "enums are")
        d = _good()
        d["file"][1]["enumType"].pop(0)
        self.assertProblem(d, "enums are")

    def test_zero_must_be_unspecified(self) -> None:
        d = _good()
        _enum_of(d, "HostReason")["value"][0]["name"] = "HOST_REASON_NONE"
        self.assertProblem(d, "HostReason: 0 is 'HOST_REASON_NONE'")

    def test_numbers_are_dense(self) -> None:
        d = _good()
        _enum_of(d, "RouterReason")["value"].append({"name": "ROUTER_REASON_GAP", "number": 9})
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
        _enum_of(d, "HostReason")["reservedRange"] = [{"start": 5, "end": 5}]
        self.assertProblem(d, "HostReason: reserves numbers")

    def test_a_key_in_two_enums(self) -> None:
        d = _good()
        # A key with the wrong prefix lands in two enums only through a
        # second, already-reported error; the duplicate is reported too.
        _enum_of(d, "CoordinatorReason")["value"].append(
            {"name": "ROUTER_REASON_DUPLICATE_COMPONENT", "number": len(_enum_of(d, "CoordinatorReason")["value"])}
        )
        self.assertProblem(d, "ROUTER_REASON_DUPLICATE_COMPONENT: a key in two enums")

    def test_host_keys_are_exactly_these(self) -> None:
        d = _good()
        values = _enum_of(d, "HostReason")["value"]
        values.append({"name": "HOST_REASON_EXTRA", "number": len(values)})
        self.assertProblem(d, "HostReason: keys are")

    def test_every_pinned_key_is_live(self) -> None:
        for key in crk.PINNED:
            with self.subTest(key=key):
                d = _good()
                for e in d["file"][1]["enumType"]:
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
                self.assertIn(key, crk.HOST_KEYS)

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
        _value(d, "HOST_REASON_HANDSHAKE_MALFORMED")["options"] = {crk.REASON_OPTION: {}}
        self.assertEqual(crk.check(d), [])
        self.assertEqual(crk.declared_args(d)["HOST_REASON_HANDSHAKE_MALFORMED"], [])

    def test_declared_args_are_read_per_key(self) -> None:
        d = _good()
        _value(d, "ROUTER_REASON_TOO_MANY_STEPS")["options"] = {crk.REASON_OPTION: {"args": ["limit"]}}
        declared = crk.declared_args(d)
        self.assertEqual(declared["ROUTER_REASON_TOO_MANY_STEPS"], ["limit"])
        self.assertNotIn("ROUTER_REASON_UNSPECIFIED", declared)

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
        self.assertEqual(crk.check_catalog(d, _catalog(d)), [])

    def test_a_key_with_no_message(self) -> None:
        d = _good()
        text = "\n".join(l for l in _catalog(d).splitlines() if not l.startswith("HOST_REASON_HANDSHAKE_MALFORMED "))
        self.assertIn("HOST_REASON_HANDSHAKE_MALFORMED: no message in the catalog", crk.check_catalog(d, text))

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

    def test_the_real_catalog_against_the_real_proto(self) -> None:
        # The catalog shipped beside reasons.proto conforms to the keys that
        # build into this test's descriptor shape: every message is a
        # well-formed entry, which is all this test can know without buf.
        text = (Path(__file__).resolve().parent.parent / crk.CATALOG).read_text(encoding="utf-8")
        messages, problems = crk.parse_catalog(text)
        self.assertEqual(problems, [])
        self.assertIn("HOST_REASON_HANDSHAKE_MALFORMED", messages)

    def test_main_exit_codes(self) -> None:
        import tempfile

        bad = _good()
        _enum_of(bad, "HostReason")["reservedRange"] = [{"start": 5, "end": 5}]
        no_message = _good()
        for descriptor, catalog, code in (
            (_good(), _catalog(_good()), 0),
            (bad, _catalog(bad), 1),
            (no_message, "", 1),
        ):
            with self.subTest(code=code, catalog=bool(catalog)):
                out, err = io.StringIO(), io.StringIO()
                sys.stdin = io.StringIO(json.dumps(descriptor))
                with tempfile.NamedTemporaryFile("w", suffix=".ftl", delete=False) as ftl:
                    ftl.write(catalog)
                try:
                    with redirect_stdout(out), redirect_stderr(err):
                        self.assertEqual(crk.main(["check_reason_keys.py", "-", ftl.name]), code)
                finally:
                    sys.stdin = sys.__stdin__
                    Path(ftl.name).unlink()
                if code:
                    self.assertIn("FAIL check-reason-keys", err.getvalue())
                else:
                    self.assertIn("ok   check-reason-keys", out.getvalue())
        with redirect_stderr(io.StringIO()):
            self.assertEqual(crk.main(["check_reason_keys.py"]), 2)
            self.assertEqual(crk.main(["check_reason_keys.py", "-"]), 2)


if __name__ == "__main__":
    unittest.main()
