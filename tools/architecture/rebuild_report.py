"""Generate the durable report and remaining-debt ledger for an accepted rebuild."""

from __future__ import annotations

import csv
from pathlib import Path
import subprocess


RECOMMENDATIONS = {
    "MODULE_CYCLE": "Break the cycle through a directed public contract.",
    "AMBIGUOUS_CONCEPT_OWNER": "Assign one normative owner and route consumers through it.",
    "AMBIGUOUS_STATE_OWNER": "Move mutation behind one typed transition owner.",
    "CROSS_SUBSYSTEM_WRITE": "Route mutation through the owning subsystem interface.",
    "HIGH_FANOUT_MODULE": "Split responsibilities or introduce a stable facade.",
    "REASONING_FIREWALL_CANDIDATE": "Register and test a compact consumer contract.",
    "LARGE_MODULE": "Separate responsibilities that change for different reasons.",
    "DIRECT_STATE_ARTIFACT_WRITE": "Use the typed artifact store for durable mutation.",
}


def read_kv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def read_tsv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def scorecard(path: Path) -> dict[str, str]:
    return {row.get("metric", ""): row.get("value", "-") for row in read_tsv(path)}


def changed_files(repository: Path, source_revision: str) -> list[str]:
    if not source_revision or source_revision == "-":
        return []
    result = subprocess.run(
        ["git", "-C", str(repository), "diff", "--name-only", source_revision, "HEAD", "--"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    return sorted(line for line in result.stdout.splitlines() if line)


def integer(metrics: dict[str, str], key: str) -> int:
    try:
        return int(float(metrics.get(key, "0")))
    except ValueError:
        return 0


def generate(run_dir: Path, repository: Path, status_override: str | None = None) -> tuple[Path, Path]:
    state = read_kv(run_dir / "state.env")
    if status_override:
        state["status"] = status_override
    before = scorecard(run_dir / "before/scorecard.tsv")
    after = scorecard(run_dir / "after/scorecard.tsv")
    before_findings = read_tsv(run_dir / "before/maps/findings.tsv")
    after_findings = read_tsv(run_dir / "after/maps/findings.tsv")
    files = changed_files(repository, state.get("source_revision", "-"))

    debt_path = run_dir / "remaining-debt.tsv"
    with debt_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("debt_id", "finding_kind", "priority", "subject", "reason_not_addressed", "suggested_action"))
        for index, finding in enumerate(after_findings, 1):
            kind = finding.get("finding_kind", "UNKNOWN")
            writer.writerow((f"AR-{index:04d}", kind, finding.get("severity", "INFO"),
                             finding.get("subject", "-"), "Remains in the accepted after-snapshot.",
                             RECOMMENDATIONS.get(kind, "Review and assign an explicit owner.")))

    metric_pairs = [
        ("Ambiguous ownership", "ambiguous_owners"),
        ("Ambiguous state ownership", "ambiguous_state_owners"),
        ("Module cycles", "cycles"),
        ("Cross-subsystem writes", "cross_subsystem_writes"),
        ("Oversized modules", "large_modules"),
        ("Direct state writers", "direct_state_writers"),
        ("Architecture debt score", "architecture_debt_score"),
    ]
    lines = [
        "# Architecture Rebuild Report", "", f"Rebuild-ID: {state.get('rebuild_id', '-')}",
        f"Status: {state.get('status', '-')}", "", "## Scope", "",
        f"Subsystems analyzed: {state.get('scope', '-')}",
        f"Subsystems modified: {state.get('scope', '-') if files else 'None recorded'}",
        "Files modified: " + (", ".join(files) if files else "None between the recorded source revision and accepted HEAD"),
        "", "## Problems discovered", "",
        f"Initial reproducible findings: {len(before_findings)}",
        f"Initial architecture debt score: {before.get('architecture_debt_score', '-')}",
        "Reasoning cost: measured through ownership ambiguity, search breadth, context bytes, fan-out, and module size.",
        "Operational risk: critical regressions are rejected by the direction-aware comparison gate.",
        "", "## Changes performed", "",
        "Architectural change: See `target-architecture.md` and `migration-ledger.tsv` in this run.",
        "Old structure: `before/maps/` and `before/scorecard.tsv`.",
        "New structure: `after/maps/` and `after/scorecard.tsv`.",
        f"Reason: {state.get('trigger', '-')}", "", "## Reasoning-index improvements", "",
    ]
    for label, metric in metric_pairs:
        old, new = integer(before, metric), integer(after, metric)
        lines.append(f"- {label}: {old} -> {new} ({old - new:+d} removed)" if old >= new
                     else f"- {label}: {old} -> {new} ({new - old} introduced)")
    lines.extend((
        "", "## Complexity-decomposition improvements", "",
        "Responsibilities separated: captured by the responsibility and dependency maps.",
        "State ownership clarified: captured by the ownership map and ambiguous-state-owner metric.",
        "Pipelines introduced: captured by the target architecture and migration ledger.",
        "Contracts introduced: captured by the public-interface and concept-owner maps.",
        "", "## Module-level improvements", "",
        f"Oversized modules decomposed: {max(0, integer(before, 'large_modules') - integer(after, 'large_modules'))}",
        "Public interfaces reduced: compare `before/maps/public-interface-map.tsv` with the after map.",
        "Duplicated semantics removed: compare concept-owner ambiguity before and after.",
        "Control flow simplified: compare cycles and dependency edges before and after.",
        "Dead abstractions removed: recorded in the operator-supplied migration ledger.",
        "", "## Verification", "",
        "Tests run: recorded in `behavioral-baseline.md` and `migration-ledger.tsv`.",
        "Tests added: recorded in the migration ledger.",
        "Architectural constraints checked: direction-aware scorecard comparison passed.",
        "Performance checks: benchmark identity and recall/context gates were compared when present.",
        "", "## Remaining architectural debt", "",
        f"Known issues: {len(after_findings)} reproducible findings remain.",
        "Reason not addressed: each item remains in the accepted after-snapshot.",
        "Priority: preserved from provider severity.",
        "Suggested future action: see `remaining-debt.tsv`.", "",
        "## Evidence", "",
        "- `state.env` and `transitions.tsv` — durable lifecycle authority",
        "- `before/` and `after/` — immutable derived evidence and scorecards",
        "- `comparison.tsv` — acceptance gate result",
        "- `approval.md` — explicit operator approval",
        "- `remaining-debt.tsv` — deferred architecture work", "",
    ))
    report_path = run_dir / "architecture-rebuild-report.md"
    report_path.write_text("\n".join(lines), encoding="utf-8")
    return report_path, debt_path
