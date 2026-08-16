#!/usr/bin/env python3

"""Import deterministic compilation-unit ownership into the repository index."""

import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import shlex
import sqlite3


CMAKE_TARGET = re.compile(r"(?:^|/)CMakeFiles/([^/]+)\.dir(?:/|$)")
INCLUDE = re.compile(r'^\s*#\s*include\s*(["<])([^">]+)[">]')


def stable_id(*parts: str) -> str:
    digest = hashlib.sha256()
    for part in parts:
        digest.update(part.encode("utf-8", errors="replace"))
        digest.update(b"\0")
    return digest.hexdigest()


def repository_path(repository: Path, directory: Path, value: str) -> str | None:
    source = Path(value)
    if not source.is_absolute():
        source = directory / source
    source = source.resolve()
    try:
        return source.relative_to(repository).as_posix()
    except ValueError:
        return None


def command_output(record: dict[str, object]) -> str:
    output = record.get("output")
    if isinstance(output, str) and output:
        return output
    arguments = record.get("arguments")
    if isinstance(arguments, list):
        words = [str(word) for word in arguments]
    else:
        command = record.get("command")
        try:
            words = shlex.split(str(command)) if command else []
        except ValueError:
            words = []
    for index, word in enumerate(words[:-1]):
        if word == "-o":
            return words[index + 1]
    return ""


def command_words(record: dict[str, object]) -> list[str]:
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
    words = command_words(record)
    index = 0
    while index < len(words):
        word = words[index]
        value = ""
        if word in ("-I", "-iquote", "-isystem") and index + 1 < len(words):
            value = words[index + 1]
            index += 1
        elif word.startswith("-I") and len(word) > 2:
            value = word[2:]
        if value:
            path = Path(value)
            result.append((directory / path).resolve() if not path.is_absolute() else path.resolve())
        index += 1
    return result


def local_includes(repository: Path, source: Path, record: dict[str, object]) -> list[tuple[str, str]]:
    try:
        lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    include_dirs = include_directories(record)
    result: set[tuple[str, str]] = set()
    for line in lines:
        match = INCLUDE.match(line)
        if not match:
            continue
        candidates = ([source.parent] if match.group(1) == '"' else []) + include_dirs
        for directory in candidates:
            candidate = (directory / match.group(2)).resolve()
            if not candidate.is_file():
                continue
            try:
                relative = candidate.relative_to(repository).as_posix()
            except ValueError:
                break
            result.add((match.group(2), relative))
            break
    return sorted(result)


def target_name(output: str, source_path: str) -> tuple[str, str]:
    normalized = output.replace("\\", "/")
    match = CMAKE_TARGET.search(normalized)
    if match:
        return match.group(1), "CMAKE_COMPILE_TARGET"
    return f"translation-unit:{source_path}", "TRANSLATION_UNIT"


def nearest_build_definition(repository: Path, source_path: str) -> str | None:
    current = (repository / source_path).parent
    while True:
        candidate = current / "CMakeLists.txt"
        if candidate.is_file():
            return candidate.relative_to(repository).as_posix()
        if current == repository:
            return None
        if repository not in current.parents:
            return None
        current = current.parent


def compile_inputs(path: str) -> list[dict[str, str]]:
    with Path(path).open(encoding="utf-8", errors="replace", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def import_commands(args: argparse.Namespace) -> tuple[int, int, int]:
    repository = Path(args.repository).resolve()
    records = json.loads(Path(args.compile_commands).read_text(encoding="utf-8"))
    connection = sqlite3.connect(args.database)
    connection.execute("PRAGMA foreign_keys = ON")
    targets: set[str] = set()
    targets_by_source: dict[str, str] = {}
    mappings = 0
    input_mappings = 0
    try:
        connection.execute("BEGIN IMMEDIATE")
        for record in records:
            directory = Path(str(record["directory"])).resolve()
            path = repository_path(repository, directory, str(record["file"]))
            if path is None:
                continue
            file_row = connection.execute(
                "SELECT file_id, generated FROM files WHERE generation_id=? AND repository_path=?",
                (args.generation, path),
            ).fetchone()
            if file_row is None:
                absolute_source = repository / path
                content_hash = hashlib.sha256(absolute_source.read_bytes()).hexdigest() if absolute_source.is_file() else None
                language = {".c": "c", ".cc": "cpp", ".cpp": "cpp", ".cxx": "cpp",
                            ".h": "c", ".hh": "cpp", ".hpp": "cpp", ".hip": "hip"}.get(absolute_source.suffix.lower())
                connection.execute(
                    """INSERT OR IGNORE INTO files(generation_id,repository_path,language,content_sha256,tracked,generated)
                       VALUES(?,?,?,?,1,0)""", (args.generation, path, language, content_hash))
                file_row = connection.execute(
                    "SELECT file_id, generated FROM files WHERE generation_id=? AND repository_path=?",
                    (args.generation, path)).fetchone()
                if file_row is None:
                    continue
                diagnostic_id = stable_id(args.generation, "unsupported-compilation-unit", path)
                connection.execute(
                    """INSERT OR REPLACE INTO diagnostics
                       (diagnostic_id,generation_id,provider,severity,code,message,repository_path,configuration_id)
                       VALUES(?,?,'compile-commands','WARNING','NO_SCIP_DOCUMENT',
                              'Compilation unit is registered but the structural provider emitted no document',?,?)""",
                    (diagnostic_id, args.generation, path, args.configuration))
            output = command_output(record)
            name, kind = target_name(output, path)
            target_id = stable_id(args.generation, "build-target", name)
            definition = nearest_build_definition(repository, path)
            connection.execute(
                """
                INSERT OR IGNORE INTO build_targets(
                    target_id, generation_id, name, target_kind, definition_path, provider
                ) VALUES (?, ?, ?, ?, ?, 'compile-commands')
                """,
                (target_id, args.generation, name, kind, definition),
            )
            role = "GENERATED_SOURCE" if int(file_row[1]) else "COMPILE_SOURCE"
            connection.execute(
                """
                INSERT OR REPLACE INTO build_target_files(
                    target_id, file_id, configuration_id, role, object_path, provider
                ) VALUES (?, ?, ?, ?, ?, 'compile-commands')
                """,
                (target_id, int(file_row[0]), args.configuration, role, output or None),
            )
            targets.add(target_id)
            targets_by_source[path] = target_id
            mappings += 1
            source_absolute = (directory / str(record["file"])).resolve() if not Path(str(record["file"])).is_absolute() else Path(str(record["file"])).resolve()
            for literal, target_path in local_includes(repository, source_absolute, record):
                target_row = connection.execute(
                    "SELECT file_id FROM files WHERE generation_id=? AND repository_path=?",
                    (args.generation, target_path)).fetchone()
                connection.execute(
                    """INSERT OR IGNORE INTO include_edges(source_file_id,target_path,resolved_file_id,provider)
                       VALUES(?,?,?,'compile-input-scan')""",
                    (int(file_row[0]), literal, int(target_row[0]) if target_row else None))
        for record in compile_inputs(args.compile_inputs):
            source = record.get("source_path", "")
            target_id = targets_by_source.get(source)
            if not target_id:
                continue
            absolute_path = record.get("absolute_path", "")
            content_hash = record.get("content_sha256", "")
            input_kind = record.get("input_kind", "")
            include_literal = record.get("include_literal", "")
            included_by = record.get("included_by", source)
            if not absolute_path or not content_hash or input_kind not in ("GENERATED_HEADER", "EXTERNAL_HEADER"):
                continue
            input_id = stable_id(args.generation, "build-input", absolute_path)
            connection.execute(
                """
                INSERT OR REPLACE INTO build_inputs(
                    input_id, generation_id, absolute_path, content_sha256, input_kind, provider
                ) VALUES (?, ?, ?, ?, ?, 'compile-input-scan')
                """,
                (input_id, args.generation, absolute_path, content_hash, input_kind),
            )
            connection.execute(
                """
                INSERT OR REPLACE INTO build_target_inputs(
                    target_id, input_id, source_path, include_literal, included_by, provider
                ) VALUES (?, ?, ?, ?, ?, 'compile-input-scan')
                """,
                (target_id, input_id, source, include_literal, included_by),
            )
            input_mappings += 1
        connection.execute(
            """
            UPDATE tests
            SET build_target=(
                SELECT bt.name
                FROM build_target_files btf
                JOIN build_targets bt ON bt.target_id=btf.target_id
                WHERE btf.file_id=tests.file_id
                ORDER BY bt.name LIMIT 1
            )
            WHERE generation_id=? AND file_id IS NOT NULL
            """,
            (args.generation,),
        )
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
    return len(targets), mappings, input_mappings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compile-commands", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--compile-inputs", required=True)
    parser.add_argument("--report", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    targets, mappings, input_mappings = import_commands(args)
    Path(args.report).write_text(
        f"metric\tvalue\nbuild_targets\t{targets}\nbuild_target_files\t{mappings}\n"
        f"build_target_inputs\t{input_mappings}\n",
        encoding="utf-8",
    )
    print(f"BUILD_TARGETS_IMPORTED targets={targets} file_mappings={mappings} input_mappings={input_mappings}")


if __name__ == "__main__":
    main()
