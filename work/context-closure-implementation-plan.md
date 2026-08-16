# Repository Architecture Index and Context Closure Implementation Plan

Status file: [`work/context-closure-status.md`](context-closure-status.md)

## 1. Objective

Extend the Full harness with a deterministic repository intelligence layer that
turns a decomposed plan leaf into a small, self-contained implementation
problem.

The target pipeline is:

```text
specification review
    -> specification IR
    -> repository architecture index
    -> Sol architecture/decomposition pass
    -> measured Luna-ready leaf
    -> Context Closure Compiler
    -> bounded worker context
    -> patch and deterministic validation
    -> observed-cost feedback
```

The main objective is better complexity decomposition. Repository navigation,
context construction, and worker execution are supporting mechanisms. Parallel
DAG execution is intentionally excluded: only one project-plan leaf remains
active at a time.

## 2. Design decisions

1. **SCIP is the authoritative structural source.** `scip-clang` supplies
   compiler-aware definitions, references, types, and symbol relationships from
   `compile_commands.json`.
2. **Joern is supplemental.** Its CPG supplies control-flow, data-flow, and
   mutation evidence where that evidence materially improves a closure. It is
   not required for every leaf.
3. **SQLite is the canonical local store.** Ordinary tables store graph and
   provenance records; FTS5 stores deterministic lexical evidence. Qdrant and
   embeddings are postponed.
4. **Recoll is an optional lexical provider.** It may improve candidate recall,
   but every selected record must be normalized into the SQLite schema with
   source coordinates and provenance. Context closure must remain functional
   without Recoll.
5. **The existing architecture registry remains normative.** Machine-derived
   facts describe implementation structure; they cannot silently override
   specification-owned invariants, decisions, edge contracts, or health gates.
6. **Context Closure is a compiler, not generic RAG.** It begins with typed
   seeds, expands approved dependency classes, records why every item entered
   the closure, and terminates at a fixed point or a declared resource boundary.
7. **Advisory precedes enforcement.** The index and compiler must demonstrate
   sufficient recall, reproducibility, and freshness before Luna workers are
   denied ordinary repository exploration.
8. **No naming collision with current closure mode.** Existing `CLOSURE_MODE`
   means high-progress worker continuation. New settings and artifacts use the
   explicit `CONTEXT_CLOSURE` prefix.
9. **Indexes live outside the source repository.** Generated indexes must not
   dirty user worktrees or become source commits.
10. **Every fact has provenance.** Tool, version, repository revision, build
    configuration, input hash, and source location are required.

## 3. Scope

### Included

- Shared, revision-addressed repository indexes.
- Compilation-database discovery and normalization.
- SCIP ingestion.
- Joern CPG ingestion for selected evidence classes.
- SQLite FTS5 lexical indexing.
- Architecture/module/ownership normalization.
- Typed context-closure construction.
- Graph-aware decomposition quality checks.
- Sol prompt integration and mandatory further decomposition for oversized
  Luna leaves.
- Bounded source excerpts, declarations, interfaces, tests, invariants, and
  validation instructions in worker capsules.
- Freshness, invalidation, observability, cost, and quality metrics.
- Advisory and enforced rollout modes.
- Unit, integration, recovery, and benchmark tests.

### Postponed or excluded

- Qdrant, embeddings, and semantic-vector retrieval.
- Parallel plan-node execution.
- Automatic architectural source refactoring merely because the index reports
  debt.
- Sourcegraph server deployment.
- Mandatory Tree-sitter dependency for the first C/C++ implementation.
- Indexing untracked data or external datasets unless the specification and
  environment explicitly authorize them.

## 4. Artifact layout

Use a shared cache keyed by repository identity, commit, build configuration,
and toolchain fingerprint:

```text
$HARNESS_ROOT/repository-indexes/
  <repository-id>/
    <index-generation>/
      manifest.env
      compile-commands.normalized.json
      index.scip
      architecture.sqlite
      joern/
        cpg.bin
        export/
      reports/
        coverage.tsv
        unresolved-symbols.tsv
        architecture-summary.tsv
        index-quality.tsv
```

Each project records only a pointer and its required configuration:

```text
control/repository-index.env
control/context-closures/<task-base>/
  manifest.env
  closure.tsv
  edges.tsv
  unresolved.tsv
  context.md
  quality.tsv
```

Index generations are immutable. A successful rebuild atomically updates the
project pointer. Interrupted generation leaves the previous index usable.

## 5. Canonical SQLite schema

The first schema should include at least:

```text
index_generations
build_configurations
files
source_regions
symbols
symbol_definitions
symbol_references
symbol_edges
include_edges
call_edges
type_edges
control_flow_edges
data_flow_edges
modules
module_edges
concept_owners
architecture_bindings
invariants
tests
test_symbol_edges
build_targets
lexical_documents
facts
fact_provenance
```

Important requirements:

- Paths are repository-relative and normalized.
- Symbol IDs retain SCIP identity and configuration identity.
- Every edge records its evidence source and confidence class.
- Derived ownership is distinguishable from registered ownership.
- FTS records use structural units, not fixed token chunks.
- Source regions identify functions, declarations, types, macros, tests,
  configuration blocks, or documentation sections.
- Schema migrations are versioned and transactional.

## 6. Context Closure model

### 6.1 Seeds

For plan node `N`, construct the initial set from:

- `Required-Symbols`;
- `Allowed-Scope` and `Context-Paths`;
- allocated specification obligations and typed relations;
- architecture node binding;
- consumed and produced decisions;
- affected invariants and edge contracts;
- focused validation and named tests;
- exact baseline diagnostics, when present.

### 6.2 Typed expansion

Expand only through declared classes:

```text
D: definitions and declarations
T: required type and macro dependencies
I: public interfaces, contracts, ownership, and architecture bindings
B: behavioral evidence, focused tests, fixtures, and baseline diagnostics
C: direct callers and callees when behavior requires them
F: control/data-flow evidence requested for this leaf
V: build target and focused-validation prerequisites
```

Each selected item records:

```text
item_id
item_kind
source_path
source_region
introduced_by
edge_kind
evidence_provider
required_or_supporting
```

Expansion stops when all required dependency classes are satisfied and another
iteration adds no required records. An unresolved required class makes the
closure incomplete; it must not be hidden by lexical similarity.

### 6.3 Resource boundaries

Initial configurable boundaries:

- maximum compiled context bytes;
- maximum symbols and source regions;
- maximum modules crossed;
- maximum ownership boundaries;
- maximum direct callers/callees;
- maximum tests and fixtures;
- maximum unresolved required symbols;
- maximum estimated input tokens.

Exceeding a Luna boundary returns `NEEDS_FURTHER_DECOMPOSITION`, together with
the exact graph cut, unresolved dependency, or cohesive child boundaries. A
Terra exception remains possible only with an explicit reason and measured
upper bound.

### 6.4 Output sections

The generated worker context should contain:

```text
Task and acceptance boundary
Allowed patch scope
Architecture and ownership contract
Target symbols and exact definitions
Required declarations, types, and macros
Relevant callers/callees
Behavioral invariants and failure paths
Focused tests and fixtures
Validation/build instructions
Known baseline failure
Unresolved or deliberately excluded evidence
Closure provenance and budget summary
```

## 7. Implementation phases

### Phase 0 — Baseline and contracts

Deliverables:

- [x] Inventory current context-capsule creation, required-symbol lookup,
  repository inventory, decomposition metrics, and worker prompt boundaries.
- [x] Record baseline measurements from representative completed and problematic
  harnesses: capsule size, files searched, repeated reads, tool actions, output
  bytes, processed tokens, completion/replan result.
- [x] Define repository-index identity, freshness, locking, and atomic
  publication contracts.
- [x] Define the SQLite schema and versioning policy.
- [x] Add fixture repositories representing C, C++, CMake, generated headers,
  multiple build configurations, and an optional HIP source.

Exit criteria:

- Schema and artifact contracts are reviewed.
- Baseline report can be regenerated without model calls.
- Existing harness tests remain unchanged and passing.

### Phase 1 — Repository index lifecycle

Add commands:

```text
harness-index-repository ENV_FILE [--force]
harness-index-status ENV_FILE [--details]
harness-index-invalidate ENV_FILE [--reason TEXT]
```

Deliverables:

- [x] Discover or generate `compile_commands.json` without modifying tracked
  source state.
- [x] Normalize command paths and calculate configuration/input hashes.
- [x] Record compiler, SCIP, Joern, SQLite, Recoll, and harness versions.
- [x] Implement per-repository lock, temporary generation, integrity check, and
  atomic pointer update.
- [x] Detect stale commit, changed compilation database, changed generated
  headers, and changed tool versions.
- [x] Reconcile interrupted index generation after a machine crash.
- [x] Add retention limits that never delete an active generation.

Exit criteria:

- Two harness projects at the same repository/configuration reuse one index.
- Different build configurations do not alias.
- Interrupted builds preserve the previous valid index.

### Phase 2 — SCIP, lexical, and Joern ingestion

Deliverables:

- [x] Invoke `scip-clang` and validate the resulting `index.scip` with the SCIP
  CLI.
- [x] Implement a decoder/importer using generated SCIP bindings rather than
  parsing CLI display text.
- [x] Import definitions, references, relationships, files, locations, and
  diagnostics into SQLite.
- [x] Build structural lexical units and the FTS5 index.
- [x] Add an optional Recoll candidate-provider adapter with deterministic
  normalization and deduplication.
- [x] Invoke Joern only for configured languages/components or on-demand
  analysis classes.
- [x] Import selected call, control-flow, data-flow, and mutation evidence.
- [x] Produce coverage and unresolved-symbol reports.

Exit criteria:

- Exact symbol lookup returns authoritative source coordinates.
- Caller/reference/type queries are reproducible.
- Every imported row names its provider and generation.
- Missing or unsupported HIP relationships are visible, not silently treated
  as absent behavior.

### Phase 3 — Repository architecture normalization

Add commands:

```text
harness-architecture-index ENV_FILE [--rebuild]
harness-query-architecture ENV_FILE QUERY...
harness-architecture-benchmarks ENV_FILE
```

Deliverables:

- [x] Infer module candidates from build targets, source roots, include
  boundaries, and symbol clusters.
- [x] Project registered invariants, decisions, edge contracts, and node
  bindings onto indexed symbols/modules.
- [x] Generate responsibility, dependency, ownership, public-interface, test,
  and concept-owner maps.
- [x] Detect cycles, ambiguous concept ownership, cross-subsystem writes,
  high-fanout symbols, and failed reasoning firewalls.
- [x] Keep inferred facts separate from normative architecture authority.
- [x] Replace the misleading reasoning-index ratio in the architecture protocol
  with measurable navigation precision, recall, search breadth, and context
  cost metrics.
- [x] Add representative architecture-navigation benchmark queries.

Exit criteria:

- A query can map a requirement/symbol to a bounded ranked subsystem, source,
  interface, owner, and focused tests.
- Architecture contradictions produce evidence reports instead of silently
  changing the registry.

### Phase 4 — Context Closure Compiler

Add commands:

```text
harness-build-context-closure ENV_FILE PLAN_NODE_OR_TASK
harness-show-context-closure ENV_FILE PLAN_NODE_OR_TASK [--why ITEM]
harness-context-closure-check ENV_FILE PLAN_NODE_OR_TASK
```

Deliverables:

- [x] Implement seed resolution and typed fixed-point expansion.
- [x] Implement deterministic ranking within each evidence class.
- [x] Extract bounded structural source regions with byte limits.
- [x] Generate closure manifest, item/edge ledgers, unresolved ledger, context
  document, and quality report.
- [x] Prevent duplicate regions and repeated declarations.
- [x] Report why each context item was selected.
- [x] Fail closed for unresolved required symbols, stale indexes, conflicting
  build configurations, or missing normative architecture records.
- [x] Keep full diagnostics on disk and only bounded summaries in context.

Exit criteria:

- Rebuilding an unchanged closure is byte-reproducible except for explicitly
  excluded timestamps.
- Every required leaf fact is either present or listed as unresolved.
- A closure cannot exceed its route-specific limits without a typed failure.

### Phase 5 — Graph-aware Sol decomposition

Deliverables:

- [x] Provide Sol with a compact architecture slice before DAG generation.
- [x] Add measured decomposition fields for estimated closure bytes, symbol
  count, module count, ownership crossings, dependency fan-out, and unresolved
  facts.
- [x] Validate every proposed Luna leaf against a dry-run context closure.
- [x] Require Sol to continue decomposition when the predicted upper bound is
  above Luna limits.
- [x] Return exact suggested child cuts based on graph seams, contracts,
  ownership, and independently testable behavior.
- [x] Route inherently indivisible architectural/integration work to Terra with
  a recorded exception.
- [x] Emit `REDESIGN_REQUIRED` when the requested feature relies on unresolved
  ownership, incompatible architecture decisions, cycles that prevent a safe
  boundary, or an absent reasoning firewall.
- [x] Preserve `--force-decomposition` as an explicit operator override with a
  permanent audit record.

Exit criteria:

- A plan marked Luna-ready passes both declarative schema checks and closure
  budget checks.
- Oversized leaves are rejected before a worker invocation.
- Architecture redesign findings identify concrete owners, edges, and proposed
  repair requirements.

### Phase 6 — Advisory harness integration

New settings, initially defaulting to advisory/off as appropriate:

```text
HARNESS_REPOSITORY_INDEX_MODE=off|advisory|required
HARNESS_CONTEXT_CLOSURE_MODE=off|advisory|required|patch_only
HARNESS_CONTEXT_CLOSURE_MAX_BYTES
HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS
HARNESS_CONTEXT_CLOSURE_MAX_MODULES
HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS
HARNESS_SCIP_CLANG_BIN
HARNESS_SCIP_BIN
HARNESS_JOERN_BIN
HARNESS_RECOLL_ENABLED
```

Deliverables:

- [x] Extend generated worker capsules with compiled context and closure
  provenance.
- [x] In advisory mode, preserve current repository access while comparing
  worker discoveries against the generated closure.
- [x] Record missing-context discoveries, unused context, repeated reads,
  exploration outside closure, and validation outcomes.
- [x] Rebuild or refresh indexes only at safe task/checkpoint boundaries.
- [x] Preserve current recovery semantics and source commits.
- [x] Add `harness-info`, `harness-statistics`, and decomposition metrics for
  index/closure state without overloading `harness-status`.

Exit criteria:

- Existing projects run unchanged with the feature disabled.
- Advisory mode cannot block or mutate execution authority.
- Closure recall and cost can be measured for real harnesses.

### Phase 7 — Required closure and patch-only worker experiment

Deliverables:

- [x] Define promotion thresholds for required mode: required-symbol recall,
  test linkage recall, closure stability, Luna success rate, and false-block
  rate.
- [x] Require a valid closure before launching Luna leaves.
- [x] Replace broad worker search authority with closure-contained source and
  narrowly declared diagnostic expansion.
- [x] Implement an experimental patch-proposal protocol in which a worker emits
  a patch, and the harness validates paths before applying it.
- [x] Validate patch syntax, allowed scope, generated/binary exclusions, and
  workspace baseline before application.
- [x] Keep Terra remediation available for a proven closure/index defect.
- [x] Never classify an index deficiency as a human product decision.

Exit criteria:

- A Luna worker can complete representative leaves without repository-wide
  search.
- A missing closure dependency routes to index/context remediation without
  wasting a full worker episode.
- Patch-only mode cannot modify undeclared paths.

### Phase 8 — Complexity prediction and feedback

Deliverables:

- [x] Join predicted leaf complexity with observed tokens, actions, source
  bytes, repeated reads, output volume, files/lines changed, retries, reviews,
  duration, and outcome.
- [x] Attribute worker outcomes to both executing model and decomposition model.
- [x] Add closure-specific outlier reporting.
- [x] Calculate model-specific completion probability and conservative upper
  bounds from accumulated local data.
- [x] Tune Luna admission using the upper bound, not the average.
- [x] Detect systematic context omissions and feed them into index/closure
  quality reports rather than repeatedly expanding worker freedom.

Exit criteria:

- The harness can explain why a leaf was Luna- or Terra-routed.
- Predicted versus observed error is reportable per leaf type and subsystem.
- Token anomalies identify closure/planner attribution.

### Phase 9 — Architecture rebuild feedback loop

Deliverables:

- [x] Generate periodic architecture scorecards from indexed facts and
  benchmark tasks.
- [x] Detect rising search breadth, fan-out, duplicate ownership, failed
  reasoning firewalls, and context size.
- [x] Produce an architecture-rebuild proposal; do not modify production code
  automatically.
- [x] Update `formats/architecture-rebuild-protocol.md` with machine-generated
  input artifacts and corrected metrics.
- [x] Compare architecture metrics before and after an operator-approved
  redesign harness.

Exit criteria:

- Architecture degradation becomes visible before ordinary feature leaves
  repeatedly fail.
- Rebuild recommendations cite reproducible graph and benchmark evidence.

### Phase 10 — Production qualification and rollout

Deliverables:

- [x] Run all harness test suites.
- [x] Run real-tool integration tests against at least one C/C++ project and
  one HIP-containing project.
- [x] Run advisory-mode benchmarks on completed harness history.
- [x] Compare token cost per verified criterion before and after closure.
- [x] Document installation, configuration, index maintenance, troubleshooting,
  migration, and rollback.
- [x] Deploy disabled-by-default, then advisory, then required for selected new
  projects.
- [x] Do not rebuild active project DAGs automatically.

Exit criteria:

- Production rollout has an explicit operator decision and rollback path.
- Existing state remains readable.
- No active harness is stopped or migrated merely by installing the binaries.

## 8. Testing strategy

### Unit tests

- SCIP decoder and malformed-index rejection.
- Path and compilation-command normalization.
- SQLite migration, transaction, and provenance constraints.
- Typed expansion and fixed-point termination.
- Duplicate-region elimination.
- Closure byte/token/module budgets.
- Missing required symbol and ambiguous build-configuration behavior.
- Normative versus inferred architecture precedence.
- Context item `--why` provenance.

### Integration tests

- Tiny C repository with exact definitions/references/tests.
- C++ overload/type dependency fixture.
- Generated-header fixture requiring a configured build.
- Multiple compile configurations with different macro-visible symbols.
- Joern data-flow fixture.
- No-Joern and no-Recoll graceful degradation.
- Optional HIP indexing coverage fixture.
- Crash during index build and atomic recovery.
- Checkpoint commit followed by safe index refresh.
- Advisory capsule comparison against worker discoveries.

### Negative and liveness tests

- Contradictory architecture ownership.
- Stale index after source/configuration change.
- Missing compile database.
- Required symbol with no authoritative definition.
- Closure graph explosion.
- Cyclic expansion.
- Lexical false positive that conflicts with structural facts.
- Luna leaf exceeding closure limits.
- Repeated decomposition that does not reduce measured complexity.
- Patch attempting to modify an unauthorized or binary path.

### Quality benchmarks

For representative tasks, measure:

- required symbol/interface/test recall;
- irrelevant context rate;
- modules initially considered;
- source bytes and tokens supplied;
- worker exploratory actions;
- repeated reads;
- time to first source edit;
- completion without replan;
- processed tokens and dollar cost per verified criterion;
- false `NEEDS_FURTHER_DECOMPOSITION` and false `REDESIGN_REQUIRED` rates.

## 9. Initial promotion criteria

Required mode should not be enabled for Luna until an agreed benchmark set
demonstrates all of the following:

- 100% required-symbol resolution or an explicit unresolved result;
- at least 95% recall of files later proven necessary by successful workers;
- zero silent stale-index use;
- zero unauthorized path inclusion;
- deterministic closure output for an unchanged generation/task;
- lower median worker exploration and processed tokens;
- no material regression in verified-leaf completion;
- a bounded false-block rate reviewed by an operator.

The exact numeric thresholds may be revised from observed data, but every
change must be recorded in the status file and test evidence.

## 10. Status-update protocol

`work/context-closure-status.md` is the authoritative current implementation
status while this work is in development.

It MUST be updated:

1. after every completed phase or milestone;
2. after a schema, interface, or rollout decision changes;
3. after substantial code or test progress;
4. when a blocker is discovered or resolved;
5. before ending a development session with unfinished work;
6. immediately before and after any production deployment.

Each update must include:

- UTC timestamp;
- active phase and milestone;
- completed work since the prior update;
- files/components changed;
- tests and results;
- measurements when available;
- blockers/risks;
- next concrete action;
- deployment state;
- relevant commit, or `uncommitted`.

Do not update the status file merely because time passed. Update it whenever
substantial progress or a decision changes the project state. Status updates
should normally be committed with the work they describe.

## 11. Definition of done

This initiative is complete when:

1. the repository index is reproducible, revision-aware, crash-safe, and
   queryable;
2. Sol uses graph evidence and measured closure bounds during decomposition;
3. every Luna leaf has a machine-validated Context Closure or is rejected for
   further decomposition before worker invocation;
4. generated contexts contain the implementation-relevant code, contracts,
   tests, and invariants with provenance and bounded size;
5. closure defects route to deterministic remediation rather than repeated
   worker search;
6. predicted and observed complexity/cost are connected in metrics;
7. architecture quality can be measured and can trigger an evidence-backed
   redesign recommendation;
8. production rollout and rollback are documented and tested;
9. existing serial execution, checkpoint, recovery, liveness, token-fuse, and
   architecture-guard behavior remains intact.
