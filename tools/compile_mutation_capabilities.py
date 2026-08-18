#!/usr/bin/env python3

"""Resolve optional plan-node symbol mutation regions from the repository index."""

from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path


SOURCE_CHANGING = {"LOCAL_IMPLEMENTATION", "TEST_IMPLEMENTATION", "MECHANICAL_API",
                   "FOCUSED_BUG", "DOCUMENTATION"}


def values(text: str) -> list[str]:
    return [part.strip() for part in text.split(",") if part.strip() not in {"", "-"}]


def inside(path: str, scopes: list[str]) -> bool:
    return any(path == scope.rstrip("/") or path.startswith(scope.rstrip("/") + "/")
               for scope in scopes)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", required=True)
    parser.add_argument("--pointer", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--require-exact-luna", action="store_true")
    args = parser.parse_args()

    pointer = Path(args.pointer)
    database: Path | None = None
    if pointer.is_file():
        pointer_values = {}
        for line in pointer.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                pointer_values[key] = value
        candidate = Path(pointer_values.get("generation_dir", "")) / "architecture.sqlite"
        if pointer_values.get("status") == "READY" and candidate.is_file():
            database = candidate

    with Path(args.plan).open(encoding="utf-8", newline="") as stream:
        plan_rows = list(csv.DictReader(stream, delimiter="\t"))
    output_rows: list[dict[str, str]] = []
    errors: list[str] = []
    connection = sqlite3.connect(str(database)) if database else None
    try:
        for row in plan_rows:
            node = row["node_id"].strip()
            symbols = values(row.get("required_symbols", "-"))
            scopes = values(row.get("allowed_paths", "-"))
            resolved_symbols: set[str] = set()
            if connection is not None:
                for symbol in symbols:
                    matches = connection.execute(
                        """
                        SELECT DISTINCT f.repository_path, s.display_name,
                               r.start_line, r.end_line, COALESCE(s.symbol_kind, '-')
                        FROM symbols s
                        JOIN symbol_definitions d ON d.symbol_id=s.symbol_id
                        JOIN source_regions r ON r.region_id=d.region_id
                        JOIN files f ON f.file_id=r.file_id
                        WHERE s.display_name=?
                        ORDER BY f.repository_path, r.start_line, r.end_line
                        """, (symbol,)).fetchall()
                    bounded = [match for match in matches if inside(match[0], scopes)]
                    if bounded:
                        resolved_symbols.add(symbol)
                    for path, display, start, end, kind in bounded:
                        output_rows.append({"node_id": node, "repository_path": path,
                                            "symbol": display, "start_line": str(start),
                                            "end_line": str(end), "symbol_kind": kind,
                                            "authority": "INDEXED"})
            complete = bool(symbols) and resolved_symbols == set(symbols)
            source_changing = row.get("leaf_type", "") in SOURCE_CHANGING
            if (args.require_exact_luna and source_changing and row.get("worker_route") == "LUNA"
                    and complete):
                resolved_paths = {item["repository_path"] for item in output_rows
                                  if item["node_id"] == node}
                broad = [scope for scope in scopes
                         if any(path.startswith(scope.rstrip("/") + "/")
                                for path in resolved_paths)]
                if broad:
                    errors.append(
                        f"node={node} resolves every required symbol to exact files "
                        f"{','.join(sorted(resolved_paths))}; replace broad allowed_paths "
                        f"{','.join(broad)} with exact source files")
    finally:
        if connection is not None:
            connection.close()

    output = Path(args.output)
    with output.open("w", encoding="utf-8", newline="") as stream:
        fieldnames = ["node_id", "repository_path", "symbol", "start_line", "end_line",
                      "symbol_kind", "authority"]
        writer = csv.DictWriter(stream, fieldnames=fieldnames, delimiter="\t",
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows(output_rows)
    if errors:
        for error in errors:
            print(f"EXACT_MUTATION_CAPABILITY_REQUIRED {error}", file=__import__("sys").stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
