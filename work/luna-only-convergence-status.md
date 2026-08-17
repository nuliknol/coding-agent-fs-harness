# Luna-Only Convergence Implementation Status

Last updated (UTC): 2026-08-17T16:48:00Z

Overall status: `IN_PROGRESS`

Current phase: `E/F — diagnostic convergence and production promotion`

## Objective

Replace the binary Context Closure gate and Sol/Terra escalation paths with an
in-place, Luna-only convergence engine. Preserve accepted specifications,
project DAG authority, verified checkpoints, commits, and Goal IDs.

## Progress summary

| Phase | Status | Evidence |
| --- | --- | --- |
| Design reconciliation | COMPLETE | Existing closure plan, status, future ideas, compiler, worker gate, manager recovery, and route normalization inspected. |
| Durable implementation plan | COMPLETE | `work/luna-only-convergence-implementation-plan.md` records target architecture, invariants, phases, and promotion criteria. |
| A. Model and escalation policy | IMPLEMENTED | Opt-in policy normalizes every inference role to Luna, rejects stale Sol/Terra process launches and Terra DAG/state routes, disables Terra strategy normalization, and updates manager/decomposition instructions. |
| B. Typed closure repair | IMPLEMENTED | Closure compiler emits condition/action/provider records and deterministic child candidates; non-ready admission enters an internal idempotent repair transaction without worker or manager-review inference. |
| C. Live repository overlay | IMPLEMENTED | Tracked workspace changes are digest-bound, stale source windows are relocated against live source, new symbols can seed closure, and Joern is lazy, resource-bounded, and exact-overlay cached. |
| D. Recursive decomposition compiler | FUNCTIONAL_SLICE_COMPLETE | Deterministic repair children compile into byte-verified child-criterion grafts with stable normative and implementation-seam facets; publication rejects semantic drift. |
| E. Diagnostic repair loop | FUNCTIONAL_SLICE_COMPLETE | Validation logs compile into typed diagnostics; patch-only Luna can request five narrowly authorized evidence classes and repair a failed patch for up to three same-thread validation rounds. Cross-invocation validation caching and empirical convergence proof remain. |
| F. Compact roles and state migration | FUNCTIONAL_SLICE_COMPLETE | Patch-only Luna receives a compact tool-less contract; stopped projects migrate ready Terra/remediation assignments in place while preserving roots, criteria, checkpoints, and installed authority. |

## Confirmed starting defects

- Non-ready closure is converted into a synthetic worker result instead of an
  internal repair transition.
- Manager remediation is forced to Terra.
- Luna exhaustion is normalized to Terra.
- Current closure cuts contain a `DECOMPOSE_OR_TERRA` route hint.
- Sol owns semantic decomposition repair.
- Dirty/checkpointed worktrees are not represented by a live overlay.
- Structured diagnostics, typed context expansion, and validation caching are
  documented as future work rather than active completion mechanisms.
- The older Context Closure status labels the feature complete without a single
  verified closed-context Luna completion.

## Change journal

### 2026-08-17 — implementation started

- Reconciled the four Context Closure work documents with current control flow.
- Defined the Luna-only convergence architecture and strict completion gates.
- Started Phase A with a compatibility-first audit of configuration, model
  dispatch, publication routing, and recovery transitions.

### 2026-08-17 — Phase A functional slice

- Added `HARNESS_MODEL_POLICY=legacy|luna_only` and
  `HARNESS_ESCALATION_POLICY=legacy|decompose`.
- Luna-only environment loading normalizes manager, decomposition, remediation,
  fallback, and enabled Oracle roles to `LUNA_WORKER_MODEL`.
- The process launcher rejects a non-Luna model or `worker_terra` role before
  launching a provider process.
- Measured-DAG validation and plan installation reject Terra routes under the
  Luna-only policy.
- Manager remediation runs through the Luna worker runtime, and strategy
  exhaustion no longer normalizes continuations to Terra when escalation policy
  is `decompose`.
- Added Luna-only overrides to bootstrap, review, replan, DAG construction, and
  DAG-repair prompts while retaining legacy compatibility.

### 2026-08-17 — Phase B typed repair schema started

- Context Closure manifests and quality reports now contain `condition`,
  `repair_action`, `repair_provider`, and `semantic_split_required`.
- Added a provenance-bearing `repair.tsv` ledger for each compiled closure.
- Luna-only suggested cuts use route `DECOMPOSE`, never
  `DECOMPOSE_OR_TERRA`.
- Closure admission handoffs preserve typed repair metadata and distinguish
  missing evidence from a genuinely over-budget semantic boundary.
- Manager rejection records `CONTEXT_CLOSURE_REPAIR` and passes its exact
  condition/action/provider into automatic recovery.
- Graph-cut repair forces child-criterion decomposition; index and authority
  failures retain their distinct repair actions.

### 2026-08-17 — internal closure-repair transaction

- Added `worker-return-context-repair`, an atomic transaction that archives the
  claimed assignment, releases its lease, records `CLOSURE_REPAIR`, preserves
  the root Goal/progress state, and creates a typed automatic-recovery marker.
- Luna-only closure admission no longer manufactures a worker result and no
  longer spends a manager-review inference turn merely to recognize deterministic
  closure evidence.
- The transaction is idempotent: replay returns the existing marker without
  creating another result, revision, or state transition.
- Oversized closures now compile `repair-children.tsv` with stable child IDs,
  path/symbol seams, source cuts, validation hints, and estimated source bytes.
  Automatic recovery exposes this bounded file to the Luna microplanner.

### 2026-08-17 — Phase C tracked-worktree overlay slice

- Added `HARNESS_REPOSITORY_OVERLAY_MODE=off|tracked`; Luna-only mode defaults
  to `tracked`, while legacy mode remains `off`.
- A dirty tracked worktree no longer invalidates an otherwise current immutable
  index when tracked overlay mode is active.
- Added an atomic changed-file overlay ledger with status, content digest, and
  byte size.
- Context Closure verifies overlay freshness, copies its provenance into the
  closure, relocates stale indexed symbol ranges against live source, and uses
  bounded lexical relocation only inside declared paths.
- Newly introduced required symbols in changed declared paths can be supplied
  by the worktree overlay instead of requiring a global SCIP rebuild.
- Overlay evidence and digest are recorded in the closure quality report and
  manifest. Global Joern rebuild behavior is unchanged; lazy flow caching is a
  later Phase C item.

### 2026-08-17 — Phase E structured diagnostic slice

- Added a deterministic compiler for compiler, linker, CTest, sanitizer,
  assertion, generic command-failure, and opaque nonzero-exit diagnostics.
- Diagnostics have stable IDs, kind, tool/target, file/line/column, symbol,
  normalized primary message, causal parent, duplicate count, and full-log
  digest.
- `harness-run-logged` retains the complete raw log but now returns the compact
  diagnostic ledger before a much smaller raw tail. Repeated identical errors
  consume one diagnostic record with an occurrence count.
- Every nonzero validation has at least one typed record, even when a provider
  emits an unknown format.

### 2026-08-17 — Phase E typed context-expansion slice

- Added a trusted resolver for exactly five request classes: type definition,
  direct caller contract, failing assertion, build owner, and representation
  writer.
- Authorization is derived from the immutable assignment seeds and compiled
  closure. Symbol expansions require the requested fact to be a seed or direct
  SCIP/Joern graph neighbor; build and test expansion remains inside declared
  paths. Arbitrary lexical search is not available.
- Patch-only Luna may emit one structured context request instead of prematurely
  returning `CONTEXT_INCOMPLETE`. The harness compiles a bounded extension with
  provider, graph relation, exact source coordinates, and evidence digest, then
  resumes the same Luna thread with only that extension.
- Added independent byte and per-leaf expansion limits. Rejected, unrelated,
  exhausted, or non-resumable requests fail closed into decomposition and never
  enable repository tools or a stronger model.
- Added four resolver tests covering direct type/caller evidence, declared-path
  build ownership, provenance, and rejection of an unrelated symbol.

### 2026-08-17 — Phase D deterministic closure-graft slice

- Added a trusted compiler that converts two or more indexed Context Closure
  repair children into an ordered append-only child-criterion graft. Child IDs,
  path/symbol seams, acceptance evidence, and order come directly from the
  closure ledger rather than Luna transcription.
- Each graft now has a machine-owned facet sidecar. Specification obligations,
  invariants, decisions, edge contracts, and health gates are preserved across
  every child; each indexed implementation seam is represented exactly once.
- Automatic recovery precompiles both files before its bounded Luna planning
  turn. Luna only authors the first child assignment; it is told not to rewrite
  the graft.
- Publication independently recompiles and byte-compares the graft and facet
  ledger, then checks the assignment's target criterion, write scope, required
  symbols, and focused validation against the first indexed child. Semantic
  drift fails before worker launch.
- Facets are installed append-only beside the root criterion decomposition.
  A single indexed seam is not misrepresented as decomposition; it remains a
  bounded semantic subdivision case.

### 2026-08-17 — Phase C on-demand Joern and CPU-governance slice

- Added `HARNESS_JOERN_EXECUTION_MODE=eager|on_demand`. Luna-only projects
  default to `on_demand`; their immutable SCIP/build index does not launch a
  JVM.
- A closure launches Joern only when its declared dependency classes contain
  flow evidence or its leaf type is concurrency/integration. The imported CPG
  projection lives in a database overlay keyed by assignment, immutable index,
  tracked-worktree digest, provider fingerprint, source root, and analysis
  classes.
- Repeated closure compilation reuses the exact overlay without another Java
  process. Eager mode retains compatibility and now caches its GraphML export
  by repository/index/provider digest.
- Joern admission remains host-global. Every admitted parse/export is bounded
  by `taskset`, JVM `ActiveProcessorCount`, heap, timeout, and nice priority.
  Luna-only defaults were reduced to one CPU and a 4096 MiB heap unless the
  project explicitly configures other limits.
- Temporary CPG/GraphML products are deleted after a successful on-demand
  import; the compact SQLite evidence and bounded reports remain. Failed
  overlays are quarantined for diagnosis instead of being mistaken for cache
  hits.

### 2026-08-17 — Phase F in-place Luna-only migration slice

- Extended state migration to require a stopped/safe scheduler boundary, move
  unclaimed pre-policy Terra/remediation assignments into their normal archive,
  preserve root progress/checkpoints, and create a typed
  `LUNA_ONLY_POLICY_MIGRATION` recovery marker.
- Installed pending Terra DAG rows remain immutable specification/architecture
  authority. At activation, planning must create at least two ordered node-local
  root criteria and publish only the first bounded Luna stage.
- Publication now measures that first stage independently of the historical
  aggregate vector. It permits only Luna-safe leaf types, focused/incremental
  validation, at most five implementation files, at most three turns, bounded
  score/actions/p95, and a scope/symbol subset of the installed node.
- Later root revisions use the same child-vector rule, so an old Terra aggregate
  cannot silently restore a Terra route after a checkpoint. The original DAG,
  normalized obligation coverage, architecture bindings, root identity,
  commits, and verified evidence are not rewritten.
- Migration writes a durable summary with moved ready-task count and installed
  Terra-node count. The latter are explicitly marked for recursive root-criteria
  activation, not claimed as already converted.

### 2026-08-17 — Phase F compact patch-only Luna prompt slice

- Patch-only execution no longer loads the generic worker protocol, shell/read
  rules, goal-continuation mechanics, or normal context capsule. It receives a
  compact trusted-runner contract, the bounded assignment, and compiled closure
  only.
- The compact prompt still specifies the exact patch envelope, terminal goal
  outcomes, decomposition reasons, architecture impact fields, and required
  result headings so protocol validation remains deterministic.
- Typed context follow-ups resume the same thread with only the newly compiled
  extension. They do not resend the original closure or generic protocol.
- Normal advisory/required workers retain the existing interactive protocol;
  this reduction is isolated to the tool-less mode where those instructions
  were impossible to use and only consumed tokens.

### 2026-08-17 — final policy escape-hatch audit

- Pending-plan reclassification now rejects a newly written Terra route under
  Luna-only policy while preserving completed/active historical rows as durable
  authority.
- Active-node reassessment cannot upgrade a Luna-only project to Terra; it must
  decompose the remaining acceptance boundary.
- Forced-redesign debt validation accepts only a bounded Luna-executable
  remediation stage in Luna-only mode, while legacy mode retains its historical
  Terra architecture-node contract.
- Architecture-fit and binding prompts no longer encode Sol/Terra as semantic
  identities where the role is running under Luna-only policy. The central
  launcher remains the independent fail-closed enforcement boundary.
- The JSONL runtime-budget test now matches the production seven-item protocol
  headroom required to let a source-changing Luna turn publish its final result.

### 2026-08-17 — bounded patch-only diagnostic convergence

- A failed patch-only focused validation is rolled back before another model
  action; no rejected source delta leaks into the next round.
- The trusted runner extracts the normalized diagnostics ledger, resumes the
  same Luna thread with only that typed delta, and preserves the original
  assignment/closure as authority without resending generic worker protocol.
- `HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS` defaults to three total validation
  attempts. It is a hard maximum, not a retry target.
- A durable per-task repair ledger records validation round, patch digest,
  semantic diagnostic digest, evidence path, and timestamp.
- Diagnostic progress excludes occurrence counts and raw-log digests. An
  unchanged consecutive semantic failure set trips the no-progress circuit
  breaker immediately and returns the leaf to deterministic child-DAG
  decomposition without a stronger model.

### 2026-08-17 — exhausted-root child-boundary migration

- Production inspection showed five preserved liveness pauses created by the
  legacy same-boundary loop (8–29 reviews/replans), not specification or
  architecture contradictions.
- Luna-only migration now archives those reassessment markers and replaces
  them with `LUNA_ONLY_POLICY_MIGRATION`, which makes child-criterion
  decomposition mandatory before another worker can launch.
- Historical review, replan, lifetime, and token totals remain durable. A
  policy-specific liveness epoch subtracts them only for the new append-only
  child acceptance boundary; ordinary restart, incident resolution, context
  rotation, or active-node revision still cannot reset liveness.
- The migration rejects a paused root that still has a ready, running, or
  pending-result artifact, so it cannot create two live state transitions.
- Added regression coverage for archival, typed recovery, retained historical
  counters, post-migration delta accounting, and absence of an immediate
  liveness re-pause.

### 2026-08-17 — mandatory migration decomposition hardened

- Production telemetry exposed a residual classification escape: the typed
  `LUNA_ONLY_POLICY_MIGRATION` marker was initially recognized, but later
  legacy same-blocker and exhausted-replan checks could overwrite its recovery
  mode with `MANAGER_REMEDIATION`.
- Both generic overrides now explicitly exclude policy migrations. Migrated
  roots therefore retain `AUTOMATIC_REPLAN` and the mandatory child-criterion
  decomposition instructions regardless of their preserved legacy history.
- Added a regression invariant covering both override sites before the
  corrected migration path is promoted again.
- Migration now also consumes an unreviewed result produced by a pre-policy
  manager-remediation assignment. The result is archived with explicit
  unaccepted provenance, its tracked workspace delta remains available to the
  closure overlay, and the root receives the same mandatory decomposition
  marker. This closes the race where a turn crossed the supervisor stop
  boundary during policy promotion.
- The same historical overrides are now forbidden for every typed Context
  Closure repair, not only policy migration. Production proved the need when a
  correctly rejected 43.5 KiB capsule queued `GRAFT_GRAPH_CUTS` but was then
  reclassified as manager remediation. Graph-cut and index repair now retain
  the automatic repair path.
- Policy migration writes a terminal transaction marker beside its archived
  assignment. Crash reconciliation recognizes the marker and cannot resurrect
  that intentionally retired assignment as an interrupted worker completion.
- The assignment publisher now recognizes the same two typed repair
  boundaries. Historical automatic-replan counts and blocker fingerprints
  remain durable, but they cannot veto the first explicitly authorized
  `LUNA_ONLY_POLICY_MIGRATION` or `CONTEXT_CLOSURE_REPAIR` publication. Normal
  continuations still enforce both budgets unchanged.
- Crash recovery now recognizes both terminal repair markers and the typed
  durable evidence written by older deployments. It backfills a permanent
  `recovery-retired` marker for Context Closure repairs and Luna-only policy
  migrations before generic orphan recovery runs. This prevents an archived
  internal transition from being recreated as a ready task after its root has
  already advanced, and therefore prevents concurrent worker/replanner state
  on the same root.

## Validation journal

- `tests/test-codex-exec-jsonl.sh` — PASS. Includes Luna-only normalization,
  direct Sol rejection, Terra-role rejection, and invalid policy pairing.
- `python3 -m unittest tests.test_context_closure_tools` — PASS, 14 tests.
  Includes typed build-index, Joern, and context-path repair classification.
- `tests/test-decomposition-v2.sh` — PASS.
- `tests/test-leaf-goal.sh` — PASS, including provider retry, continuation,
  resource recovery, repair, and Oracle paths.
- `tests/test-luna-only-convergence.sh` — PASS. Verifies internal repair state,
  assignment/lease transactionality, absence of a synthetic result, typed
  marker fields, and idempotent replay.
- Context Closure suite expanded to 16 passing tests, including live symbol
  relocation and Luna-only deterministic graph-cut candidates.
- `python3 -m unittest tests.test_validation_diagnostics` — PASS, 2 tests.
- `python3 -m unittest tests.test_context_request` — PASS, 4 tests.
- `python3 -m unittest tests.test_closure_graft` — PASS, 2 tests.
- `tests/test-scip-importer.sh` — PASS, including eager Joern, JVM resource
  bounds, on-demand base-index suppression, exact flow-overlay creation, and
  digest-cache reuse.
- `tests/test-luna-only-convergence.sh` — PASS after migration coverage was
  added for safe-boundary archiving, typed recovery, and durable migration
  state.
- `tests/test-decomposition-v2.sh` passed again after structured diagnostics
  were integrated into logged validation.
- `tests/test-repository-index.sh` — PASS.
- `tests/test-harness.sh` — PASS; all v4.4 compatibility, recovery, manager,
  worker, and Oracle regression scenarios completed successfully.
- Bash syntax validation passed for all modified orchestrator scripts.
- `tests/test-active-plan-revision.sh` — PASS after the Luna-only state-route
  guard was added.
- `tests/test-architecture-redesign.sh` and
  `tests/test-architecture-guards.sh` — PASS after policy-specific remediation
  validation was added.
- Full regression rerun: `tests/test-harness.sh`,
  `tests/test-codex-exec-jsonl.sh`, `tests/test-repository-index.sh`,
  `tests/test-scip-importer.sh`, `tests/test-leaf-goal.sh`,
  `tests/test-decomposition-v2.sh`, and
  `tests/test-luna-only-convergence.sh` — PASS.
- Combined Python suite — PASS, 24 tests.
- `git diff --check` and Bash syntax validation — PASS.

## Next actions

1. Add fingerprint-keyed focused-validation pass caching with strict dependency
   invalidation; diagnostic normalization is implemented, but pass reuse is not.
2. Add an integration fixture that drives patch-only Luna through fail/repair/
   pass and repeated-diagnostic/decompose paths against a real compiled closure;
   compatibility suites pass, but those two new branches still need direct
   end-to-end fixtures.
3. Extend compact prompt generation to planning, review, and final audit roles;
   patch-only workers are compact, but legacy-compatible manager prompts still
   carry superseded prose before their Luna-only override.
4. Run stopped production projects through the safe migration boundary, enable
   `luna_only`, `decompose`, required Context Closure, tracked overlay, and
   on-demand Joern, then collect per-obligation token and convergence telemetry.
5. Promote only after production evidence meets the completion criteria in the
   implementation plan; the code path is implemented, but token/divergence
   improvement has not yet been empirically demonstrated on completed projects.
