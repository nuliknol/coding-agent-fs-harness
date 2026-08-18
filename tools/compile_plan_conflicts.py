#!/usr/bin/env python3

"""Compile a durable conservative conflict graph for parallel plan nodes."""

from __future__ import annotations

import argparse
import csv
from itertools import combinations
from pathlib import Path


def split(value: str) -> set[str]:
    return {part.strip() for part in value.split(",") if part.strip() not in {"", "-"}}


def path_overlap(left: str, right: str) -> bool:
    left, right = left.rstrip("/"), right.rstrip("/")
    return left == right or left.startswith(right + "/") or right.startswith(left + "/")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", required=True)
    parser.add_argument("--capabilities", required=True)
    parser.add_argument("--architecture-bindings")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    with Path(args.plan).open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    capability_rows: list[dict[str, str]] = []
    capability_file = Path(args.capabilities)
    if capability_file.exists():
        with capability_file.open(encoding="utf-8", newline="") as stream:
            capability_rows = list(csv.DictReader(stream, delimiter="\t"))
    capabilities: dict[str, dict[str, list[tuple[int, int, str]]]] = {}
    for row in capability_rows:
        capabilities.setdefault(row["node_id"], {}).setdefault(row["repository_path"], []).append(
            (int(row["start_line"]), int(row["end_line"]), row["symbol"]))
    bindings: dict[str, dict[str, set[str]]] = {}
    binding_path = Path(args.architecture_bindings) if args.architecture_bindings else None
    if binding_path and binding_path.exists():
        with binding_path.open(encoding="utf-8", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                bindings[row["node_id"]] = {key: split(value) for key, value in row.items()
                                             if key != "node_id" and value is not None}

    conflicts: list[tuple[str, str, str]] = []
    for left, right in combinations(rows, 2):
        left_id, right_id = left["node_id"], right["node_id"]
        reasons: set[str] = set()
        left_paths, right_paths = split(left.get("allowed_paths", "-")), split(right.get("allowed_paths", "-"))
        for left_path in left_paths:
            for right_path in right_paths:
                if not path_overlap(left_path, right_path):
                    continue
                if left_path == right_path and left_path in capabilities.get(left_id, {}) and \
                        right_path in capabilities.get(right_id, {}):
                    overlap = False
                    for lstart, lend, _ in capabilities[left_id][left_path]:
                        for rstart, rend, _ in capabilities[right_id][right_path]:
                            overlap |= not (lend < rstart or rend < lstart)
                    if not overlap:
                        continue
                reasons.add(f"path:{left_path}:{right_path}")
        shared_symbols = split(left.get("required_symbols", "-")) & split(right.get("required_symbols", "-"))
        reasons.update(f"symbol:{symbol}" for symbol in shared_symbols)
        left_bind, right_bind = bindings.get(left_id, {}), bindings.get(right_id, {})
        for field in ("produces_decisions", "edge_contracts", "health_gates"):
            for identity in left_bind.get(field, set()) & right_bind.get(field, set()):
                reasons.add(f"architecture:{field}:{identity}")
        for identity in left_bind.get("produces_decisions", set()) & right_bind.get("consumes_decisions", set()):
            reasons.add(f"architecture:producer-consumer:{identity}")
        for identity in right_bind.get("produces_decisions", set()) & left_bind.get("consumes_decisions", set()):
            reasons.add(f"architecture:producer-consumer:{identity}")
        if reasons:
            conflicts.append((left_id, right_id, ";".join(sorted(reasons))))
    with Path(args.output).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(["left_node", "right_node", "reasons"])
        writer.writerows(conflicts)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
