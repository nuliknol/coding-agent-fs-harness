#!/usr/bin/env python3

"""Resolve optional plan-node symbol mutation regions from the repository index."""

from __future__ import annotations

import argparse
import csv
import re
import sqlite3
from pathlib import Path


SOURCE_CHANGING = {"LOCAL_IMPLEMENTATION", "TEST_IMPLEMENTATION", "MECHANICAL_API",
                   "FOCUSED_BUG", "DOCUMENTATION"}


def values(text: str) -> list[str]:
    return [part.strip() for part in text.split(",") if part.strip() not in {"", "-"}]


def metadata(path: Path) -> dict[str, str]:
    """Read the single-line assignment metadata used for task authority."""
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        # An assignment is validated by the publisher before it can be used
        # here. Retaining the first value also prevents a later prose line
        # from silently widening task authority.
        result.setdefault(key, value)
    return result


def inside(path: str, scopes: list[str]) -> bool:
    return any(path == scope.rstrip("/") or path.startswith(scope.rstrip("/") + "/")
               for scope in scopes)


def live_braced_definition(repository: Path | None, repository_path: str,
                            symbol: str) -> tuple[int, int] | None:
    """Relocate an indexed braced definition against the live worktree.

    Checkpointed edits can move or extend a function long after the immutable
    repository index was generated.  Mutation authority is still the exact
    indexed symbol, but its stale line numbers must not reject a patch inside
    that same live definition.  Only a token followed by a brace before any
    declaration semicolon is admitted; prototypes and unrelated later blocks
    therefore cannot broaden the region.
    """
    if repository is None:
        return None
    candidate = (repository / repository_path).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError:
        return None
    if not candidate.is_file():
        return None
    lines = candidate.read_text(encoding="utf-8", errors="replace").splitlines()
    token = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(symbol) +
                       r"(?![A-Za-z0-9_])")
    for index, line in enumerate(lines):
        match = token.search(line)
        if match is None:
            continue
        signature = "\n".join([line[match.start():], *lines[index + 1:index + 40]])
        opening = signature.find("{")
        semicolon = signature.find(";")
        if opening < 0 or (semicolon >= 0 and semicolon < opening):
            continue
        opening_line = index + signature[:opening].count("\n")
        depth = 0
        opened = False
        for end_index in range(opening_line, min(len(lines), opening_line + 1024)):
            depth += lines[end_index].count("{")
            opened = opened or "{" in lines[end_index]
            depth -= lines[end_index].count("}")
            if opened and depth <= 0:
                return index + 1, end_index + 1
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--plan")
    source.add_argument("--assignment")
    parser.add_argument("--node-id")
    parser.add_argument("--pointer", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--repository")
    parser.add_argument("--require-exact-luna", action="store_true")
    parser.add_argument("--require-complete-source", action="store_true")
    args = parser.parse_args()
    repository = Path(args.repository).resolve() if args.repository else None

    if args.assignment and not args.node_id:
        parser.error("--assignment requires --node-id")
    if args.plan and args.node_id:
        parser.error("--node-id is valid only with --assignment")

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

    if args.plan:
        with Path(args.plan).open(encoding="utf-8", newline="") as stream:
            plan_rows = list(csv.DictReader(stream, delimiter="\t"))
    else:
        assignment = metadata(Path(args.assignment))
        plan_rows = [{
            "node_id": args.node_id,
            "allowed_paths": assignment.get("Allowed-Scope", "-"),
            "required_symbols": assignment.get("Required-Symbols", "-"),
            "leaf_type": assignment.get("Leaf-Type", ""),
            "worker_route": assignment.get("Worker-Route", ""),
        }]
    output_rows: list[dict[str, str]] = []
    errors: list[str] = []
    connection = sqlite3.connect(str(database)) if database else None
    try:
        for row in plan_rows:
            node = row["node_id"].strip()
            symbols = values(row.get("required_symbols", "-"))
            scopes = values(row.get("allowed_paths", "-"))
            resolved_symbols: set[str] = set()
            node_rows: list[dict[str, str]] = []
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
                        live_window = live_braced_definition(repository, path, display)
                        authority = "INDEXED"
                        if live_window is not None and live_window != (start, end):
                            start, end = live_window
                            authority = "INDEXED_LIVE_RELOCATED"
                        node_rows.append({"node_id": node, "repository_path": path,
                                          "symbol": display, "start_line": str(start),
                                          "end_line": str(end), "symbol_kind": kind,
                                          "authority": authority})
            complete = bool(symbols) and resolved_symbols == set(symbols)
            # Mutation regions are an all-or-nothing refinement of the plan's
            # Allowed-Scope.  Publishing a partial symbol set makes the patch
            # validator deny legitimate changes for the unresolved part of the
            # same node.  When closure is incomplete, publish no indexed rows so
            # execution correctly falls back to the exact Allowed-Scope.
            if complete:
                output_rows.extend(node_rows)
            source_changing = row.get("leaf_type", "") in SOURCE_CHANGING
            if (args.require_exact_luna and source_changing and row.get("worker_route") == "LUNA"
                    and complete):
                resolved_paths = {item["repository_path"] for item in node_rows}
                broad = [scope for scope in scopes
                         if any(path.startswith(scope.rstrip("/") + "/")
                                for path in resolved_paths)]
                if broad:
                    errors.append(
                        f"node={node} resolves every required symbol to exact files "
                        f"{','.join(sorted(resolved_paths))}; replace broad allowed_paths "
                        f"{','.join(broad)} with exact source files")
            if args.require_complete_source and source_changing and not complete:
                errors.append(
                    f"node={node} cannot compile exact Mutation-Regions because one or more "
                    f"Required-Symbols are absent from the repository index")
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
