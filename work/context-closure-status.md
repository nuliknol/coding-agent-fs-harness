# Context Closure Implementation Status

Last updated (UTC): 2026-08-17T04:08:00Z

Overall status: `COMPLETE`

Active phase: `PRODUCTION ENFORCEMENT — selected active projects`

Active milestone: `Rebuild selected project indexes and enforce compiled Luna contexts`

Deployment state: `5.17.3 candidate; defaults remain off, selected projects are operator-promoted to required index and patch-only closure`

Commit: `5eb60c3` (production-enforcement corrections), following the original `bba8e609f575a159e254d50f7b308dce737e87ce` implementation

## Production-enforcement corrections

- Corrected SCIP test ownership so only callable non-local definitions in test
  translation units become tests. Local variables, fixtures, constants, and
  type definitions can no longer inflate one source file into thousands of
  independent tests.
- Corrected normative architecture projection so descriptive invariant scopes
  remain authority text instead of becoming false missing filesystem paths.
- Made directory context entries bounded evidence scopes: an exact symbol or
  file seed must select structural evidence inside the directory; the compiler
  no longer dumps every descendant file.
- Stopped generic SCIP references from becoming required structural
  dependencies. Required type/interface edges still close to a fixed point,
  while direct Joern callers/callees remain bounded supporting evidence.
- Kept external SDK/toolchain headers hash-addressed in closure provenance
  without embedding recursive SDK contents in every worker prompt. Generated
  project headers remain embedded and fail closed when they exceed the route
  budget.
- Added real-tool and focused regression coverage for test cardinality,
  descriptive architecture scopes, bounded directory seeds, and external SDK
  prerequisites.
- Restored legacy/spec-review-disabled decomposition capsule construction by
  treating `-` authority placeholders as absent inputs rather than filenames.
- Escaped literal bounded-read examples in all interpolated Sol/reviewer
  prompts so prompt construction cannot execute `head` and wait on stdin.
- Selected running projects are intentionally promoted by the operator after
  deployment. Non-ready Luna leaves must return to deterministic Sol
  decomposition; they must not fall back to repository exploration.
- Included the harness release, environment, shared runtime, and manager-review
  invoker in the durable review fingerprint. A corrected deployment now makes
  a preserved `REVIEW_STALLED` result eligible for one fresh review instead of
  retaining a suppression decision made by obsolete harness code.

## Completed since previous update

- Advanced the repository schema to version 5 with provider-run,
  diagnostics, mutation, architecture-finding, and navigation-benchmark
  records.
- Added recursive generated/external include discovery, compile-unit
  diagnostics for sources omitted by SCIP, real Joern call/control/data-flow
  and mutation ingestion, and optional deterministic Recoll normalization.
- Added crash reconciliation, immutable-generation retention, provider/tool
  provenance, and safe-boundary index refresh after accepted checkpoints.
- Added deterministic architecture normalization, responsibility/dependency/
  ownership/interface/test/concept maps, cycle/fan-out/ownership/firewall
  findings, project-local normative projection, navigation benchmarks,
  scorecards, redesign proposals, and before/after scorecard comparison.
- Enforced conflicting-configuration, required-flow-provider, architecture
  binding, stale-index, unresolved-symbol, and route-budget failures in Context
  Closure.
- Added required and patch-only Luna admission. A non-ready closure now returns
  a deterministic decomposition handoff before model launch; patch-only workers
  run without repository tools and their single Git diff is checked for
  baseline, syntax, scope, file count, binary/build outputs, and symlinks before
  focused validation and controlled commit.
- Added closure promotion, learned model/leaf-type p95 prediction, outlier, and
  systematic-omission reports. Observation records now retain both executing
  model and decomposition-model attribution plus the actual leaf type.
- Expanded the real fixture with recursive generated headers, C++ overloads,
  an optional HIP compilation unit, and real Joern graph evidence. Added
  focused negative tests for configuration ambiguity, absent Joern flow,
  unauthorized patches, and normative-versus-derived authority.

- Inventoried the existing bounded context capsules, decomposition metadata,
  complexity observations/outcomes, repository inventory, and worker prompt
  boundaries.
- Added a model-free `harness-context-baseline` command that summarizes
  historical capsule bytes, worker episodes, actions, command output, source
  reads, repeated reads, processed tokens, and outcomes.
- Defined the immutable repository-index identity, freshness, provenance,
  locking, quarantine, integrity, and atomic-publication contracts.
- Added canonical SQLite schema version 2, including structural graph,
  architecture authority, tests/build targets, fact provenance, and FTS5
  lexical tables.
- Added disabled-by-default repository-index and Context Closure environment
  settings and validation.
- Implemented shared, revision/configuration/toolchain-addressed index lifecycle:
  build, reuse, inspect, invalidate, quarantine failed generations, and atomic
  project pointer publication.
- Added deterministic compilation-database normalization. Null optional fields
  are omitted because real `scip-clang` rejects JSON null values.
- Implemented a Go SCIP importer using generated protobuf bindings and
  document-at-a-time streaming. It imports files, source regions, symbols,
  definitions, references, relationship edges, tests, lexical units, provider
  provenance, and language metadata transactionally.
- Retained `scip lint` findings as index-quality evidence without treating
  optional local-symbol metadata omissions from `scip-clang 0.4.0` as a corrupt
  protobuf.
- Implemented the first deterministic Context Closure compiler. It accepts an
  explicit assignment, existing task/capsule, or DAG node; resolves exact SCIP
  symbols; includes definitions, interface/test references, direct structural
  dependencies, and manager-declared context paths; and writes context,
  item/edge, graph-cut, authority, unresolved, quality, and manifest artifacts.
- Added typed closure outcomes: `READY`, `INCOMPLETE`, and
  `NEEDS_FURTHER_DECOMPOSITION` for unresolved authority or exceeded byte,
  symbol, module, and estimated-token budgets.
- Added stale-index rejection for changed tracked source, committed revision,
  compilation database, `scip-clang`, or SCIP CLI.
- Added architecture query, closure inspection, item provenance (`--why`), and
  closure-check commands.
- Projected exact registered architecture invariants, decisions, edge contracts,
  health gates, and allocated specification records into the closure. Their
  scopes, evidence artifacts, and public interfaces contribute typed structural
  seeds; unknown registered IDs make the closure incomplete.
- Added bounded structural expansion: direct behavioral references remain
  one-hop, while required type/interface relationships expand to a deterministic
  fixed point. Fan-out and symbol-budget cuts are written to `graph-cut.tsv` and
  return `NEEDS_FURTHER_DECOMPOSITION` rather than silently truncating context.
- Strengthened immutable generation identity and freshness with the compiled
  importer binary hash and schema content hash. Schema version 2 records both,
  preventing reuse after ingestion semantics change even when source and
  compilation commands are unchanged.
- Added deterministic bounded C/C++ structural-region extraction for SCIP
  producers that expose identifier-only enclosing ranges. Closures now include
  complete function/declaration/macro bodies while respecting comments, quoted
  delimiters, balanced braces, and byte ceilings.
- Added test-to-symbol edges and full focused-test regions, so behavioral
  evidence is selected as a test unit rather than only the call-site line.
- Integrated `READY` closures into worker prompts when
  `HARNESS_CONTEXT_CLOSURE_MODE=advisory`. Missing, stale, incomplete, or
  oversized closures are logged and cannot block or broaden the worker.
  Machine-readable outcomes are appended to `logs/context-closure-events.tsv`.
- Documented the foundation and explicitly kept worker integration advisory and
  disabled.
- Advanced the canonical schema to version 3 and imported compilation-unit
  ownership from normalized `compile_commands.json`: CMake target names,
  translation-unit fallbacks, source-to-target mappings, object paths,
  configuration provenance, and nearest build definitions.
- Added exact build-target, ownership-boundary, focused-test, and structural
  relationship measurements and configurable Context Closure budgets.
- Added `build-targets.tsv`, `ownership-boundaries.tsv`, and deterministic
  `suggested-cuts.tsv` artifacts. Suggested child boundaries name cohesive
  build-target or source-root seams, exact paths/symbols, validation hints,
  measured source bytes, and a route hint.
- Added decomposition-wide dry-run admission. Every proposed Luna row can now
  be compiled against the current index before worker launch, producing a
  per-node `admission.tsv` and aggregate suggested cuts.
- Added a deterministic repository architecture slice containing build
  ownership, source roots, public-interface candidates, high-fanout symbols,
  and focused-test mappings. New-project startup builds/reuses the index and
  supplies this bounded slice to Sol before DAG construction.
- Connected Context Closure evidence to recursive Sol repair. When available,
  Sol receives exact non-ready dimensions and suggested graph seams rather than
  only declarative complexity estimates.
- Added advisory context-usage comparison after each worker invocation. It
  records closure paths observed by commands/file-change events, unused
  candidates, repository paths discovered outside the closure, and changed
  paths outside the closure without treating transcript absence as proof.
- Correlated advisory path-usage reports with independent manager outcomes and
  exposed reviewed used/unused/missing/changed-outside totals through
  `harness-context-baseline`. Unreviewed worker episodes cannot influence these
  quality totals.
- Expanded the real-tool fixture to C++17 and verified namespace-qualified
  overloads, type-bearing interfaces, complete overloaded function bodies,
  focused C++ tests, and CMake build-owner mapping. The deterministic
  architecture slice now derives public-interface candidates from both
  declarations/references and definitions while filtering local-symbol noise.
- Updated completed checkboxes in the working plan so the plan and mandatory
  status record agree on delivered lifecycle, ingestion, closure, graph-aware
  decomposition, advisory telemetry, and observed-complexity work.
- Advanced the schema to version 4 and added deterministic direct
  compilation-input discovery. Generated/external headers resolved through
  compilation-command include paths are hashed into generation identity,
  mapped to build targets, rechecked for freshness, and embedded as bounded
  read-only closure prerequisites even when SCIP omits them.
- Added a generated-CMake-header fixture proving that changing an external
  generated header invalidates the project pointer and that an unchanged
  generated macro reaches the self-contained worker context.

## Files/components changed

- Runtime/configuration: `lib/harness-common.sh`, `bin/harness-check-env`,
  `examples/project.env.example`
- Index lifecycle: `lib/harness-repository-index.sh`,
  `bin/harness-index-repository`, `bin/harness-index-status`,
  `bin/harness-index-invalidate`, `bin/harness-build-index-tools`
- Canonical contracts: `formats/repository-index-contract.md`,
  `formats/repository-index-schema.sql`
- Build ownership/input ingestion: `tools/scan_compile_inputs.py`,
  `tools/import_compile_commands.py`
- SCIP ingestion: `tools/go.mod`, `tools/go.sum`,
  `tools/cmd/harness-scip-importer/main.go`
- Closure/query tools: `tools/context_closure.py`,
  `bin/harness-build-context-closure`, `bin/harness-show-context-closure`,
  `bin/harness-context-closure-check`, `bin/harness-query-architecture`,
  `bin/harness-context-baseline`
- Advisory precision/recall telemetry: `tools/analyze_context_usage.py`,
  `bin/harness-context-closure-usage`, `bin/worker-invoke-task`
- Graph-aware decomposition: `tools/evaluate_decomposition_context.py`,
  `bin/harness-evaluate-decomposition-context`,
  `tools/export_architecture_slice.py`,
  `bin/harness-export-architecture-slice`, `bin/harness-start`,
  `bin/manager-decomposition-critic`, `bin/manager-stage-decomposition-dag`,
  `bin/manager-submit-decomposition`,
  `bin/manager-decomposition-dag-repair`
- Tests/fixtures: `tests/test-repository-index.sh`,
  `tests/test-scip-importer.sh`, `tests/fixtures/context-index-c/`
- Go structural-region unit tests:
  `tools/cmd/harness-scip-importer/main_test.go`
- Documentation: `README.md`, `docs/context-closure.md`

## Tests

Passed:

```text
go test ./...
bash tests/test-repository-index.sh
bash tests/test-scip-importer.sh
bash tests/test-decomposition-v2.sh
bash tests/test-architecture-guards.sh
bash tests/test-harness.sh
bash tests/test-leaf-goal.sh
bash tests/test-root-liveness.sh
bash tests/test-active-plan-revision.sh
bash tests/test-specification-review.sh
git diff --check
```

The schema-v5 provider/architecture milestone passed Go tests, the real SCIP integration test,
repository lifecycle test, decomposition-v2 test, architecture-guard test,
root-liveness test, active-plan-revision test, leaf-goal test,
specification-review test, SQL schema initialization, shell syntax checks,
`git diff --check`, and the complete harness regression suite. The full harness
suite reported `All v4.4 harness tests passed.`

`test-decomposition-v2.sh` retains two pre-existing awk diagnostics but exits
successfully. The real-tool integration test also covers recursive generated
inputs, C++ overloads, an indexed HIP compile unit, real Joern call/control/
data-flow and mutation evidence, absent-provider degradation, project-local
normative projection, navigation benchmarks, scorecards, and required-mode
pre-launch rejection. Focused tests cover Recoll overlays, configuration
ambiguity, flow-provider failure, systematic omission remediation,
model/leaf-type predictions, promotion thresholds, unauthorized patches, and
baseline cost comparison.

## Measurements

Real C fixture using `scip-clang 0.4.0`, SCIP CLI `0.9.0`, and SQLite `3.45.1`:

```text
SCIP documents imported:       7
Repository files imported:     7
Symbols imported:             35
Definitions imported:         36
References imported:          32
Skipped documents:             0
Malformed import residue:      0 rows
Build targets inferred:        6
Build/source mappings:         6
Generated build inputs:        2 (recursive)
Dry-run Luna rows evaluated:   1 fixture row (`READY`)
```

Two projects with the same repository revision and compilation configuration
reuse one immutable generation. A distinct compiler configuration produces a
distinct generation. An indexing failure preserves the prior pointer.

## Blockers and risks

- No implementation blocker remains. `scip-clang 0.4.0` can emit nonzero lint
  for optional local-symbol metadata; this stays visible as provider-quality
  evidence while malformed protobuf and database integrity remain fatal.
- Suggested graph cuts identify reproducible structural seams; Sol still owns
  the semantic proof that every child preserves an independently complete
  acceptance boundary.
- Required and patch-only modes are implemented and tested, but remain an
  operator promotion decision. Production defaults stay `off`; real projects
  should collect reviewed advisory samples before promotion.
- Deployment must not stop active harnesses, rebuild active DAGs, or change
  existing environment files. Installing disabled-by-default binaries is the
  only rollout in this phase.

## Next concrete action

No implementation action remains. Select new projects for advisory mode,
collect reviewed outcomes, and use the promotion report before enabling
required or patch-only mode.

## Update history

| UTC date | Phase | Status | Summary |
|---|---|---|---|
| 2026-08-16 | Phase 0 | PLANNED | Initial implementation plan and status protocol created. |
| 2026-08-16T18:37:08Z | Phase 0 | PLANNED | Deferred ideas recorded separately; active scope unchanged. |
| 2026-08-16T19:15:39Z | Phases 0/1/2/4 foundation | IN_PROGRESS | Added crash-safe SCIP/SQLite repository indexing, baseline metrics, exact architecture queries, and the first deterministic bounded Context Closure compiler with real-tool tests. |
| 2026-08-16T19:23:59Z | Phases 1/4 | IN_PROGRESS | Added normative architecture projection, bounded structural fixed-point expansion with explicit graph cuts, and importer/schema-addressed generation identity. |
| 2026-08-16T19:32:20Z | Phases 2/6 | IN_PROGRESS | Added full bounded C/C++ regions, focused test linkage, and non-blocking advisory closure embedding with event telemetry. |
| 2026-08-16T19:48:23Z | Phases 3/5/6 | IN_PROGRESS | Added schema-v3 build ownership, ownership/resource bounds, actionable graph seams, repository architecture slices, per-Luna dry-run admission, and Sol repair feedback. |
| 2026-08-16T19:51:23Z | Phase 6 | IN_PROGRESS | Added non-blocking per-invocation used/unused/missing Context Closure path telemetry. |
| 2026-08-16T19:55:07Z | Phases 5/6 | IN_PROGRESS | Correlated Context Closure usage with manager outcomes and completed the full regression matrix. |
| 2026-08-16T19:59:01Z | Phases 0/2/3 | IN_PROGRESS | Added C++17 overload/type/test coverage and refined deterministic architecture interface mapping. |
| 2026-08-16T20:04:28Z | Phases 1/2/4 | IN_PROGRESS | Added schema-v4 direct generated-input hashing, build ownership, freshness invalidation, and bounded closure embedding. |
| 2026-08-16T20:07:12Z | Phases 1/2/4/6 | IN_PROGRESS | Re-ran static, real-tool, architecture, liveness, specification, decomposition, and complete harness regressions after schema v4; all passed. |
| 2026-08-16T21:00:44Z | Phases 7/8/9/10 | IN_PROGRESS | Added enforced/patch-only closure, learned admission, provider overlays, normative projection, scorecards, complete fixtures, and rollout documentation; final post-change regression remains. |
| 2026-08-16T21:08:08Z | Phase 10 | QUALIFIED_PENDING_DEPLOYMENT | All Go and shell suites, real SCIP/Joern/HIP integration, focused Python tests, syntax checks, and diff checks passed; production is clean and active environments inherit disabled defaults. |
| 2026-08-16T21:09:47Z | Phase 10 | QUALIFIED_PENDING_DEPLOYMENT | Initial fast-forward exposed missing importer `--version`; added stable schema-v5 provenance output and passed Go, real-tool, lifecycle, focused, and diff checks. |
| 2026-08-16T21:10:22Z | Phase 10 | COMPLETE | Version 5.17.1 is synchronized across development, remote main, and production; importer provenance and all four active environments verified, modes remain off, and no active supervisor or DAG was restarted. |
