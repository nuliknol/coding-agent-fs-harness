#!/usr/bin/env python3

"""Generate evidence-backed architecture health and redesign proposals."""

import argparse
import csv
import json
from pathlib import Path
import sqlite3


def scalar(connection: sqlite3.Connection, query: str) -> int:
    return int(connection.execute(query).fetchone()[0])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--proposal", required=True)
    parser.add_argument("--benchmarks")
    args = parser.parse_args()
    connection = sqlite3.connect(args.database)
    generation = args.generation.replace("'", "''")
    metrics: dict[str, float | int | str] = {}
    metrics["generation"] = args.generation
    metrics["modules"] = scalar(connection, f"SELECT count(*) FROM modules WHERE generation_id='{generation}'")
    metrics["module_edges"] = scalar(connection, "SELECT count(*) FROM module_edges")
    metrics["cycles"] = scalar(connection, f"SELECT count(*) FROM architecture_findings WHERE generation_id='{generation}' AND finding_kind='MODULE_CYCLE'")
    metrics["ambiguous_owners"] = scalar(connection, f"SELECT count(*) FROM architecture_findings WHERE generation_id='{generation}' AND finding_kind='AMBIGUOUS_CONCEPT_OWNER'")
    metrics["high_fanout"] = scalar(connection, f"SELECT count(*) FROM architecture_findings WHERE generation_id='{generation}' AND finding_kind='HIGH_FANOUT_MODULE'")
    metrics["reasoning_firewall_candidates"] = scalar(connection, f"SELECT count(*) FROM architecture_findings WHERE generation_id='{generation}' AND finding_kind='REASONING_FIREWALL_CANDIDATE'")
    metrics["cross_subsystem_writes"] = scalar(connection, f"SELECT count(*) FROM architecture_findings WHERE generation_id='{generation}' AND finding_kind='CROSS_SUBSYSTEM_WRITE'")
    relevant = expected = returned = context_bytes = benchmark_count = 0
    if args.benchmarks and Path(args.benchmarks).is_file():
        with Path(args.benchmarks).open(encoding="utf-8", errors="replace", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                relevant += int(row.get("relevant_returned", "0"))
                expected += int(row.get("expected_total", "0"))
                returned += int(row.get("returned_total", "0"))
                context_bytes += int(row.get("context_bytes", "0"))
                benchmark_count += 1
    metrics["benchmark_queries"] = benchmark_count
    metrics["navigation_recall_percent"] = 100.0 if expected == 0 else relevant * 100.0 / expected
    metrics["navigation_precision_percent"] = 100.0 if returned == 0 else relevant * 100.0 / returned
    metrics["search_breadth_paths_per_query"] = 0.0 if benchmark_count == 0 else returned / benchmark_count
    metrics["context_bytes_per_query"] = 0.0 if benchmark_count == 0 else context_bytes / benchmark_count
    debt_score = (int(metrics["cycles"]) * 5 + int(metrics["ambiguous_owners"]) * 4 +
                  int(metrics["cross_subsystem_writes"]) * 4 + int(metrics["high_fanout"]) * 2 +
                  int(metrics["reasoning_firewall_candidates"]))
    metrics["architecture_debt_score"] = debt_score
    metrics["status"] = "REBUILD_CANDIDATE" if debt_score >= 10 else "OBSERVE" if debt_score else "HEALTHY"
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("metric", "value"))
        writer.writerows(metrics.items())
    findings = connection.execute(
        "SELECT finding_kind,severity,subject_id,evidence,authority,provider FROM architecture_findings WHERE generation_id=? ORDER BY severity,finding_kind,subject_id",
        (args.generation,)).fetchall()
    proposal = Path(args.proposal)
    lines = ["# Architecture Rebuild Proposal", "", f"Generation: {args.generation}",
             f"Decision: {metrics['status']}", "",
             "This report is advisory. It does not modify production source or architecture authority.", "",
             "## Measured architecture health", ""]
    lines.extend(f"- {key}: {value}" for key, value in metrics.items() if key not in {"generation", "status"})
    lines.extend(("", "## Reproducible findings", ""))
    if findings:
        lines.extend(f"- [{severity}] {kind} `{subject}`: {evidence} ({authority}, {provider})"
                     for kind, severity, subject, evidence, authority, provider in findings)
    else:
        lines.append("No indexed degradation findings.")
    lines.extend(("", "## Recommended redesign requirements", ""))
    recommendations = {
        "MODULE_CYCLE": "Introduce or restore a directed public contract that breaks the cited module cycle.",
        "AMBIGUOUS_CONCEPT_OWNER": "Assign one normative concept owner and make other modules consume its public interface.",
        "HIGH_FANOUT_MODULE": "Split responsibility or add a stable facade to bound dependency fan-out.",
        "CROSS_SUBSYSTEM_WRITE": "Move mutation behind the owning subsystem's explicit transaction/interface boundary.",
        "REASONING_FIREWALL_CANDIDATE": "Register and test a compact contract so consumers need not inspect private implementation.",
    }
    kinds = sorted({row[0] for row in findings})
    lines.extend(f"- {recommendations[kind]}" for kind in kinds if kind in recommendations)
    if not kinds:
        lines.append("No redesign harness is currently recommended.")
    lines.extend(("", "Run a separate operator-approved redesign harness before changing normative architecture. Compare a new scorecard against this generation afterward.", ""))
    proposal.write_text("\n".join(lines), encoding="utf-8")
    connection.close()


if __name__ == "__main__":
    main()
