# Harness Architecture Rebuild Implementation Plan

Status: COMPLETED (2026-08-18)

## Objective

Implement the periodic architecture-rebuild protocol as a compatibility-preserving
harness capability and use its boundaries to reduce the harness's own reasoning
surface. The work must preserve existing task, manager, worker, repository-index,
and architecture-guard behavior while introducing explicit ownership, typed state
transitions, multi-language architecture evidence, and a resumable rebuild lifecycle.

## Governing principles

- Refactor incrementally; do not rewrite working behavior.
- Add characterization and architectural tests before migrating high-risk callers.
- Keep existing command-line entry points stable.
- Separate policy from mechanism and derived evidence from normative authority.
- Make every migration reversible until its callers and tests have moved.
- Treat rebuild proposals as advisory until an operator explicitly approves them.

## Phase 1 — Characterize and constrain

1. Record current module/source dependencies and high-churn entry points.
2. Add tests for atomic artifacts, legal state transitions, architecture findings,
   scorecard polarity, interrupted rebuild recovery, and compatibility facades.
3. Add architecture constraints preventing new direct state-file writers in migrated
   subsystems and preventing dependency reversal across the new module boundaries.

## Phase 2 — Modular state and configuration foundation

Introduce narrow libraries with one responsibility each:

```text
lib/harness-config.sh
lib/harness-artifact-store.sh
lib/harness-task-state.sh
lib/harness-rebuild.sh
```

The artifact store owns validated key/value records, atomic replacement, append-only
ledgers, fingerprints, and transition compare-and-swap. The task-state module owns
legal task/root states and their transition vocabulary. Existing helpers remain as
compatibility facades while callers migrate.

## Phase 3 — Architecture evidence providers

Replace the monolithic normalizer with an importable architecture package:

```text
tools/architecture/model.py
tools/architecture/providers/sqlite_provider.py
tools/architecture/providers/bash_provider.py
tools/architecture/inference.py
tools/architecture/benchmarks.py
tools/architecture/scorecard.py
```

The Bash provider records scripts, sourced libraries, function definitions/calls,
command dependencies, configuration references, and state-path reads/writes. Provider
facts retain authority and provenance. Concept ownership must not be inferred merely
from equal symbol display names. `ownership-map.tsv` and `concept-owner-map.tsv` must
have distinct schemas and meanings.

## Phase 4 — Unified architecture lifecycle

Define explicit namespaces:

```text
architecture/registry     normative invariants, decisions, edges, gates, debt
architecture/evidence     immutable derived implementation observations
architecture/rebuild      operator-approved rebuild runs and comparisons
```

Add a rebuild coordinator with these durable phases:

```text
OBSERVE -> DIAGNOSE -> DESIGN -> BASELINE -> REFACTOR -> RECOMPUTE ->
COMPARE -> AWAITING_APPROVAL -> ACCEPTED
```

Any phase may transition to `FAILED`; a failed or interrupted invocation must be
resumable without losing the last accepted phase. Each run records scope, trigger,
source revision, before/after evidence generations, scorecards, benchmark set,
behavioral baseline, target design, migration ledger, comparison, approval, and debt.

## Phase 5 — Repository-index services

Separate repository-index responsibilities into identity, providers, generation
construction, verification/publication, pointer refresh, and retention. Keep
`harness-index-repository` as a thin compatibility entry point. Add a source-only
architecture provider path so repositories dominated by Bash/Python can produce
architecture evidence without pretending to have a C/C++ compilation database.

## Phase 6 — Execution-path decomposition

Extract bounded policy interfaces from:

- `manager-publish-task`: assignment parsing, recovery normalization, authority
  validation, criterion changes, and atomic publication;
- `worker-invoke-task`: admission, prompt construction, invocation, ACP handling,
  trusted patch validation, and result publication;
- `harness-supervisor`: event polling, index maintenance, review scheduling,
  dependency processing, recovery scheduling, capacity scheduling, and completion.

The initial migration moves coherent policy and transition operations behind narrow
interfaces without changing the established command entry points.

## Phase 7 — Metrics and acceptance

1. Version scorecard schemas and finding-policy configuration.
2. Give every metric a direction (`LOWER`, `HIGHER`, or `INFORMATIONAL`) and threshold.
3. Compare benchmark sets only when their identity matches.
4. Fail rebuild acceptance on newly introduced cycles, ambiguous normative ownership,
   cross-subsystem mutation, forbidden dependencies, benchmark recall regression, or
   excessive context/search-breadth regression.
5. Generate the required architecture rebuild report and remaining-debt ledger.

## Verification

- Shell syntax and ShellCheck-compatible source boundaries.
- Python unit tests for every provider, transition, scorecard, and coordinator phase.
- Existing repository-index, architecture guard/redesign, ACP parallel, root liveness,
  supervisor barrier, and full harness regression suites.
- End-to-end source-only Bash architecture index and interrupted rebuild resume test.
- Before/after architecture scorecard comparison for this repository.

## Completion criteria

- Existing commands and tests remain compatible.
- Periodic scorecard generation emits a durable rebuild-candidate event.
- A separate operator-approved command can create, advance, resume, compare, and
  accept a rebuild run.
- The harness can generate meaningful architecture evidence for its own Bash code.
- High-risk execution paths use the typed artifact/transition interface.
- The rebuild report identifies remaining debt and the reason it was deferred.

## Implementation result

All phases above are implemented behind the existing command entry points.

- Configuration trust, canonical project/task layout, typed atomic artifacts,
  task-domain validation, assignment publication, worker routing, index generation,
  provider ledgers, supervisor ordering, and rebuild transitions now have explicit
  module owners under `lib/`.
- Architecture evidence is provider-based (`SQLite/SCIP`, optional Joern, Bash,
  and Python), with provider-neutral records, graph inference, navigation
  benchmarks, versioned scorecards, explicit direction/threshold policy, and
  benchmark-safe comparison.
- Source-only Bash/Python repositories can use architecture index, benchmark, and
  scorecard commands without a compilation database.
- Rebuild runs are compare-and-swap state machines with failure/resume support,
  clean-source evidence capture, canonical target/baseline/migration/approval
  artifacts, explicit operator acceptance, a mandatory report, and remaining-debt
  ledger.
- Periodic scorecards record durable rebuild-candidate events but never mutate the
  normative architecture registry.
- Repository-index construction/publication and supervisor cycle ordering are
  separated from their compatibility commands. Manager assignment publication and
  worker execution policy use the new bounded interfaces.
- Module-boundary, primitive, provider, scorecard, lifecycle, CLI, interrupted
  recovery, repository-index, ACP parallel, and existing harness regression tests
  cover the migrated boundaries.

## Measured acceptance

The retained before/after evidence is under `work/architecture-evidence/` and the
benchmark definition is `work/architecture-navigation-benchmarks.tsv`.

```text
comparison_status: PASS
navigation_recall_percent: 0.0 -> 100.0
context_bytes_per_query: 38167.875 -> 4869.25
ambiguous_state_owners: 174 -> 173
architecture_debt_score: 782 -> 779
cycles: 1 -> 1
ambiguous_owners: 0 -> 0
```

The accepted remaining debt is deliberately visible rather than hidden: the large
legacy compatibility facades still contain behavior not yet worth moving without a
specific change driver, one pre-existing module cycle remains, and source inference
still reports many historical direct state writers. The new periodic lifecycle is
the mechanism for addressing those items incrementally with measured before/after
evidence.
