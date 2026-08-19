#!/usr/bin/env python3

"""Compile one bounded, assignment-authorized Context Closure extension."""

import argparse
import csv
import hashlib
from pathlib import Path
import re
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
    "SOURCE_WINDOW",
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


def path_qualified_symbol(repository: Path, identifier: str) -> tuple[str, str] | None:
    """Split an exact ``repository/path:symbol`` request without guessing.

    Workers use this form when the decisive definition is known to be in one
    declared file.  Treating the whole value as a symbol loses the path
    authority, while treating it as a Context-Paths entry makes a valid file
    look absent.  Accept only an existing repository file and a C-family
    identifier so a colon in arbitrary request text cannot broaden access.
    """
    if ":" not in identifier:
        return None
    relative, symbol = identifier.rsplit(":", 1)
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.$~-]*", symbol):
        return None
    source = safe_path(repository, relative)
    if source is None:
        return None
    return source.relative_to(repository).as_posix(), symbol


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
        "SELECT symbol_id,display_name,symbol_kind,provider FROM symbols "
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


def references(connection: sqlite3.Connection, symbol_ids: list[str]) -> list[sqlite3.Row]:
    """Return exact indexed declaration/reference regions for unresolved symbols."""
    if not symbol_ids:
        return []
    marks = ",".join("?" for _ in symbol_ids)
    return connection.execute(
        f"SELECT s.symbol_id,s.display_name,f.repository_path,r.start_line,r.end_line,sr.provider "
        f"FROM symbols s JOIN symbol_references sr ON sr.symbol_id=s.symbol_id "
        f"JOIN source_regions r ON r.region_id=sr.region_id "
        f"JOIN files f ON f.file_id=r.file_id WHERE s.symbol_id IN ({marks}) "
        "ORDER BY f.repository_path,r.start_line,s.symbol_id",
        symbol_ids,
    ).fetchall()


def direct_semantic_neighbors(connection: sqlite3.Connection, seed_ids: set[str],
                              requested_ids: list[str]) -> set[str]:
    """Return requested symbols joined to a seed by one authoritative graph hop."""
    if not seed_ids or not requested_ids:
        return set()
    neighbors: set[str] = set()
    for requested in requested_ids:
        for seed in seed_ids:
            row = connection.execute(
                "SELECT 1 FROM ("
                "SELECT caller_symbol_id AS a,callee_symbol_id AS b FROM call_edges "
                "UNION ALL SELECT source_symbol_id,type_symbol_id FROM type_edges "
                "UNION ALL SELECT source_symbol_id,target_symbol_id FROM mutation_edges"
                ") WHERE (a=? AND b=?) OR (a=? AND b=?) LIMIT 1",
                (seed, requested, requested, seed),
            ).fetchone()
            if row is not None:
                neighbors.add(requested)
                break
    return neighbors


def rows_inside_boundary(repository: Path, rows: list[sqlite3.Row],
                         boundaries: set[str]) -> list[sqlite3.Row]:
    return [row for row in rows if inside_declared_boundary(
        repository, row["repository_path"], boundaries)]


def indexed_lexical_function_definitions(connection: sqlite3.Connection,
                                         repository: Path, identifier: str
                                         ) -> list[tuple[str, int, int]]:
    """Recover exact C-family definitions omitted by a structural importer.

    HIP translation units can be present in the immutable indexed file inventory
    while SCIP records only declarations/references for an exact required symbol.
    Scan only that inventory, require an exact function identifier, and admit a
    region only when the function header reaches an opening body brace before a
    declaration/call semicolon. This is bounded context evidence, never mutation
    authority.
    """
    pattern = re.compile(rf"\b{re.escape(identifier)}\s*\(")
    suffixes = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".hip", ".cu"}
    recovered: list[tuple[str, int, int]] = []
    rows = connection.execute(
        "SELECT repository_path FROM files ORDER BY repository_path").fetchall()
    for row in rows:
        path = row["repository_path"]
        if Path(path).suffix.lower() not in suffixes:
            continue
        source = safe_path(repository, path)
        if source is None:
            continue
        lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
        for index, line in enumerate(lines):
            match = pattern.search(line)
            if match is None:
                continue
            header = "\n".join([line[match.start():], *lines[index + 1:index + 80]])
            body = header.find("{")
            terminator = header.find(";")
            if body < 0 or (terminator >= 0 and terminator < body):
                continue
            body_line = index + header[:body].count("\n")
            depth = 0
            opened = False
            end = min(len(lines), index + 1 + 256)
            for candidate in range(body_line, end):
                depth += lines[candidate].count("{")
                if "{" in lines[candidate]:
                    opened = True
                depth -= lines[candidate].count("}")
                if opened and depth <= 0:
                    end = candidate + 1
                    break
            recovered.append((path, max(1, index + 1 - 20), end))
            break
        if len(recovered) >= 4:
            break
    return recovered


def bounded_lexical_type_definitions(repository: Path, identifier: str,
                                     boundaries: set[str]
                                     ) -> list[tuple[str, int, int]]:
    """Recover an exact type declaration from already-authorized files.

    A tracked overlay can add a typedef after the immutable SCIP generation
    was published.  Context-closure paths are read authority, so scanning only
    those exact files preserves the same boundary as an indexed definition
    while allowing the broker to return the live declaration.  This is a
    deliberately small C-family recognizer, not repository-wide recall.
    """
    token = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(identifier)}(?![A-Za-z0-9_])")
    type_start = re.compile(
        r"^\s*(?:typedef\b|(?:struct|union|enum|class)\s+[A-Za-z_][A-Za-z0-9_]*)")
    suffixes = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".hip", ".cu"}
    recovered: list[tuple[str, int, int]] = []
    for boundary in sorted(boundaries):
        normalized = boundary.split("#", 1)[0].rstrip("/")
        entry = safe_entry(repository, normalized)
        if entry is None or not entry.is_file() or entry.suffix.lower() not in suffixes:
            continue
        lines = entry.read_text(encoding="utf-8", errors="replace").splitlines()
        for start, line in enumerate(lines):
            if not type_start.search(line):
                continue
            depth = 0
            opened = False
            end_limit = min(len(lines), start + 256)
            for end in range(start, end_limit):
                depth += lines[end].count("{")
                opened = opened or "{" in lines[end]
                depth -= lines[end].count("}")
                if ";" not in lines[end] or depth > 0:
                    continue
                declaration = "\n".join(lines[start:end + 1])
                if token.search(declaration) and (line.lstrip().startswith("typedef") or opened):
                    recovered.append((normalized, start + 1, end + 1))
                break
        if len(recovered) >= 4:
            break
    return recovered[:4]


def bounded_lexical_caller_contracts(connection: sqlite3.Connection,
                                     repository: Path, identifier: str,
                                     requested_ids: list[str],
                                     boundaries: set[str]
                                     ) -> list[tuple[str, int, int, str]]:
    """Recover callers omitted from the call graph inside declared files.

    HIP and other partially indexed translation units can retain an exact
    required-symbol definition while omitting its call edges.  In that case a
    CALLER_CONTRACT request would otherwise reject evidence already covered by
    the assignment's read boundary.  Search only exact declared C-family files,
    exclude the requested symbol's own indexed definition, and prefer an
    indexed enclosing definition for each lexical use.  A small line window is
    the bounded fallback when the enclosing function is also absent from the
    structural index.
    """
    token = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(identifier)}(?![A-Za-z0-9_])")
    suffixes = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".hip", ".cu"}
    requested_regions = {
        (row["repository_path"], row["start_line"], row["end_line"])
        for row in definitions(connection, requested_ids)
    }
    recovered: list[tuple[str, int, int, str]] = []
    seen: set[tuple[str, int, int]] = set()
    for boundary in sorted(boundaries):
        normalized = boundary.split("#", 1)[0].rstrip("/")
        entry = safe_entry(repository, normalized)
        if entry is None or not entry.is_file() or entry.suffix.lower() not in suffixes:
            continue
        lines = entry.read_text(encoding="utf-8", errors="replace").splitlines()
        for line_number, line in enumerate(lines, start=1):
            if token.search(line) is None:
                continue
            if any(path == normalized and start <= line_number <= end
                   for path, start, end in requested_regions):
                continue
            enclosing = connection.execute(
                "SELECT s.display_name,r.start_line,r.end_line FROM files f "
                "JOIN source_regions r ON r.file_id=f.file_id "
                "JOIN symbol_definitions d ON d.region_id=r.region_id "
                "JOIN symbols s ON s.symbol_id=d.symbol_id "
                "WHERE f.repository_path=? AND r.start_line<=? AND r.end_line>=? "
                "ORDER BY (r.end_line-r.start_line),r.start_line LIMIT 1",
                (normalized, line_number, line_number),
            ).fetchone()
            if enclosing is not None:
                start, end = enclosing["start_line"], enclosing["end_line"]
                symbol = enclosing["display_name"]
            else:
                start = max(1, line_number - 40)
                end = min(len(lines), line_number + 80)
                symbol = f"lexical-caller-of-{identifier}"
            key = (normalized, start, end)
            if key in seen:
                continue
            seen.add(key)
            recovered.append((normalized, start, end, symbol))
            if len(recovered) >= 4:
                return recovered
    return recovered


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

    assignment_path = Path(args.assignment)
    assignment_text = assignment_path.read_text(encoding="utf-8", errors="replace")
    compiled_context_path = Path(args.closure).parent / "context.md"
    compiled_context_text = (
        compiled_context_path.read_text(encoding="utf-8", errors="replace")
        if compiled_context_path.is_file() else ""
    )
    authority_text = assignment_text + "\n" + compiled_context_text
    assignment = metadata(assignment_path)
    closure = closure_rows(Path(args.closure))
    repository = Path(args.repository).resolve()
    raw_identifier = args.identifier.strip()
    if not raw_identifier or len(raw_identifier) > 256 or "\n" in raw_identifier:
        print("status=REJECTED\nreason=invalid-identifier")
        return 2
    qualified_symbol = (path_qualified_symbol(repository, raw_identifier)
                        if args.request_kind in {
                            "SYMBOL_DEFINITION", "REPRESENTATION_WRITER", "PRODUCER"
                        } else None)
    qualified_path = qualified_symbol[0] if qualified_symbol else ""
    identifier = qualified_symbol[1] if qualified_symbol else raw_identifier

    required_symbols = split_list(assignment.get("Required-Symbols", ""))
    declared_paths = split_list(assignment.get("Context-Paths", "")) | split_list(
        assignment.get("Allowed-Scope", ""))
    closure_symbols = {row.get("symbol", "") for row in closure} - {"", "-"}
    closure_paths = {row.get("source_path", "") for row in closure} - {"", "-"}
    seed_symbols = required_symbols | closure_symbols
    seed_paths = declared_paths | closure_paths
    validation_paths = declared_validation_paths(
        repository, assignment.get("Focused-Validation", ""))
    validation_command = assignment.get("Focused-Validation", "")
    read_boundaries = seed_paths | validation_paths

    if qualified_path and not inside_declared_boundary(
            repository, qualified_path, read_boundaries):
        print("status=REJECTED\n"
              "reason=no-authorized-evidence\n"
              "relation=path-qualified-symbol-outside-assignment-boundary")
        return 3

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
        if not requested_ids:
            relation = "missing-exact-symbol"
        authorized = set(requested_ids) & seed_ids
        if not authorized and seed_ids and requested_ids:
            marks = ",".join("?" for _ in seed_ids)
            request_marks = ",".join("?" for _ in requested_ids)
            rows = connection.execute(
                f"SELECT type_symbol_id FROM type_edges WHERE "
                f"source_symbol_id IN ({marks}) AND type_symbol_id IN ({request_marks})",
                [*sorted(seed_ids), *requested_ids],
            ).fetchall()
            authorized = {row[0] for row in rows}
            if authorized:
                relation = "direct-type-symbol-definition"
        if not authorized:
            authorized = direct_semantic_neighbors(connection, seed_ids, requested_ids)
            if authorized:
                relation = "direct-semantic-neighbor-definition"
        if authorized:
            relation = relation or "exact-required-symbol"
            for row in definitions(connection, sorted(authorized)):
                if qualified_path and row["repository_path"] != qualified_path:
                    continue
                records.append(("SYMBOL_DEFINITION", row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
            if not records and relation == "exact-required-symbol":
                for path, start, end in indexed_lexical_function_definitions(
                        connection, repository, identifier):
                    if qualified_path and path != qualified_path:
                        continue
                    records.append(("SYMBOL_DEFINITION", path, start, end, identifier,
                                    "indexed-file-lexical-definition-fallback"))
                if records:
                    relation = "exact-required-symbol-lexical-definition-fallback"
        elif requested_ids:
            bounded_definitions = rows_inside_boundary(
                repository, definitions(connection, requested_ids), read_boundaries)
            if qualified_path:
                bounded_definitions = [row for row in bounded_definitions
                                       if row["repository_path"] == qualified_path]
            if bounded_definitions:
                relation = "exact-symbol-inside-declared-read-boundary"
                for row in bounded_definitions:
                    records.append(("SYMBOL_DEFINITION", row["repository_path"],
                                    row["start_line"], row["end_line"],
                                    row["display_name"], row["provider"]))
            else:
                # HIP and other partially indexed translation units can expose
                # an exact symbol record without a structural definition row.
                # Recover only an exact lexical function body that is already
                # inside declared read authority; never use this fallback to
                # broaden the assignment boundary.
                for path, start, end in indexed_lexical_function_definitions(
                        connection, repository, identifier):
                    if qualified_path and path != qualified_path:
                        continue
                    if not inside_declared_boundary(repository, path, read_boundaries):
                        continue
                    records.append(("SYMBOL_DEFINITION", path, start, end, identifier,
                                    "indexed-file-lexical-definition-fallback"))
                relation = (
                    "exact-symbol-inside-declared-read-boundary-lexical-definition-fallback"
                    if records else "symbol-outside-assignment-boundary"
                )
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
            if not records:
                requested_type_ids = [row["symbol_id"] for row in requested
                                      if (row["symbol_kind"] or "").lower() in {
                                          "type", "struct", "class", "union", "enum",
                                          "typedef", "interface", "protocol"}]
                bounded_definitions = rows_inside_boundary(
                    repository, definitions(connection, requested_type_ids), read_boundaries)
                if bounded_definitions:
                    relation = "exact-type-inside-declared-read-boundary"
                    for row in bounded_definitions:
                        records.append(("TYPE_DEFINITION", row["repository_path"],
                                        row["start_line"], row["end_line"],
                                        row["display_name"], row["provider"]))
            if not records and requested_type_ids:
                # Incompletely indexed HIP translation units may omit type
                # edges even though an exact required helper lexically uses the
                # type.  Prove that one-hop relation only inside exact declared
                # files, then return the indexed type definition as read-only
                # evidence.  Directory-wide lexical searches remain forbidden.
                token = re.compile(rf"\b{re.escape(identifier)}\b")
                referenced = False
                for boundary in sorted(read_boundaries):
                    entry = safe_entry(repository, boundary.split("#", 1)[0].rstrip("/"))
                    if entry is None or not entry.is_file():
                        continue
                    if token.search(entry.read_text(encoding="utf-8", errors="replace")):
                        referenced = True
                        break
                if referenced:
                    relation = "exact-type-referenced-inside-declared-read-boundary"
                    for row in definitions(connection, requested_type_ids):
                        records.append(("TYPE_DEFINITION", row["repository_path"],
                                        row["start_line"], row["end_line"],
                                        row["display_name"], row["provider"]))
        if not records:
            for path, start, end in bounded_lexical_type_definitions(
                    repository, identifier, read_boundaries):
                records.append(("TYPE_DEFINITION", path, start, end, identifier,
                                "declared-read-boundary-lexical-type-fallback"))
            if records:
                relation = "exact-type-inside-declared-read-boundary-lexical-definition-fallback"
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
            if not records:
                for path, start, end, symbol in bounded_lexical_caller_contracts(
                        connection, repository, identifier, sorted(authorized),
                        read_boundaries):
                    records.append(("CALLER_CONTRACT", path, start, end, symbol,
                                    "declared-read-boundary-lexical-caller-fallback"))
                if records:
                    relation = "required-symbol-lexical-caller-inside-declared-read-boundary"
        if not records and identifier in required_symbols:
            # Some HIP index generations omit the required function from the
            # symbol table altogether.  The exact required-symbol body is still
            # an assignment-authorized caller contract when it lexically exists
            # inside a declared read file.  This is especially important for a
            # dispatch function whose body contains the downstream launch the
            # worker is trying to inspect.
            for path, start, end in indexed_lexical_function_definitions(
                    connection, repository, identifier):
                if not inside_declared_boundary(repository, path, read_boundaries):
                    continue
                records.append(("CALLER_CONTRACT", path, start, end, identifier,
                                "declared-read-boundary-lexical-required-symbol-fallback"))
            if records:
                relation = "exact-required-symbol-lexical-contract-inside-declared-read-boundary"
        if (not records and
                re.search(rf"(?<![A-Za-z0-9_]){re.escape(identifier)}(?![A-Za-z0-9_])",
                          authority_text)):
            # A worker can name the assignment's public interface while asking
            # for the backend dispatch contract that calls the exact required
            # symbol.  Resolve that relationship through the required symbol,
            # never through a name-prefix or repository-wide guess, and keep
            # the returned caller inside the declared read boundary.
            for required in sorted(required_symbols):
                required_rows = exact_symbols(connection, required)
                required_ids = [row["symbol_id"] for row in required_rows]
                if required_ids:
                    marks = ",".join("?" for _ in required_ids)
                    callers = connection.execute(
                        f"SELECT DISTINCT caller_symbol_id FROM call_edges "
                        f"WHERE callee_symbol_id IN ({marks}) ORDER BY caller_symbol_id",
                        required_ids,
                    ).fetchall()
                    for row in rows_inside_boundary(
                            repository,
                            definitions(connection, [item[0] for item in callers]),
                            read_boundaries):
                        records.append(("CALLER_CONTRACT", row["repository_path"],
                                        row["start_line"], row["end_line"],
                                        row["display_name"], row["provider"]))
                if not records:
                    for path, start, end, symbol in bounded_lexical_caller_contracts(
                            connection, repository, required, required_ids,
                            read_boundaries):
                        records.append(("CALLER_CONTRACT", path, start, end, symbol,
                                        "declared-read-boundary-interface-required-caller-fallback"))
                if records:
                    break
            if records:
                relation = "compiled-authority-interface-to-required-symbol-caller"
    elif args.request_kind == "CALLEE_CONTRACT":
        # Workers name the missing callee whose contract they need, while the
        # assignment normally seeds the caller.  Admit that exact callee when
        # the index proves a direct seed->requested edge.  Keep the historical
        # caller-name form as a compatibility fallback.
        adjacent: set[str] = set()
        if requested_ids and seed_ids:
            seed_marks = ",".join("?" for _ in seed_ids)
            request_marks = ",".join("?" for _ in requested_ids)
            rows = connection.execute(
                f"SELECT DISTINCT callee_symbol_id FROM call_edges WHERE "
                f"caller_symbol_id IN ({seed_marks}) AND callee_symbol_id IN ({request_marks}) "
                "ORDER BY callee_symbol_id", [*sorted(seed_ids), *requested_ids]).fetchall()
            adjacent = {row[0] for row in rows}
        authorized = set(requested_ids) & seed_ids
        if adjacent:
            relation = "requested-direct-callee-of-required-symbol"
            for row in definitions(connection, sorted(adjacent)):
                records.append(("CALLEE_CONTRACT", row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
        elif authorized:
            marks = ",".join("?" for _ in authorized)
            callees = connection.execute(
                f"SELECT DISTINCT callee_symbol_id FROM call_edges WHERE caller_symbol_id IN ({marks}) "
                "ORDER BY callee_symbol_id", sorted(authorized)).fetchall()
            relation = "direct-callee-of-required-symbol"
            for row in definitions(connection, [item[0] for item in callees]):
                records.append(("CALLEE_CONTRACT", row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
        # Some language importers (notably HIP translation units without a
        # compile-command entry) emit the public declaration as an exact SCIP
        # reference but cannot emit a definition or call edge.  When the callee
        # itself is already an explicit required symbol, that indexed region is
        # still a bounded contract.  Do not perform a lexical repository scan.
        if not records and authorized:
            relation = "exact-required-callee-reference-contract"
            for row in references(connection, sorted(authorized)):
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
            validation_names_identifier = identifier in validation_command
            if (row["repository_path"] and row["start_line"] and
                    (inside_declared_boundary(repository, row["repository_path"], seed_paths) or
                     validation_names_identifier)):
                records.append((args.request_kind, row["repository_path"], row["start_line"],
                                row["end_line"], row["name"], row["provider"]))
        relation = ("named-test-in-focused-validation" if records and identifier in validation_command
                    else "named-test-inside-assignment-boundary")
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
            if (row["repository_path"] and row["definition_path"] and
                    (inside_declared_boundary(repository, row["repository_path"], seed_paths) or
                     identifier in validation_command)):
                records.append(("BUILD_TARGET", row["definition_path"], 1, 200,
                                row["name"], row["provider"]))
        relation = ("named-build-target-in-focused-validation" if records and
                    identifier in validation_command else
                    "named-build-target-owning-assignment-path")
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
        authorized = ((set(requested_ids) & seed_ids) |
                      direct_semantic_neighbors(connection, seed_ids, requested_ids))
        if authorized and not records:
            marks = ",".join("?" for _ in authorized)
            writers = connection.execute(
                f"SELECT DISTINCT source_symbol_id FROM mutation_edges WHERE "
                f"source_symbol_id IN ({marks}) OR target_symbol_id IN ({marks}) "
                "ORDER BY source_symbol_id", [*sorted(authorized), *sorted(authorized)]).fetchall()
            relation = "joern-mutation-adjacent-to-required-symbol"
            writer_ids = [item[0] for item in writers]
            for row in definitions(connection, writer_ids):
                if qualified_path and row["repository_path"] != qualified_path:
                    continue
                records.append((args.request_kind, row["repository_path"], row["start_line"],
                                row["end_line"], row["display_name"], row["provider"]))
            # Structural indexes can carry the mutation edge while omitting the
            # writer definition (notably generated/HIP translation units). The
            # immutable indexed-file inventory still bounds an exact lexical
            # definition lookup, so return the requested writer seam instead of
            # reporting the contradictory no-authorized-evidence result.
            if not records and writer_ids:
                for writer in connection.execute(
                        f"SELECT symbol_id,display_name FROM symbols WHERE symbol_id IN ({marks}) "
                        "ORDER BY symbol_id", sorted(set(writer_ids))).fetchall():
                    for path, start, end in indexed_lexical_function_definitions(
                            connection, repository, writer["display_name"]):
                        if qualified_path and path != qualified_path:
                            continue
                        records.append((args.request_kind, path, start, end,
                                        writer["display_name"],
                                        "indexed-file-lexical-writer-fallback"))
                if records:
                    relation = "joern-mutation-adjacent-lexical-writer-fallback"
            if not records and qualified_path:
                window = exact_identifier_window(repository, qualified_path, identifier)
                if window:
                    records.append((args.request_kind, qualified_path, window[0], window[1],
                                    identifier, "path-qualified-writer"))
                    relation = "path-qualified-writer-inside-assignment-boundary"
    elif args.request_kind == "CONSUMER":
        authorized = ((set(requested_ids) & seed_ids) |
                      direct_semantic_neighbors(connection, seed_ids, requested_ids))
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
    elif args.request_kind == "SOURCE_WINDOW":
        normalized_identifier = identifier.split("#", 1)[0].rstrip("/")
        if normalized_identifier in read_boundaries:
            window = tail_window(repository, normalized_identifier, args.max_bytes)
            if window:
                records.append(("SOURCE_WINDOW", normalized_identifier, window[0], window[1],
                                normalized_identifier, "declared-read-window"))
                relation = "exact-declared-read-path"
        else:
            relation = "path-outside-declared-read-boundary"
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
        f"Context-Request-Identifier: {raw_identifier}",
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
