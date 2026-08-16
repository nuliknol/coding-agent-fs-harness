#!/usr/bin/env python3

"""Normalize optional Recoll candidates into canonical lexical documents."""

import argparse
import hashlib
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import unquote, urlparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-database", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--recoll-bin", required=True)
    parser.add_argument("--query", required=True)
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    repository = Path(args.repository).resolve()
    result = subprocess.run(
        [args.recoll_bin, "--paths-only", "-b", "-n", str(args.limit), args.query],
        check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    accepted: dict[str, Path] = {}
    for line in result.stdout.splitlines():
        value = unquote(urlparse(line.strip()).path) if line.startswith("file:") else line.strip()
        if not value:
            continue
        candidate = Path(value).resolve()
        try:
            relative = candidate.relative_to(repository).as_posix()
        except ValueError:
            continue
        if candidate.is_file():
            accepted[relative] = candidate
    output_database = Path(args.output_database)
    output_database.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(output_database)
    try:
        connection.execute("BEGIN IMMEDIATE")
        connection.execute("""CREATE TABLE IF NOT EXISTS candidates(
            document_id TEXT PRIMARY KEY, generation_id TEXT NOT NULL,
            repository_path TEXT NOT NULL, query TEXT NOT NULL,
            document_kind TEXT NOT NULL, content TEXT NOT NULL,
            provider TEXT NOT NULL, provider_fingerprint TEXT NOT NULL)""")
        connection.execute("""CREATE TABLE IF NOT EXISTS provider_runs(
            provider TEXT NOT NULL, generation_id TEXT NOT NULL,
            provider_version TEXT NOT NULL, fingerprint TEXT NOT NULL,
            status TEXT NOT NULL, evidence_path TEXT, recorded_at TEXT NOT NULL,
            PRIMARY KEY(provider,generation_id,fingerprint))""")
        for relative, candidate in sorted(accepted.items()):
            text = candidate.read_text(encoding="utf-8", errors="replace")[:65536]
            document_id = "recoll:" + hashlib.sha256((args.generation + "\0" + relative).encode()).hexdigest()
            connection.execute(
                "INSERT OR REPLACE INTO candidates VALUES(?,?,?,?,?,?,?,?)",
                (document_id, args.generation, relative, args.query, "recoll_candidate", text,
                 "recoll", hashlib.sha256((args.recoll_bin + "\0" + args.query).encode()).hexdigest()))
        status = "READY" if result.returncode == 0 else "DEGRADED"
        fingerprint = hashlib.sha256((args.recoll_bin + "\0" + args.query).encode()).hexdigest()
        connection.execute(
            """INSERT OR REPLACE INTO provider_runs
               (provider,generation_id,provider_version,fingerprint,status,evidence_path,recorded_at)
               VALUES('recoll',?,'runtime-query',?,?,?,datetime('now'))""",
            (args.generation, fingerprint, status, args.report))
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
    Path(args.report).write_text(
        f"status\t{status}\nreturn_code\t{result.returncode}\naccepted\t{len(accepted)}\n"
        f"overlay_database\t{output_database}\n"
        f"stderr_sha256\t{hashlib.sha256(result.stderr.encode()).hexdigest()}\n", encoding="utf-8")
    if result.returncode not in (0, 1):
        raise SystemExit(3)


if __name__ == "__main__":
    main()
