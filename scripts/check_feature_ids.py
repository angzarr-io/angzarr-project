#!/usr/bin/env python3
"""Scenario-ID gate for Gherkin feature files.

Every ``Scenario:`` / ``Scenario Outline:`` / ``Scenario Template:`` /
``Example:`` must carry exactly one well-formed ID tag of the form
``@<TIER>-NNNN`` (uppercase tier code, dash, four digits; see
features/STEP_VOCABULARY.md section 16) on the tag lines directly above it.
IDs must be unique across every file scanned in one run.

Usage: check_feature_ids.py DIR [DIR ...]

Exits 0 when every scenario conforms, 1 otherwise (one line per problem,
``path:line: message``).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TIER_CODES = ("C", "EU", "EA")
SCENARIO_RE = re.compile(r"^\s*(Scenario Outline|Scenario Template|Scenario|Example):")
VALID_ID_RE = re.compile(r"^@(?:" + "|".join(TIER_CODES) + r")-\d{4}$")
# Anything that looks like an attempt at an ID: a tier code (any case)
# followed by a dash or underscore. Catches @C-42, @c-0042, @C_0042,
# @EU-1184B.
ID_LIKE_RE = re.compile(r"^@(?i:" + "|".join(TIER_CODES) + r")[-_]")


def tags_above(lines: list[str], index: int) -> list[str]:
    """Tags on the contiguous tag lines directly above ``lines[index]``.

    Comment lines between tag lines and the scenario keyword are skipped
    (Gherkin attaches tags across them); a blank or any other line ends
    the tag block.
    """
    tags: list[str] = []
    j = index - 1
    while j >= 0:
        stripped = lines[j].strip()
        if stripped.startswith("@"):
            body = stripped.split(" #", 1)[0]
            tags.extend(body.split())
        elif not stripped.startswith("#"):
            break
        j -= 1
    return tags


def scan(paths: list[Path]) -> list[str]:
    problems: list[str] = []
    seen: dict[str, str] = {}
    for path in paths:
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if not SCENARIO_RE.match(line):
                continue
            where = f"{path}:{i + 1}"
            tags = tags_above(lines, i)
            ids = [t for t in tags if VALID_ID_RE.match(t)]
            malformed = [t for t in tags if ID_LIKE_RE.match(t) and not VALID_ID_RE.match(t)]
            for tag in malformed:
                problems.append(f"{where}: malformed scenario ID tag {tag}")
            if not ids and not malformed:
                problems.append(f"{where}: scenario has no ID tag")
            elif len(ids) > 1:
                problems.append(f"{where}: scenario has {len(ids)} ID tags ({' '.join(ids)})")
            for tag in ids:
                if tag in seen:
                    problems.append(f"{where}: duplicate scenario ID {tag} (first at {seen[tag]})")
                else:
                    seen[tag] = where
    return problems


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    files: list[Path] = []
    for arg in argv:
        root = Path(arg)
        if not root.exists():
            print(f"{arg}: no such file or directory", file=sys.stderr)
            return 2
        files.extend(sorted(root.rglob("*.feature")) if root.is_dir() else [root])
    problems = scan(files)
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-feature-ids: {len(problems)} problem(s) in {len(files)} file(s)", file=sys.stderr)
        return 1
    print(f"check-feature-ids: {len(files)} file(s) OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
