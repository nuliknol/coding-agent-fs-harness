#!/usr/bin/env python3

"""Compile the bounded evidence surface consumed by architecture-fit review."""

from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
from pathlib import Path
import re


BOUNDARY_WORDS = re.compile(
    r"\b(architect|atomic|compatib|concurr|contract|depend|invariant|lifetime|"
    r"migrat|observ|ownership|public[ -]?api|resource|serializ|state|transaction)\w*\b",
    re.IGNORECASE,
)
BOUNDARY_TYPES = {
    "COMPATIBILITY", "CONTRACT", "INTEGRATION", "INVARIANT", "PERFORMANCE",
    "RESOURCE_LIFETIME",
}
BOUNDARY_RELATIONS = {
    "CONSUMES", "DEPENDS_ON", "FINAL_HEALTH_DEPENDENCY", "OWNS", "PRESERVES",
    "PRODUCES", "REGRESSION_BOUNDARY", "REQUIRES_ACCEPTED",
}
BOUNDARY_FACT_KINDS = {
    "BUILD_TARGET", "CONSUMER", "DEPENDENCY", "EXISTING_BEHAVIOR", "PATH",
    "PRODUCER", "PUBLIC_CONTRACT", "SYMBOL", "TEST_TARGET",
}
SLICE_SECTIONS = {
    "## Architecture findings requiring targeted verification",
    "## Build ownership",
    "## Derived module graph",
    "### Module dependencies",
    "## Evidence-provider coverage",
    "## Focused test map",
    "## Public interface candidates",
}
LOCATION = re.compile(r"^([^:,;]+):([1-9][0-9]*)$")


def sha256(path: Path | None) -> str:
    if path is None or not path.is_file():
        return "none"
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def optional_path(value: str | None) -> Path | None:
    if not value or value in ("-", "NONE"):
        return None
    return Path(value)


def one_line(value: object, maximum: int = 240) -> str:
    text = " ".join(str(value or "-").replace("\t", " ").split()) or "-"
    encoded = text.encode("utf-8")
    if len(encoded) <= maximum:
        return text
    return encoded[: maximum - 3].decode("utf-8", errors="ignore") + "..."


def read_tsv(path: Path, required: set[str]) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        fields = set(reader.fieldnames or [])
        missing = required.difference(fields)
        if missing:
            raise ValueError(f"{path} lacks fields: {','.join(sorted(missing))}")
        return list(reader)


def review_excerpt(path: Path | None) -> list[str]:
    if path is None:
        return []
    selected: list[str] = []
    active = False
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw.startswith("## "):
            active = raw in {"## Review summary", "## Repository grounding", "## Conclusion"}
            if active:
                selected.append(raw)
            continue
        if active and raw.strip():
            selected.append(one_line(raw, 300))
        if len(selected) >= 24:
            break
    return selected


def authority_excerpt(paths: list[Path]) -> list[str]:
    selected: list[str] = []
    for path in paths:
        selected.append(f"### `{path.name}` (sha256={sha256(path)})")
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if raw.strip():
                selected.append(one_line(raw, 320))
            if len(selected) >= 48:
                return selected
    return selected


def architecture_slice_excerpt(path: Path | None) -> list[str]:
    if path is None or not path.is_file():
        return ["- No current indexed architecture slice was available."]
    buckets: dict[str, list[str]] = {heading: [] for heading in SLICE_SECTIONS}
    active = ""
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw.startswith("##"):
            active = raw if raw in SLICE_SECTIONS else ""
            continue
        if active and raw.strip():
            limit = 8 if active == "## Architecture findings requiring targeted verification" else 5
            if len(buckets[active]) < limit:
                buckets[active].append(one_line(raw, 260))
    selected: list[str] = []
    for heading in (
        "## Architecture findings requiring targeted verification",
        "## Build ownership",
        "## Derived module graph",
        "### Module dependencies",
        "## Public interface candidates",
        "## Focused test map",
        "## Evidence-provider coverage",
    ):
        if buckets[heading]:
            selected.extend((heading, *buckets[heading]))
    return selected or ["- The current slice contains no selected architecture boundary facts."]


def evidence_locations(rows: list[dict[str, str]], selected_obligations: list[dict[str, str]]) -> list[str]:
    candidates: set[str] = set()
    for row in selected_obligations:
        candidates.update(re.split(r"[,;]", row.get("source_location", "")))
    for row in rows:
        if row.get("authority") != "OBSERVED":
            continue
        candidates.update(re.split(r"[,;]", row.get("evidence", "")))
    return sorted(value.strip() for value in candidates if value.strip())


def source_excerpts(repository: Path, locations: list[str]) -> list[str]:
    excerpts: list[str] = []
    root = repository.resolve()
    for location in locations:
        match = LOCATION.fullmatch(location)
        if not match:
            continue
        relative, line_text = match.groups()
        candidate = (root / relative).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            continue
        if not candidate.is_file():
            continue
        wanted = int(line_text)
        text = ""
        with candidate.open(encoding="utf-8", errors="replace") as stream:
            for number, raw in enumerate(stream, 1):
                if number == wanted:
                    text = one_line(raw, 420)
                    break
        if text:
            excerpts.append(f"- `{relative}:{wanted}`: {text}")
        if len(excerpts) >= 24:
            break
    return excerpts or ["- No exact repository source line was selected from accepted evidence coordinates."]


def section(title: str, lines: list[str]) -> list[str]:
    return ["", title, "", *lines]


def bounded_section(title: str, lines: list[str], maximum_bytes: int) -> list[str]:
    result = ["", title, ""]
    marker = f"- [{title.lstrip('#').strip()} truncated at section budget]"
    for line in lines:
        if len("\n".join([*result, line, ""]).encode("utf-8")) > maximum_bytes:
            if len("\n".join([*result, marker, ""]).encode("utf-8")) <= maximum_bytes:
                result.append(marker)
            break
        result.append(line)
    return result


def append_bounded(output: list[str], lines: list[str], maximum_bytes: int, marker: str) -> None:
    for line in lines:
        candidate = "\n".join([*output, line, ""]).encode("utf-8")
        if len(candidate) > maximum_bytes:
            marker_line = f"- [{marker} truncated at capsule byte ceiling]"
            if len("\n".join([*output, marker_line, ""]).encode("utf-8")) <= maximum_bytes:
                output.append(marker_line)
            return
        output.append(line)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--specification-sha256", required=True)
    parser.add_argument("--repository-baseline", required=True)
    parser.add_argument("--domain-profiles-sha256", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--review-report", required=True)
    parser.add_argument("--facts", required=True)
    parser.add_argument("--obligations", required=True)
    parser.add_argument("--relations", required=True)
    parser.add_argument("--architecture-slice")
    parser.add_argument("--purpose", choices=("architecture-fit", "decomposition", "architecture-binding"),
                        default="architecture-fit")
    parser.add_argument("--authority-file", action="append", default=[])
    parser.add_argument("--dag")
    parser.add_argument("--coverage")
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-bytes", required=True, type=int)
    args = parser.parse_args()
    if args.max_bytes < 8192:
        raise ValueError("--max-bytes must be at least 8192")

    repository = Path(args.repository)
    report_path = optional_path(args.review_report)
    facts_path = optional_path(args.facts)
    obligations_path = optional_path(args.obligations)
    relations_path = optional_path(args.relations)
    slice_path = Path(args.architecture_slice) if args.architecture_slice else None
    authority_paths = [Path(value) for value in args.authority_file]
    dag_path = Path(args.dag) if args.dag else None
    coverage_path = Path(args.coverage) if args.coverage else None
    if args.purpose == "architecture-binding" and (
            dag_path is None or coverage_path is None or not dag_path.is_file() or not coverage_path.is_file()):
        raise ValueError("architecture-binding purpose requires existing --dag and --coverage files")
    obligations = read_tsv(obligations_path, {
        "obligation_id", "authority", "source_requirement", "source_location",
        "obligation_type", "statement", "observable_outcome", "acceptance_authority",
    }) if obligations_path is not None else []
    relations = read_tsv(relations_path, {
        "relation_id", "relation_type", "subject", "object", "authority", "evidence",
    }) if relations_path is not None else []
    facts = read_tsv(facts_path, {
        "fact_id", "kind", "subject", "value", "evidence", "authority", "confidence",
    }) if facts_path is not None else []
    obligations.sort(key=lambda row: row["obligation_id"])
    relations.sort(key=lambda row: row["relation_id"])
    facts.sort(key=lambda row: row["fact_id"])

    selected_obligations = [
        row for row in obligations
        if row.get("obligation_type") in BOUNDARY_TYPES
        or BOUNDARY_WORDS.search(" ".join((row.get("statement", ""), row.get("observable_outcome", ""))))
    ]
    selected_relations = [row for row in relations if row.get("relation_type") in BOUNDARY_RELATIONS]
    selected_facts = [row for row in facts if row.get("kind") in BOUNDARY_FACT_KINDS]

    capsule_title = {
        "architecture-fit": "# Deterministic Architecture-Fit Capsule",
        "decomposition": "# Deterministic Decomposition Capsule",
        "architecture-binding": "# Deterministic Architecture-Binding Capsule",
    }[args.purpose]
    lines = [
        capsule_title, "",
        f"Project: {one_line(args.project, 160)}",
        f"Specification-SHA256: {args.specification_sha256}",
        f"Repository-Baseline: {args.repository_baseline}",
        f"Domain-Profiles-SHA256: {args.domain_profiles_sha256}",
        f"Accepted-Review-SHA256: {sha256(report_path)}",
        f"Repository-Facts-SHA256: {sha256(facts_path)}",
        f"Obligations-SHA256: {sha256(obligations_path)}",
        f"Relations-SHA256: {sha256(relations_path)}",
        f"Architecture-Slice-SHA256: {sha256(slice_path)}", "",
        f"DAG-SHA256: {sha256(dag_path)}",
        f"Coverage-SHA256: {sha256(coverage_path)}", "",
        f"Purpose: {args.purpose}",
        "This capsule is compiled evidence. Specification authority outranks "
        "observed and derived repository evidence. Absence from an inferred index is UNKNOWN, not proof of absence.",
        f"Counts: obligations={len(obligations)} relations={len(relations)} facts={len(facts)} "
        f"boundary-obligations={len(selected_obligations)} boundary-relations={len(selected_relations)}.",
    ]
    lines += section("## Decision boundary", [
        "Evaluate ownership, transaction, dependency direction, migration, contract authority, observability, "
        "critical invariants, and resource lifetime only from the compiled evidence below.",
        "Open one exact repository source window only when a decisive fact remains unresolved and the capsule names its path.",
    ])
    mandatory = section("## Complete normalized obligation projection", [
        f"- `{one_line(row['obligation_id'], 100)}` | {one_line(row['authority'], 24)}/"
        f"{one_line(row['obligation_type'], 32)} | {one_line(row['statement'], 120)} "
        f"=> {one_line(row['observable_outcome'], 80)} | `{one_line(row['source_location'], 80)}`"
        for row in obligations
    ] or ["- NONE"])
    mandatory_bytes = len("\n".join([*lines, *mandatory, ""]).encode("utf-8"))
    if mandatory_bytes > args.max_bytes - 7000:
        raise ValueError(
            f"complete normalized obligation projection leaves less than 7000 bytes for architecture evidence "
            f"({mandatory_bytes}/{args.max_bytes})"
        )
    lines.extend(mandatory)

    relation_counts = Counter(row["relation_type"] for row in relations)
    if args.purpose in {"decomposition", "architecture-binding"}:
        complete_relations = section("## Complete normalized typed relation projection", [
            f"- `{one_line(row['relation_id'], 90)}` | {one_line(row['relation_type'], 40)} | "
            f"`{one_line(row['subject'], 90)}` -> `{one_line(row['object'], 120)}` | "
            f"{one_line(row['authority'], 32)} | {one_line(row['evidence'], 120)}"
            for row in relations
        ] or ["- NONE"])
        complete_bytes = len("\n".join([*lines, *complete_relations, ""]).encode("utf-8"))
        if complete_bytes > args.max_bytes - 12000:
            raise ValueError(
                f"complete normalized IR projection leaves less than 12000 bytes for repository evidence "
                f"({complete_bytes}/{args.max_bytes})"
            )
        lines.extend(complete_relations)
    else:
        detail = bounded_section("## Normalized architecture relation projection", [
            "- Relation counts: " + ", ".join(f"{kind}={relation_counts[kind]}" for kind in sorted(relation_counts)),
            *[
            f"- `{one_line(row['relation_id'], 90)}`: {one_line(row['relation_type'], 40)} "
            f"`{one_line(row['subject'], 90)}` -> `{one_line(row['object'], 120)}`; "
            f"authority={one_line(row['authority'], 32)}; evidence={one_line(row['evidence'], 140)}"
            for row in selected_relations
            ],
        ], 3000)
        append_bounded(lines, detail, args.max_bytes, "architecture relation projection")
    if args.purpose == "architecture-binding":
        fixed_graph = section("## Complete fixed decomposition DAG", [
            "```tsv", *dag_path.read_text(encoding="utf-8", errors="replace").splitlines(), "```",
            "", "## Complete fixed specification coverage", "",
            "```tsv", *coverage_path.read_text(encoding="utf-8", errors="replace").splitlines(), "```",
        ])
        fixed_bytes = len("\n".join([*lines, *fixed_graph, ""]).encode("utf-8"))
        if fixed_bytes > args.max_bytes - 10000:
            raise ValueError(
                f"complete fixed DAG/coverage leaves less than 10000 bytes for architecture evidence "
                f"({fixed_bytes}/{args.max_bytes})"
            )
        lines.extend(fixed_graph)
    detail = bounded_section("## Accepted repository facts", [
        f"- `{one_line(row['fact_id'], 100)}` [{one_line(row['kind'], 40)}/{one_line(row['authority'], 40)}]: "
        f"{one_line(row['subject'], 140)} = {one_line(row['value'], 260)}; evidence={one_line(row['evidence'], 180)}"
        for row in selected_facts
    ] or ["- NONE"], 3000)
    append_bounded(lines, detail, args.max_bytes, "accepted repository facts")
    append_bounded(lines, bounded_section("## Exact selected source evidence", source_excerpts(
        repository, evidence_locations(facts, selected_obligations)), 2500), args.max_bytes, "source evidence")
    append_bounded(lines, bounded_section("## Indexed architecture facts", architecture_slice_excerpt(slice_path), 5000),
                   args.max_bytes, "indexed architecture facts")
    append_bounded(lines, bounded_section("## Accepted review conclusions", review_excerpt(report_path) or ["- NONE"], 1800),
                   args.max_bytes, "accepted review conclusions")
    if authority_paths:
        append_bounded(lines, bounded_section("## Accepted architecture decisions",
                                              authority_excerpt(authority_paths), 4000),
                       args.max_bytes, "accepted architecture decisions")

    output = Path(args.output)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if output.stat().st_size > args.max_bytes:
        raise AssertionError("compiled evidence capsule exceeded its byte ceiling")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"compiled evidence capsule: {error}", file=__import__("sys").stderr)
        raise SystemExit(2)
