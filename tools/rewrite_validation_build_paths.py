#!/usr/bin/env python3

"""Rewrite static CMake build paths to one isolated validation namespace."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shlex
from pathlib import Path


def literal_build_paths(command: str) -> set[str]:
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return set()
    paths: set[str] = set()
    index = 0
    while index < len(tokens):
        token = tokens[index]
        candidate = ""
        if token in {"-B", "--build"} and index + 1 < len(tokens):
            candidate = tokens[index + 1]
            index += 1
        elif token.startswith("-B") and token != "-B":
            candidate = token[2:]
        elif token.startswith("--build="):
            candidate = token.split("=", 1)[1]
        if (candidate and candidate not in {".", ".."}
                and not re.search(r"[$`]", candidate)):
            paths.add(candidate.rstrip("/"))
        index += 1
    return paths


def rewrite(command: str, cwd: Path, private_root: Path) -> str:
    mappings: list[tuple[str, str]] = []
    for requested in literal_build_paths(command):
        canonical = Path(os.path.realpath(cwd / requested))
        key = hashlib.sha256(str(canonical).encode()).hexdigest()
        mappings.append((requested, str(private_root / key)))
    # Replace longer spellings first in case one declared build path nests in
    # another. Boundaries retain quoted paths and later references such as
    # /tmp/build/test_binary or ctest --test-dir /tmp/build.
    for requested, private in sorted(mappings, key=lambda item: len(item[0]), reverse=True):
        pattern = re.compile(
            rf"(?<![A-Za-z0-9_.~/+\-]){re.escape(requested)}"
            rf"(?=$|[\s;&|<>\"'/])")
        command = pattern.sub(lambda _: private, command)
    return command


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--command", required=True)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--private-root", required=True)
    args = parser.parse_args()
    print(rewrite(args.command, Path(args.cwd), Path(args.private_root)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
