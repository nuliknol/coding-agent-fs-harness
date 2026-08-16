#!/usr/bin/env python3

"""Dry-run Context Closure for every proposed Luna decomposition leaf."""

import argparse
import csv
from pathlib import Path
import re
import shutil
import sys
from types import SimpleNamespace

sys.dont_write_bytecode = True
from context_closure import build_closure


SAFE_NODE = re.compile(r"^[A-Za-z0-9._-]+$")


def split_list(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip() not in ("", "-", "NONE")]


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        fields = reader.fieldnames or []
        return fields, list(reader)


def obligation_mapping(path: Path | None) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    if path is None:
        return result
    _, rows = read_tsv(path)
    for row in rows:
        obligation = row.get("obligation_id", "").strip()
        for node in split_list(row.get("node_ids", "")):
            result.setdefault(node, []).append(obligation)
    return result


def architecture_bindings(directory: Path | None) -> dict[str, dict[str, str]]:
    if directory is None:
        return {}
    path = directory / "node-bindings.tsv"
    if not path.is_file():
        return {}
    _, rows = read_tsv(path)
    return {row.get("node_id", ""): row for row in rows if row.get("node_id", "")}


def metric_file(path: Path) -> dict[str, str]:
    _, rows = read_tsv(path)
    return {row.get("metric", ""): row.get("value", "") for row in rows}


def learned_upper_bounds(path: Path | None) -> dict[str, int]:
    if path is None or not path.is_file():
        return {}
    _, rows = read_tsv(path)
    result: dict[str, int] = {}
    for row in rows:
        if "luna" not in row.get("model", "").lower():
            continue
        leaf = row.get("leaf_type", "")
        try:
            upper = int(row.get("processed_tokens_p95", "0"))
        except ValueError:
            continue
        if leaf and upper > 0:
            result[leaf] = max(result.get(leaf, 0), upper)
    return result


def write_assignment(path: Path, node: dict[str, str], obligations: list[str],
                     binding: dict[str, str]) -> None:
    values = (
        ("Task-ID", f"decomposition-dry-run-{node['node_id']}"),
        ("Plan-Node", node["node_id"]),
        ("Worker-Route", node.get("worker_route", "-")),
        ("Deliverable", node.get("deliverable", "-")),
        ("Acceptance-Evidence", node.get("acceptance_evidence", "-")),
        ("Focused-Validation", node.get("focused_validation", "-")),
        ("Allowed-Scope", node.get("allowed_paths", "-")),
        ("Context-Paths", node.get("allowed_paths", "-")),
        ("Required-Symbols", node.get("required_symbols", "-")),
        ("Leaf-Type", node.get("leaf_type", "-")),
        ("Complexity-Class", node.get("complexity_class", "-")),
        ("Specification-Obligations", ",".join(sorted(obligations)) or "-"),
        ("Affected-Invariants", binding.get("invariant_ids", "-")),
        ("Consumed-Decisions", binding.get("consumes_decisions", "-")),
        ("Produced-Decisions", binding.get("produces_decisions", "-")),
        ("Edge-Contracts", binding.get("edge_contracts", "-")),
        ("Health-Gates", binding.get("health_gates", "-")),
    )
    path.write_text("".join(f"{key}: {value}\n" for key, value in values), encoding="utf-8")


def evaluate(args: argparse.Namespace) -> int:
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    fields, nodes = read_tsv(Path(args.dag))
    required = {"node_id", "deliverable", "acceptance_evidence", "focused_validation",
                "allowed_paths", "required_symbols", "leaf_type", "complexity_class", "worker_route"}
    missing = required.difference(fields)
    if missing:
        raise ValueError(f"DAG lacks Context Closure fields: {','.join(sorted(missing))}")
    obligations = obligation_mapping(Path(args.coverage) if args.coverage else None)
    architecture = architecture_bindings(Path(args.architecture) if args.architecture else None)
    learned_bounds = learned_upper_bounds(Path(args.predictions) if args.predictions else None)
    admission_rows: list[dict[str, str]] = []
    aggregate_cuts: list[dict[str, str]] = []
    non_ready_luna = 0
    for node in nodes:
        node_id = node.get("node_id", "")
        if not SAFE_NODE.fullmatch(node_id):
            raise ValueError(f"unsafe decomposition node identifier: {node_id}")
        if node.get("worker_route") != "LUNA":
            continue
        node_dir = output / node_id
        if node_dir.exists():
            shutil.rmtree(node_dir)
        node_dir.mkdir()
        assignment = node_dir / "assignment.md"
        write_assignment(assignment, node, obligations.get(node_id, []), architecture.get(node_id, {}))
        closure_args = SimpleNamespace(
            assignment=str(assignment), database=args.database, repository=args.repository,
            generation=args.generation, output=str(node_dir), max_bytes=args.max_bytes,
            max_symbols=args.max_symbols, max_modules=args.max_modules,
            max_ownership_boundaries=args.max_ownership_boundaries,
            max_direct_relationships=args.max_direct_relationships, max_tests=args.max_tests,
            max_build_targets=args.max_build_targets, max_tokens=args.max_tokens,
            obligations_file=args.obligations_file, relations_file=args.relations_file,
            invariants_file=f"{args.architecture}/invariants.tsv" if args.architecture else None,
            decisions_file=f"{args.architecture}/decisions.tsv" if args.architecture else None,
            edges_file=f"{args.architecture}/edges.tsv" if args.architecture else None,
            health_gates_file=f"{args.architecture}/health-gates.tsv" if args.architecture else None,
            node_bindings_file=f"{args.architecture}/node-bindings.tsv" if args.architecture else None,
            omissions_file=args.omissions_file,
        )
        status = build_closure(closure_args)
        quality = metric_file(node_dir / "quality.tsv")
        learned_p95 = learned_bounds.get(node.get("leaf_type", ""), 0)
        reasons = quality.get("reasons", "-")
        if learned_p95 > args.max_tokens:
            status = "NEEDS_FURTHER_DECOMPOSITION"
            reasons = ",".join(value for value in (reasons if reasons != "-" else "",
                                                     f"learned-luna-p95-{learned_p95}-over-{args.max_tokens}") if value)
        suggested = max(sum(1 for _ in (node_dir / "suggested-cuts.tsv").open(encoding="utf-8")) - 1, 0)
        _, node_cuts = read_tsv(node_dir / "suggested-cuts.tsv")
        for cut in node_cuts:
            aggregate_cuts.append({"node_id": node_id, **cut})
        if status != "READY":
            non_ready_luna += 1
        admission_rows.append({
            "node_id": node_id, "worker_route": "LUNA", "status": status,
            "context_bytes": quality.get("context_bytes", "0"),
            "estimated_tokens": quality.get("estimated_tokens", "0"),
            "symbols": quality.get("symbols", "0"), "modules": quality.get("modules", "0"),
            "ownership_boundaries": quality.get("ownership_boundaries", "0"),
            "direct_relationships": quality.get("direct_relationships", "0"),
            "tests": quality.get("tests", "0"), "build_targets": quality.get("build_targets", "0"),
            "unresolved": quality.get("unresolved", "0"),
            "graph_cuts": quality.get("graph_cuts", "0"),
            "learned_luna_p95_tokens": str(learned_p95),
            "suggested_child_boundaries": str(suggested),
            "reasons": reasons or "-",
        })
    columns = ("node_id", "worker_route", "status", "context_bytes", "estimated_tokens",
               "symbols", "modules", "ownership_boundaries", "direct_relationships", "tests",
               "build_targets", "unresolved", "graph_cuts", "learned_luna_p95_tokens",
               "suggested_child_boundaries", "reasons")
    with (output / "admission.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(admission_rows)
    cut_columns = ("node_id", "cut_id", "seam_kind", "cohesive_key", "required_symbols",
                   "allowed_paths", "acceptance_hint", "route_hint", "estimated_source_bytes", "rationale")
    with (output / "suggested-cuts.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=cut_columns, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(aggregate_cuts)
    ready = len(admission_rows) - non_ready_luna
    (output / "summary.env").write_text(
        f"luna_nodes={len(admission_rows)}\nready={ready}\nnon_ready={non_ready_luna}\n",
        encoding="utf-8",
    )
    return 3 if args.enforce and non_ready_luna else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dag", required=True)
    parser.add_argument("--coverage")
    parser.add_argument("--architecture")
    parser.add_argument("--database", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--obligations-file")
    parser.add_argument("--relations-file")
    parser.add_argument("--max-bytes", required=True, type=int)
    parser.add_argument("--max-symbols", required=True, type=int)
    parser.add_argument("--max-modules", required=True, type=int)
    parser.add_argument("--max-ownership-boundaries", required=True, type=int)
    parser.add_argument("--max-direct-relationships", required=True, type=int)
    parser.add_argument("--max-tests", required=True, type=int)
    parser.add_argument("--max-build-targets", required=True, type=int)
    parser.add_argument("--max-tokens", required=True, type=int)
    parser.add_argument("--enforce", action="store_true")
    parser.add_argument("--predictions")
    parser.add_argument("--omissions-file")
    return parser.parse_args()


if __name__ == "__main__":
    try:
        raise SystemExit(evaluate(parse_args()))
    except (OSError, ValueError) as error:
        print(f"decomposition context evaluation: {error}", file=__import__("sys").stderr)
        raise SystemExit(2)
