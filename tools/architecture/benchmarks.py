"""Versioned architecture navigation benchmarks."""

from __future__ import annotations

import csv
from pathlib import Path
import sqlite3

from .reporting import write_tsv


def _read_queries(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        required = {"benchmark_id", "query", "expected_paths"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("benchmark TSV requires benchmark_id, query, expected_paths")
        return list(reader)


def benchmark_database(database: Path, generation: str, repository: Path,
                       queries: Path, output: Path) -> None:
    connection = sqlite3.connect(database)
    output_rows: list[tuple] = []
    try:
        for record in _read_queries(queries):
            expected = {value.strip() for value in record["expected_paths"].split(",") if value.strip()}
            query = record["query"]
            found = connection.execute("""SELECT DISTINCT f.repository_path FROM symbols s
                JOIN symbol_definitions d USING(symbol_id) JOIN source_regions r USING(region_id)
                JOIN files f USING(file_id) WHERE s.generation_id=? AND
                (s.display_name=? COLLATE NOCASE OR s.symbol_id=?) ORDER BY f.repository_path LIMIT 50""",
                                       (generation, query, query)).fetchall()
            returned = {row[0] for row in found}
            if not returned:
                returned = {row[0] for row in connection.execute(
                    "SELECT repository_path FROM lexical_documents WHERE lexical_documents MATCH ? ORDER BY rank LIMIT 50",
                    (f'"{query}"',))}
            output_rows.append(_benchmark_row(record, expected, returned, repository))
    finally:
        connection.close()
    _write(output, output_rows)


def benchmark_maps(maps: Path, repository: Path, queries: Path, output: Path) -> None:
    searchable: list[tuple[str, str]] = []
    for name, key_columns, path_column in (
        ("public-interface-map.tsv", ("symbol",), "path"),
        ("concept-owner-map.tsv", ("concept",), "evidence"),
        ("responsibility-map.tsv", ("module", "module_id"), "path"),
    ):
        path = maps / name
        if not path.is_file():
            continue
        with path.open(encoding="utf-8", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                evidence = row.get(path_column, "").split(":", 1)[0]
                for column in key_columns:
                    searchable.append((row.get(column, ""), evidence))
    output_rows: list[tuple] = []
    for record in _read_queries(queries):
        expected = {value.strip() for value in record["expected_paths"].split(",") if value.strip()}
        query = record["query"].casefold()
        exact = {path for value, path in searchable if value.casefold() == query}
        returned = exact or {path for value, path in searchable if query in value.casefold()}
        output_rows.append(_benchmark_row(record, expected, returned, repository))
    _write(output, output_rows)


def _benchmark_row(record: dict[str, str], expected: set[str], returned: set[str], repository: Path) -> tuple:
    relevant = len(expected & returned)
    context_bytes = sum((repository / path).stat().st_size
                        for path in returned if (repository / path).is_file())
    return (record["benchmark_id"], record["query"], ",".join(sorted(expected)),
            ",".join(sorted(returned)), relevant, len(expected), len(returned), context_bytes)


def _write(output: Path, records: list[tuple]) -> None:
    write_tsv(output, ("benchmark_id", "query", "expected_paths", "returned_paths",
                       "relevant_returned", "expected_total", "returned_total", "context_bytes"), records)

