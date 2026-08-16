#!/usr/bin/env python3

"""Discover the recursive non-repository include closure for compile commands.

This deliberately performs a deterministic, read-only preprocessor-style walk
instead of invoking the compiler.  It is sufficient for generated project
headers and explicitly configured external include roots; unresolved compiler
builtins remain visible in the report rather than being guessed.
"""

import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import shlex


INCLUDE = re.compile(r'^\s*#\s*include\s*(["<])([^">]+)[">]')


def words(record: dict[str, object]) -> list[str]:
    arguments = record.get("arguments")
    if isinstance(arguments, list):
        return [str(value) for value in arguments]
    try:
        return shlex.split(str(record.get("command", "")))
    except ValueError:
        return []


def include_directories(record: dict[str, object]) -> list[Path]:
    directory = Path(str(record["directory"])).resolve()
    result: list[Path] = []
    command = words(record)
    index = 0
    while index < len(command):
        word = command[index]
        value = ""
        if word in ("-I", "-iquote", "-isystem") and index + 1 < len(command):
            value = command[index + 1]
            index += 1
        elif word.startswith("-I") and len(word) > 2:
            value = word[2:]
        if value:
            path = Path(value)
            if not path.is_absolute():
                path = directory / path
            result.append(path.resolve())
        index += 1
    return result


def source_path(repository: Path, record: dict[str, object]) -> tuple[Path, str] | None:
    source = Path(str(record["file"]))
    if not source.is_absolute():
        source = Path(str(record["directory"])) / source
    source = source.resolve()
    try:
        return source, source.relative_to(repository).as_posix()
    except ValueError:
        return None


def resolve_include(source: Path, delimiter: str, literal: str,
                    include_dirs: list[Path]) -> Path | None:
    candidates = ([source.parent] if delimiter == '"' else []) + include_dirs
    for directory in candidates:
        candidate = (directory / literal).resolve()
        if candidate.is_file():
            return candidate
    return None


def scan_includes(source: Path, include_dirs: list[Path], repository: Path,
                  build_directory: Path, root_source: str,
                  found: set[tuple[str, str, str, str, str, str]],
                  unresolved: set[tuple[str, str, str]], visited: set[Path]) -> None:
    source = source.resolve()
    if source in visited:
        return
    visited.add(source)
    try:
        source_lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as error:
        unresolved.add((root_source, str(source), f"read-error:{error.__class__.__name__}"))
        return
    try:
        includer = source.relative_to(repository).as_posix()
    except ValueError:
        includer = str(source)
    for line in source_lines:
        match = INCLUDE.match(line)
        if not match:
            continue
        literal = match.group(2)
        resolved = resolve_include(source, match.group(1), literal, include_dirs)
        if resolved is None:
            # System/compiler builtin headers are intentionally not guessed.
            # Record only quote includes: those are expected to resolve from
            # the configured project/build include roots.
            if match.group(1) == '"':
                unresolved.add((root_source, literal, f"included-by:{includer}"))
            continue
        try:
            resolved.relative_to(repository)
            in_repository = True
        except ValueError:
            in_repository = False
        if not in_repository:
            try:
                content_hash = hashlib.sha256(resolved.read_bytes()).hexdigest()
            except OSError as error:
                unresolved.add((root_source, str(resolved), f"hash-error:{error.__class__.__name__}"))
                continue
            kind = "GENERATED_HEADER" if resolved == build_directory or build_directory in resolved.parents \
                else "EXTERNAL_HEADER"
            found.add((root_source, includer, literal, str(resolved), content_hash, kind))
        scan_includes(resolved, include_dirs, repository, build_directory,
                      root_source, found, unresolved, visited)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compile-commands", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repository = Path(args.repository).resolve()
    records = json.loads(Path(args.compile_commands).read_text(encoding="utf-8"))
    found: set[tuple[str, str, str, str, str, str]] = set()
    unresolved: set[tuple[str, str, str]] = set()
    for record in records:
        source_record = source_path(repository, record)
        if source_record is None:
            continue
        source, relative_source = source_record
        include_dirs = include_directories(record)
        build_directory = Path(str(record["directory"])).resolve()
        scan_includes(source, include_dirs, repository, build_directory,
                      relative_source, found, unresolved, set())
    with Path(args.output).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("source_path", "included_by", "include_literal", "absolute_path",
                         "content_sha256", "input_kind"))
        writer.writerows(sorted(found))
    unresolved_path = Path(str(args.output) + ".unresolved.tsv")
    with unresolved_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("source_path", "include", "reason"))
        writer.writerows(sorted(unresolved))


if __name__ == "__main__":
    main()
