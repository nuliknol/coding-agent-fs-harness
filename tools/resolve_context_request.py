#!/usr/bin/env python3

"""Compile one bounded, assignment-authorized Context Closure extension."""

import argparse
import csv
import hashlib
from pathlib import Path
import shlex
import sqlite3
import sys


REQUEST_KINDS = {
    "TYPE_DEFINITION",
    "SYMBOL_DEFINITION",
    "CALLER_CONTRACT",
    "CALLEE_CONTRACT",
    "FAILING_ASSERTION",
    "TEST_TARGET",
    "TEST_OWNER",
    "BUILD_TARGET",
    "BUILD_OWNER",
    "OWNER",
    "PRODUCER",
    "CONSUMER",
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


def safe_entry(repository: Path, relative: str) -> Path | None:
    """Resolve one declared repository file or directory without escaping it."""
    candidate = (repository / relative).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError:
        return None
    return candidate if candidate.is_file() or candidate.is_dir() else None


def inside_declared_boundary(repository: Path, path: str,
                             boundaries: set[str]) -> bool:
    for boundary in boundaries:
        normalized = boundary.split("#", 1)[0].rstrip("/")
        entry = safe_entry(repository, normalized)
        if entry is None:
            continue
        if entry.is_file() and path == normalized:
            return True
        if entry.is_dir() and (path == normalized or path.startswith(normalized + "/")):
            return True
    return False


def exact_identifier_window(repository: Path, path: str,
                            identifier: str) -> tuple[int, int] | None:
    source = safe_path(repository, path)
    if source is None:
        return None
    lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
    for line_number, line in enumerate(lines, start=1):
        if identifier in line:
            return max(1, line_number - 20), min(len(lines), line_number + 20)
    return None


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


def tail_window(repository: Path, path: str, maximum: int) -> tuple[int, int] | None:
    """Return the largest line-aligned tail that fits a bounded extension.

    A declared file can already be present in the initial closure while its
    rendered excerpt is necessarily truncated.  An exact path request asks
    for the complementary tail, not an unrelated repository search.
    """
    source = safe_path(repository, path)
    if source is None:
        return None
    lines = source.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    if not lines:
        return (1, 1)
    used = 0
    start = len(lines)
    budget = max(1, maximum - 1024)
    while start > 0:
        encoded = lines[start - 1].encode("utf-8")
        if used and used + len(encoded) > budget:
            break
        used += len(encoded)
        start -= 1
    return start + 1, len(lines)


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


def declared_validation_paths(repository: Path, command: str) -> set[str]:
    """Return exact existing repository paths named as validation arguments."""
    try:
        tokens = shlex.split(command)
    except ValueError:
        return set()
    paths: set[str] = set()
    for token in tokens:
        if not token or token.startswith("-"):
            continue
        entry = safe_entry(repository, token)
        if entry is None:
            continue
        paths.add(entry.relative_to(repository).as_posix() or ".")
    return paths


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
    validation_paths = declared_validation_paths(
        repository, assignment.get("Focused-Validation", ""))

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
    if args.request_kind == "SYMBOL_DEFINITION":
        authorized = set(requested_ids) & seed_ids
        if authorized:
            relation = "exact-required-symbol"
            for row in definitions(connection, sorted(authorized)):
                records.append(("SYMBOL_DEFINITION", row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
        else:
            relation = "symbol-outside-assignment-boundary"
    elif args.request_kind == "TYPE_DEFINITION":
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
    elif args.request_kind == "CALLEE_CONTRACT":
        authorized = set(requested_ids) & seed_ids
        if authorized:
            marks = ",".join("?" for _ in authorized)
            callees = connection.execute(
                f"SELECT DISTINCT callee_symbol_id FROM call_edges WHERE caller_symbol_id IN ({marks}) "
                "ORDER BY callee_symbol_id", sorted(authorized)).fetchall()
            relation = "direct-callee-of-required-symbol"
            for row in definitions(connection, [item[0] for item in callees]):
                records.append(("CALLEE_CONTRACT", row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
    elif args.request_kind in {"FAILING_ASSERTION", "TEST_TARGET"}:
        test_rows = connection.execute(
            "SELECT t.name,f.repository_path,r.start_line,r.end_line,t.provider,t.test_id "
            "FROM tests t LEFT JOIN files f ON f.file_id=t.file_id "
            "LEFT JOIN source_regions r ON r.region_id=t.region_id "
            "WHERE t.name=? COLLATE NOCASE OR t.test_id=? ORDER BY t.test_id",
            (identifier, identifier),
        ).fetchall()
        for row in test_rows:
            if (row["repository_path"] and
                    inside_declared_boundary(repository, row["repository_path"], seed_paths) and
                    row["start_line"]):
                records.append((args.request_kind, row["repository_path"], row["start_line"],
                                row["end_line"], row["name"], row["provider"]))
        relation = "named-test-inside-assignment-boundary"
        if not records:
            # Some importers cannot discover framework-specific test macros or
            # selectors. Search only indexed files inside the already declared
            # assignment boundary, select the first exact identifier windows,
            # and retain the same four-region/output caps as structural rows.
            candidate_paths: set[str] = set()
            for boundary in sorted(seed_paths):
                normalized = boundary.split("#", 1)[0].rstrip("/")
                entry = safe_entry(repository, normalized)
                if entry is None:
                    continue
                if entry.is_file():
                    candidate_paths.add(normalized)
                    continue
                rows = connection.execute(
                    "SELECT repository_path FROM files WHERE repository_path LIKE ? "
                    "ORDER BY repository_path LIMIT 257", (normalized + "/%",)).fetchall()
                if len(rows) <= 256:
                    candidate_paths.update(row["repository_path"] for row in rows)
            for candidate_path in sorted(candidate_paths):
                window = exact_identifier_window(repository, candidate_path, identifier)
                if window:
                    records.append((args.request_kind, candidate_path, window[0], window[1],
                                    identifier, "declared-context-search"))
            if records:
                relation = "exact-test-identifier-inside-assignment-boundary"
    elif args.request_kind == "TEST_OWNER":
        authorized = set(requested_ids) & seed_ids
        if authorized:
            marks = ",".join("?" for _ in authorized)
            rows = connection.execute(
                f"SELECT DISTINCT t.name,f.repository_path,r.start_line,r.end_line,t.provider "
                f"FROM test_symbol_edges e JOIN tests t ON t.test_id=e.test_id "
                f"LEFT JOIN files f ON f.file_id=t.file_id "
                f"LEFT JOIN source_regions r ON r.region_id=t.region_id "
                f"WHERE e.symbol_id IN ({marks}) ORDER BY t.test_id", sorted(authorized)).fetchall()
            relation = "indexed-test-of-required-symbol"
            for row in rows:
                if row["repository_path"] and row["start_line"]:
                    records.append(("TEST_OWNER", row["repository_path"], row["start_line"],
                                    row["end_line"], row["name"], row["provider"]))
    elif args.request_kind == "BUILD_TARGET":
        rows = connection.execute(
            "SELECT DISTINCT bt.name,bt.definition_path,bt.provider,f.repository_path "
            "FROM build_targets bt LEFT JOIN build_target_files btf ON btf.target_id=bt.target_id "
            "LEFT JOIN files f ON f.file_id=btf.file_id "
            "WHERE bt.name=? COLLATE NOCASE OR bt.target_id=? ORDER BY bt.name,f.repository_path",
            (identifier, identifier),
        ).fetchall()
        for row in rows:
            if (row["repository_path"] and
                    inside_declared_boundary(repository, row["repository_path"], seed_paths) and
                    row["definition_path"]):
                records.append(("BUILD_TARGET", row["definition_path"], 1, 200,
                                row["name"], row["provider"]))
        relation = "named-build-target-owning-assignment-path"
    elif args.request_kind in {"BUILD_OWNER", "OWNER"}:
        if identifier in seed_paths | validation_paths:
            declared_entry = safe_entry(repository, identifier)
            if declared_entry is None:
                relation = "declared-build-boundary-is-absent"
            else:
                normalized_identifier = identifier.rstrip("/")
                descendant_pattern = normalized_identifier + "/%"
                rows = connection.execute(
                    "SELECT DISTINCT bt.name,bt.definition_path,bt.provider FROM build_targets bt "
                    "JOIN build_target_files btf ON btf.target_id=bt.target_id "
                    "JOIN files f ON f.file_id=btf.file_id WHERE f.repository_path=? "
                    "OR f.repository_path LIKE ? ORDER BY bt.name",
                    (normalized_identifier, descendant_pattern),
                ).fetchall()
                for row in rows:
                    if row["definition_path"]:
                        records.append((args.request_kind, row["definition_path"], 1, 200,
                                        row["name"], row["provider"]))
                relation = "build-owner-of-declared-path"
        elif args.request_kind == "OWNER":
            owner_rows = connection.execute(
                "SELECT owner_kind,owner_id,provider,authority FROM concept_owners "
                "WHERE concept_id=? ORDER BY authority,owner_kind,owner_id", (identifier,)).fetchall()
            for owner in owner_rows:
                if owner["owner_kind"] == "FILE" and inside_declared_boundary(
                        repository, owner["owner_id"], seed_paths):
                    records.append(("OWNER", owner["owner_id"], 1, 200, identifier,
                                    owner["provider"]))
                elif owner["owner_kind"] == "SYMBOL" and owner["owner_id"] in seed_ids:
                    for row in definitions(connection, [owner["owner_id"]]):
                        records.append(("OWNER", row["repository_path"], row["start_line"],
                                        row["end_line"], row["display_name"], row["provider"]))
            relation = "registered-or-derived-owner-inside-assignment-boundary"
    elif args.request_kind in {"REPRESENTATION_WRITER", "PRODUCER"}:
        normalized_identifier = identifier.split("#", 1)[0].rstrip("/")
        if normalized_identifier in seed_paths and safe_path(repository, normalized_identifier):
            window = tail_window(repository, normalized_identifier, args.max_bytes)
            if window:
                records.append((args.request_kind, normalized_identifier,
                                window[0], window[1], identifier,
                                "declared-context-tail"))
                relation = "exact-declared-path-complement"
        authorized = set(requested_ids) & seed_ids
        if authorized and not records:
            marks = ",".join("?" for _ in authorized)
            writers = connection.execute(
                f"SELECT DISTINCT source_symbol_id FROM mutation_edges WHERE "
                f"source_symbol_id IN ({marks}) OR target_symbol_id IN ({marks}) "
                "ORDER BY source_symbol_id", [*sorted(authorized), *sorted(authorized)]).fetchall()
            relation = "joern-mutation-adjacent-to-required-symbol"
            for row in definitions(connection, [item[0] for item in writers]):
                records.append((args.request_kind, row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
    elif args.request_kind == "CONSUMER":
        authorized = set(requested_ids) & seed_ids
        if authorized:
            marks = ",".join("?" for _ in authorized)
            consumers = connection.execute(
                f"SELECT DISTINCT caller_symbol_id FROM call_edges WHERE callee_symbol_id IN ({marks}) "
                "UNION SELECT DISTINCT source_symbol_id FROM mutation_edges "
                f"WHERE target_symbol_id IN ({marks}) ORDER BY 1",
                [*sorted(authorized), *sorted(authorized)]).fetchall()
            relation = "direct-call-or-mutation-consumer-of-required-symbol"
            for row in definitions(connection, [item[0] for item in consumers]):
                records.append(("CONSUMER", row["repository_path"], row["start_line"],
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
