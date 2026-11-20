"""Unit tests for check_feature_ids.py (run: python3 -m unittest scripts/test_check_feature_ids.py)."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_feature_ids as cfi  # noqa: E402


def _scan(*bodies: str) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for n, body in enumerate(bodies):
            p = Path(tmp) / f"f{n}.feature"
            p.write_text(body, encoding="utf-8")
            paths.append(p)
        return [line.split(": ", 1)[1] for line in cfi.scan(paths)]


class CheckFeatureIdsTest(unittest.TestCase):
    def test_tagged_scenarios_pass(self) -> None:
        body = "Feature: x\n\n  @C-0001 @slow\n  Scenario: a\n\n  @EU-0002\n  # note\n  Scenario Outline: b\n"
        self.assertEqual(_scan(body), [])

    def test_missing_tag_is_reported(self) -> None:
        self.assertEqual(_scan("Feature: x\n  @wip\n  Scenario: a\n"), ["scenario has no ID tag"])

    def test_every_scenario_keyword_requires_a_tag(self) -> None:
        for keyword in ("Scenario Outline", "Scenario Template", "Example"):
            with self.subTest(keyword=keyword):
                self.assertEqual(_scan(f"Feature: x\n  {keyword}: a\n"), ["scenario has no ID tag"])

    def test_trailing_comment_on_tag_line(self) -> None:
        self.assertEqual(_scan("Feature: x\n  @C-0001 # see @C-0002\n  Scenario: a\n"), [])

    def test_tag_separated_by_blank_line_does_not_count(self) -> None:
        self.assertEqual(_scan("Feature: x\n  @C-0001\n\n  Scenario: a\n"), ["scenario has no ID tag"])

    def test_two_ids_on_one_scenario(self) -> None:
        self.assertEqual(
            _scan("Feature: x\n  @C-0001\n  @C-0002\n  Scenario: a\n"),
            ["scenario has 2 ID tags (@C-0002 @C-0001)"],
        )

    def test_duplicate_across_files(self) -> None:
        problems = _scan("Feature: x\n  @C-0007\n  Scenario: a\n", "Feature: y\n  @C-0007\n  Scenario: b\n")
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith("duplicate scenario ID @C-0007"))

    def test_malformed_ids(self) -> None:
        for tag in ("@C-42", "@c-0042", "@C_0042", "@EU-1184B"):
            with self.subTest(tag=tag):
                self.assertEqual(
                    _scan(f"Feature: x\n  {tag}\n  Scenario: a\n"),
                    [f"malformed scenario ID tag {tag}"],
                )

    def test_examples_keyword_is_not_a_scenario(self) -> None:
        body = "Feature: x\n  @C-0001\n  Scenario Outline: a\n    Examples:\n      | v |\n      | 1 |\n"
        self.assertEqual(_scan(body), [])

    def test_unrelated_tags_are_ignored(self) -> None:
        self.assertEqual(_scan("Feature: x\n  @merge_strict @cluster @C-0003\n  Scenario: a\n"), [])


if __name__ == "__main__":
    unittest.main()
