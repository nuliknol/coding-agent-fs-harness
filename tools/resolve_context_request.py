#!/usr/bin/env python3

"""Compile one bounded, assignment-authorized Context Closure extension."""

import argparse
import csv
import hashlib
from pathlib import Path
import sqlite3
import sys


REQUEST_KINDS = {
    "TYPE_DEFINITION",
    "CALLER_CONTRACT",
    "FAILING_ASSERTION",
    "BUILD_OWNER",
    "REPRESENTATION_WRITER",
}


def metadata(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            values.setdefault(key, value)
    return values


def split_list(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip() not in {"", "-", "NONE"}}


def closure_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def safe_path(repository: Path, relative: str) -> Path | None:
    candidate = (repository / relative).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError:
        return None
    return candidate if candidate.is_file() else None


def source_excerpt(repository: Path, path: str, start: int, end: int,
                   maximum: int) -> str:
    source = safe_path(repository, path)
    if source is None:
        return ""
    lines = source.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    first = max(start - 1, 0)
    last = min(max(end, start), len(lines))
    encoded = "".join(lines[first:last]).encode("utf-8")
    if len(encoded) > maximum:
        encoded = encoded[:maximum]
    return encoded.decode("utf-8", errors="ignore")


def exact_symbols(connection: sqlite3.Connection, identifier: str) -> list[sqlite3.Row]:
    return connection.execute(
        "SELECT symbol_id,display_name,provider FROM symbols "
        "WHERE display_name=? COLLATE NOCASE OR symbol_id=? ORDER BY symbol_id",
        (identifier, identifier),
    ).fetchall()


def definitions(connection: sqlite3.Connection, symbol_ids: list[str]) -> list[sqlite3.Row]:
    if not symbol_ids:
        return []
    marks = ",".join("?" for _ in symbol_ids)
    return connection.execute(
        f"SELECT s.symbol_id,s.display_name,f.repository_path,r.start_line,r.end_line,d.provider "
        f"FROM symbols s JOIN symbol_definitions d ON d.symbol_id=s.symbol_id "
        f"JOIN source_regions r ON r.region_id=d.region_id "
        f"JOIN files f ON f.file_id=r.file_id WHERE s.symbol_id IN ({marks}) "
        "ORDER BY f.repository_path,r.start_line,s.symbol_id",
        symbol_ids,
    ).fetchall()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assignment", required=True)
    parser.add_argument("--closure", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--request-kind", required=True, choices=sorted(REQUEST_KINDS))
    parser.add_argument("--identifier", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-bytes", required=True, type=int)
    args = parser.parse_args()

    assignment = metadata(Path(args.assignment))
    closure = closure_rows(Path(args.closure))
    repository = Path(args.repository).resolve()
    identifier = args.identifier.strip()
    if not identifier or len(identifier) > 256 or "\n" in identifier:
        print("status=REJECTED\nreason=invalid-identifier")
        return 2

    required_symbols = split_list(assignment.get("Required-Symbols", ""))
    declared_paths = split_list(assignment.get("Context-Paths", "")) | split_list(
        assignment.get("Allowed-Scope", ""))
    closure_symbols = {row.get("symbol", "") for row in closure} - {"", "-"}
    closure_paths = {row.get("source_path", "") for row in closure} - {"", "-"}
    seed_symbols = required_symbols | closure_symbols
    seed_paths = declared_paths | closure_paths

    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    requested = exact_symbols(connection, identifier)
    requested_ids = [row["symbol_id"] for row in requested]
    requested_names = {row["display_name"] for row in requested}
    seed_rows: list[sqlite3.Row] = []
    for seed in sorted(seed_symbols):
        seed_rows.extend(exact_symbols(connection, seed))
    seed_ids = {row["symbol_id"] for row in seed_rows}

    records: list[tuple[str, str, int, int, str, str]] = []
    relation = ""
    if args.request_kind == "TYPE_DEFINITION":
        if not requested_ids:
            relation = "missing-exact-symbol"
        else:
            adjacent = set(requested_ids) & seed_ids
            if not adjacent and seed_ids:
                marks = ",".join("?" for _ in seed_ids)
                request_marks = ",".join("?" for _ in requested_ids)
                rows = connection.execute(
                    f"SELECT type_symbol_id FROM type_edges WHERE "
                    f"source_symbol_id IN ({marks}) AND type_symbol_id IN ({request_marks})",
                    [*sorted(seed_ids), *requested_ids],
                ).fetchall()
                adjacent = {row[0] for row in rows}
            if adjacent:
                relation = "required-or-direct-type"
                for row in definitions(connection, sorted(adjacent)):
                    records.append(("TYPE_DEFINITION", row["repository_path"], row["start_line"],
                                    row["end_line"], row["display_name"], row["provider"]))
    elif args.request_kind == "CALLER_CONTRACT":
        authorized = set(requested_ids) & seed_ids
        if authorized:
            marks = ",".join("?" for _ in authorized)
            callers = connection.execute(
                f"SELECT DISTINCT caller_symbol_id FROM call_edges WHERE callee_symbol_id IN ({marks}) "
                "ORDER BY caller_symbol_id", sorted(authorized)).fetchall()
            relation = "direct-caller-of-required-symbol"
            for row in definitions(connection, [item[0] for item in callers]):
                records.append(("CALLER_CONTRACT", row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
    elif args.request_kind == "FAILING_ASSERTION":
        test_rows = connection.execute(
            "SELECT t.name,f.repository_path,r.start_line,r.end_line,t.provider,t.test_id "
            "FROM tests t LEFT JOIN files f ON f.file_id=t.file_id "
            "LEFT JOIN source_regions r ON r.region_id=t.region_id "
            "WHERE t.name=? COLLATE NOCASE OR t.test_id=? ORDER BY t.test_id",
            (identifier, identifier),
        ).fetchall()
        for row in test_rows:
            if row["repository_path"] in seed_paths and row["start_line"]:
                records.append(("FAILING_ASSERTION", row["repository_path"], row["start_line"],
                                row["end_line"], row["name"], row["provider"]))
        relation = "named-test-inside-assignment-boundary"
    elif args.request_kind == "BUILD_OWNER":
        if identifier in seed_paths:
            rows = connection.execute(
                "SELECT DISTINCT bt.name,bt.definition_path,bt.provider FROM build_targets bt "
                "JOIN build_target_files btf ON btf.target_id=bt.target_id "
                "JOIN files f ON f.file_id=btf.file_id WHERE f.repository_path=? "
                "ORDER BY bt.name", (identifier,)).fetchall()
            for row in rows:
                if row["definition_path"]:
                    records.append(("BUILD_OWNER", row["definition_path"], 1, 200,
                                    row["name"], row["provider"]))
            relation = "build-owner-of-declared-path"
    elif args.request_kind == "REPRESENTATION_WRITER":
        authorized = set(requested_ids) & seed_ids
        if authorized:
            marks = ",".join("?" for _ in authorized)
            writers = connection.execute(
                f"SELECT DISTINCT source_symbol_id FROM mutation_edges WHERE "
                f"source_symbol_id IN ({marks}) OR target_symbol_id IN ({marks}) "
                "ORDER BY source_symbol_id", [*sorted(authorized), *sorted(authorized)]).fetchall()
            relation = "joern-mutation-adjacent-to-required-symbol"
            for row in definitions(connection, [item[0] for item in writers]):
                records.append(("REPRESENTATION_WRITER", row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
    connection.close()

    # Extensions may expose a direct graph neighbor outside the original source
    # path set, but never arbitrary lexical matches. Keep deterministic order and
    # at most four exact regions within the byte budget.
    records = sorted(set(records), key=lambda item: (item[1], item[2], item[4]))[:4]
    if not records:
        print(f"status=REJECTED\nreason=no-authorized-evidence\nrelation={relation or 'none'}")
        return 3

    content: list[str] = [
        "# Trusted Context Closure Extension", "",
        f"Context-Request-Kind: {args.request_kind}",
        f"Context-Request-Identifier: {identifier}",
        f"Authorization-Relation: {relation}", "",
    ]
    remaining = args.max_bytes - len("\n".join(content).encode("utf-8")) - 256
    included = 0
    evidence_digest = hashlib.sha256()
    for kind, path, start, end, symbol, provider in records:
        if remaining <= 0:
            break
        text = source_excerpt(repository, path, start, end, remaining)
        if not text:
            continue
        evidence_digest.update(f"{kind}\0{path}\0{start}\0{end}\0{symbol}\0{provider}\0".encode())
        evidence_digest.update(text.encode())
        block = [
            f"## {kind}: `{path}:{start}` — `{symbol}`", "",
            f"Provider: `{provider}`; relation: `{relation}`.", "", "```text",
            text.rstrip("\n"), "```", "",
        ]
        rendered = "\n".join(block)
        content.append(rendered)
        remaining -= len(rendered.encode("utf-8"))
        included += 1
    if included == 0:
        print("status=REJECTED\nreason=evidence-unreadable")
        return 4
    content.insert(6, f"Evidence-SHA256: {evidence_digest.hexdigest()}")
    rendered = "\n".join(content).rstrip() + "\n"
    if len(rendered.encode("utf-8")) > args.max_bytes:
        print("status=REJECTED\nreason=extension-budget-exceeded")
        return 5
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_text(rendered, encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(output)
    print(f"status=READY\npath={output}\nbytes={len(rendered.encode('utf-8'))}\n"
          f"evidence_sha256={evidence_digest.hexdigest()}\nrelation={relation}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
