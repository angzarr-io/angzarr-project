#!/usr/bin/env python3
"""Gherkin syntax gate.

Parses every ``*.feature`` file under the given directories with the
official Cucumber Gherkin parser (the ``gherkin-official`` package) and
reports each file that fails to parse.

Usage: check_gherkin_parse.py DIR [DIR ...]

Exits 0 when every file parses, 1 otherwise.
"""

from __future__ import annotations

import sys
from pathlib import Path

from gherkin.parser import Parser


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
    failures = 0
    scenarios = 0
    for path in files:
        try:
            document = Parser().parse(path.read_text(encoding="utf-8"))
        except Exception as err:  # the parser raises a composite error per file
            failures += 1
            print(f"{path}: {err}")
            continue
        feature = document.get("feature") or {}
        for child in feature.get("children", []):
            if "scenario" in child:
                scenarios += 1
            for grandchild in child.get("rule", {}).get("children", []):
                if "scenario" in grandchild:
                    scenarios += 1
    if failures:
        print(f"check-gherkin: {failures} of {len(files)} file(s) failed to parse", file=sys.stderr)
        return 1
    print(f"check-gherkin: {len(files)} file(s), {scenarios} scenario(s) parsed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
