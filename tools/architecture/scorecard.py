"""Versioned architecture scorecards and advisory rebuild proposals."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import sqlite3


SCHEMA_VERSION = 2
METRIC_DIRECTIONS = {
    "schema_version": "INFORMATIONAL", "generation": "INFORMATIONAL",
    "benchmark_set_sha256": "INFORMATIONAL", "modules": "INFORMATIONAL",
    "module_edges": "LOWER", "cycles": "LOWER", "ambiguous_owners": "LOWER",
    "ambiguous_state_owners": "LOWER", "high_fanout": "LOWER",
    "reasoning_firewall_candidates": "LOWER", "cross_subsystem_writes": "LOWER",
    "large_modules": "LOWER", "direct_state_writers": "LOWER",
    "benchmark_queries": "INFORMATIONAL", "navigation_recall_percent": "HIGHER",
    "navigation_precision_percent": "HIGHER", "search_breadth_paths_per_query": "LOWER",
    "context_bytes_per_query": "LOWER", "architecture_debt_score": "LOWER",
    "status": "INFORMATIONAL",
}
METRIC_THRESHOLDS = {
    "schema_version": "-", "generation": "-", "benchmark_set_sha256": "-",
    # Modular extraction intentionally makes previously implicit dependency
    # edges visible. A rebuild may add up to 100 edges while reducing measured
    # debt; larger jumps require explicit review.
    "modules": "-", "module_edges": "100", "cycles": "0", "ambiguous_owners": "0",
    "ambiguous_state_owners": "0", "high_fanout": "0",
    "reasoning_firewall_candidates": "5", "cross_subsystem_writes": "0",
    # Moving an existing writer into its own owner can increase the number of
    # writer modules by one without introducing a new write site.
    "large_modules": "0", "direct_state_writers": "1", "benchmark_queries": "-",
    "navigation_recall_percent": "1", "navigation_precision_percent": "2",
    "search_breadth_paths_per_query": "1", "context_bytes_per_query": "10%",
    "architecture_debt_score": "0", "status": "-",
}
FINDING_WEIGHTS = {
    "MODULE_CYCLE": 5, "AMBIGUOUS_CONCEPT_OWNER": 4, "AMBIGUOUS_STATE_OWNER": 4,
    "CROSS_SUBSYSTEM_WRITE": 4, "HIGH_FANOUT_MODULE": 2,
    "REASONING_FIREWALL_CANDIDATE": 1, "LARGE_MODULE": 1,
    "DIRECT_STATE_ARTIFACT_WRITE": 1,
}
RECOMMENDATIONS = {
    "MODULE_CYCLE": "Introduce or restore a directed public contract that breaks the cited module cycle.",
    "AMBIGUOUS_CONCEPT_OWNER": "Assign one normative concept owner and make other modules consume its public interface.",
    "AMBIGUOUS_STATE_OWNER": "Move state mutation behind one typed transition owner.",
    "HIGH_FANOUT_MODULE": "Split responsibility or add a stable facade to bound dependency fan-out.",
    "CROSS_SUBSYSTEM_WRITE": "Move mutation behind the owning subsystem's explicit transaction/interface boundary.",
    "REASONING_FIREWALL_CANDIDATE": "Register and test a compact contract so consumers need not inspect private implementation.",
    "LARGE_MODULE": "Separate responsibilities that change for different reasons behind narrow interfaces.",
    "DIRECT_STATE_ARTIFACT_WRITE": "Route durable state mutation through the typed artifact store.",
}


def _read_tsv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def _benchmark_metrics(path: Path | None) -> tuple[dict[str, float | int | str], str]:
    relevant = expected = returned = context_bytes = 0
    rows = _read_tsv(path) if path else []
    identity = hashlib.sha256()
    for row in rows:
        relevant += int(row.get("relevant_returned", "0"))
        expected += int(row.get("expected_total", "0"))
        returned += int(row.get("returned_total", "0"))
        context_bytes += int(row.get("context_bytes", "0"))
        identity.update((row.get("benchmark_id", "") + "\0" + row.get("query", "") + "\0" +
                         row.get("expected_paths", "") + "\0").encode())
    count = len(rows)
    metrics: dict[str, float | int | str] = {
        "benchmark_queries": count,
        "navigation_recall_percent": 100.0 if expected == 0 else relevant * 100.0 / expected,
        "navigation_precision_percent": 100.0 if returned == 0 else relevant * 100.0 / returned,
        "search_breadth_paths_per_query": 0.0 if count == 0 else returned / count,
        "context_bytes_per_query": 0.0 if count == 0 else context_bytes / count,
    }
    return metrics, ("sha256:" + identity.hexdigest() if rows else "-")


def from_maps(maps: Path, generation: str, benchmarks: Path | None = None):
    summary = json.loads((maps / "summary.json").read_text(encoding="utf-8"))
    findings = _read_tsv(maps / "findings.tsv")
    counts: dict[str, int] = {}
    for finding in findings:
        kind = finding.get("finding_kind", "")
        counts[kind] = counts.get(kind, 0) + 1
    metrics: dict[str, float | int | str] = {
        "schema_version": SCHEMA_VERSION, "generation": generation,
        "modules": int(summary.get("modules", 0)), "module_edges": int(summary.get("module_edges", 0)),
        "cycles": counts.get("MODULE_CYCLE", 0),
        "ambiguous_owners": counts.get("AMBIGUOUS_CONCEPT_OWNER", 0),
        "ambiguous_state_owners": counts.get("AMBIGUOUS_STATE_OWNER", 0),
        "high_fanout": counts.get("HIGH_FANOUT_MODULE", 0),
        "reasoning_firewall_candidates": counts.get("REASONING_FIREWALL_CANDIDATE", 0),
        "cross_subsystem_writes": counts.get("CROSS_SUBSYSTEM_WRITE", 0),
        "large_modules": counts.get("LARGE_MODULE", 0),
        "direct_state_writers": counts.get("DIRECT_STATE_ARTIFACT_WRITE", 0),
    }
    benchmark_metrics, benchmark_hash = _benchmark_metrics(benchmarks)
    metrics["benchmark_set_sha256"] = benchmark_hash
    metrics.update(benchmark_metrics)
    return _finalize(metrics, findings)


def from_database(database: Path, generation: str, benchmarks: Path | None = None):
    connection = sqlite3.connect(database)
    try:
        modules = int(connection.execute("SELECT count(*) FROM modules WHERE generation_id=?", (generation,)).fetchone()[0])
        edges = int(connection.execute("""SELECT count(*) FROM module_edges e
            JOIN modules m ON m.module_id=e.source_module_id WHERE m.generation_id=?""", (generation,)).fetchone()[0])
        rows = connection.execute("""SELECT finding_kind,severity,subject_id,evidence,authority,provider
            FROM architecture_findings WHERE generation_id=? ORDER BY severity,finding_kind,subject_id""",
                                  (generation,)).fetchall()
    finally:
        connection.close()
    findings = [{"finding_kind": row[0], "severity": row[1], "subject": row[2],
                 "evidence": row[3], "authority": row[4], "provider": row[5]} for row in rows]
    counts: dict[str, int] = {}
    for finding in findings:
        kind = finding["finding_kind"]
        counts[kind] = counts.get(kind, 0) + 1
    metrics: dict[str, float | int | str] = {
        "schema_version": SCHEMA_VERSION, "generation": generation, "modules": modules,
        "module_edges": edges, "cycles": counts.get("MODULE_CYCLE", 0),
        "ambiguous_owners": counts.get("AMBIGUOUS_CONCEPT_OWNER", 0),
        "ambiguous_state_owners": counts.get("AMBIGUOUS_STATE_OWNER", 0),
        "high_fanout": counts.get("HIGH_FANOUT_MODULE", 0),
        "reasoning_firewall_candidates": counts.get("REASONING_FIREWALL_CANDIDATE", 0),
        "cross_subsystem_writes": counts.get("CROSS_SUBSYSTEM_WRITE", 0),
        "large_modules": counts.get("LARGE_MODULE", 0),
        "direct_state_writers": counts.get("DIRECT_STATE_ARTIFACT_WRITE", 0),
    }
    benchmark_metrics, benchmark_hash = _benchmark_metrics(benchmarks)
    metrics["benchmark_set_sha256"] = benchmark_hash
    metrics.update(benchmark_metrics)
    return _finalize(metrics, findings)


def _finalize(metrics, findings):
    debt = sum(FINDING_WEIGHTS.get(finding.get("finding_kind", ""), 0) for finding in findings)
    metrics["architecture_debt_score"] = debt
    metrics["status"] = "REBUILD_CANDIDATE" if debt >= 10 else "OBSERVE" if debt else "HEALTHY"
    return metrics, findings


def write_scorecard(output: Path, proposal: Path, metrics, findings) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("metric", "value", "direction", "regression_threshold"))
        writer.writerows((key, value, METRIC_DIRECTIONS.get(key, "INFORMATIONAL"),
                          METRIC_THRESHOLDS.get(key, "-")) for key, value in metrics.items())
    lines = ["# Architecture Rebuild Proposal", "", f"Generation: {metrics['generation']}",
             f"Decision: {metrics['status']}", "", "This report is advisory. It does not modify production source or architecture authority.",
             "", "## Measured architecture health", ""]
    lines.extend(f"- {key}: {value}" for key, value in metrics.items())
    lines.extend(("", "## Reproducible findings", ""))
    if findings:
        lines.extend(f"- [{row.get('severity','-')}] {row.get('finding_kind','-')} `{row.get('subject',row.get('subject_id','-'))}`: "
                     f"{row.get('evidence','-')} ({row.get('authority','-')}, {row.get('provider','-')})" for row in findings)
    else:
        lines.append("No indexed degradation findings.")
    lines.extend(("", "## Recommended redesign requirements", ""))
    kinds = sorted({row.get("finding_kind", "") for row in findings})
    recommendations = [RECOMMENDATIONS[kind] for kind in kinds if kind in RECOMMENDATIONS]
    lines.extend(f"- {item}" for item in recommendations)
    if not recommendations:
        lines.append("No redesign harness is currently recommended.")
    lines.extend(("", "Run a separate operator-approved rebuild before changing normative architecture. Compare a new scorecard against this generation afterward.", ""))
    proposal.write_text("\n".join(lines), encoding="utf-8")
