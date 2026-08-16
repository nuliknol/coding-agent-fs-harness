#!/usr/bin/env python3

"""Import bounded indexer diagnostics with provider/configuration provenance."""

import argparse
import csv
import hashlib
from pathlib import Path
import sqlite3


def add(connection: sqlite3.Connection, generation: str, provider: str, severity: str,
        code: str, message: str, path: str | None, configuration: str | None) -> None:
    identifier = hashlib.sha256("\0".join((generation, provider, code, message, path or "")).encode()).hexdigest()
    connection.execute(
        "INSERT OR REPLACE INTO diagnostics VALUES(?,?,?,?,?,?,?,?,?,?)",
        (identifier, generation, provider, severity, code, message[:4096], path, None, None, configuration))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--configuration")
    parser.add_argument("--scip-unresolved", required=True)
    parser.add_argument("--include-unresolved", required=True)
    parser.add_argument("--scip-lint-status", required=True, type=int)
    parser.add_argument("--scip-lint-log", required=True)
    args = parser.parse_args()
    connection = sqlite3.connect(args.database)
    try:
        connection.execute("BEGIN IMMEDIATE")
        for provider, source in (("scip-clang", Path(args.scip_unresolved)),
                                 ("compile-input-scan", Path(args.include_unresolved))):
            if not source.is_file():
                continue
            with source.open(encoding="utf-8", errors="replace", newline="") as stream:
                reader = csv.DictReader(stream, delimiter="\t")
                for record in reader:
                    path = record.get("document") or record.get("source_path") or record.get("path")
                    message = record.get("reason") or record.get("diagnostic") or str(record)
                    add(connection, args.generation, provider, "WARNING", "UNRESOLVED", message,
                        path, args.configuration)
        if args.scip_lint_status:
            lint = Path(args.scip_lint_log).read_text(encoding="utf-8", errors="replace")[:4096]
            add(connection, args.generation, "scip", "WARNING", "SCIP_LINT_NONZERO", lint,
                None, args.configuration)
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    main()
