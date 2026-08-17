#!/usr/bin/env python3
"""Deterministic efficiency and decomposition-irregularity detectors."""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from pathlib import Path


def rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def integer(value: str | None) -> int:
    try:
        return int(value or "0")
    except ValueError:
        return 0


def emit(category: str, reason: str, evidence: str) -> None:
    clean = lambda value: value.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    print("\t".join(map(clean, (category, reason, evidence))))


def episode(args: argparse.Namespace) -> int:
    observations = rows(args.observations)
    selected = [row for row in observations if row.get("task_id") == args.task]
    if not selected:
        return 0
    latest = selected[-1]
    actual = integer(latest.get("processed_tokens"))
    predicted = integer(latest.get("predicted_p95_tokens"))
    threshold = args.regression_percent
    if predicted > 0 and actual * 100 > predicted * threshold:
        emit(
            "RELATIVE_TOKEN_REGRESSION",
            f"episode used {actual} tokens, above {threshold}% of its declared p95 {predicted}",
            f"basis=declared_p95 task={args.task} actual={actual} predicted_p95={predicted}",
        )

    accepted = {
        (row.get("project", ""), row.get("task_id", ""))
        for row in rows(args.outcomes)
        if row.get("outcome") == "ACCEPTED"
    } if args.outcomes else set()
    comparable = [
        integer(row.get("processed_tokens"))
        for row in observations
        if row.get("task_id") != args.task
        and row.get("model") == latest.get("model")
        and row.get("leaf_type") == latest.get("leaf_type")
        and row.get("classification") == "success"
        and integer(row.get("processed_tokens")) > 0
        and (not accepted or (row.get("project", ""), row.get("task_id", "")) in accepted)
    ]
    if len(comparable) >= args.min_samples:
        median = int(statistics.median(comparable))
        if median > 0 and actual * 100 > median * threshold:
            emit(
                "RELATIVE_TOKEN_REGRESSION",
                f"episode used {actual} tokens, above {threshold}% of the comparable-task median {median}",
                f"basis=historical_median task={args.task} samples={len(comparable)} actual={actual} median={median}",
            )

    repeated = integer(latest.get("repeated_source_reads"))
    source_bytes = integer(latest.get("source_read_bytes"))
    if repeated >= 2:
        emit(
            "CONTEXT_AMPLIFICATION",
            f"episode repeated {repeated} source-evidence commands instead of reusing compiled context",
            f"task={args.task} repeated_source_reads={repeated} source_read_bytes={source_bytes}",
        )
    return 0


def decomposition(args: argparse.Namespace) -> int:
    dag = {row.get("node_id", ""): row for row in rows(args.dag)}
    report = {row.get("node_id", ""): row for row in rows(args.complexity)}
    found = False
    for node, child in dag.items():
        parent_id = child.get("parent_id", "")
        if not node or parent_id in ("", "-") or parent_id not in dag:
            continue
        child_report = report.get(node, {})
        parent_report = report.get(parent_id, {})
        if not child_report or not parent_report:
            continue
        dimensions = {
            "obligations": (integer(child_report.get("obligations")), integer(parent_report.get("obligations"))),
            "complexity_score": (integer(child_report.get("complexity_score")), integer(parent_report.get("complexity_score"))),
            "context_entries": (
                integer(child_report.get("allowed_paths")) + integer(child_report.get("required_symbols")),
                integer(parent_report.get("allowed_paths")) + integer(parent_report.get("required_symbols")),
            ),
            "effective_p95_tokens": (
                integer(child_report.get("effective_p95_tokens")),
                integer(parent_report.get("effective_p95_tokens")),
            ),
        }
        # A child is useful when at least one measured boundary strictly shrinks.
        # If all stay equal or grow, decomposition only renamed the parent cost.
        if all(child_value >= parent_value for child_value, parent_value in dimensions.values()):
            found = True
            evidence = " ".join(
                f"{name}={child_value}/{parent_value}"
                for name, (child_value, parent_value) in dimensions.items()
            )
            emit(
                "NON_SHRINKING_DECOMPOSITION",
                f"child {node} does not shrink any measured boundary from parent {parent_id}",
                f"child={node} parent={parent_id} {evidence}",
            )
    return 1 if found else 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    ep = commands.add_parser("episode")
    ep.add_argument("--observations", type=Path, required=True)
    ep.add_argument("--task", required=True)
    ep.add_argument("--outcomes", type=Path)
    ep.add_argument("--regression-percent", type=int, required=True)
    ep.add_argument("--min-samples", type=int, required=True)
    ep.set_defaults(run=episode)
    decomp = commands.add_parser("decomposition")
    decomp.add_argument("--dag", type=Path, required=True)
    decomp.add_argument("--complexity", type=Path, required=True)
    decomp.set_defaults(run=decomposition)
    return root


def main() -> int:
    args = parser().parse_args()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
