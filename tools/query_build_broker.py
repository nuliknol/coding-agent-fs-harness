#!/usr/bin/env python3

"""Deterministic bounded queries over indexed build/test evidence."""

from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path


QUERIES = {
    "SOURCE_TO_TARGET": """
        SELECT DISTINCT f.repository_path, b.name, COALESCE(b.target_kind, '-'),
                        b.definition_path, bf.role
        FROM files f JOIN build_target_files bf ON bf.file_id=f.file_id
        JOIN build_targets b ON b.target_id=bf.target_id
        WHERE f.repository_path=? ORDER BY b.name LIMIT 32""",
    "TARGET_TO_SOURCE": """
        SELECT DISTINCT b.name, f.repository_path, bf.role, COALESCE(bf.object_path, '-')
        FROM build_targets b JOIN build_target_files bf ON bf.target_id=b.target_id
        JOIN files f ON f.file_id=bf.file_id
        WHERE b.name=? ORDER BY f.repository_path LIMIT 64""",
    "MINIMAL_TARGET": """
        SELECT DISTINCT b.name, COALESCE(b.target_kind, '-'), b.definition_path
        FROM symbols s JOIN symbol_definitions d ON d.symbol_id=s.symbol_id
        JOIN source_regions r ON r.region_id=d.region_id
        JOIN files f ON f.file_id=r.file_id
        JOIN build_target_files bf ON bf.file_id=f.file_id
        JOIN build_targets b ON b.target_id=bf.target_id
        WHERE s.display_name=? ORDER BY b.name LIMIT 16""",
    "TEST_SELECTOR": """
        SELECT DISTINCT name, COALESCE(build_target, '-'), COALESCE(selector, '-'),
                        COALESCE((SELECT repository_path FROM files WHERE file_id=tests.file_id), '-')
        FROM tests WHERE name=? OR selector=? OR build_target=? ORDER BY name LIMIT 32""",
    "DEPENDENCY_ARTIFACT": """
        SELECT DISTINCT b.name, i.absolute_path, i.input_kind, bt.source_path, bt.include_literal
        FROM build_targets b JOIN build_target_inputs bt ON bt.target_id=b.target_id
        JOIN build_inputs i ON i.input_id=bt.input_id
        WHERE b.name=? ORDER BY i.absolute_path LIMIT 64""",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pointer", required=True)
    parser.add_argument("--query", choices=[*QUERIES, "FIRST_CAUSAL_ERROR"], required=True)
    parser.add_argument("--value", required=True)
    parser.add_argument("--diagnostics-root")
    args = parser.parse_args()
    if args.query == "FIRST_CAUSAL_ERROR":
        root = Path(args.diagnostics_root or ".")
        matches = sorted(root.glob(f"**/*{args.value}*.diagnostics.tsv"),
                         key=lambda path: path.stat().st_mtime, reverse=True)
        if not matches:
            return 4
        with matches[0].open(encoding="utf-8", errors="replace") as stream:
            header = stream.readline().rstrip("\n")
            row = stream.readline().rstrip("\n")
        print(header)
        if row:
            print(row)
        return 0
    pointer_values = {}
    for line in Path(args.pointer).read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            pointer_values[key] = value
    database = Path(pointer_values.get("generation_dir", "")) / "architecture.sqlite"
    if pointer_values.get("status") != "READY" or not database.is_file():
        return 3
    connection = sqlite3.connect(str(database))
    try:
        parameters = (args.value, args.value, args.value) if args.query == "TEST_SELECTOR" else (args.value,)
        cursor = connection.execute(QUERIES[args.query], parameters)
        writer = csv.writer(__import__("sys").stdout, delimiter="\t", lineterminator="\n")
        writer.writerow([description[0] for description in cursor.description])
        writer.writerows(cursor.fetchall())
    finally:
        connection.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
