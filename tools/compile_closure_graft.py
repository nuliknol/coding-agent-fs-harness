#!/usr/bin/env python3

"""Compile Context Closure graph cuts into an immutable child-criterion graft."""

import argparse
import csv
from pathlib import Path
import re
import sys


def metadata(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            result.setdefault(key, value)
    return result


def split_values(value: str) -> list[str]:
    return sorted({item.strip() for item in value.split(",")
                   if item.strip() not in {"", "-", "NONE"}})


def atomic_tsv(path: Path, fields: tuple[str, ...], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    temporary.chmod(0o600)
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assignment", required=True)
    parser.add_argument("--repair-children", required=True)
    parser.add_argument("--parent-criterion", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--facets-output", required=True)
    args = parser.parse_args()

    parent = args.parent_criterion.strip()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", parent):
        raise ValueError("invalid parent criterion identifier")
    with Path(args.repair_children).open(encoding="utf-8", errors="replace", newline="") as stream:
        children = list(csv.DictReader(stream, delimiter="\t"))
    children.sort(key=lambda row: (int(row.get("sequence", "0")), row.get("child_id", "")))
    if len(children) < 2:
        raise ValueError("a deterministic closure graft requires at least two repair children")

    assignment = metadata(Path(args.assignment))
    normative: list[tuple[str, str]] = []
    for key, kind in (
        ("Specification-Obligations", "SPECIFICATION_OBLIGATION"),
        ("Obligations", "SPECIFICATION_OBLIGATION"),
        ("Affected-Invariants", "ARCHITECTURE_INVARIANT"),
        ("Consumed-Decisions", "ARCHITECTURE_DECISION"),
        ("Produced-Decisions", "ARCHITECTURE_DECISION"),
        ("Edge-Contracts", "EDGE_CONTRACT"),
        ("Health-Gates", "HEALTH_GATE"),
    ):
        normative.extend((kind, value) for value in split_values(assignment.get(key, "")))
    normative = sorted(set(normative))
    if not normative:
        normative = [("PARENT_CRITERION", parent)]

    decomposition: list[dict[str, str]] = []
    facets: list[dict[str, str]] = []
    seen_ids: set[str] = set()
    for child in children:
        child_id = child.get("child_id", "")
        source_cut = child.get("source_cut", "")
        if child.get("status") != "PROPOSED":
            raise ValueError(f"repair child is not proposed: {child_id}")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", child_id):
            raise ValueError(f"invalid repair child identifier: {child_id}")
        criterion = f"{parent}.{child_id}"
        if criterion in seen_ids or not source_cut:
            raise ValueError("repair children must have unique criterion IDs and a source cut")
        seen_ids.add(criterion)
        paths = child.get("allowed_paths", "-")
        symbols = child.get("required_symbols", "-")
        seam = child.get("seam_kind", "SOURCE_SEAM")
        decomposition.append({
            "parent_criterion": parent,
            "child_criterion": criterion,
            "title": f"{seam} cut {source_cut}: {paths} [{symbols}]",
            "acceptance_evidence": child.get("acceptance_evidence", "-") or "-",
        })
        for kind, facet_id in normative:
            facets.append({
                "parent_criterion": parent,
                "child_criterion": criterion,
                "facet_kind": kind,
                "facet_id": facet_id,
                "relation": "PRESERVES",
                "source_cut": source_cut,
            })
        facets.append({
            "parent_criterion": parent,
            "child_criterion": criterion,
            "facet_kind": "IMPLEMENTATION_SEAM",
            "facet_id": child_id,
            "relation": "IMPLEMENTS",
            "source_cut": source_cut,
        })

    atomic_tsv(Path(args.output),
               ("parent_criterion", "child_criterion", "title", "acceptance_evidence"),
               decomposition)
    atomic_tsv(Path(args.facets_output),
               ("parent_criterion", "child_criterion", "facet_kind", "facet_id", "relation",
                "source_cut"), facets)
    print(f"children={len(decomposition)}\nnormative_facets={len(normative)}\n"
          f"decomposition={args.output}\nfacets={args.facets_output}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, csv.Error) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)
