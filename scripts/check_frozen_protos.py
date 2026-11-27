#!/usr/bin/env python3
"""Frozen-package gate (decision 14.113, docs/design/wire-versioning.md).

proto/FROZEN lists the packages that are frozen, each as a header line
``package <name> dir=<dir under proto/>`` followed by ``<sha256>  <path>``
for every file of the package. A frozen package is never changed, whatever
the change (buf breaking cannot hold that: it allows an additive edit), and
a package never leaves the list. This script fails when:

- a listed file's digest differs, or the file is gone;
- a file exists under a frozen directory that the manifest does not list;
- a file of a frozen package declares another package than its header's;
- a package or file of the base manifest (the one at the merge base) is
  missing from the current one, or listed with another digest: so neither
  the files nor the manifest can be edited to agree.

Freezing a package (a new block whose digests match its files) is allowed.

Usage: check_frozen_protos.py --proto-dir DIR --base-manifest FILE
A base manifest that does not exist is an empty one (the first adoption).
Exits 0 when the gate holds, 1 otherwise (a line per problem on stderr).
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

Manifest = dict[str, tuple[str, dict[str, str]]]

PACKAGE_RE = re.compile(r"^\s*package\s+([A-Za-z0-9_.]+)\s*;", re.MULTILINE)


def parse(text: str) -> Manifest:
    """``{package: (dir, {path: sha256})}`` from a manifest's text."""
    manifest: Manifest = {}
    current: dict[str, str] | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("package "):
            parts = line.split()
            name = parts[1]
            directory = next((p[4:] for p in parts[2:] if p.startswith("dir=")), "")
            current = {}
            manifest[name] = (directory, current)
        elif current is not None:
            digest, _, path = line.partition("  ")
            current[path.strip()] = digest.strip()
    return manifest


def digest_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(proto_dir: Path, current: Manifest, base: Manifest) -> list[str]:
    problems: list[str] = []
    for package, (directory, files) in current.items():
        root = proto_dir / directory
        for path, digest in sorted(files.items()):
            target = proto_dir / path
            if not target.is_file():
                problems.append(f"{path}: a file of frozen package {package} is gone")
                continue
            if digest_of(target) != digest:
                problems.append(f"{path}: a file of frozen package {package} was changed")
                continue
            declared = PACKAGE_RE.search(target.read_text(encoding="utf-8"))
            if declared is None or declared.group(1) != package:
                problems.append(f"{path}: declares another package than frozen {package}")
        listed = set(files)
        if root.is_dir():
            for found in sorted(p for p in root.rglob("*") if p.is_file()):
                relative = found.relative_to(proto_dir).as_posix()
                if relative not in listed:
                    problems.append(f"{relative}: a file added to frozen package {package}")
    for package, (directory, files) in base.items():
        if package not in current:
            problems.append(f"{package}: a frozen package was removed from proto/FROZEN")
            continue
        now_directory, now_files = current[package]
        if now_directory != directory:
            problems.append(f"{package}: its frozen directory moved from {directory}")
        for path, digest in sorted(files.items()):
            if path not in now_files:
                problems.append(f"{path}: a file of frozen package {package} was unlisted")
            elif now_files[path] != digest:
                problems.append(f"{path}: the frozen digest of a file of {package} was changed")
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--proto-dir", required=True, type=Path)
    parser.add_argument("--base-manifest", required=True, type=Path)
    args = parser.parse_args(argv)
    manifest = args.proto_dir / "FROZEN"
    current = parse(manifest.read_text(encoding="utf-8")) if manifest.is_file() else {}
    base_file: Path = args.base_manifest
    base = parse(base_file.read_text(encoding="utf-8")) if base_file.is_file() else {}
    problems = check(args.proto_dir, current, base)
    for problem in problems:
        print(f"check_frozen_protos: {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
