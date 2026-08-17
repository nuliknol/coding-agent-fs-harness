# Luna-Only Convergence Implementation Status

Last updated (UTC): 2026-08-17T19:56:00Z

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
- Crash recovery also reconciles the two partial-order states left by an
  interrupted historical transition. A newer ready revision archives an older
  stale replan marker; an equal/newer typed marker archives an older
  resurrected ready assignment. This establishes exactly one live transition
  per root before supervisors start.
- Migrated goal records now enter terminal `MIGRATED` state instead of
  remaining false-positive orphan goals. Reset-mode recovery also moves stale
  transaction scratch files out of hot control/task directories into the
  crash-recovery archive. This removes repeated scanning and hundreds of noisy
  startup diagnostics without deleting forensic evidence.
- Recovery also backfills `MIGRATED` onto active goal records created by an
  older deployment whenever their assignment already has durable repair or
  retirement evidence, removing the last false-positive orphan-goal reports.
- Planning-gap dispatch now requires the same inactive plan fingerprint to
  survive a one-second settle window and rechecks all active artifacts before
  invoking Luna. This closes the millisecond race between Context Closure
  assignment retirement and typed replan-marker publication without adding a
  blocking sleep or delaying event processing.
- Tracked repository overlays now span the complete delta from the immutable
  indexed baseline commit through current HEAD and the dirty tracked worktree.
  Compile commands, generated inputs, index integrity, schema, and all provider
  fingerprints must still match; otherwise admission remains fail-closed.
- A `CLOSURE_BUILD_UNAVAILABLE` repair caused only by that source-history gap
  deterministically requeues the same archived assignment once against the
  compiled overlay. An exact input fingerprint suppresses identical retries.
  This consumes no Luna/Sol/Terra turn and does not launch SCIP, Joern, Java, or
  SQLite repeatedly.

### 2026-08-17 — mixed closure defects route to compiled decomposition

- Production evidence showed that compmod-wc-3 and dplm had respectively four
  and three deterministic indexed graph cuts, while their mixed
  unresolved-evidence plus byte/test/module/build budget failures emitted zero
  repair children. The unresolved-evidence branch incorrectly took precedence
  and sent both roots through an index refresh/manager-replan path.
- The five affected production process groups were stopped at preserved repair
  boundaries before another planning revision could be consumed.
- The closure compiler now prefers `GRAFT_GRAPH_CUTS` for every mixed evidence
  and resource failure. Pure missing evidence remains fail-closed on
  `REFRESH_INDEX_OR_OVERLAY`; authority failures retain their dedicated repair.
- This classification keeps unresolved facts visible in `repair.tsv`, while
  compiling Luna-sized child candidates from evidence already present instead
  of asking a model to rediscover the decomposition.
- The first production promotion proved the new mixed-failure classification,
  then exposed a separate scope-conservation defect before publication: graph
  cuts treated read-only headers, tests, and build evidence as child write
  authority. All five turns were stopped before the deterministic publisher
  could accept such a child.
- Repair candidates now intersect every indexed cut with the immutable parent
  `Allowed-Scope`; a read-only context path can never become child mutation
  scope. The repair schema carries distinct `allowed_paths` and
  `context_paths`, and publication verifies both against the compiled row.
- Automatically discovered behavioral tests are globally capped at the
  configured test budget, and large test/reference/flow excerpts use smaller
  kind-specific byte windows. Explicit named tests remain required. This
  removes irrelevant multi-megabyte test aggregation from otherwise focused
  Luna capsules without weakening provider freshness or exact-symbol checks.
- Production then completed the first intended convergence transition:
  compmod-wc-3 decomposed its 93.6 KiB rejected parent into revision 23, whose
  compiled capsule was `READY` at 12,306 bytes (3,077 estimated tokens), and
  only then launched a `gpt-5.6-luna` worker. No fallback context or repository
  exploration permission was used.
- Four other published children immediately entered another typed closure
  repair. This exposed a fast-transition race: the manager wrapper saw no ready
  file after worker admission had already archived the assignment and queued
  the exact successor marker, and falsely reported publication failure.
- Publication commit detection now accepts that state only when the archived
  expected assignment and a successor marker whose `Triggered-By` exactly
  equals that expected revision both exist. This makes the next repair durable
  without a correction turn or supervisor restart.
- Supplemental callers, references, discovered tests, and flow records are now
  packed deterministically into half the total capsule byte budget after every
  required record. Omitted neighbors remain available through the typed
  one-request extension protocol. Ambiguous display-name matches prefer exact
  definitions inside declared Context-Paths/Allowed-Scope, and accepted
  decision provenance is no longer redundantly dumped beside its compiled
  authority record.
- Luna-only publication telemetry now reports the enforced Luna model instead
  of retaining a stale Sol decomposition label from an immutable legacy DAG.
- Production preflight under the packed-evidence compiler converted three more
  preserved revisions directly to `READY`: compmod-wc-2 at 32,760 bytes,
  compmod-wc-4 at 23,807 bytes, and dpvis at 14,313 bytes. Their live admission
  rebuilds were smaller still (30,543; 19,795; and 11,363 bytes respectively),
  and all three launched Luna workers without another planning revision.
- Along with compmod-wc-3, four projects have now demonstrated the intended
  pairing: `CONTEXT_CLOSURE_PREPARED status=READY` immediately precedes a
  `WORKER_INVOCATION_STARTED model=gpt-5.6-luna` record. Process inspection
  shows no Java, Joern, or SQLite CPU consumers on these launches.
- The remaining dplm child is a header-only mechanical API task. SCIP records
  the header site as a reference while three same-display-name implementations
  exist elsewhere, so the compiler previously selected all implementations.
  Resolution now prefers an exact declaration/reference inside the declared
  path boundary when no in-boundary definition exists; out-of-boundary
  implementations do not inflate that header capsule.
- The dplm production preflight is now `READY` at 23,063 bytes (5,766
  estimated tokens), one module, and zero build targets; its live admission
  rebuild was 21,987 bytes and launched Luna. All five target projects have now
  supplied at least one validated compiled capsule to a Luna worker.
- Typed extension rejection exposed another liveness bug: a nonzero trusted
  resolver outcome could escape through Bash errexit before the patch-only
  state machine synthesized its `CONTEXT_INCOMPLETE` result. The resolver call
  is now an explicit conditional, so rejection is handled as typed data and
  cannot leave an orphan running task.
- Exact scoped declaration evidence now includes a bounded 16-line window on
  each side of the indexed declaration. This supplies nearby contract comments
  needed by documentation/mechanical API leaves without opening a whole header
  or granting repository exploration.
- Production proved the rejected-extension liveness repair: dplm and dpvis
  both emitted `CONTEXT_EXPANSION_REJECTED`, synthesized and committed
  `Goal-Outcome: NEEDS_DECOMPOSITION`, released their leases, and entered
  ordinary Luna review. Neither remained as an orphan running task.
- Patch-only syntax failures now receive at most two same-thread correction
  prompts (under the existing three-round ceiling). The prompt contains only
  the bounded parser diagnostic and requires one complete unified diff; no
  source reread, scope expansion, general context request, or manager model is
  authorized. Repeated malformed output still closes deterministically.

### Checkpoint — 2026-08-17T16:54:00Z

- Production inspection found a policy/route mismatch in manager-remediation
  leaves: the selected model was Luna, but `Worker-Route` remained
  `MANAGER_REMEDIATION`. Closure admission, compact no-tools prompting, patch
  validation, typed expansion, and format repair were keyed only to the route
  label, so an incomplete remediation capsule could still launch Luna with the
  legacy explorer prompt.
- `worker-invoke-task` now derives one `luna_bounded_execution` decision from
  the actual execution policy. Luna-only manager remediation and ordinary Luna
  leaves use the identical fail-closed Context Closure and patch-only state
  machine. Non-Luna manager remediation retains its existing behavior.
- Caller/callee fanout is now an informational cut after the compiler embeds
  its deterministic bounded prefix. It no longer forces a graph-cut replan by
  itself when all required evidence is resolved and the compiled capsule fits
  byte/token budgets. Required type/interface fanout, symbol overflow, and
  oversized build inputs remain blocking cuts.
- This directly addresses `compmod-wc-2` revision 29, whose complete capsule
  was only 29,626 bytes and whose sole rejection was one supplemental
  `call-fanout` cut. The cut remains visible in `graph-cut.tsv` and quality
  telemetry, but does not misclassify an implementation-ready leaf.
- Current process sampling found zero Java, Joern, or SQLite processes. Active
  inference/replanning processes all used `gpt-5.6-luna` and consumed roughly
  0.1–0.2% CPU each. `compmod-wc-3` and `dpvis-w2-a2` had live Luna turns;
  `compmod-wc-2` and dplm had live Luna planning/remediation turns; compmod-wc-4
  had just completed review/checkpoint work.

### Checkpoint — 2026-08-17T17:01:30Z

- Two remaining global pauses were convergence-policy dead ends rather than
  process stalls. `compmod-wc-4` completed and checkpointed a leaf criterion,
  but the next criterion inherited the prior criterion's lifetime replan count
  and immediately hit `TOTAL_ROOT_REPLANS`. A verified criterion checkpoint now
  records an authorized `verified-criterion-boundary` epoch. Only counters for
  work after that acceptance boundary are enforced; lifetime totals remain in
  the snapshot and logs. Verified narrative increments do not reset budgets.
- dplm's Luna remediation planner ignored its eight-action contract, performed
  thirteen source/publisher commands, and hit the 500,000-token live estimate.
  Under Luna-only policy a manager-replan resource fuse is now a local recovery
  signal, not a project-wide `TOKEN_USAGE_ANOMALY`. The owner retries fresh with
  the bounded publisher diagnostic and an explicit compiled-evidence-only,
  no-repository-exploration prompt. Balanced-policy review/replan anomalies
  retain their existing inspection interlock.
- The Luna-only replan override now caps the intended path to the plan-node
  capsule, predecessor evidence digest, task output, and publisher. If compiled
  inputs do not identify a seam, Luna must decompose the first-unmet criterion
  instead of searching the repository.
- Focused Codex resource tests, root-liveness tests, Luna-only convergence tests,
  and the full v4.4 harness suite pass after these changes.

### Checkpoint — 2026-08-17T17:06:00Z

- The compmod-wc-4 reassessment was resolved from its verified revision-15
  criterion checkpoint. It immediately resumed Luna planning, published
  revision 16 in three commands, and correctly routed its 38,476-byte capsule
  to deterministic graph-cut repair without launching a worker.
- The dplm token incident was archived with preserved tracked overlay and
  rotated goal threads. Its fresh Luna planner used two commands before
  publication instead of the failed episode's thirteen source/publisher
  commands. Revision 26 then proved the manager-remediation closure fix in
  production: its incomplete 53,958-byte capsule was rejected before Luna
  launch even though its route label was `MANAGER_REMEDIATION`, and automatic
  graph-cut replanning began.
- Production patch repair exposed independent format and validation counters:
  a declared three-turn leaf could consume two format corrections and then a
  validation correction as attempt four. Patch-only format, diagnostic, and
  typed-context resumes now share the smaller of the configured patch-round
  ceiling and the leaf's declared expected-turn ceiling. Exhaustion publishes
  typed decomposition instead of starting another Luna turn.
- Luna-only convergence and the full v4.4 harness suite pass with the unified
  attempt ceiling.

### Checkpoint — 2026-08-17T17:09:15Z

- compmod-wc-4 revision 17 exposed a zero-file verification defect. Luna's
  closed evidence correctly concluded that no new mutation was required and
  emitted an empty diff header, but the generic patch parser converted that
  into `CONTEXT_INCOMPLETE` before running the declared focused validation.
- Patch-only `VERIFICATION_ONLY` leaves with
  `Expected-Max-Implementation-Files: 0` now take a trusted zero-file path. The
  harness requires the workspace fingerprint to equal the admitted baseline,
  runs focused validation itself, and synthesizes COMPLETE only on validator
  success. Failure becomes `VALIDATION_PREREQUISITE`; an actual patch is still
  rejected by the normal zero-file scope contract.
- The full v4.4 suite and Luna-only convergence tests pass after this change.

### Fuse-policy correction — 2026-08-17

- Investigation fuses are fail-stop boundaries and must never become automatic
  retry budgets. The 500,000-token defaults for authoritative per-invocation
  usage, live estimated per-invocation usage, and cumulative worker-task usage
  were audited and remain enforced through durable `TOKEN_USAGE_ANOMALY`
  interlocks.
- The temporary Luna-only exception for manager-replan resource guards has been
  removed. Manager review/replan item, command-output, estimated-token, and
  authoritative-token breaches again publish the same investigation marker and
  suppress all later project agent launches regardless of model policy.
- The temporary verified-criterion reset for monotonic root liveness has also
  been removed. Total root reviews, total replans, no-criterion reviews,
  lifetime, and root processed-token limits retain their fail-stop semantics.
  Only the explicit one-time Luna policy migration boundary remains authorized
  to establish its recorded child-decomposition epoch.
- Compact compiled-evidence planning, strict Context Closure admission,
  deterministic decomposition, patch repair limits, and zero-file trusted
  validation remain in place to prevent fuse breaches without weakening their
  investigative function.
- Production was fast-forwarded to `1a0d91c`. Effective configuration was
  evaluated for `compmod-wc-2`, `compmod-wc-3`, `compmod-wc-4`,
  `dplm-final-v2`, and `dpvis-w2-a2`; all five resolve each per-invocation
  authoritative limit, per-invocation live-estimate limit, and cumulative
  worker-task limit to exactly 500,000 tokens.
- The temporary verified-criterion epoch had overwritten `compmod-wc-4`'s
  legitimate policy-migration baseline. Its exact archived migration counters
  were restored (8 reviews, 8 criterionless reviews, 7 replans, 21,628 seconds,
  zero recorded processed tokens). The corrected monotonic calculation then
  stopped the root with `TOTAL_ROOT_REPLANS` at 11 post-migration replans versus
  the configured limit of 8. This investigation fuse was not resolved or
  bypassed.
- The one manager replan that predated deployment was terminated and only its
  induced local recovery-failure suppression record was cleared. Supervisors
  were restarted without changing task/fuse history; `dplm-final-v2` resumed a
  fresh manager replan under the corrected code. At the deployment check,
  `compmod-wc-2`, `compmod-wc-3`, `dplm-final-v2`, and `dpvis-w2-a2` were
  running, while `compmod-wc-4` was correctly paused for investigation.

## Validation journal

- `tests/test-codex-exec-jsonl.sh` — PASS. Includes Luna-only normalization,
  direct Sol rejection, Terra-role rejection, invalid policy pairing, exact
  500,000-token defaults, and Luna manager-replan anomaly interlocking.
- `python3 -m unittest tests.test_context_closure_tools` — PASS, 23 tests.
  Includes typed build-index, Joern, and context-path repair classification.
- `tests/test-decomposition-v2.sh` — PASS.
- `tests/test-leaf-goal.sh` — PASS, including provider retry, continuation,
  cumulative worker-task token-fuse publication/suppression, repair, and Oracle
  paths.
- `tests/test-root-liveness.sh` — PASS after restoring monotonic investigation
  accounting without verified-criterion resets.
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
- Context Closure and graft tool suites — PASS, 24 tests after adding
  mixed-defect routing, write-scope conservation, bounded discovered-test
  evidence, and pure-evidence-refresh coverage.
- Post-classifier regression: Luna-only convergence, SCIP importer,
  repository-index, and the complete v4.4 harness suite — PASS.
- Post-scope-conservation regression: Luna-only convergence, decomposition v2,
  Python Context Closure/graft tools, Bash syntax, and the complete v4.4
  harness suite — PASS.
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
4. Continue collecting per-obligation token and convergence telemetry from the
   five migrated production projects; all are already on `luna_only`,
   `decompose`, patch-only required closure, tracked overlay, and on-demand
   Joern.
5. Promote only after production evidence meets the completion criteria in the
   implementation plan; the code path is implemented, but token/divergence
   improvement has not yet been empirically demonstrated on completed projects.

## 2026-08-17 paused-project repair

- Corrected `STATE_OSCILLATION` to require consecutive equality of target,
  material strategy fingerprint, blocker fingerprint, and verified-item count.
  Historical visits to one criterion with different evidence no longer count.
- Moved the oscillation decision before task installation and replan-ledger
  mutation; a real anomaly now rejects publication atomically instead of
  publishing a runnable task and then creating a contradictory pause marker.
- Routed exact compiled Context Closure `repair.tsv` evidence into Luna
  recovery planning and enabled one fingerprinted provider retry for
  `INDEX_EVIDENCE_MISSING` as well as provider-unavailable failures.
- Recognized exact indexed build targets named in legacy `Required-Symbols` as
  build/validation boundaries rather than nonexistent SCIP source symbols.
- Separated Context Closure DAG admission repair from measured complexity
  repair. Pre-complexity closure rejection now consumes admission and suggested
  cut reports without requiring the not-yet-created `complexity.tsv`.
- Focused tests pass: irregularity detection, 24 Python Context Closure tests,
  decomposition startup transaction, Bash syntax, and Python compilation.
- Broader suites pass: Luna-only convergence, root liveness, leaf goal and its
  resource fuses, Context Closure shell tools, supervisor result barrier,
  decomposition v2, repository index, and the complete v4.4 harness suite.
- Deployment and audited production pause resolution are the remaining steps.
- Added an explicit `REARM_AFTER_HARNESS_BUG` liveness resolution for roots
  whose investigation fuse exposed a now-fixed harness loop. It requires an
  installed ancestor commit, refuses reuse of the same fix for the same root,
  preserves raw counters, and starts a new bounded fuse epoch. Normal incident
  resolution still cannot reset liveness.
- Live recovery exposed and corrected loss of typed pending transitions during
  architecture resolution. Context Closure condition/action/provider fields
  and `LUNA_ONLY_POLICY_MIGRATION` are now captured in the pause record and
  restored verbatim rather than downgraded to a generic replan.
- Pre-complexity Context Closure repair now publishes `COMPLEXITY_REPORT=-`
  instead of a plausible but nonexistent path, so bounded planners do not
  waste an action probing evidence that admission has not measured yet.
- Decomposition admission now aggregates every non-ready node's exact closure
  repair row into `context-admission/repair.tsv`; bounded DAG repair receives
  that compiled report directly alongside admission measurements and cuts.
- Live DPLM repair evidence showed architecture `affected_interfaces` entries
  containing repository paths were being treated as SCIP symbols. Existing
  paths in decision/edge interface metadata now seed exact path evidence;
  non-path identifiers remain symbol seeds.
- Production was advanced through commits `9bf4e63`..`509bfe6` using the
  required dev-push/production-pull workflow. The five previously paused roots
  were resolved without discarding accepted reviews, checkpoints, raw liveness
  history, or task evidence; liveness roots were rearmed only through audited
  fix-commit epochs.
- A live compmod-wc-4 leaf exposed duplicated required and supporting reference
  windows in compiled capsules. Required scoped references are now bounded to
  one stable occurrence per indexed symbol, supporting navigation to one item
  per semantic file boundary, and optional supporting source to one quarter of
  the complete capsule budget. The exact preserved leaf changed from repeated
  `CLOSURE_BUDGET_EXCEEDED` at 40,746 bytes to `READY` at 23,101 bytes with all
  five required symbols, two ownership boundaries, and six authority records.
- A live DPVIS worker exposed a typed expansion defect: `BUILD_OWNER` accepted
  exact files but rejected an authorized validation directory. The resolver
  now recognizes exact existing repository paths named by `Focused-Validation`
  and queries build ownership for descendant files. The formerly rejected
  `tests/render_compile` request now returns a 9,842-byte trusted extension;
  directory-wide mutation authority remains denied.
- The story startup repository index is reused in on-demand Joern mode, its
  specification and architecture fit remain accepted, and its all-Luna DAG has
  reached deterministic staging. No eager Joern/JVM or SQLite workload was
  present during the production restart checks.
- Current focused regression: Context Closure tools, typed context requests,
  and their production reproductions pass (31 Python tests total). All
  500,000-token authoritative, live-estimate, and cumulative task fuses remain
  unchanged.
- A live zero-file verification exposed that assigned validation inherited the
  persistent supervisor's launch directory. Relative commands such as
  `cmake -S resys` therefore resolved below `HARNESS_HOME` and produced a false
  `VALIDATION_PREREQUISITE`. Commit `8ecfe0d` makes the trusted runner enter the
  configured repository before executing the complete captured expression.
  A regression invokes the runner from `/`, and the preserved production
  command now builds the exact `resys_semantic_smoke` target successfully.
- The resulting compmod-wc-4 `REVIEW_STALLED` investigation fuse was retained,
  the fix was deployed, and only then was the preserved result explicitly
  requeued. A fresh Luna manager review is active; no task history, accepted
  evidence, or fuse threshold was removed.
- Current live state after deployment: compmod-wc-2, compmod-wc-3,
  compmod-wc-4, dplm-final-v2, and dpvis-w2-a2 are running worker, review, or
  local replanning transactions. DPVIS revision 52 and DPLM revision 47 both
  compiled `READY` capsules and launched Luna. The story startup remains an
  active bounded architecture-binding transaction after index reuse and DAG
  staging, not a paused supervisor loop.
- Story architecture binding subsequently found six non-ready leaves in an
  81-node candidate. Its repair prompt ambiguously requested both a line cap
  and byte cap, and Luna implemented that as two semicolon-separated reads of
  the same DAG, producing 66,597 command-output bytes. Startup correctly
  preserved the candidate as `RECOVERABLE`; it did not replay the input.
- Commit `f92328f` completes the startup repair input boundary. Context Closure
  aggregation now retains provider-only graph-cut rows whose evidence fields
  are `-`, context-closure candidate rejection points at the compact typed
  `repair.tsv` instead of the full admission table, and both repair prompts
  specify the single `head -n ... | head -c ...` pipeline while forbidding
  duplicate reads. A regression verifies that an ownership/byte-budget graph
  cut survives aggregation.
- Production resumed the preserved story startup after deployment. Its repair
  input is now 951 bytes and names all seven typed repair rows covering the six
  rejected leaves; observed repair commands use one source and remain at or
  below 32,768 bytes. The other resumable projects have no current blocking
  marker and remain active under Luna-only execution.
- The first bounded submission exposed a routing mismatch rather than another
  output failure: architecture-bound `GRAFT_GRAPH_CUTS` rows were entering the
  schema-only full-candidate repair contract, which forbids re-decomposition.
  Commit `ac619d1` adds a durable `recursive_context_closure` route that
  projects the exact bound admission, repair, and cut reports onto the staged
  pre-binding DAG checkpoint, marks the full candidate `REPAIR_ROUTED`, and
  requires recursive DAG repair before architecture binds again.
- Commit `91f41cd` preserves `CONTEXT_CLOSURE_REPAIR=1` from the typed durable
  `rejection_stage`, instead of inferring the phase from an obsolete prose
  rejection line. The live story restart now runs the recursive decomposition
  phase with the exact six rejected node IDs, seven repair rows, and compiled
  cut seams. No startup evidence or accepted specification state was reset.

### 2026-08-17 20:08 UTC — investigation-fuse repairs

- DPVIS reached its monotonic replan fuse after Luna emitted the same correct
  one-line change three times with off-by-one unified-diff hunk counts. Commit
  `70b4ffd` derives those redundant counts from the literal patch body before
  the unchanged Git syntax, baseline, scope, whitespace, focused-validation,
  and commit gates. The root was rearmed through an audited fix-commit epoch;
  revision 56 now has a validated 24,205-byte capsule and is running on Luna.
- COMP2's manager-replan episode correctly tripped the authoritative 500,000
  token fuse at 761,831 processed tokens. The live estimator had reported only
  418,612 because it omitted fixed system/tool context on every inference
  round. Commit `70b4ffd` includes the existing 20,000-token per-round
  allowance in the live estimate and aligns manager replans with their stated
  eight-action transaction ceiling. All three 500,000-token investigation
  fuses remain unchanged. The amplified thread was rotated and the exact
  query-stage prerequisite received separately audited scope authority.
- DPLM's N04 fuse recorded eighteen consecutive Context Closure repairs. The
  accepted architecture decision was present as compact normative authority,
  but its complete `affected_interfaces` inventory was also expanded into raw
  source, inflating the exact revision-54 capsule to 82,469 bytes. Commit
  `a2c7969` keeps decisions, invariants, edges, and gates as compiled authority
  and admits raw source only from explicit leaf paths/symbols and indexed
  relations. Recompiling the same assignment/index/overlay now returns
  `READY` at 20,438 bytes (5,110 estimated tokens); DPLM was rearmed against
  that exact evidence and is running.
- The story recursive repair expanded four rejected nodes into ordered Luna
  leaves and reached `ready=94 non_ready=0`. Startup then advanced into the
  architecture-binding critic. Its manager/worker supervisors remain stopped
  only because the startup transaction is still active; it is not stalled or
  paused.
- Active configured production projects currently have no architecture,
  token-usage, integrity, or human-dependency blocker markers. COMP2, COMP3,
  COMP4, DPLM, and DPVIS are in active manager/worker transactions; completed
  projects remain untouched. No harness-owned Java, Joern, or SQLite CPU load
  was present during verification.

### 2026-08-17 20:19 UTC — compiled publication and SCIP fallback repair

- COMP4 subsequently tripped its eight-item manager-replan investigation fuse
  at item 9/8. The fuse is valid and remains unchanged. The bounded episode had
  already found the right local runtime seam, but spent two extra actions on
  deterministic publisher diagnostics: removing a project `/tmp` build entry
  from `Context-Paths`, then adding the exact tracked file containing
  `semantic_gpu_architecture`.
- Recovery publication now compiles those corrections locally. For Luna-only
  recovery tasks the publisher removes only project-owned temporary validation
  paths and fills a missing required-symbol context path from one stable,
  tracked repository match, without widening mutation authority. This avoids
  spending model actions on metadata that the harness can derive exactly.
- Context Closure now uses one exact bounded excerpt from an explicitly
  declared `Context-Paths` file when SCIP omits a file-local variable, macro,
  generated declaration, or unsupported language construct. SCIP remains the
  structural relationship authority; the fallback supplies only the decisive
  source window and never triggers repository exploration by Luna.
- Recompiling the preserved COMP4 revision-33 assignment against the unchanged
  index and tracked worktree overlay changed it from
  `INDEX_EVIDENCE_MISSING` to `READY`: 23,614 bytes, 5,904 estimated tokens,
  with `semantic_gpu_architecture` supplied by an 18-line declared-path
  excerpt. No specification, source checkpoint, or task history was reset.
- Focused verification passes: 29 Context Closure unit tests, Luna-only
  convergence, SCIP importer, irregularity detection, Codex JSONL policy and
  fuse tests, Bash syntax, Python compilation, and `git diff --check`. The
  authoritative-per-invocation, live-estimated-per-invocation, and cumulative
  worker-task limits remain exactly 500,000 tokens; the manager replan ceiling
  remains eight item starts.
- The first COMP4 restart exposed a restart-time policy migration defect:
  `Manager-Remediation: 1` was treated as proof of a stronger-model route even
  when the assignment was already a publisher-validated LOW/LUNA bounded leaf
  and the effective manager model under `luna_only` was Luna. Startup archived
  revision 33 and began an unnecessary replan; that process group was stopped
  before it could publish another assignment.
- Luna-only migration now distinguishes remediation authority from execution
  model. It preserves manager-remediation assignments only when all executable
  leaf limits (route, type, complexity, validation, files, turns, actions, p95,
  score, and Terra exception) satisfy the Luna contract. Legacy broad or
  incomplete manager assignments still migrate. Upgrade recovery also reverses
  the exact false-migration state atomically when no newer root artifact exists,
  restoring the archived safe assignment and clearing only its matching policy
  marker. A focused regression covers both preservation and reversal.

### 2026-08-17 20:35 UTC — compiled manager-review evidence

- COMP3 revision 44 and DPVIS revision 56 independently tripped the unchanged
  500,000 live-estimated-token fuse during Luna manager review, at 521,235 and
  516,624 tokens respectively. Both terminal rejections had already committed,
  no worker/source mutation was left partial, and each root has a durable
  `NEEDS_REPLAN` continuation. The fuse behavior is correct; the common defect
  was review-context amplification.
- The review prompt named valid bounded component paths but also instructed the
  model to read them individually. One optional missing criteria file caused a
  combined read to abort; Luna then searched project control directories for
  review context and schemas. COMP3 followed the same compatibility prose into
  repeated filesystem discovery. This spent the review budget rediscovering
  harness evidence that had already been compiled.
- Manager review now deterministically emits one
  `manager-review-packet.md`. It contains the development policy, compiled
  plan/DAG/specification/architecture authority, exact assignment, bounded
  worker/result digest, and all pass, checkpoint, accept, and reject schemas.
  Optional absence is represented as `NONE`. The packet is atomically written,
  permission-restricted, and rejected before launch if it exceeds the existing
  32 KiB bounded-read cap.
- The final prompt authority requires exactly one packet read, the harness
  bounded diff, assigned focused validation, at most one decisive source
  window, one review-note write, and one terminal command. It explicitly
  forbids probing, concatenating, or searching for the component files. The
  archived evidence that triggered these incidents totals well below the cap
  for both projects.
- Full `test-harness.sh`, Luna-only convergence, irregularity detection, Bash
  syntax, and `git diff --check` pass. The standalone Codex JSONL test retains
  a pre-existing fixture-order failure: its intentional Luna-only model-policy
  violation now creates the expected durable project-integrity marker, but the
  fixture does not resolve or isolate that marker before its next launch.
- A separate orphaned `resys_knowledge_fixed_point_smoke` process group from an
  older interactive Codex validation was consuming one CPU continuously. It
  was not a Joern/SCIP/SQLite closure process; the exact process group was
  terminated. The two anomaly-paused supervisors were stopped before deploy so
  they cannot perform background maintenance until their incident records are
  explicitly resolved.
- Commit `9813147` was deployed through the required dev-push/production-pull
  path. Both anomaly records were resolved with `PRESERVE`, their amplified
  goal threads were rotated, and COMP3/DPVIS restarted from the existing
  `NEEDS_REPLAN` boundaries. Both supervisors launched fresh Luna manager
  remediation rather than replaying a review or remaining paused.
- The first new DPVIS publication exposed a separate deterministic closure
  admission defect. Revision 57 had exact indexed/overlay definitions for both
  `dpv_render_compile` and `validate_payload`; its only unresolved row was the
  extra read-only `tests/render_compile` directory, because no descendant was
  selected. Context Closure now distinguishes a directory that contains
  mutable `Allowed-Scope` (which still requires an exact structural seed) from
  an otherwise unused read-only evidence boundary (which contributes zero
  evidence and is not missing evidence). The 30-test closure suite covers both
  cases and passes.
- COMP3 revision 45 exposed another deterministic selector mismatch:
  `resys/include/rs_computing.h#rs_computing_supersede_normalized_acquisition`
  is an exact bounded source selector, but the compiler had treated the full
  string as a filesystem path. Context Closure now resolves a repository-local
  `file#symbol` selector to one bounded live symbol window and reports a typed
  `CONTEXT_SELECTOR` omission only when the file exists but the symbol does
  not. The closure suite now has 31 passing tests.
- DPVIS revision 58 then requested the exact failing `IT-RCP-000` assertion.
  Expansion correctly rejected it because revision 58 had removed the tests
  boundary, but replaying the same request against revision 57's declared
  `tests/render_compile` boundary exposed two resolver gaps: indexed test rows
  were authorized only by exact path equality, and framework-specific tests
  absent from the test table had no bounded fallback. The resolver now honors
  file-or-directory containment and, only inside declared indexed files,
  selects up to four exact identifier windows when the test importer omitted
  the selector. The archived request now compiles a 9,647-byte trusted
  extension from `render_compile_tests.hip`; all six resolver tests pass.
- Live manager-review verification showed that the first packet format met the
  32 KiB byte cap but exceeded the 200-line policy, so Luna split COMP3's
  23,867-byte packet into three `sed` reads. Embedded packet components are now
  newline/tab/carriage-return/backslash escaped onto one content line each.
  Packet construction enforces both byte and line caps, and the prompt supplies
  one exact `head -c` command while forbidding line-range reads. Full harness
  regression passes with the compact packet and asserts both limits.
- DPVIS revision 59 named `tests/render_compile/CMakeLists.txt` in exact
  `Allowed-Scope` while using its containing `tests/render_compile` directory
  as Context-Paths. The compiler previously recognized that the directory
  contained mutable scope but still reported no exact seed. Exact file
  descendants of a declared context directory are now promoted directly from
  immutable mutation authority into `DECLARED_CONTEXT` evidence. A broad
  directory mutation scope remains incomplete and must still be decomposed.
  The closure suite now has 32 passing cases.
- DPVIS revision 60 then supplied the misspelled read-only path
  `include/dpv/render_compile.h`; the repository index contains exactly one
  matching tracked basename at `include/dpvis/render_compile.h`. Missing
  repository-like Context-Paths now relocate only when the current index has
  one unique exact basename and that file exists in the live repository.
  Ambiguous or absent paths still fail closed. The closure suite now has 33
  passing cases.
- COMP4's new 8/8 architecture-reassessment fuse was reached after revision 34
  closure admission, not after a worker architecture decision. SCIP retained
  the identity of `rs_sol_program_choice_evaluate_required_gpu_hip` but omitted
  its definition region. The compiler therefore reported a missing required
  definition and later embedded the complete declared 289-line HIP source,
  producing a 38,707-byte capsule. Known symbols with no definition now use the
  same exact declared-path symbol-window fallback as wholly omitted symbols,
  capped at 96 lines for this weaker provider case;
  the full file is not subsequently duplicated. The fuse remains enforced and
  will be resolved only after the archived revision recompiles within budget.
  The closure suite now has 34 passing cases.
- With the 96-line cap deployed, the exact archived COMP4 revision 34 compiles
  `READY` at 30,692 bytes and 7,673 estimated tokens with no unresolved rows.
  The 8/8 marker was resolved through the audited
  `REARM_AFTER_HARNESS_BUG` path tied to commit `79db684`; no limit was raised.
  COMP4 restarted successfully and is running a fresh Luna remediation turn
  from the preserved typed closure boundary.
- The compact review packet is now proven in production: COMP3 revision 48's
  packet is 21,520 bytes, 57 lines, mode 0600, and Luna read it with exactly
  one `head -c 32768` command before the bounded review diff. No component
  discovery or line-range packet read occurred.
- Repeated CPU inspection found no harness-owned Joern, SCIP, Java, or SQLite
  workload. Additional `resys_knowledge_fixed_point_smoke` process groups were
  launched by a separate long-lived interactive Codex session in
  `/home/mf/mf-kss-refactor/resys`, outside every configured harness. Their
  exact process groups were terminated without stopping that unrelated Codex
  session; they are not Context Closure activity.
- DPLM revision 65 exposed a manager-replan action-amplification defect. The
  recovery turn consumed three reads of overlapping control evidence, then two
  publisher corrections: one semantic scope/context correction and one purely
  mechanical heading-case correction. Its third publish command became item
  9/8 and correctly tripped the unchanged manager-replan action fuse before a
  worker or source edit ran.
- Manager recovery now receives one deterministic compiled packet containing
  bounded plan/specification/architecture authority, trigger and criterion
  state, typed closure repair, continuity evidence, operator resolution, and
  recent strategy history. Components are individually capped, escaped onto
  one line, permission-restricted, and the complete packet is rejected before
  inference if it exceeds the existing 32 KiB or 200-line bounded-read policy.
  The final prompt permits one packet read and only one additional exact read
  when the packet explicitly marks a decisive component truncated.
- Recovery publication now canonicalizes only case variants of the three
  already-mandatory section headings (`Objective`, `Acceptance criteria`, and
  `Validation commands`). This removes a no-judgment repair turn while leaving
  scope, context, strategy, acceptance, model-policy, and publication-attempt
  validation unchanged. Regression coverage deliberately emits title-case
  variants and proves they publish through the canonical schema. The 8-action,
  two-publication-attempt, and all 500,000-token fuses remain unchanged.
- Live DPLM recovery confirms the compiled path: revision 66 used five items,
  began with exactly one 20,516-byte packet read, published on its bounded
  second validator attempt, compiled a 21,592-byte `READY` Context Closure
  capsule, and launched Luna without fallback repository context.
- DPVIS then reached the intentional `TOKENS_WITHOUT_VERIFIED_GAIN` fuse after
  17 paid episodes and 564,590 processed tokens without a new facet. The final
  three attempts all proposed the same exact one-line source correction, but
  format repair reduced the patch to a zero-context hunk whose stale line
  number made plain `git apply` reject it. This was patch framing failure, not
  another semantic exploration failure.
- The trusted patch runner now admits a zero-context replacement only when its
  complete removed-line sequence occurs exactly once in the current allowed
  source file. Only after that live uniqueness proof does it use Git's explicit
  `--unidiff-zero` mode for check and apply. Zero-context additions, missing
  anchors, ambiguous anchors, out-of-scope paths, binaries, generated paths,
  and whitespace errors still fail closed. The closure/tool suite now has 36
  passing cases, including stale-line relocation and ambiguous-anchor rejection.
