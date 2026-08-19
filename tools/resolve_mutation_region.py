#!/usr/bin/env python3

"""Resolve a repository-relative ``path:line`` to one indexed code symbol.

This is intentionally deterministic.  An ACP mutation-region request may add
read/mutation evidence inside an already-authorized file, but it must not send
the manager back to a model merely to rediscover the enclosing definition.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path, PurePosixPath


def database_from_pointer(pointer: Path) -> Path:
    values: dict[str, str] = {}
    for line in pointer.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    candidate = Path(values.get("generation_dir", "")) / "architecture.sqlite"
    if values.get("status") != "READY" or not candidate.is_file():
        raise ValueError("repository index pointer is not READY")
    return candidate


def parse_identifier(identifier: str) -> tuple[str, int]:
    path, separator, line_text = identifier.rpartition(":")
    if not separator or not path or not line_text.isdigit() or int(line_text) < 1:
        raise ValueError("identifier must be a repository-relative path followed by a positive line number")
    pure = PurePosixPath(path)
    if pure.is_absolute() or ".." in pure.parts or path.startswith("./"):
        raise ValueError("identifier path must be a normalized repository-relative path")
    return path, int(line_text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pointer", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--identifier", required=True)
    args = parser.parse_args()
    try:
        repository_path, line = parse_identifier(args.identifier)
        repository = Path(args.repository).resolve()
        candidate = (repository / repository_path).resolve()
        candidate.relative_to(repository)
        if not candidate.is_file():
            raise ValueError("identifier path does not name a tracked repository file")
        database = database_from_pointer(Path(args.pointer))
        connection = sqlite3.connect(database)
        try:
            rows = connection.execute(
                """
                SELECT s.display_name, r.start_line, r.end_line
                FROM symbols AS s
                JOIN symbol_definitions AS d ON d.symbol_id=s.symbol_id
                JOIN source_regions AS r ON r.region_id=d.region_id
                JOIN files AS f ON f.file_id=r.file_id
                WHERE f.repository_path=?
                  AND r.start_line<=?
                  AND r.end_line>=?
                  AND s.display_name GLOB '[A-Za-z_]*'
                ORDER BY (r.end_line-r.start_line), r.start_line, s.display_name
                """, (repository_path, line, line)).fetchall()
        finally:
            connection.close()
        if not rows:
            raise ValueError("no indexed named symbol encloses the requested mutation line")
        symbol, _start, _end = rows[0]
        print(f"{repository_path}\t{symbol}")
        return 0
    except (OSError, ValueError, sqlite3.Error) as error:
        print(f"MUTATION_REGION_RESOLUTION_ERROR {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
