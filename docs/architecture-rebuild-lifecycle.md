# Periodic Architecture Rebuild Lifecycle

The harness treats architecture as three different kinds of authority:

- **Registry** — operator-owned invariants, decisions, dependency edges, gates,
  bindings, and debt. Existing projects retain the compatible
  `control/architecture` registry layout.
- **Evidence** — immutable, provider-derived observations and scorecards. Evidence
  can inform a decision but cannot revise the registry.
- **Rebuild** — resumable operator-approved runs under
  `control/architecture/rebuild/`.

This separation is deliberate. A scorecard may create a rebuild-candidate event,
but no periodic or agent-driven command silently changes normative architecture.

## Source evidence

Repositories with Bash or Python source do not require a compilation database:

```bash
harness-architecture-index project.env --source-only
harness-architecture-benchmarks project.env queries.tsv --source-only
harness-architecture-scorecard project.env --source-only
```

The source providers record modules, sourcing/import dependencies, public
interfaces, concept ownership, configuration access, durable-state access, tests,
and reproducible findings. C/C++ projects can continue to use the SCIP/SQLite and
optional Joern provider path.

## Rebuild transaction

Begin a run from a clean tracked worktree:

```bash
harness-architecture-rebuild project.env begin SCOPE TRIGGER [BENCHMARKS_TSV]
```

`begin` captures the before maps and scorecard and advances the durable state to
`DESIGN`. Continue with explicit evidence at each boundary:

```bash
harness-architecture-rebuild project.env design REBUILD_ID target-architecture.md
harness-architecture-rebuild project.env baseline REBUILD_ID behavioral-baseline.md
harness-architecture-rebuild project.env refactor-complete REBUILD_ID migration-ledger.tsv
harness-architecture-rebuild project.env recompute REBUILD_ID
harness-architecture-rebuild project.env accept REBUILD_ID operator-approval.md
```

The lifecycle is:

```text
OBSERVE -> DIAGNOSE -> DESIGN -> BASELINE -> REFACTOR -> RECOMPUTE ->
COMPARE -> AWAITING_APPROVAL -> ACCEPTED
```

Any active phase can fail. `resume` returns a failed run to the failed phase without
discarding its accepted evidence:

```bash
harness-architecture-rebuild project.env fail REBUILD_ID EXPECTED evidence.md NOTE
harness-architecture-rebuild project.env resume REBUILD_ID
```

The compare gate is direction-aware and schema-versioned. It rejects newly
introduced cycles, ambiguous ownership, ambiguous state ownership,
cross-subsystem mutation, threshold-exceeding debt, benchmark recall loss, and
excessive context growth. Benchmark metrics are comparable only when their query
set identity matches.

Acceptance generates `architecture-rebuild-report.md` and
`remaining-debt.tsv`. The report points to the target design, behavioral baseline,
migration ledger, before/after evidence, comparison, approval, and deferred debt.

## Compatibility boundaries

Public command names remain stable. The large legacy shell entry points are
compatibility facades; narrow modules now own configuration trust, canonical
layout, typed artifacts, task transitions, assignment publication, worker routing,
index generation/provider ledgers, supervisor ordering, and rebuild transitions.
New durable writers should use `lib/harness-artifact-store.sh` rather than adding
ad hoc state-file replacement logic to command scripts.

