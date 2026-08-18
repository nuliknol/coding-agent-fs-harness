"""Provider-neutral architecture evidence records."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib


def stable_id(*parts: str) -> str:
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


@dataclass(frozen=True, order=True)
class Module:
    module_id: str
    name: str
    path: str
    kind: str
    authority: str = "DERIVED"
    provider: str = "unknown"


@dataclass(frozen=True, order=True)
class Dependency:
    source: str
    target: str
    kind: str
    evidence_count: int = 1
    provider: str = "unknown"


@dataclass(frozen=True, order=True)
class ConceptOwner:
    concept: str
    owner_kind: str
    owner_id: str
    evidence: str
    authority: str = "DERIVED"
    provider: str = "unknown"


@dataclass(frozen=True, order=True)
class PublicInterface:
    symbol: str
    kind: str
    path: str
    module_id: str
    authority: str = "DERIVED"
    provider: str = "unknown"


@dataclass(frozen=True, order=True)
class StateAccess:
    state_kind: str
    state_id: str
    module_id: str
    access: str
    evidence: str
    authority: str = "DERIVED"
    provider: str = "unknown"


@dataclass(frozen=True, order=True)
class TestRecord:
    name: str
    path: str
    build_target: str = "-"
    selector: str = "-"
    provider: str = "unknown"


@dataclass(frozen=True, order=True)
class Finding:
    kind: str
    severity: str
    subject: str
    evidence: str
    authority: str
    provider: str


@dataclass
class ArchitectureSnapshot:
    generation: str
    modules: set[Module] = field(default_factory=set)
    dependencies: set[Dependency] = field(default_factory=set)
    concept_owners: set[ConceptOwner] = field(default_factory=set)
    public_interfaces: set[PublicInterface] = field(default_factory=set)
    state_accesses: set[StateAccess] = field(default_factory=set)
    tests: set[TestRecord] = field(default_factory=set)
    findings: set[Finding] = field(default_factory=set)

    def merge(self, other: "ArchitectureSnapshot") -> None:
        if self.generation != other.generation:
            raise ValueError("cannot merge architecture snapshots from different generations")
        for name in (
            "modules", "dependencies", "concept_owners", "public_interfaces",
            "state_accesses", "tests", "findings",
        ):
            getattr(self, name).update(getattr(other, name))

