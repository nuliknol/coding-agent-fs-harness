"""Provider-neutral architecture degradation inference."""

from __future__ import annotations

from collections import defaultdict

from .graph import strongly_connected
from .model import ArchitectureSnapshot, Finding


def infer_findings(snapshot: ArchitectureSnapshot, high_fanout: int = 20) -> None:
    owners: dict[str, set[str]] = defaultdict(set)
    for owner in snapshot.concept_owners:
        owners[owner.concept].add(owner.owner_id)
    for concept, module_ids in sorted(owners.items()):
        if len(module_ids) > 1:
            snapshot.findings.add(Finding(
                "AMBIGUOUS_CONCEPT_OWNER", "HIGH", concept, ",".join(sorted(module_ids)),
                "DERIVED", "architecture-inference",
            ))

    graph: dict[str, set[str]] = defaultdict(set)
    for edge in snapshot.dependencies:
        graph[edge.source].add(edge.target)
    for component in strongly_connected(graph):
        snapshot.findings.add(Finding(
            "MODULE_CYCLE", "HIGH", component[0], ",".join(component),
            "DERIVED", "architecture-inference",
        ))
    for source, targets in sorted(graph.items()):
        if len(targets) >= high_fanout:
            snapshot.findings.add(Finding(
                "HIGH_FANOUT_MODULE", "MEDIUM", source,
                f"fanout={len(targets)} targets={','.join(sorted(targets))}",
                "DERIVED", "architecture-inference",
            ))

    incoming: dict[str, set[str]] = defaultdict(set)
    for source, targets in graph.items():
        for target in targets:
            incoming[target].add(source)
    public_modules = {interface.module_id for interface in snapshot.public_interfaces}
    for target, sources in sorted(incoming.items()):
        if len(sources) >= max(5, high_fanout // 2) and target not in public_modules:
            snapshot.findings.add(Finding(
                "REASONING_FIREWALL_CANDIDATE", "LOW", target,
                f"inbound_dependents={len(sources)} sources={','.join(sorted(sources))}",
                "DERIVED", "architecture-inference",
            ))

    state_writers: dict[tuple[str, str], set[str]] = defaultdict(set)
    state_evidence: dict[tuple[str, str], list[str]] = defaultdict(list)
    for access in snapshot.state_accesses:
        if access.access == "WRITE":
            key = (access.state_kind, access.state_id)
            state_writers[key].add(access.module_id)
            state_evidence[key].append(access.evidence)
    for (kind, state_id), module_ids in sorted(state_writers.items()):
        if len(module_ids) > 1:
            snapshot.findings.add(Finding(
                "AMBIGUOUS_STATE_OWNER", "HIGH", f"{kind}:{state_id}",
                f"writers={','.join(sorted(module_ids))} evidence={','.join(sorted(state_evidence[(kind, state_id)]))}",
                "DERIVED", "architecture-inference",
            ))

    module_paths = {module.module_id: module.path for module in snapshot.modules}
    direct_writers: dict[str, list[str]] = defaultdict(list)
    for access in snapshot.state_accesses:
        if access.access == "WRITE" and access.state_kind == "PROJECT_ARTIFACT":
            path = module_paths.get(access.module_id, "-")
            if path != "lib/harness-artifact-store.sh":
                direct_writers[access.module_id].append(access.evidence)
    for module_id, evidence in sorted(direct_writers.items()):
        snapshot.findings.add(Finding(
            "DIRECT_STATE_ARTIFACT_WRITE", "LOW", module_id,
            f"path={module_paths.get(module_id, '-')} evidence={','.join(sorted(set(evidence)))}",
            "DERIVED", "architecture-inference",
        ))
