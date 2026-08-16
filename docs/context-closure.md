# Repository Intelligence and Context Closure

## Purpose

The Full harness can compile a bounded, provenance-bearing implementation
context for every decomposed Luna leaf. SCIP supplies authoritative structural
symbols; Joern optionally supplies call, control-flow, data-flow, and mutation
evidence; SQLite FTS5 supplies local lexical lookup; Recoll can provide
project-local secondary candidates. Normative architecture registries remain
authoritative and are never overwritten by inferred facts.

Repository intelligence is disabled by default. Existing project state and
active DAGs remain readable without migration.

## Installation

Required for C/C++ indexing:

- `sqlite3` with FTS5;
- `scip-clang`;
- SCIP CLI (`scip`);
- Go, once, to build the harness SCIP importer;
- a valid `compile_commands.json`.

Optional:

- Joern for directional call and flow/mutation evidence;
- Recoll/`recollq` for bounded secondary lexical candidates.

Build the importer after installing or updating the harness:

```bash
harness-build-index-tools "$HARNESS_HOME/libexec"
```

Joern and Recoll are not required for ordinary structural closure. A leaf that
explicitly requests flow class `F` fails closed when Joern evidence is absent.
When Joern is enabled on a repository containing generated build trees, set
`HARNESS_JOERN_EXCLUDE_REGEX` explicitly. The harness also supplies the selected
compilation database to C2CPG; exclusions affect Joern only and never hide SCIP,
Git, specification, or registered architecture evidence.

## Configuration

Start in advisory mode:

```bash
export HARNESS_REPOSITORY_INDEX_MODE="advisory"
export HARNESS_CONTEXT_CLOSURE_MODE="advisory"
export HARNESS_COMPILE_COMMANDS="$REPOSITORY/build/compile_commands.json"
export HARNESS_SCIP_CLANG_BIN="scip-clang"
export HARNESS_SCIP_BIN="scip"
export HARNESS_SCIP_IMPORTER_BIN="$HARNESS_HOME/libexec/harness-scip-importer"
export HARNESS_JOERN_BIN="joern"
export HARNESS_JOERN_ENABLED="0"
export HARNESS_JOERN_ANALYSIS_CLASSES="call,control-flow,data-flow,mutation"
export HARNESS_JOERN_SOURCE_ROOT="."
export HARNESS_JOERN_EXCLUDE_REGEX='(^|/)(\.git|build)($|/)'
export HARNESS_RECOLL_BIN="recollq"
export HARNESS_RECOLL_ENABLED="0"
```

Resource boundaries:

```bash
export HARNESS_CONTEXT_CLOSURE_MAX_BYTES="32768"
export HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS="64"
export HARNESS_CONTEXT_CLOSURE_MAX_MODULES="4"
export HARNESS_CONTEXT_CLOSURE_MAX_OWNERSHIP_BOUNDARIES="2"
export HARNESS_CONTEXT_CLOSURE_MAX_DIRECT_RELATIONSHIPS="16"
export HARNESS_CONTEXT_CLOSURE_MAX_TESTS="8"
export HARNESS_CONTEXT_CLOSURE_MAX_BUILD_TARGETS="4"
export HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS="250000"
export HARNESS_REPOSITORY_INDEX_RETENTION="3"
export HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES="4"
```

Promotion policy:

```bash
export HARNESS_CONTEXT_CLOSURE_PROMOTION_MIN_SAMPLES="20"
export HARNESS_CONTEXT_CLOSURE_MIN_FILE_RECALL_PERCENT="95"
export HARNESS_CONTEXT_CLOSURE_MIN_LUNA_SUCCESS_PERCENT="80"
export HARNESS_CONTEXT_CLOSURE_MAX_FALSE_BLOCK_PERCENT="5"
```

Modes have distinct authority:

- `off`: no index or compiled closure is required.
- `advisory`: compile and measure closures while workers retain normal access.
- `required`: reject a non-ready Luna leaf before an agent launch and return it
  to Sol/manager decomposition.
- `patch_only`: required closure plus a read-only, tool-less Luna invocation
  that emits one Git patch for deterministic harness validation.

Do not enable `required` or `patch_only` merely because the software supports
them. Run `harness-context-closure-promotion` and review the local benchmark
sample first.

## Index and architecture workflow

```bash
harness-index-repository project.env
harness-index-status project.env --details
harness-architecture-index project.env
harness-query-architecture project.env SYMBOL
harness-export-architecture-slice project.env
```

The index generation identity includes repository identity/revision,
compilation database, recursive generated/external compile inputs, schema,
provider/importer code, and tool fingerprints. Generations are immutable and
shared by projects with the same identity. Project-local normative projections,
Recoll candidate overlays, benchmarks, closures, and scorecards never mutate
the shared database.

Run representative navigation benchmarks:

```bash
harness-architecture-benchmarks project.env queries.tsv
harness-architecture-scorecard project.env
harness-compare-architecture-scorecards before.tsv after.tsv
```

The query TSV has columns `benchmark_id`, `query`, and comma-separated
`expected_paths`. Scorecards report precision, recall, search breadth, context
bytes, cycles, fan-out, ownership ambiguity, cross-subsystem mutation, and
reasoning-firewall candidates. Rebuild proposals are advisory; they never edit
source or architecture authority.

## Closure and decomposition workflow

```bash
harness-build-context-closure project.env TASK_OR_NODE
harness-context-closure-check project.env TASK_OR_NODE
harness-show-context-closure project.env TASK_OR_NODE
harness-show-context-closure project.env TASK_OR_NODE --why SYMBOL_OR_PATH
harness-evaluate-decomposition-context project.env DAG COVERAGE ARCHITECTURE OUTPUT --enforce
```

`READY` means all declared evidence classes resolved inside the configured
budget. `INCOMPLETE` identifies missing authority, symbols, configurations, or
providers. `NEEDS_FURTHER_DECOMPOSITION` identifies a measured graph/resource
boundary and includes suggested cohesive cuts. Sol receives those cuts and
must keep decomposing routine coding work until it is Luna-ready. A Terra
exception is reserved for an explicitly recorded irreducible integration or
architecture boundary. Existing `REDESIGN_REQUIRED` and
`--force-decomposition` audit semantics remain unchanged.

## Metrics and promotion

```bash
harness-context-baseline project.env
harness-context-closure-promotion project.env
harness-context-closure-predictions project.env
harness-context-closure-outliers project.env
harness-context-closure-omissions project.env
harness-compare-context-baselines before.tsv after.tsv
```

Predictions are grouped by executing model and leaf type. Luna admission uses
the learned local p95 when it is stricter than the cold-start declaration.
Every observation retains the worker model and the Sol decomposition model, so
worker failures can be attributed to both execution and planning.

## Maintenance and crash recovery

Index builds hold a per-repository lock, build in a hidden temporary directory,
run SQLite/manifest integrity checks, and publish the project pointer
atomically. The next builder quarantines an interrupted temporary generation.
Retention never removes the active generation.

Accepted/checkpointed leaves are safe refresh boundaries. Advisory projects
may defer refresh until the configured accepted-leaf interval; required mode
refreshes stale state at the boundary. Refresh failure is logged and cannot
silently substitute a stale generation. A scorecard follows a successful safe
refresh.

Manual maintenance:

```bash
harness-index-invalidate project.env --reason "toolchain changed"
harness-index-repository project.env --force
harness-index-status project.env --details
```

## Troubleshooting

- `compile_commands.json was not found`: configure CMake with
  `CMAKE_EXPORT_COMPILE_COMMANDS=ON` or set `HARNESS_COMPILE_COMMANDS`.
- `multiple compilation databases`: select the exact configuration explicitly.
- `tracked-worktree-changed`: checkpoint/commit source before rebuilding; the
  index intentionally describes a committed boundary.
- `generated-inputs-changed`: regenerate/rebuild the index after an external
  configured header changes.
- `Joern flow evidence was requested`: enable Joern for that project/component
  or split/restate the leaf so flow evidence is not falsely claimed.
- `CONTEXT_INCOMPLETE`: repair index/registry evidence or decompose again. It is
  not a human product decision.
- `NEEDS_FURTHER_DECOMPOSITION`: inspect `suggested-cuts.tsv` and the quality
  ledger; do not simply raise the Luna budget.
- patch-only rejection: inspect the retained proposed patch and focused
  validation log. Unauthorized, binary/generated, symlink, stale-baseline, and
  multi-patch results are rejected before controlled commit.

## Migration, rollout, and rollback

Installation does not rebuild an active DAG or stop a running harness. Deploy
with both modes `off`, then enable `advisory` only for selected new projects.
After enough reviewed outcomes satisfy promotion thresholds, opt selected new
projects into `required`; treat `patch_only` as a separate experiment.

To roll back enforcement without changing project state:

```bash
export HARNESS_CONTEXT_CLOSURE_MODE="advisory"  # or off
export HARNESS_REPOSITORY_INDEX_MODE="advisory" # or off
```

Stop at a clean task boundary before changing modes. Existing index pointers,
closures, ledgers, and scorecards may remain on disk; older harness behavior
does not depend on them. Use `harness-index-invalidate` when the index should no
longer be selected. Never delete active project state as a rollback mechanism.
