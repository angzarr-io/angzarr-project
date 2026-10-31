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
    values += [{"name": k, "number": n} for n, k in enumerate(keys, start=1)]
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
        _enum_of(d, "HostReason")["value"].append({"name": "HOST_REASON_EXTRA", "number": 5})
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

    def test_the_good_descriptor_is_not_mutated(self) -> None:
        d = _good()
        before = copy.deepcopy(d)
        crk.check(d)
        self.assertEqual(d, before)

    def test_main_exit_codes(self) -> None:
        bad = _good()
        _enum_of(bad, "HostReason")["reservedRange"] = [{"start": 5, "end": 5}]
        for descriptor, code in ((_good(), 0), (bad, 1)):
            with self.subTest(code=code):
                out, err = io.StringIO(), io.StringIO()
                sys.stdin = io.StringIO(json.dumps(descriptor))
                try:
                    with redirect_stdout(out), redirect_stderr(err):
                        self.assertEqual(crk.main(["check_reason_keys.py", "-"]), code)
                finally:
                    sys.stdin = sys.__stdin__
                if code:
                    self.assertIn("FAIL check-reason-keys", err.getvalue())
                else:
                    self.assertIn("ok   check-reason-keys", out.getvalue())
        with redirect_stderr(io.StringIO()):
            self.assertEqual(crk.main(["check_reason_keys.py"]), 2)


if __name__ == "__main__":
    unittest.main()
