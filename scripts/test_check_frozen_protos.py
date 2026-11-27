"""Tests for check_frozen_protos.py (run: python3 -m unittest scripts/test_check_frozen_protos.py).

The gate of decision 14.113: a frozen package (listed in proto/FROZEN) never
changes, whatever the change, and the manifest only grows. Each test runs the
script as the justfile does.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check_frozen_protos.py"

V0_FILE = "io/angzarr/v0/stored.proto"
V0_BODY = 'syntax = "proto3";\npackage io.angzarr.v0;\nmessage UUID { bytes value = 1; }\n'


def digest(body: str) -> str:
    return hashlib.sha256(body.encode()).hexdigest()


def manifest(entries: dict[str, str], package: str = "io.angzarr.v0", dir_: str = "io/angzarr/v0") -> str:
    lines = [f"package {package} dir={dir_}"]
    lines += [f"{digest(body)}  {path}" for path, body in entries.items()]
    return "\n".join(lines) + "\n"


class Tree:
    """A proto dir with a manifest, and the manifest at the merge base."""

    def __init__(self, files: dict[str, str], current: str, base: str) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.proto = root / "proto"
        self.proto.mkdir()
        for path, body in files.items():
            target = self.proto / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
        (self.proto / "FROZEN").write_text(current, encoding="utf-8")
        self.base = root / "FROZEN.base"
        self.base.write_text(base, encoding="utf-8")

    def run(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--proto-dir", str(self.proto), "--base-manifest", str(self.base)],
            capture_output=True,
            text=True,
        )

    def close(self) -> None:
        self.tmp.cleanup()


class CheckFrozenProtosTest(unittest.TestCase):
    def tree(self, files: dict[str, str], current: str, base: str) -> Tree:
        t = Tree(files, current, base)
        self.addCleanup(t.close)
        return t

    def test_an_unchanged_frozen_package_passes(self) -> None:
        m = manifest({V0_FILE: V0_BODY})
        r = self.tree({V0_FILE: V0_BODY}, m, m).run()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_an_edited_frozen_file_is_refused_and_named(self) -> None:
        m = manifest({V0_FILE: V0_BODY})
        r = self.tree({V0_FILE: V0_BODY + "// a comment\n"}, m, m).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(V0_FILE, r.stderr)

    def test_a_deleted_frozen_file_is_refused_and_named(self) -> None:
        m = manifest({V0_FILE: V0_BODY})
        r = self.tree({}, m, m).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(V0_FILE, r.stderr)

    def test_a_new_file_in_a_frozen_directory_is_refused_and_named(self) -> None:
        m = manifest({V0_FILE: V0_BODY})
        extra = "io/angzarr/v0/extra.proto"
        r = self.tree({V0_FILE: V0_BODY, extra: "syntax = \"proto3\";\n"}, m, m).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(extra, r.stderr)

    def test_editing_the_manifest_to_match_an_edited_file_is_refused(self) -> None:
        edited = V0_BODY + "// changed\n"
        r = self.tree({V0_FILE: edited}, manifest({V0_FILE: edited}), manifest({V0_FILE: V0_BODY})).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(V0_FILE, r.stderr)

    def test_unfreezing_a_package_is_refused(self) -> None:
        r = self.tree({V0_FILE: V0_BODY}, "", manifest({V0_FILE: V0_BODY})).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("io.angzarr.v0", r.stderr)

    def test_freezing_a_package_whose_files_match_passes(self) -> None:
        v1 = "io/angzarr/v1/stored.proto"
        v1_body = 'syntax = "proto3";\npackage io.angzarr.v1;\n'
        base = manifest({V0_FILE: V0_BODY})
        current = base + manifest({v1: v1_body}, "io.angzarr.v1", "io/angzarr/v1")
        r = self.tree({V0_FILE: V0_BODY, v1: v1_body}, current, base).run()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_package_that_is_not_frozen_may_change(self) -> None:
        m = manifest({V0_FILE: V0_BODY})
        r = self.tree({V0_FILE: V0_BODY, "io/angzarr/v1/stored.proto": "anything"}, m, m).run()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_frozen_file_declaring_another_package_is_refused(self) -> None:
        other = 'syntax = "proto3";\npackage io.angzarr.v9;\n'
        m = manifest({V0_FILE: other})
        r = self.tree({V0_FILE: other}, m, m).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("another package", r.stderr)

    def test_unlisting_one_file_of_a_frozen_package_is_refused(self) -> None:
        second = "io/angzarr/v0/second.proto"
        body = 'syntax = "proto3";\npackage io.angzarr.v0;\n'
        base = manifest({V0_FILE: V0_BODY, second: body})
        current = manifest({V0_FILE: V0_BODY})
        r = self.tree({V0_FILE: V0_BODY, second: body}, current, base).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(second, r.stderr)

    def test_moving_a_frozen_directory_is_refused(self) -> None:
        base = manifest({V0_FILE: V0_BODY})
        current = manifest({V0_FILE: V0_BODY}, dir_="io/angzarr")
        r = self.tree({V0_FILE: V0_BODY}, current, base).run()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("moved", r.stderr)

    def test_comments_and_blank_lines_in_a_manifest_are_ignored(self) -> None:
        m = "# frozen\n\n" + manifest({V0_FILE: V0_BODY})
        r = self.tree({V0_FILE: V0_BODY}, m, m).run()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_missing_base_manifest_is_an_empty_one(self) -> None:
        m = manifest({V0_FILE: V0_BODY})
        t = self.tree({V0_FILE: V0_BODY}, m, m)
        t.base.unlink()
        self.assertEqual(t.run().returncode, 0)


if __name__ == "__main__":
    unittest.main()
