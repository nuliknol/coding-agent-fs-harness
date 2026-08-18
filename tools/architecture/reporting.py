"""Stable report serialization for architecture snapshots."""

from __future__ import annotations

import csv
import json
from pathlib import Path

from .model import ArchitectureSnapshot


def write_tsv(path: Path, columns: tuple[str, ...], records) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(columns)
        writer.writerows(records)


def write_snapshot(output: Path, snapshot: ArchitectureSnapshot) -> None:
    output.mkdir(parents=True, exist_ok=True)
    write_tsv(output / "responsibility-map.tsv",
              ("module_id", "module", "path", "basis", "authority", "provider"),
              ((m.module_id, m.name, m.path, m.kind, m.authority, m.provider)
               for m in sorted(snapshot.modules)))
    write_tsv(output / "dependency-map.tsv",
              ("source_module", "target_module", "edge_kind", "evidence_count", "provider"),
              ((d.source, d.target, d.kind, d.evidence_count, d.provider)
               for d in sorted(snapshot.dependencies)))
    write_tsv(output / "ownership-map.tsv",
              ("state_kind", "state_id", "owner_module", "access", "evidence", "authority", "provider"),
              ((s.state_kind, s.state_id, s.module_id, s.access, s.evidence, s.authority, s.provider)
               for s in sorted(snapshot.state_accesses)))
    write_tsv(output / "public-interface-map.tsv",
              ("symbol", "kind", "path", "module", "authority", "provider"),
              ((p.symbol, p.kind, p.path, p.module_id, p.authority, p.provider)
               for p in sorted(snapshot.public_interfaces)))
    write_tsv(output / "test-map.tsv", ("test", "path", "build_target", "selector", "provider"),
              ((t.name, t.path, t.build_target, t.selector, t.provider)
               for t in sorted(snapshot.tests)))
    write_tsv(output / "concept-owner-map.tsv",
              ("concept", "owner_kind", "owner_id", "evidence", "authority", "provider"),
              ((c.concept, c.owner_kind, c.owner_id, c.evidence, c.authority, c.provider)
               for c in sorted(snapshot.concept_owners)))
    write_tsv(output / "findings.tsv",
              ("finding_kind", "severity", "subject", "evidence", "authority", "provider"),
              ((f.kind, f.severity, f.subject, f.evidence, f.authority, f.provider)
               for f in sorted(snapshot.findings)))
    summary = {
        "schema_version": 2,
        "generation": snapshot.generation,
        "modules": len(snapshot.modules),
        "module_edges": len(snapshot.dependencies),
        "concepts": len({c.concept for c in snapshot.concept_owners}),
        "public_interfaces": len(snapshot.public_interfaces),
        "state_accesses": len(snapshot.state_accesses),
        "tests": len(snapshot.tests),
        "findings": len(snapshot.findings),
        "cycles": sum(f.kind == "MODULE_CYCLE" for f in snapshot.findings),
        "ambiguous_owners": sum(f.kind == "AMBIGUOUS_CONCEPT_OWNER" for f in snapshot.findings),
    }
    (output / "summary.json").write_text(
        json.dumps(summary, sort_keys=True, indent=2) + "\n", encoding="utf-8")

