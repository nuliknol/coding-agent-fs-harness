#!/usr/bin/env python3

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import sys


def metadata(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if ": " not in line:
                continue
            key, value = line.rstrip("\n").split(": ", 1)
            result.setdefault(key, value)
    return result


def split_list(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip() not in ("", "-", "NONE")]


def path_is_allowed(path: str, scopes: list[str]) -> bool:
    return any(path == scope.rstrip("/") or path.startswith(scope.rstrip("/") + "/")
               for scope in scopes)


def dependency_classes(values: dict[str, str]) -> set[str]:
    """Return the evidence classes that this leaf actually requires.

    Older DAGs predate Required-Dependency-Classes.  Derive a conservative
    class set from their typed leaf boundary instead of treating every leaf as
    behavioral implementation work.  An explicit declaration remains
    authoritative.
    """
    declared = set(split_list(values.get("Required-Dependency-Classes", "")))
    if declared:
        return declared
    leaf_type = values.get("Leaf-Type", "").strip()
    if leaf_type == "DOCUMENTATION":
        return {"D", "I", "V"}
    if leaf_type == "VERIFICATION_ONLY":
        return {"D", "B", "V"}
    if leaf_type == "TEST_IMPLEMENTATION":
        return {"D", "B", "V"}
    if leaf_type in {"CONTRACT_DESIGN", "CROSS_COMPONENT_ARCHITECTURE"}:
        return {"D", "T", "I", "C", "V"}
    if leaf_type in {"CONCURRENCY_PROTOCOL", "INTEGRATION"}:
        return {"D", "T", "I", "B", "C", "F", "V"}
    # Legacy/untyped assignments retain the original behavior.
    return {"D", "T", "I", "B", "C", "V"}


def tsv_records(path: str | None) -> tuple[list[str], dict[str, dict[str, str]]]:
    if not path:
        return [], {}
    with Path(path).open(encoding="utf-8", errors="replace", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        fields = reader.fieldnames or []
        if not fields:
            raise ValueError(f"authority TSV has no header: {path}")
        identifier = fields[0]
        records: dict[str, dict[str, str]] = {}
        for row in reader:
            key = (row.get(identifier) or "").strip()
            if not key:
                continue
            if key in records:
                raise ValueError(f"duplicate authority identifier {key}: {path}")
            records[key] = {field: row.get(field, "") for field in fields}
        return fields, records


def stable_id(*parts: str) -> str:
    digest = hashlib.sha256()
    for part in parts:
        digest.update(part.encode("utf-8", errors="replace"))
        digest.update(b"\0")
    return digest.hexdigest()


def safe_source_path(repository: Path, relative: str) -> Path | None:
    candidate = (repository / relative).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError:
        return None
    return candidate if candidate.is_file() else None


def safe_repository_path(repository: Path, relative: str) -> Path | None:
    candidate = (repository / relative).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError:
        return None
    return candidate if candidate.exists() else None


def excerpt(path: Path, start: int, end: int, maximum: int = 16384) -> str:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    except OSError:
        return ""
    start_index = max(start - 1, 0)
    end_index = min(max(end, start), len(lines))
    text = "".join(lines[start_index:end_index])
    encoded = text.encode("utf-8")
    if len(encoded) > maximum:
        text = encoded[:maximum].decode("utf-8", errors="ignore") + "\n[excerpt truncated]\n"
    return text


def item_excerpt(path: Path, item: dict) -> str:
    """Render one evidence record within its kind-specific read budget."""
    maximum = {
        "FOCUSED_TEST": 4096,
        "TEST_REFERENCE": 2048,
        "INTERFACE_REFERENCE": 4096,
        "CONTROL_FLOW": 2048,
        "DATA_FLOW": 2048,
        "MUTATION": 2048,
    }.get(item["kind"], 16384)
    return excerpt(path, item["start"], item["end"], maximum)


def worktree_overlay(path: str | None) -> dict[str, dict[str, str]]:
    if not path:
        return {}
    overlay_path = Path(path)
    if not overlay_path.is_file():
        raise ValueError(f"worktree overlay does not exist: {path}")
    with overlay_path.open(encoding="utf-8", errors="replace", newline="") as stream:
        records: dict[str, dict[str, str]] = {}
        for row in csv.DictReader(stream, delimiter="\t"):
            repository_path = (row.get("repository_path") or "").strip()
            if repository_path:
                records[repository_path] = dict(row)
        return records


def live_symbol_window(path: Path, symbol: str, maximum_lines: int = 160) -> tuple[int, int] | None:
    """Return a bounded live-worktree window for an exact symbol token.

    This is an overlay relocation fallback, not a semantic parser. SCIP remains
    the baseline authority; the bounded live window prevents stale line ranges
    from selecting unrelated source after a checkpointed edit.
    """
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None
    token = symbol.rsplit("/", 1)[-1].rsplit("#", 1)[-1]
    token = token.split("(", 1)[0].strip()
    if not token or token == "-":
        return None
    pattern = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(token) + r"(?![A-Za-z0-9_])")
    matches = [index for index, line in enumerate(lines) if pattern.search(line)]
    if not matches:
        return None
    center = matches[0]
    start = max(0, center - 12)
    end = min(len(lines), start + maximum_lines)
    # Prefer a complete nearby brace-delimited definition while keeping the
    # window bounded. This works for C-family sources and harmlessly falls back
    # to the fixed window for other languages.
    depth = 0
    opened = False
    for index in range(center, end):
        depth += lines[index].count("{")
        if lines[index].count("{"):
            opened = True
        depth -= lines[index].count("}")
        if opened and depth <= 0:
            end = index + 1
            break
    return start + 1, max(end, start + 1)


def add_item(items: dict[tuple, dict], *, kind: str, path: str, start: int, end: int,
             symbol: str, why: str, required: bool, provider: str) -> None:
    key = (kind, path, start, end, symbol)
    candidate = {
        "item_id": stable_id(*map(str, key)),
        "kind": kind,
        "path": path,
        "start": start,
        "end": end,
        "symbol": symbol,
        "why": why,
        "required": "REQUIRED" if required else "SUPPORTING",
        "provider": provider,
    }
    previous = items.get(key)
    if previous is None or (candidate["required"] == "REQUIRED" and previous["required"] != "REQUIRED"):
        items[key] = candidate


def exact_symbol_rows(connection: sqlite3.Connection, requested: str) -> list[sqlite3.Row]:
    return connection.execute(
        """
        SELECT DISTINCT s.symbol_id, s.display_name, s.symbol_kind,
               f.repository_path, r.start_line, r.end_line, d.definition_kind
        FROM symbols s
        LEFT JOIN symbol_definitions d ON d.symbol_id=s.symbol_id
        LEFT JOIN source_regions r ON r.region_id=d.region_id
        LEFT JOIN files f ON f.file_id=r.file_id
        WHERE s.symbol_id=? OR s.display_name=? COLLATE NOCASE
        ORDER BY CASE WHEN d.definition_kind='definition' THEN 0 ELSE 1 END,
                 f.repository_path, r.start_line
        """, (requested, requested)).fetchall()


def build_closure(args: argparse.Namespace) -> str:
    repository = Path(args.repository).resolve()
    assignment = Path(args.assignment).resolve()
    output = Path(args.output)
    values = metadata(assignment)
    task_id = values.get("Task-ID", assignment.stem)
    plan_node = values.get("Plan-Node", values.get("Project-Plan-Item-ID", "-"))
    assigned_symbols = split_list(values.get("Required-Symbols", ""))
    allowed_scopes = split_list(values.get("Allowed-Scope", ""))
    symbol_seeds = {symbol: "assignment required symbol" for symbol in assigned_symbols}
    path_seeds = {path: "manager-declared context path"
                  for path in split_list(values.get("Context-Paths", values.get("Allowed-Scope", "")))}
    overlay = worktree_overlay(getattr(args, "overlay_file", None))
    for overlay_path, overlay_record in overlay.items():
        if overlay_record.get("status") == "DELETED":
            continue
        source = safe_source_path(repository, overlay_path)
        if source is None:
            raise ValueError(f"worktree overlay source is unavailable: {overlay_path}")
        current_digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if current_digest != overlay_record.get("content_sha256"):
            raise ValueError(f"worktree overlay is stale: {overlay_path}")

    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    items: dict[tuple, dict] = {}
    edges: list[tuple[str, str, str, str]] = []
    unresolved: list[tuple[str, str, str]] = []
    graph_cuts: list[tuple[str, str, str]] = []
    selected_symbol_ids: set[str] = set()
    seed_symbol_ids: set[str] = set()
    authority_records: list[tuple[str, str, str, dict[str, str]]] = []
    ownership_boundaries: set[tuple[str, str, str, str]] = set()
    selected_tests: set[str] = set()
    bounded_test_candidates_omitted = 0
    expanded_seed_ids: set[str] = set()
    selected_call_edges: set[tuple[str, str, str, str]] = set()
    remaining_calls = args.max_direct_relationships
    requested_classes = dependency_classes(values)
    invalid_classes = requested_classes.difference({"D", "T", "I", "B", "C", "F", "V"})
    if invalid_classes:
        raise ValueError(
            "unknown Required-Dependency-Classes: " + ",".join(sorted(invalid_classes)))

    configuration_rows = connection.execute(
        "SELECT configuration_id FROM build_configurations WHERE generation_id=? ORDER BY configuration_id",
        (args.generation,)).fetchall()
    requested_configuration = values.get("Build-Configuration", "").strip()
    if requested_configuration and requested_configuration not in ("-", "NONE"):
        if requested_configuration not in {row[0] for row in configuration_rows}:
            unresolved.append(("BUILD_CONFIGURATION", requested_configuration,
                               "requested configuration is absent from the index generation"))
    elif len(configuration_rows) > 1:
        unresolved.append(("BUILD_CONFIGURATION", "-",
                           "multiple indexed configurations require an explicit Build-Configuration"))

    if args.node_bindings_file and plan_node not in ("", "-"):
        _, binding_records = tsv_records(args.node_bindings_file)
        if plan_node not in binding_records:
            unresolved.append(("ARCHITECTURE_BINDING", plan_node,
                               f"plan node absent from {Path(args.node_bindings_file).name}"))

    authority_specs = (
        ("SPECIFICATION_OBLIGATION", "Specification-Obligations", args.obligations_file),
        ("ARCHITECTURE_INVARIANT", "Affected-Invariants", args.invariants_file),
        ("ARCHITECTURE_DECISION", "Consumed-Decisions", args.decisions_file),
        ("ARCHITECTURE_DECISION", "Produced-Decisions", args.decisions_file),
        ("ARCHITECTURE_DECISION", "Architecture-Decisions", args.decisions_file),
        ("EDGE_CONTRACT", "Edge-Contracts", args.edges_file),
        ("HEALTH_GATE", "Health-Gates", args.health_gates_file),
    )
    loaded_authority: set[tuple[str, str]] = set()
    selected_obligations: set[str] = set()
    for authority_kind, metadata_field, authority_file in authority_specs:
        identifiers = split_list(values.get(metadata_field, ""))
        if not identifiers:
            continue
        if not authority_file:
            # The corresponding authority system is disabled for this project.
            # Metadata with the same label may be descriptive in legacy tasks;
            # it becomes enforceable only when its registry is supplied.
            continue
        fields, records = tsv_records(authority_file)
        for identifier in identifiers:
            record = records.get(identifier)
            if record is None:
                unresolved.append((authority_kind, identifier,
                                   f"identifier absent from {Path(authority_file).name}"))
                continue
            key = (authority_kind, identifier)
            if key in loaded_authority:
                continue
            loaded_authority.add(key)
            authority_records.append((authority_kind, identifier, authority_file, record))
            if authority_kind == "SPECIFICATION_OBLIGATION":
                selected_obligations.add(identifier)
            elif authority_kind == "ARCHITECTURE_INVARIANT":
                for path in split_list(record.get("scope", "")):
                    # Architecture scope is commonly a semantic phrase (for
                    # example, "Query plan wire ABI"), not a filesystem path.
                    # It remains present in authority.tsv/context.md, but only
                    # an actual repository path is a structural path seed.
                    if safe_repository_path(repository, path) is not None:
                        path_seeds.setdefault(path, f"scope of invariant {identifier}")
            elif authority_kind == "ARCHITECTURE_DECISION":
                # The complete decision remains allocated below as normative
                # authority.  Its complete interface inventory must not widen
                # a leaf that already declares exact Required-Symbols.
                if "I" in requested_classes and not assigned_symbols:
                    for symbol in split_list(record.get("affected_interfaces", "")):
                        symbol_seeds.setdefault(symbol, f"interface governed by decision {identifier}")
                evidence = record.get("evidence", "")
                if evidence and evidence not in ("-", "NONE"):
                    evidence = evidence.removeprefix("operator-worktree:")
                    # The accepted decision record is the compiled authority.
                    # Its provenance path remains in authority.tsv, but dumping
                    # that complete design document would duplicate the record
                    # and consume a Luna capsule with non-executable prose.
            elif authority_kind == "EDGE_CONTRACT":
                producer = record.get("producer_node", "-") or "-"
                consumer = record.get("consumer_node", "-") or "-"
                ownership = record.get("ownership_model", "-") or "-"
                ownership_boundaries.add((identifier, producer, consumer, ownership))
                if "I" in requested_classes and not assigned_symbols:
                    for symbol in split_list(record.get("public_symbols", "")):
                        symbol_seeds.setdefault(symbol, f"public symbol of edge contract {identifier}")
                for artifact in split_list(record.get("contract_artifact", "")):
                    if not artifact.startswith("decision:"):
                        path_seeds.setdefault(artifact, f"artifact of edge contract {identifier}")

    if selected_obligations and args.relations_file:
        _, relations = tsv_records(args.relations_file)
        for identifier, record in relations.items():
            if record.get("subject", "") in selected_obligations or record.get("object", "") in selected_obligations:
                authority_records.append(("SPECIFICATION_RELATION", identifier,
                                          args.relations_file, record))

    for requested, seed_reason in sorted(symbol_seeds.items()):
        rows = exact_symbol_rows(connection, requested)
        if not rows:
            overlay_match = False
            for overlay_path, overlay_record in sorted(overlay.items()):
                if overlay_record.get("status") == "DELETED":
                    continue
                if path_seeds and not any(
                        overlay_path == seed.rstrip("/") or
                        overlay_path.startswith(seed.rstrip("/") + "/")
                        for seed in path_seeds):
                    continue
                source = safe_source_path(repository, overlay_path)
                window = live_symbol_window(source, requested) if source else None
                if not window:
                    continue
                add_item(items, kind="OVERLAY_DEFINITION", path=overlay_path,
                         start=window[0], end=window[1], symbol=requested,
                         why=f"{seed_reason}: live worktree definition for {requested}",
                         required=True, provider="worktree-overlay")
                overlay_match = True
            if not overlay_match:
                unresolved.append(("REQUIRED_SYMBOL", requested, "no exact SCIP or worktree-overlay definition"))
            continue
        definitions = [row for row in rows if row["repository_path"] is not None]
        definition_boundaries = sorted(set(path_seeds) | set(allowed_scopes))
        scoped_definitions = [
            row for row in definitions
            if path_is_allowed(row["repository_path"], definition_boundaries)
        ]
        scoped_references: list[sqlite3.Row] = []
        if scoped_definitions:
            scoped_symbol_ids = {row["symbol_id"] for row in scoped_definitions}
            definitions = scoped_definitions
            rows = [row for row in rows if row["symbol_id"] in scoped_symbol_ids]
        elif definition_boundaries:
            candidate_symbol_ids = sorted({row["symbol_id"] for row in rows})
            if candidate_symbol_ids:
                marks = ",".join("?" for _ in candidate_symbol_ids)
                reference_rows = connection.execute(
                    f"""
                    SELECT DISTINCT x.symbol_id,s.display_name,f.repository_path,
                                    r.start_line,r.end_line,x.reference_kind,x.provider
                    FROM symbol_references x
                    JOIN symbols s ON s.symbol_id=x.symbol_id
                    JOIN source_regions r ON r.region_id=x.region_id
                    JOIN files f ON f.file_id=r.file_id
                    WHERE x.symbol_id IN ({marks})
                    ORDER BY f.repository_path,r.start_line,x.symbol_id
                    """, candidate_symbol_ids).fetchall()
                scoped_references = [
                    row for row in reference_rows
                    if path_is_allowed(row["repository_path"], definition_boundaries)
                ]
            if scoped_references:
                scoped_symbol_ids = {row["symbol_id"] for row in scoped_references}
                rows = [row for row in rows if row["symbol_id"] in scoped_symbol_ids]
                definitions = []
                for reference in scoped_references:
                    add_item(items, kind="SCOPED_DECLARATION",
                             path=reference["repository_path"],
                             start=reference["start_line"], end=reference["end_line"],
                             symbol=reference["display_name"],
                             why=f"{seed_reason}: exact declaration for {requested}",
                             required=True, provider=reference["provider"])
        if "D" in requested_classes and not definitions and not scoped_references:
            unresolved.append(("REQUIRED_DEFINITION", requested, "symbol exists but has no indexed definition"))
        if "D" in requested_classes:
            for row in definitions:
                selected_symbol_ids.add(row["symbol_id"])
                add_item(items, kind="DEFINITION", path=row["repository_path"],
                         start=row["start_line"], end=row["end_line"],
                         symbol=row["display_name"], why=f"{seed_reason}: {requested}",
                         required=True, provider="scip-clang")

        for row in rows:
            selected_symbol_ids.add(row["symbol_id"])
            seed_symbol_ids.add(row["symbol_id"])
            if row["symbol_id"] in expanded_seed_ids:
                continue
            expanded_seed_ids.add(row["symbol_id"])
            if requested_classes.intersection({"I", "B"}):
                reference_rows = connection.execute(
                    """
                    SELECT DISTINCT f.repository_path, r.start_line, r.end_line, x.reference_kind
                    FROM symbol_references x
                    JOIN source_regions r ON r.region_id=x.region_id
                    JOIN files f ON f.file_id=r.file_id
                    WHERE x.symbol_id=? AND
                          (f.repository_path LIKE '%/include/%' OR
                           f.repository_path LIKE 'include/%' OR
                           f.repository_path LIKE '%/tests/%' OR
                           f.repository_path LIKE 'tests/%')
                    ORDER BY f.repository_path, r.start_line LIMIT 12
                    """, (row["symbol_id"],)).fetchall()
                for reference in reference_rows:
                    is_test = ("/tests/" in f"/{reference['repository_path']}" or
                               reference["repository_path"].startswith("tests/"))
                    if (is_test and "B" not in requested_classes) or (
                            not is_test and "I" not in requested_classes):
                        continue
                    add_item(items, kind="TEST_REFERENCE" if is_test else "INTERFACE_REFERENCE",
                             path=reference["repository_path"], start=reference["start_line"],
                             end=reference["end_line"], symbol=row["display_name"],
                             why=f"indexed {'test' if is_test else 'interface'} reference for {requested}",
                             required=False, provider="scip-clang")

            if "B" in requested_classes:
                test_rows = connection.execute(
                    """
                    SELECT DISTINCT t.name, f.repository_path, r.start_line, r.end_line,
                                    x.edge_kind, t.selector, t.build_target
                    FROM test_symbol_edges x
                    JOIN tests t ON t.test_id=x.test_id
                    JOIN source_regions r ON r.region_id=t.region_id
                    JOIN files f ON f.file_id=t.file_id
                    WHERE x.symbol_id=?
                    ORDER BY f.repository_path, r.start_line LIMIT 8
                    """, (row["symbol_id"],)).fetchall()
                for test in test_rows:
                    if (test["name"] not in selected_tests and
                            len(selected_tests) >= args.max_tests):
                        bounded_test_candidates_omitted += 1
                        continue
                    selected_tests.add(test["name"])
                    add_item(items, kind="FOCUSED_TEST", path=test["repository_path"],
                             start=test["start_line"], end=test["end_line"],
                             symbol=test["name"], why=f"indexed test covering {requested}",
                             required=False, provider="scip-clang")

            relation_rows = connection.execute(
                """
                SELECT e.edge_kind, t.symbol_id, t.display_name,
                       f.repository_path, r.start_line, r.end_line
                FROM symbol_edges e
                JOIN symbols t ON t.symbol_id=e.target_symbol_id
                LEFT JOIN symbol_definitions d ON d.symbol_id=t.symbol_id
                LEFT JOIN source_regions r ON r.region_id=d.region_id
                LEFT JOIN files f ON f.file_id=r.file_id
                WHERE e.source_symbol_id=? AND e.edge_kind != 'REFERENCES'
                ORDER BY e.edge_kind, f.repository_path, r.start_line LIMIT 17
                """, (row["symbol_id"],)).fetchall() if "T" in requested_classes else []
            if len(relation_rows) > 16:
                graph_cuts.append((row["symbol_id"], "direct-edge-fanout",
                                   "more than 16 direct structural dependencies"))
            for relation in relation_rows[:16]:
                selected_symbol_ids.add(relation["symbol_id"])
                edges.append((row["symbol_id"], relation["symbol_id"], relation["edge_kind"], "scip-clang"))
                if relation["repository_path"] is not None:
                    add_item(items, kind=relation["edge_kind"], path=relation["repository_path"],
                             start=relation["start_line"], end=relation["end_line"],
                             symbol=relation["display_name"],
                             why=f"{relation['edge_kind']} dependency of {requested}",
                             required=True, provider="scip-clang")

            call_rows = []
            if "C" in requested_classes and remaining_calls > 0:
                call_rows = connection.execute(
                """SELECT 'CALLEE' direction,t.symbol_id,t.display_name,f.repository_path,r.start_line,r.end_line,c.provider
                   FROM call_edges c JOIN symbols t ON t.symbol_id=c.callee_symbol_id
                   LEFT JOIN symbol_definitions d ON d.symbol_id=t.symbol_id
                   LEFT JOIN source_regions r ON r.region_id=d.region_id LEFT JOIN files f ON f.file_id=r.file_id
                   WHERE c.caller_symbol_id=?
                   UNION ALL
                   SELECT 'CALLER',s.symbol_id,s.display_name,f.repository_path,r.start_line,r.end_line,c.provider
                   FROM call_edges c JOIN symbols s ON s.symbol_id=c.caller_symbol_id
                   LEFT JOIN symbol_definitions d ON d.symbol_id=s.symbol_id
                   LEFT JOIN source_regions r ON r.region_id=d.region_id LEFT JOIN files f ON f.file_id=r.file_id
                   WHERE c.callee_symbol_id=? ORDER BY direction,repository_path,start_line LIMIT ?""",
                    (row["symbol_id"], row["symbol_id"], remaining_calls + 1)).fetchall()
            if len(call_rows) > remaining_calls:
                graph_cuts.append((row["symbol_id"], "call-fanout",
                                   "aggregate caller/callee evidence exceeds the direct relationship budget"))
            for call in call_rows[:remaining_calls]:
                call_edge = (row["symbol_id"], call["symbol_id"], call["direction"], call["provider"])
                edges.append(call_edge)
                selected_call_edges.add(call_edge)
                if call["repository_path"] is not None:
                    add_item(items, kind=call["direction"], path=call["repository_path"],
                             start=call["start_line"], end=call["end_line"],
                             symbol=call["display_name"], why=f"direct {call['direction'].lower()} of {requested}",
                             required=False, provider=call["provider"])
            remaining_calls = args.max_direct_relationships - len(selected_call_edges)
            if "C" in requested_classes and remaining_calls <= 0:
                remaining_calls = 0

    joern_ready = False
    joern_flow_relationships = 0
    joern_mutations = 0
    if "F" in requested_classes:
        provider = connection.execute(
            "SELECT status FROM provider_runs WHERE generation_id=? AND provider='joern'",
            (args.generation,)).fetchone()
        if not provider or provider[0] != "READY":
            unresolved.append(("FLOW_EVIDENCE", "F", "Joern flow evidence was requested but is unavailable"))
        else:
            joern_ready = True

    # Joern flow is supplemental evidence for exact assignment seeds.  Keep a
    # deterministic bounded sample of the direct control/data-flow and
    # mutation seam; never recursively copy a complete CPG into a worker
    # capsule.
    if joern_ready:
        remaining_flow = args.max_direct_relationships
        definitions = connection.execute(
            """
            SELECT DISTINCT d.symbol_id,f.repository_path,r.start_line,r.end_line
            FROM symbol_definitions d
            JOIN source_regions r ON r.region_id=d.region_id
            JOIN files f ON f.file_id=r.file_id
            WHERE d.symbol_id IN ({})
            ORDER BY d.symbol_id,f.repository_path,r.start_line
            """.format(",".join("?" for _ in seed_symbol_ids)),
            tuple(sorted(seed_symbol_ids))).fetchall() if seed_symbol_ids else []
        for definition in definitions:
            if remaining_flow <= 0:
                break
            for table, value_column, kind in (
                    ("control_flow_edges", "e.edge_kind", "CONTROL_FLOW"),
                    ("data_flow_edges", "COALESCE(e.value_name,e.edge_kind)", "DATA_FLOW")):
                if remaining_flow <= 0:
                    break
                class_limit = (max(1, remaining_flow // 2)
                               if kind == "CONTROL_FLOW" else remaining_flow)
                rows = connection.execute(
                    f"""
                    SELECT e.source_region_id,e.target_region_id,{value_column} AS detail,
                           sf.repository_path AS source_path,sr.start_line AS source_line,
                           tf.repository_path AS target_path,tr.start_line AS target_line
                    FROM {table} e
                    JOIN source_regions sr ON sr.region_id=e.source_region_id
                    JOIN files sf ON sf.file_id=sr.file_id
                    JOIN source_regions tr ON tr.region_id=e.target_region_id
                    JOIN files tf ON tf.file_id=tr.file_id
                    WHERE e.provider='joern' AND sf.repository_path=?
                      AND sr.start_line BETWEEN ? AND ?
                    ORDER BY e.source_region_id,e.target_region_id,e.edge_kind
                    LIMIT ?
                    """, (definition["repository_path"], definition["start_line"],
                           definition["end_line"], class_limit)).fetchall()
                for flow in rows:
                    flow_id = f"joern-region:{flow['source_region_id']}"
                    target_id = f"joern-region:{flow['target_region_id']}"
                    edges.append((flow_id, target_id, kind, "joern"))
                    add_item(items, kind=kind, path=flow["source_path"],
                             start=flow["source_line"], end=flow["source_line"],
                             symbol=definition["symbol_id"],
                             why=f"direct Joern {kind.lower().replace('_', '-')} evidence: {flow['detail']}",
                             required=False, provider="joern")
                    if (flow["target_path"], flow["target_line"]) != (
                            flow["source_path"], flow["source_line"]):
                        add_item(items, kind=kind, path=flow["target_path"],
                                 start=flow["target_line"], end=flow["target_line"],
                                 symbol=definition["symbol_id"],
                                 why=f"target of direct Joern {kind.lower().replace('_', '-')}",
                                 required=False, provider="joern")
                    remaining_flow -= 1
                    joern_flow_relationships += 1
        remaining_mutations = args.max_direct_relationships
        if seed_symbol_ids:
            mutation_rows = connection.execute(
                """
                SELECT m.source_symbol_id,m.target_value,f.repository_path,r.start_line
                FROM mutation_edges m
                LEFT JOIN source_regions r ON r.region_id=m.evidence_region_id
                LEFT JOIN files f ON f.file_id=r.file_id
                WHERE m.provider='joern' AND m.source_symbol_id IN ({})
                ORDER BY m.source_symbol_id,f.repository_path,r.start_line,m.target_value
                LIMIT ?
                """.format(",".join("?" for _ in seed_symbol_ids)),
                (*sorted(seed_symbol_ids), remaining_mutations)).fetchall()
            for mutation in mutation_rows:
                if mutation["repository_path"] is None or mutation["start_line"] is None:
                    continue
                add_item(items, kind="MUTATION", path=mutation["repository_path"],
                         start=mutation["start_line"], end=mutation["start_line"],
                         symbol=mutation["source_symbol_id"],
                         why=f"direct Joern mutation evidence: {mutation['target_value']}",
                         required=False, provider="joern")
                joern_mutations += 1

    # Definitions, type relationships, and interface relationships form the
    # required structural closure. Direct REFERENCES edges above are bounded
    # behavioral neighbors; they are deliberately not expanded transitively.
    fixed_point_queue = sorted(selected_symbol_ids) if "T" in requested_classes else []
    fixed_point_expanded: set[str] = set()
    missing_dependency_definitions: set[str] = set()
    while fixed_point_queue:
        source_symbol = fixed_point_queue.pop(0)
        if source_symbol in fixed_point_expanded:
            continue
        fixed_point_expanded.add(source_symbol)
        relation_rows = connection.execute(
            """
            SELECT e.edge_kind, t.symbol_id, t.display_name,
                   f.repository_path, r.start_line, r.end_line
            FROM symbol_edges e
            JOIN symbols t ON t.symbol_id=e.target_symbol_id
            LEFT JOIN symbol_definitions d ON d.symbol_id=t.symbol_id
            LEFT JOIN source_regions r ON r.region_id=d.region_id
            LEFT JOIN files f ON f.file_id=r.file_id
            WHERE e.source_symbol_id=? AND
                  e.edge_kind IN ('TYPE_DEFINITION','IMPLEMENTS','RELATED_DEFINITION')
            ORDER BY e.edge_kind, t.symbol_id, f.repository_path, r.start_line
            LIMIT 17
            """, (source_symbol,)).fetchall()
        if len(relation_rows) > 16:
            graph_cuts.append((source_symbol, "required-edge-fanout",
                               "more than 16 required type/interface dependencies"))
        grouped: dict[str, list[sqlite3.Row]] = {}
        for relation in relation_rows[:16]:
            grouped.setdefault(relation["symbol_id"], []).append(relation)
            edges.append((source_symbol, relation["symbol_id"],
                          relation["edge_kind"], "scip-clang"))
        for target_symbol, target_rows in sorted(grouped.items()):
            if target_symbol not in selected_symbol_ids:
                selected_symbol_ids.add(target_symbol)
                fixed_point_queue.append(target_symbol)
            definitions = [row for row in target_rows if row["repository_path"] is not None]
            if not definitions and target_symbol not in missing_dependency_definitions:
                missing_dependency_definitions.add(target_symbol)
                unresolved.append(("DEPENDENCY_DEFINITION", target_symbol,
                                   "required type/interface dependency has no indexed definition"))
            for relation in definitions:
                add_item(items, kind=relation["edge_kind"], path=relation["repository_path"],
                         start=relation["start_line"], end=relation["end_line"],
                         symbol=relation["display_name"],
                         why=f"fixed-point {relation['edge_kind']} dependency of {source_symbol}",
                         required=True, provider="scip-clang")
        fixed_point_queue.sort()
        if len(selected_symbol_ids) > args.max_symbols:
            graph_cuts.append((source_symbol, "symbol-budget",
                               "fixed-point expansion exceeded the configured symbol budget"))
            break

    named_tests = sorted(split_list(values.get("Named-Tests", "")))
    if named_tests and "B" not in requested_classes:
        unresolved.append(("DEPENDENCY_CLASS", "B",
                           "Named-Tests requires behavioral evidence class B"))
    for requested_test in named_tests if "B" in requested_classes else []:
        test_rows = connection.execute(
            """
            SELECT DISTINCT t.test_id, t.name, t.selector, t.build_target,
                            f.repository_path, r.start_line, r.end_line
            FROM tests t
            LEFT JOIN files f ON f.file_id=t.file_id
            LEFT JOIN source_regions r ON r.region_id=t.region_id
            WHERE t.name=? COLLATE NOCASE OR t.selector=?
            ORDER BY f.repository_path, r.start_line
            """, (requested_test, requested_test)).fetchall()
        if not test_rows:
            unresolved.append(("NAMED_TEST", requested_test, "no exact indexed test or selector"))
            continue
        for test in test_rows:
            selected_tests.add(test["name"])
            if test["repository_path"] is None or test["start_line"] is None:
                unresolved.append(("NAMED_TEST_REGION", requested_test,
                                   "indexed test has no structural source region"))
                continue
            add_item(items, kind="FOCUSED_TEST", path=test["repository_path"],
                     start=test["start_line"], end=test["end_line"],
                     symbol=test["name"], why=f"manager-required named test {requested_test}",
                     required=True, provider="scip-clang")

    for requested_path, seed_reason in sorted(path_seeds.items()):
        normalized = requested_path.rstrip("/")
        repository_path = safe_repository_path(repository, normalized)
        if repository_path is not None and repository_path.is_dir():
            # A directory is an evidence boundary, not an instruction to dump
            # every descendant file. Exact symbol/file seeds must select the
            # structural regions inside it.
            prefix = normalized + "/"
            if not any(item["path"] == normalized or item["path"].startswith(prefix)
                       for item in items.values()):
                unresolved.append(("CONTEXT_PATH", normalized,
                                   "directory path has no exact required symbol or file evidence seed"))
            continue
        file_rows = connection.execute(
            """
            SELECT repository_path FROM files
            WHERE repository_path=? OR repository_path LIKE ?
            ORDER BY repository_path LIMIT 64
            """, (normalized, normalized + "/%")).fetchall()
        if not file_rows:
            source = safe_source_path(repository, normalized)
            if source is None:
                unresolved.append(("CONTEXT_PATH", normalized, "path is absent from index and repository"))
                continue
            with source.open(encoding="utf-8", errors="replace") as stream:
                line_count = sum(1 for _ in stream)
            add_item(items, kind="DECLARED_CONTEXT", path=normalized, start=1,
                     end=max(line_count, 1), symbol="-", why=seed_reason,
                     required=True, provider="assignment")
            continue
        for file_row in file_rows:
            path = file_row["repository_path"]
            if any(item["path"] == path for item in items.values()):
                continue
            source = safe_source_path(repository, path)
            if source is None:
                continue
            with source.open(encoding="utf-8", errors="replace") as stream:
                line_count = sum(1 for _ in stream)
            add_item(items, kind="DECLARED_CONTEXT", path=path, start=1,
                     end=max(line_count, 1), symbol="-", why=seed_reason,
                     required=True, provider="assignment")

    systematic_omissions: list[str] = []
    if args.omissions_file and Path(args.omissions_file).is_file():
        with Path(args.omissions_file).open(encoding="utf-8", errors="replace", newline="") as stream:
            for record in csv.DictReader(stream, delimiter="\t"):
                if record.get("action") != "INDEX_OR_CLOSURE_REMEDIATION":
                    continue
                candidate = record.get("repository_path", "").strip()
                if not candidate:
                    continue
                if any(candidate == seed.rstrip("/") or candidate.startswith(seed.rstrip("/") + "/")
                       or seed.rstrip("/").startswith(candidate.rstrip("/") + "/") for seed in path_seeds):
                    systematic_omissions.append(candidate)
                    unresolved.append(("SYSTEMATIC_CONTEXT_OMISSION", candidate,
                                       "reviewed episodes repeatedly required this path; repair index/closure rules"))

    for item in items.values():
        overlay_record = overlay.get(item["path"])
        if not overlay_record:
            continue
        if overlay_record.get("status") == "DELETED":
            if item["required"] == "REQUIRED":
                unresolved.append(("WORKTREE_OVERLAY", item["path"],
                                   "required indexed source was deleted in the live worktree"))
            continue
        source = safe_source_path(repository, item["path"])
        window = live_symbol_window(source, item["symbol"]) if source else None
        if window:
            item["start"], item["end"] = window
        elif source and item["kind"] == "DECLARED_CONTEXT":
            line_count = len(source.read_text(encoding="utf-8", errors="replace").splitlines())
            item["start"], item["end"] = 1, max(line_count, 1)
        item["provider"] = "worktree-overlay"
        item["why"] += "; relocated against live tracked workspace content"

    ordered_items = sorted(items.values(), key=lambda row: (
        0 if row["required"] == "REQUIRED" else 1,
        row["path"], row["start"], row["kind"], row["symbol"]))
    # Required exact definitions and declared authority always survive. Pack
    # supplemental callers, references, discovered tests, and flow evidence
    # into a deterministic fraction of the complete capsule budget. A worker
    # can request one typed extension later if an omitted direct neighbor is
    # decisive; it must not receive every discoverable neighbor up front.
    supporting_evidence_budget = max(4096, args.max_bytes // 2)
    required_items = [row for row in ordered_items if row["required"] == "REQUIRED"]
    supporting_items = [row for row in ordered_items if row["required"] != "REQUIRED"]
    packed_items = list(required_items)
    packed_source_bytes = 0
    for row in required_items:
        source = safe_source_path(repository, row["path"])
        if source:
            packed_source_bytes += len(item_excerpt(source, row).encode("utf-8"))
    bounded_supporting_items_omitted = 0
    for row in supporting_items:
        source = safe_source_path(repository, row["path"])
        evidence_bytes = len(item_excerpt(source, row).encode("utf-8")) if source else 0
        if packed_source_bytes + evidence_bytes > supporting_evidence_budget:
            bounded_supporting_items_omitted += 1
            continue
        packed_items.append(row)
        packed_source_bytes += evidence_bytes
    ordered_items = packed_items
    selected_tests = {row["symbol"] for row in ordered_items if row["kind"] == "FOCUSED_TEST"}
    selected_paths = sorted({row["path"] for row in ordered_items})
    build_targets: dict[str, dict[str, str]] = {}
    build_targets_by_path: dict[str, set[str]] = {}
    for path in selected_paths if "V" in requested_classes else []:
        rows = connection.execute(
            """
            SELECT bt.target_id, bt.name, bt.target_kind, bt.definition_path,
                   btf.role, btf.object_path, bt.provider
            FROM files f
            JOIN build_target_files btf ON btf.file_id=f.file_id
            JOIN build_targets bt ON bt.target_id=btf.target_id
            WHERE f.repository_path=?
            ORDER BY bt.name
            """, (path,)).fetchall()
        for row in rows:
            build_targets[row["target_id"]] = {key: str(row[key] or "-") for key in row.keys()}
            build_targets_by_path.setdefault(path, set()).add(row["name"])

    requested_targets = sorted(split_list(values.get("Build-Targets", "")))
    if requested_targets and "V" not in requested_classes:
        unresolved.append(("DEPENDENCY_CLASS", "V",
                           "Build-Targets requires validation prerequisite class V"))
    for requested_target in requested_targets if "V" in requested_classes else []:
        rows = connection.execute(
            """
            SELECT target_id, name, target_kind, definition_path,
                   '-' AS role, '-' AS object_path, provider
            FROM build_targets
            WHERE name=? COLLATE NOCASE
            ORDER BY name
            """, (requested_target,)).fetchall()
        if not rows:
            unresolved.append(("BUILD_TARGET", requested_target, "no exact indexed build target"))
            continue
        for row in rows:
            build_targets[row["target_id"]] = {key: str(row[key] or "-") for key in row.keys()}

    build_inputs: dict[str, dict[str, str]] = {}
    build_input_bytes_by_source: dict[str, int] = {}
    for target_id in sorted(build_targets):
        rows = connection.execute(
            """
            SELECT bi.input_id, bi.absolute_path, bi.content_sha256, bi.input_kind,
                   bti.source_path, bti.include_literal, bi.provider
            FROM build_target_inputs bti
            JOIN build_inputs bi ON bi.input_id=bti.input_id
            WHERE bti.target_id=?
            ORDER BY bi.absolute_path, bti.source_path
            """, (target_id,)).fetchall()
        for row in rows:
            record = {key: str(row[key] or "-") for key in row.keys()}
            input_path = Path(record["absolute_path"])
            try:
                input_bytes = input_path.stat().st_size
            except OSError:
                input_bytes = 0
                unresolved.append(("BUILD_INPUT", record["absolute_path"],
                                   "indexed compilation input is unreadable"))
            record["content_bytes"] = str(input_bytes)
            build_inputs[row["input_id"]] = record
            build_input_bytes_by_source[record["source_path"]] = \
                build_input_bytes_by_source.get(record["source_path"], 0) + input_bytes
            # Generated project inputs must be self-contained because they may
            # not exist in Git or SCIP. Toolchain/SDK headers are immutable
            # provider prerequisites: retain their hashes and provenance, but
            # do not make every leaf embed an entire recursive system SDK.
            if record["input_kind"] == "GENERATED_HEADER" and input_bytes > args.max_bytes:
                graph_cuts.append((record["absolute_path"], "build-input-size",
                                   "generated/external build input exceeds the complete context byte budget"))

    modules: set[str] = set()
    for row in ordered_items:
        targets = build_targets_by_path.get(row["path"], set())
        if targets:
            modules.update(f"build:{target}" for target in targets)
        else:
            root = row["path"].split("/", 1)[0] if "/" in row["path"] else "."
            modules.add(f"path:{root}")

    direct_relationships = len({edge for edge in edges if edge[2] in {"CALLER", "CALLEE"}})
    suggested_cuts: list[dict[str, str]] = []
    cohesive_groups: dict[str, list[dict]] = {}
    for row in ordered_items:
        targets = sorted(build_targets_by_path.get(row["path"], set()))
        if targets:
            key = f"build-target:{targets[0]}"
            seam_kind = "BUILD_TARGET"
        else:
            root = row["path"].split("/", 1)[0] if "/" in row["path"] else "."
            key = f"source-root:{root}"
            seam_kind = "SOURCE_ROOT"
        row_with_seam = dict(row)
        row_with_seam["seam_kind"] = seam_kind
        cohesive_groups.setdefault(key, []).append(row_with_seam)
    for key, group in sorted(cohesive_groups.items()):
        paths = sorted({row["path"] for row in group})
        symbols = sorted({row["symbol"] for row in group if row["symbol"] != "-"})
        source_bytes = 0
        for row in group:
            source = safe_source_path(repository, row["path"])
            if source:
                source_bytes += len(item_excerpt(source, row).encode("utf-8"))
        source_bytes += sum(build_input_bytes_by_source.get(path, 0) for path in paths)
        route = "LUNA" if source_bytes <= args.max_bytes and len(symbols) <= args.max_symbols else \
            ("DECOMPOSE" if getattr(args, "luna_only", False) else "DECOMPOSE_OR_TERRA")
        cut_id = stable_id(task_id, key, ",".join(paths), ",".join(symbols))[:16]
        suggested_cuts.append({
            "cut_id": cut_id,
            "seam_kind": group[0]["seam_kind"],
            "cohesive_key": key,
            "required_symbols": ",".join(symbols) or "-",
            "allowed_paths": ",".join(paths) or "-",
            "acceptance_hint": values.get("Focused-Validation", "-") or "-",
            "route_hint": route,
            "estimated_source_bytes": str(source_bytes),
            "rationale": f"cohesive indexed {group[0]['seam_kind'].lower()} boundary",
        })

    output.mkdir(parents=True, exist_ok=True)
    with (output / "closure.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("item_id", "item_kind", "source_path", "start_line", "end_line",
                         "symbol", "introduced_by", "required", "provider"))
        for row in ordered_items:
            writer.writerow((row["item_id"], row["kind"], row["path"], row["start"],
                             row["end"], row["symbol"], row["why"], row["required"], row["provider"]))
    with (output / "edges.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("source_symbol", "target_symbol", "edge_kind", "provider"))
        writer.writerows(sorted(set(edges)))
    with (output / "unresolved.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("unresolved_kind", "identifier", "reason"))
        writer.writerows(unresolved)
    with (output / "graph-cut.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("source", "cut_kind", "reason"))
        writer.writerows(sorted(set(graph_cuts)))
    with (output / "suggested-cuts.tsv").open("w", encoding="utf-8", newline="") as stream:
        fields = ("cut_id", "seam_kind", "cohesive_key", "required_symbols", "allowed_paths",
                  "acceptance_hint", "route_hint", "estimated_source_bytes", "rationale")
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(suggested_cuts)
    with (output / "build-targets.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("target_id", "name", "target_kind", "definition_path", "role",
                         "object_path", "provider"))
        for target_id, record in sorted(build_targets.items(), key=lambda entry: entry[1]["name"]):
            writer.writerow((target_id, record["name"], record["target_kind"],
                             record["definition_path"], record["role"],
                             record["object_path"], record["provider"]))
    with (output / "build-inputs.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("input_id", "absolute_path", "content_sha256", "input_kind",
                         "source_path", "include_literal", "provider"))
        for input_id, record in sorted(build_inputs.items(), key=lambda entry: entry[1]["absolute_path"]):
            writer.writerow((input_id, record["absolute_path"], record["content_sha256"],
                             record["input_kind"], record["source_path"],
                             record["include_literal"], record["provider"]))
    with (output / "ownership-boundaries.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("edge_id", "producer_node", "consumer_node", "ownership_model"))
        writer.writerows(sorted(ownership_boundaries))
    with (output / "authority.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("authority_kind", "identifier", "source", "record_json"))
        for kind, identifier, source, record in sorted(
                authority_records, key=lambda entry: (entry[0], entry[1], entry[2])):
            writer.writerow((kind, identifier, source,
                             json.dumps(record, sort_keys=True, separators=(",", ":"))))
    with (output / "worktree-overlay.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("repository_path", "status", "content_sha256", "content_bytes"))
        for overlay_path, record in sorted(overlay.items()):
            writer.writerow((overlay_path, record.get("status", "-"),
                             record.get("content_sha256", "-"),
                             record.get("content_bytes", "0")))

    context_lines = [
        "# Compiled Context Closure", "", f"Task-ID: {task_id}", f"Plan-Node: {plan_node}",
        f"Worker-Route: {values.get('Worker-Route', '-')}",
        f"Deliverable: {values.get('Deliverable', '-')}",
        f"Acceptance-Evidence: {values.get('Acceptance-Evidence', values.get('Goal-Success-Evidence', '-'))}",
        f"Focused-Validation: {values.get('Focused-Validation', '-')}",
        f"Allowed-Scope: {values.get('Allowed-Scope', '-')}",
        f"Required-Symbols: {values.get('Required-Symbols', '-')}", "",
        f"Required-Dependency-Classes: {','.join(sorted(requested_classes))}", "",
        f"Worktree-Overlay-Paths: {len(overlay)}", "",
        "## Architecture and behavior contract", "",
        f"Architecture-Decisions: {values.get('Architecture-Decisions', 'NONE')}",
        f"Affected-Invariants: {values.get('Affected-Invariants', '-')}",
        f"Edge-Contracts: {values.get('Edge-Contracts', '-')}",
        f"Baseline-Boundary: {values.get('Baseline-Boundary', '-')}", "",
        "## Ownership boundaries", "",
    ]
    if ownership_boundaries:
        for edge_id, producer, consumer, ownership in sorted(ownership_boundaries):
            context_lines.append(
                f"- `{edge_id}`: `{producer}` -> `{consumer}`; ownership `{ownership}`")
    else:
        context_lines.append("NONE")
    context_lines.extend(("", "## Build and validation prerequisites", ""))
    if build_targets:
        for _, record in sorted(build_targets.items(), key=lambda entry: entry[1]["name"]):
            context_lines.append(
                f"- `{record['name']}` ({record['target_kind']}), definition `{record['definition_path']}`")
    else:
        context_lines.append("NONE")
    if build_inputs:
        context_lines.extend(("", "### Generated/external compilation inputs", ""))
        for _, record in sorted(build_inputs.items(), key=lambda entry: entry[1]["absolute_path"]):
            if record["input_kind"] == "EXTERNAL_HEADER":
                context_lines.append(
                    f"- External prerequisite `{record['include_literal']}` at "
                    f"`{record['absolute_path']}`; sha256 `{record['content_sha256']}`; "
                    f"included by `{record['source_path']}`. Content is represented by "
                    "the indexed toolchain fingerprint and is not embedded.")
                continue
            input_path = Path(record["absolute_path"])
            try:
                input_text = input_path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                input_text = "[indexed build input is currently unreadable]"
            encoded = input_text.encode("utf-8")
            if len(encoded) > args.max_bytes:
                input_text = encoded[:args.max_bytes].decode("utf-8", errors="ignore") + \
                    "\n[input exceeds closure budget; decomposition required]\n"
            context_lines.extend((
                f"#### {record['input_kind']}: `{record['include_literal']}`", "",
                f"Indexed path: `{record['absolute_path']}`; sha256 `{record['content_sha256']}`; "
                f"included by `{record['source_path']}`.", "", "```text", input_text.rstrip("\n"), "```", "",
            ))
    context_lines.extend(("", "## Suggested cohesive child boundaries", ""))
    if suggested_cuts:
        for cut in suggested_cuts:
            context_lines.append(
                f"- `{cut['cut_id']}` {cut['cohesive_key']}: paths `{cut['allowed_paths']}`; "
                f"symbols `{cut['required_symbols']}`; route `{cut['route_hint']}`")
    else:
        context_lines.append("NONE")
    context_lines.extend(("",
        "## Allocated normative authority", "",
    ))
    if authority_records:
        for kind, identifier, source, record in sorted(
                authority_records, key=lambda entry: (entry[0], entry[1], entry[2])):
            context_lines.extend((
                f"### {kind}: `{identifier}`", "",
                f"Authority source: `{source}`", "",
                "```json", json.dumps(record, sort_keys=True, indent=2), "```", "",
            ))
    else:
        context_lines.extend(("NONE", ""))
    context_lines.extend((
        "## Closed source evidence", "",
    ))
    for row in ordered_items:
        source = safe_source_path(repository, row["path"])
        text = item_excerpt(source, row) if source else ""
        context_lines.extend((
            f"### {row['kind']}: `{row['path']}:{row['start']}` — `{row['symbol']}`", "",
            f"Selected because: {row['why']} ({row['required']}, {row['provider']}).", "",
            "```text", text.rstrip("\n"), "```", "",
        ))
    context_lines.extend(("## Unresolved evidence", ""))
    if unresolved:
        for kind, identifier, reason in unresolved:
            context_lines.append(f"- {kind} `{identifier}`: {reason}")
    else:
        context_lines.append("NONE")
    context_lines.extend(("", "## Structural graph cuts", ""))
    if graph_cuts:
        for source, kind, reason in sorted(set(graph_cuts)):
            context_lines.append(f"- {kind} at `{source}`: {reason}")
    else:
        context_lines.append("NONE")
    context_lines.append("")
    context_text = "\n".join(context_lines)
    context_bytes = len(context_text.encode("utf-8"))
    estimated_tokens = math.ceil(context_bytes / 4)

    reasons: list[str] = []
    if unresolved:
        reasons.append("unresolved-required-evidence")
    if len(selected_symbol_ids) > args.max_symbols:
        reasons.append("symbol-budget-exceeded")
    if len(modules) > args.max_modules:
        reasons.append("module-budget-exceeded")
    if len(ownership_boundaries) > args.max_ownership_boundaries:
        reasons.append("ownership-boundary-budget-exceeded")
    if direct_relationships > args.max_direct_relationships:
        reasons.append("direct-relationship-budget-exceeded")
    if len(selected_tests) > args.max_tests:
        reasons.append("test-budget-exceeded")
    if len(build_targets) > args.max_build_targets:
        reasons.append("build-target-budget-exceeded")
    if context_bytes > args.max_bytes:
        reasons.append("context-byte-budget-exceeded")
    if estimated_tokens > args.max_tokens:
        reasons.append("estimated-token-budget-exceeded")
    if graph_cuts:
        reasons.append("structural-graph-cut")
    if unresolved:
        status = "INCOMPLETE"
    elif reasons:
        status = "NEEDS_FURTHER_DECOMPOSITION"
    else:
        status = "READY"

    unresolved_kinds = {kind for kind, _, _ in unresolved}
    authority_kinds = {"ARCHITECTURE_BINDING", "SPECIFICATION_OBLIGATION",
                       "ARCHITECTURE_INVARIANT", "ARCHITECTURE_DECISION",
                       "EDGE_CONTRACT", "HEALTH_GATE"}
    provider_by_kind = {
        "FLOW_EVIDENCE": "joern",
        "REQUIRED_SYMBOL": "scip",
        "REQUIRED_DEFINITION": "scip",
        "DEPENDENCY_DEFINITION": "scip",
        "NAMED_TEST": "repository-index",
        "NAMED_TEST_REGION": "repository-index",
        "BUILD_CONFIGURATION": "build-index",
        "BUILD_TARGET": "build-index",
        "BUILD_INPUT": "build-index",
        "CONTEXT_PATH": "repository-index",
        "SYSTEMATIC_CONTEXT_OMISSION": "repository-index",
        "WORKTREE_OVERLAY": "worktree-overlay",
    }
    # Compile candidate mutation seams before classifying the repair. Context
    # evidence can legitimately live outside Allowed-Scope, but it can never
    # become child write authority. Each candidate therefore intersects the
    # indexed cut with the immutable assignment scope and carries a separate
    # exact context path field.
    repair_children: list[dict[str, str]] = []
    for cut in suggested_cuts:
        cut_paths = split_list(cut["allowed_paths"])
        mutable_paths = [path for path in cut_paths if path_is_allowed(path, allowed_scopes)]
        if not mutable_paths:
            continue
        symbols_by_path: dict[str, list[str]] = {}
        for item in ordered_items:
            if item["path"] in mutable_paths and item["symbol"] != "-":
                symbols_by_path.setdefault(item["path"], []).append(item["symbol"])
        boundaries: list[tuple[list[str], list[str]]] = []
        if cut["route_hint"] == "LUNA":
            mutable_symbols = sorted({symbol for path in mutable_paths
                                      for symbol in symbols_by_path.get(path, [])})
            boundaries.append((mutable_paths, mutable_symbols))
        elif len(mutable_paths) > 1:
            for path in mutable_paths:
                boundaries.append(([path], sorted(set(symbols_by_path.get(path, [])))))
        elif mutable_paths:
            path_symbols = sorted(set(symbols_by_path.get(mutable_paths[0], [])))
            if len(path_symbols) > 1:
                boundaries.extend((mutable_paths, [symbol]) for symbol in path_symbols)
            else:
                boundaries.append((mutable_paths, path_symbols))
        for child_paths, child_symbols in boundaries:
            child_id = "CCR-" + stable_id(task_id, cut["cut_id"],
                                           ",".join(child_paths),
                                           ",".join(child_symbols))[:12]
            child_source_bytes = 0
            for item in ordered_items:
                if item["path"] not in child_paths:
                    continue
                source = safe_source_path(repository, item["path"])
                if source:
                    child_source_bytes += len(item_excerpt(source, item).encode("utf-8"))
            repair_children.append({
                "child_id": child_id,
                "parent_task": task_id,
                "sequence": "0",
                "allowed_paths": ",".join(child_paths) or "-",
                "context_paths": ",".join(child_paths) or "-",
                "required_symbols": ",".join(child_symbols) or "-",
                "acceptance_evidence": cut["acceptance_hint"],
                "focused_validation": cut["acceptance_hint"],
                "source_cut": cut["cut_id"],
                "seam_kind": cut["seam_kind"],
                "estimated_source_bytes": str(child_source_bytes),
                "status": "PROPOSED",
            })
    repair_children.sort(key=lambda row: (row["allowed_paths"], row["required_symbols"],
                                          row["child_id"]))
    for sequence, child in enumerate(repair_children, start=1):
        child["sequence"] = str(sequence)

    # Missing evidence and an oversized evidence set are independent closure
    # defects. Refreshing an already-current provider cannot make an oversized
    # assignment Luna-sized, so any mixed resource failure remains a semantic
    # decomposition signal. A pure evidence miss still routes to its provider.
    decomposition_reasons = [
        reason for reason in reasons if reason != "unresolved-required-evidence"
    ]
    if status == "READY":
        condition = "READY"
        repair_action = "LAUNCH_LUNA"
        repair_provider = "-"
        semantic_split_required = 0
    elif unresolved_kinds & authority_kinds:
        condition = "AUTHORITY_EVIDENCE_MISSING"
        repair_action = "REPAIR_AUTHORITY_BINDING"
        repair_provider = "architecture-registry"
        semantic_split_required = 0
    elif unresolved and decomposition_reasons:
        condition = "CLOSURE_BUDGET_EXCEEDED"
        repair_action = "GRAFT_GRAPH_CUTS"
        repair_provider = "decomposition-compiler"
        semantic_split_required = 1
    elif unresolved:
        condition = "INDEX_EVIDENCE_MISSING"
        repair_action = "REFRESH_INDEX_OR_OVERLAY"
        repair_provider = next(
            (provider_by_kind[kind] for kind, _, _ in unresolved if kind in provider_by_kind),
            "repository-index")
        semantic_split_required = 0
    else:
        condition = "CLOSURE_BUDGET_EXCEEDED"
        repair_action = "GRAFT_GRAPH_CUTS"
        repair_provider = "decomposition-compiler"
        semantic_split_required = 1

    if repair_action != "GRAFT_GRAPH_CUTS":
        repair_children = []

    (output / "context.md").write_text(context_text, encoding="utf-8")
    with (output / "quality.tsv").open("w", encoding="utf-8") as stream:
        stream.write("metric\tvalue\n")
        stream.write(f"status\t{status}\n")
        stream.write(f"items\t{len(ordered_items)}\n")
        stream.write(f"symbols\t{len(selected_symbol_ids)}\n")
        stream.write(f"modules\t{len(modules)}\n")
        stream.write(f"ownership_boundaries\t{len(ownership_boundaries)}\n")
        stream.write(f"direct_relationships\t{direct_relationships}\n")
        stream.write(f"joern_flow_relationships\t{joern_flow_relationships}\n")
        stream.write(f"joern_mutations\t{joern_mutations}\n")
        stream.write(f"tests\t{len(selected_tests)}\n")
        stream.write(f"bounded_test_candidates_omitted\t{bounded_test_candidates_omitted}\n")
        stream.write(f"bounded_supporting_items_omitted\t{bounded_supporting_items_omitted}\n")
        stream.write(f"build_targets\t{len(build_targets)}\n")
        stream.write(f"build_inputs\t{len(build_inputs)}\n")
        stream.write(f"unresolved\t{len(unresolved)}\n")
        stream.write(f"graph_cuts\t{len(set(graph_cuts))}\n")
        stream.write(f"authority_records\t{len(authority_records)}\n")
        stream.write(f"systematic_omissions\t{len(systematic_omissions)}\n")
        stream.write(f"context_bytes\t{context_bytes}\n")
        stream.write(f"estimated_tokens\t{estimated_tokens}\n")
        stream.write(f"reasons\t{','.join(reasons) if reasons else '-'}\n")
        stream.write(f"condition\t{condition}\n")
        stream.write(f"repair_action\t{repair_action}\n")
        stream.write(f"repair_provider\t{repair_provider}\n")
        stream.write(f"semantic_split_required\t{semantic_split_required}\n")
        stream.write(f"worktree_overlay_paths\t{len(overlay)}\n")
        stream.write(f"repair_candidate_children\t{len(repair_children)}\n")
    with (output / "repair.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("condition", "repair_action", "provider", "evidence_kind",
                         "identifier", "reason"))
        if unresolved:
            for kind, identifier, reason in unresolved:
                writer.writerow((condition, repair_action, provider_by_kind.get(kind, repair_provider),
                                 kind, identifier, reason))
        else:
            writer.writerow((condition, repair_action, repair_provider, "-", "-",
                             ",".join(reasons) if reasons else "ready"))
    with (output / "repair-children.tsv").open("w", encoding="utf-8", newline="") as stream:
        fields = ("child_id", "parent_task", "sequence", "allowed_paths", "context_paths",
                  "required_symbols", "acceptance_evidence", "focused_validation", "source_cut",
                  "seam_kind", "estimated_source_bytes", "status")
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(repair_children)
    assignment_hash = hashlib.sha256(assignment.read_bytes()).hexdigest()
    with (output / "manifest.env").open("w", encoding="utf-8") as stream:
        stream.write(f"status={status}\n")
        stream.write(f"task_id={task_id}\n")
        stream.write(f"plan_node={plan_node}\n")
        stream.write(f"index_generation={args.generation}\n")
        stream.write(f"assignment_sha256={assignment_hash}\n")
        stream.write(f"context_bytes={context_bytes}\n")
        stream.write(f"estimated_tokens={estimated_tokens}\n")
        stream.write(f"reasons={','.join(reasons) if reasons else '-'}\n")
        stream.write(f"condition={condition}\n")
        stream.write(f"repair_action={repair_action}\n")
        stream.write(f"repair_provider={repair_provider}\n")
        stream.write(f"semantic_split_required={semantic_split_required}\n")
        stream.write(f"worktree_overlay_paths={len(overlay)}\n")
        stream.write(f"worktree_overlay_sha256={hashlib.sha256(Path(args.overlay_file).read_bytes()).hexdigest() if getattr(args, 'overlay_file', None) else '-'}\n")
        stream.write(f"repair_candidate_children={len(repair_children)}\n")
    connection.close()
    return status


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assignment", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-bytes", required=True, type=int)
    parser.add_argument("--max-symbols", required=True, type=int)
    parser.add_argument("--max-modules", required=True, type=int)
    parser.add_argument("--max-ownership-boundaries", required=True, type=int)
    parser.add_argument("--max-direct-relationships", required=True, type=int)
    parser.add_argument("--max-tests", required=True, type=int)
    parser.add_argument("--max-build-targets", required=True, type=int)
    parser.add_argument("--max-tokens", required=True, type=int)
    parser.add_argument("--luna-only", action="store_true")
    parser.add_argument("--overlay-file")
    parser.add_argument("--obligations-file")
    parser.add_argument("--relations-file")
    parser.add_argument("--invariants-file")
    parser.add_argument("--decisions-file")
    parser.add_argument("--edges-file")
    parser.add_argument("--health-gates-file")
    parser.add_argument("--node-bindings-file")
    parser.add_argument("--omissions-file")
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    try:
        result = build_closure(arguments)
    except (OSError, sqlite3.Error, ValueError) as error:
        print(f"context-closure compiler: {error}", file=sys.stderr)
        sys.exit(1)
    print(result)
