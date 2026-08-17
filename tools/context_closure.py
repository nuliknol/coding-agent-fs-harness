#!/usr/bin/env python3

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
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
    symbol_seeds = {symbol: "assignment required symbol"
                    for symbol in split_list(values.get("Required-Symbols", ""))}
    path_seeds = {path: "manager-declared context path"
                  for path in split_list(values.get("Context-Paths", values.get("Allowed-Scope", "")))}

    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    items: dict[tuple, dict] = {}
    edges: list[tuple[str, str, str, str]] = []
    unresolved: list[tuple[str, str, str]] = []
    graph_cuts: list[tuple[str, str, str]] = []
    selected_symbol_ids: set[str] = set()
    authority_records: list[tuple[str, str, str, dict[str, str]]] = []
    ownership_boundaries: set[tuple[str, str, str, str]] = set()
    selected_tests: set[str] = set()
    requested_classes = set(split_list(values.get("Required-Dependency-Classes", "D,T,I,B,C,V")))

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
                for symbol in split_list(record.get("affected_interfaces", "")):
                    symbol_seeds.setdefault(symbol, f"interface governed by decision {identifier}")
                evidence = record.get("evidence", "")
                if evidence and evidence not in ("-", "NONE"):
                    evidence = evidence.removeprefix("operator-worktree:")
                    if safe_repository_path(repository, evidence) is not None:
                        path_seeds.setdefault(evidence, f"evidence for decision {identifier}")
            elif authority_kind == "EDGE_CONTRACT":
                producer = record.get("producer_node", "-") or "-"
                consumer = record.get("consumer_node", "-") or "-"
                ownership = record.get("ownership_model", "-") or "-"
                ownership_boundaries.add((identifier, producer, consumer, ownership))
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
            unresolved.append(("REQUIRED_SYMBOL", requested, "no exact SCIP symbol or definition"))
            continue
        definitions = [row for row in rows if row["repository_path"] is not None]
        if not definitions:
            unresolved.append(("REQUIRED_DEFINITION", requested, "symbol exists but has no indexed definition"))
        for row in definitions:
            selected_symbol_ids.add(row["symbol_id"])
            add_item(items, kind="DEFINITION", path=row["repository_path"],
                     start=row["start_line"], end=row["end_line"],
                     symbol=row["display_name"], why=f"{seed_reason}: {requested}",
                     required=True, provider="scip-clang")

        for row in rows:
            selected_symbol_ids.add(row["symbol_id"])
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
                is_test = "/tests/" in f"/{reference['repository_path']}" or reference["repository_path"].startswith("tests/")
                add_item(items, kind="TEST_REFERENCE" if is_test else "INTERFACE_REFERENCE",
                         path=reference["repository_path"], start=reference["start_line"],
                         end=reference["end_line"], symbol=row["display_name"],
                         why=f"indexed {'test' if is_test else 'interface'} reference for {requested}",
                         required=False, provider="scip-clang")

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
                selected_tests.add(test["name"])
                add_item(items, kind="FOCUSED_TEST", path=test["repository_path"],
                         start=test["start_line"], end=test["end_line"],
                         symbol=test["name"], why=f"indexed test covering {requested}",
                         required=True, provider="scip-clang")

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
                """, (row["symbol_id"],)).fetchall()
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
            if "C" in requested_classes:
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
                    (row["symbol_id"], row["symbol_id"], args.max_direct_relationships + 1)).fetchall()
            if len(call_rows) > args.max_direct_relationships:
                graph_cuts.append((row["symbol_id"], "call-fanout",
                                   "caller/callee evidence exceeds the direct relationship budget"))
            for call in call_rows[:args.max_direct_relationships]:
                edges.append((row["symbol_id"], call["symbol_id"], call["direction"], call["provider"]))
                if call["repository_path"] is not None:
                    add_item(items, kind=call["direction"], path=call["repository_path"],
                             start=call["start_line"], end=call["end_line"],
                             symbol=call["display_name"], why=f"direct {call['direction'].lower()} of {requested}",
                             required=False, provider=call["provider"])

    if "F" in requested_classes:
        provider = connection.execute(
            "SELECT status FROM provider_runs WHERE generation_id=? AND provider='joern'",
            (args.generation,)).fetchone()
        if not provider or provider[0] != "READY":
            unresolved.append(("FLOW_EVIDENCE", "F", "Joern flow evidence was requested but is unavailable"))

    # Definitions, type relationships, and interface relationships form the
    # required structural closure. Direct REFERENCES edges above are bounded
    # behavioral neighbors; they are deliberately not expanded transitively.
    fixed_point_queue = sorted(selected_symbol_ids)
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

    for requested_test in sorted(split_list(values.get("Named-Tests", ""))):
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
            line_count = sum(1 for _ in source.open(encoding="utf-8", errors="replace"))
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
            line_count = sum(1 for _ in source.open(encoding="utf-8", errors="replace"))
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

    ordered_items = sorted(items.values(), key=lambda row: (
        0 if row["required"] == "REQUIRED" else 1,
        row["path"], row["start"], row["kind"], row["symbol"]))
    selected_paths = sorted({row["path"] for row in ordered_items})
    build_targets: dict[str, dict[str, str]] = {}
    build_targets_by_path: dict[str, set[str]] = {}
    for path in selected_paths:
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

    for requested_target in sorted(split_list(values.get("Build-Targets", ""))):
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

    direct_relationships = len(set(edges))
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
                source_bytes += len(excerpt(source, row["start"], row["end"]).encode("utf-8"))
        source_bytes += sum(build_input_bytes_by_source.get(path, 0) for path in paths)
        route = "LUNA" if source_bytes <= args.max_bytes and len(symbols) <= args.max_symbols else "DECOMPOSE_OR_TERRA"
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

    context_lines = [
        "# Compiled Context Closure", "", f"Task-ID: {task_id}", f"Plan-Node: {plan_node}",
        f"Worker-Route: {values.get('Worker-Route', '-')}",
        f"Deliverable: {values.get('Deliverable', '-')}",
        f"Acceptance-Evidence: {values.get('Acceptance-Evidence', values.get('Goal-Success-Evidence', '-'))}",
        f"Focused-Validation: {values.get('Focused-Validation', '-')}",
        f"Allowed-Scope: {values.get('Allowed-Scope', '-')}",
        f"Required-Symbols: {values.get('Required-Symbols', '-')}", "",
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
        text = excerpt(source, row["start"], row["end"]) if source else ""
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

    (output / "context.md").write_text(context_text, encoding="utf-8")
    with (output / "quality.tsv").open("w", encoding="utf-8") as stream:
        stream.write("metric\tvalue\n")
        stream.write(f"status\t{status}\n")
        stream.write(f"items\t{len(ordered_items)}\n")
        stream.write(f"symbols\t{len(selected_symbol_ids)}\n")
        stream.write(f"modules\t{len(modules)}\n")
        stream.write(f"ownership_boundaries\t{len(ownership_boundaries)}\n")
        stream.write(f"direct_relationships\t{direct_relationships}\n")
        stream.write(f"tests\t{len(selected_tests)}\n")
        stream.write(f"build_targets\t{len(build_targets)}\n")
        stream.write(f"build_inputs\t{len(build_inputs)}\n")
        stream.write(f"unresolved\t{len(unresolved)}\n")
        stream.write(f"graph_cuts\t{len(set(graph_cuts))}\n")
        stream.write(f"authority_records\t{len(authority_records)}\n")
        stream.write(f"systematic_omissions\t{len(systematic_omissions)}\n")
        stream.write(f"context_bytes\t{context_bytes}\n")
        stream.write(f"estimated_tokens\t{estimated_tokens}\n")
        stream.write(f"reasons\t{','.join(reasons) if reasons else '-'}\n")
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
