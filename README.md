# Coding Agent Filesystem Harness v5.0 (for Codex CLI)

A local, event-driven coding harness for Linux. One source tree now contains
both execution modes, selected per project with `HARNESS_MODE=full` or
`HARNESS_MODE=light`. The lowercase spelling `harness_mode` is accepted as a
compatibility alias; new files should use the uppercase shell variable.

## Features

- Unified modes: Full keeps durable multi-level decomposition and independent
  review; Light keeps the lower-overhead persistent worker loop. Existing
  Light files that define `DEVELOPMENT_POLICY` but omit `HARNESS_MODE` continue
  to dispatch to Light, while existing Full files default to Full.
- Proactive v2 decomposition: a fresh Terra planning/critic turn registers a
  topologically ordered DAG with dependencies, deliverables, evidence,
  focused validation, bounded paths/symbols, complexity, and worker routing.
- Per-leaf model routing: deterministic low-complexity leaves go to Luna;
  architecture, contracts, concurrency, ambiguity, and integration go to
  Terra. Optional final Oracle audits default to Sol when enabled.
- Bounded context capsules: every v2 assignment receives a concise generated
  package of its contract, dependencies, allowed discovery surface, baseline,
  and authoritative files.
- Durable specification planning: the manager records an immutable project
  plan and advances only the first unfinished plan item.
- Explicit task decomposition: each root has ordered, independently verifiable
  criteria, broad leaves may gain append-only children, and every continuation
  targets the first unmet leaf.
- Incremental delivery: verified partial work is checkpointed with source
  snapshots, evidence hashes, and append-only criterion/history ledgers.
- Default leaf-goal workers: one independently verifiable leaf can span multiple
  bounded Codex processes, with durable continuation receipts and one manager
  review only at a terminal outcome.
- Gain-aware automatic replanning: convergence guards ask the persistent
  project manager for a materially different strategy without discarding
  checkpoints; each new verified item resets escalation.
- Manager remediation for local blockers: an exhausted ordinary-replan budget
  or unchanged local code/build/integration blocker becomes a visible task
  executed with the manager model, not a human-intervention stop.
- Persistent but bounded worker context: root-scoped conversations resume
  across checkpoints and rejections and rotate after repeated rejection.
- Event-driven execution: ordinary Bash supervisors launch Codex only when
  work exists; no Codex process remains alive while waiting.
- Provider resilience: transient network, capacity, rate-limit, and quota
  failures retry while preserving ownership and heartbeat state.
- Bootstrap recovery: when a first task was durably published before bootstrap
  failed, restart registers its captured manager thread without another model
  invocation or duplicate publication attempt.
- Recovery routing names the exact controlled Terra exception after the bounded
  Luna strategy budget is exhausted, preventing schema-rejection replan loops.
- Revision publication keeps generated build trees in validation context,
  clamps execution budgets to root ceilings, and returns a failure status for
  genuine authority expansion so managers cannot report a false publication.
- Reassessment resolution atomically restores replanning for taskless active
  roots, and publication rejects a stale planner's second live revision of the
  same root.
- Luna worker-turn metadata is capped independently from predicted agent-action
  counts, and remediation prompts keep validation-only sources outside mutation
  authority unless evidence identifies a required edit there.
- Focused closure mode: high-progress tasks receive a bounded
  diagnose-correct-rebuild-smoke budget instead of unbounded revision churn.
- Independent final audit: an optional fresh Oracle checks specification
  traceability and may create bounded remediation plan items.
- Filesystem observability: assignments, results, reviews, JSONL streams,
  checkpoints, progress, and lifecycle events remain inspectable on disk.
- Attention-only watcher color: problematic states render only their STATUS
  text in red; normal, stopped, and completed rows retain ordinary terminal
  colors without row-wide inversion.
- Executable architecture gates: invariant, compatibility, and health
  validations reject accidental English prose before DAG installation; bounded
  review-attested checks use explicit focused, incremental, or clean descriptors.
- Race-safe result review: the manager snapshots a worker-invocation barrier
  once, so normal worker-supervisor cleanup cannot strand a published result or
  terminate the manager between separate marker-field reads.
- Checkpoint-aware recovery: a completed Terra decision can hand its bounded,
  zero-write validation residue to a deterministically measured LOW/LUNA leaf.
  Suppressed recovery failures appear as `RECOVERY_STALLED` instead of a
  healthy running manager merely because its idle watcher process still exists.
- Safe restart and recovery: supervisor restarts preserve plans, task state,
  checkpoints, retained threads, and completed evidence; child processes do
  not inherit supervisor lifetime locks.
- Explicit runtime configuration: one trusted `.env` selects repositories,
  state, accounts, models, timing, and child-process runtime paths.
- Validated Git delivery: implementation agents commit task-owned source and
  related text artifacts by default; generated output, binaries, ignored files,
  unrelated paths, and direct model-driven Git history mutations are rejected.
- Complete publication diagnostics: architecture-guarded assignments report
  every missing or mismatched binding field in one rejection, preserving the
  bounded manager correction budget for a successful second publication.
- Measured remediation limits: Terra manager-remediation leaves obey the same
  Sol-authored action and p95 token ceilings as ordinary worker leaves; their
  non-token leaf fuse produces a decomposition handoff instead of a false
  human-dependency marker.
- Aggregate decomposition diagnostics: malformed complexity vectors and
  Terra-routed routine coding leaves are reported together across the complete
  candidate, avoiding one paid Sol correction turn per defective node.
- Machine-owned recovery bindings: automatic replans and manager remediation
  restore invariant, decision, edge, and health-gate metadata from the accepted
  architecture registry before validation instead of asking an agent to copy
  five exact fields and spending a publication attempt on transcription.
- Linearized DAG ancestry: specification-relation validation exploits the
  already-enforced topological node order to build ancestor sets once, avoiding
  repeated pairwise transitive-closure scans on large decomposition graphs.
- Effective measured metadata: task publication compares normalized dimensions
  with the deterministic complexity report rather than stale lower declarations.
  After the configured Luna-strategy limit, a fresh measured recovery may keep
  its vector while escalating to a justified HIGH/TERRA boundary.

## Process model

```text
manager-decomposition-critic (Full v2, fresh Sol context by default)
    -> drafts and criticizes the dependency DAG
    -> registers only a schema-valid, topologically ordered plan

manager-bootstrap
    -> reads the registered DAG (or records a legacy plan)
    -> publishes one dependency-ready routed leaf
    -> manager exits

worker-supervisor (local Bash, no tokens)
    -> detects task 001
    -> launches Luna or Terra from the leaf route
    -> legacy mode: worker publishes one result and exits
    -> leaf-goal mode: worker may publish CONTINUE and exit
       -> launcher resumes the same logical goal
       -> only COMPLETE / NEEDS_DECOMPOSITION / HARD_BLOCKED publishes a result

manager-supervisor (local Bash, no tokens)
    -> detects terminal result 001
    -> resumes manager Codex thread
    -> manager accepts/checkpoints/rejects and publishes the next task
    -> convergence guards may request a persistent-manager automatic replan
    -> repeated local blockers become bounded manager-remediation tasks
    -> if acceptance leaves a planning gap, resumes a dedicated planning turn
    -> manager exits

worker-supervisor
    -> detects the next task
    -> repeats
```

## Selecting a mode

Use the same top-level `bin/` commands for both modes:

```bash
export HARNESS_MODE="full"  # or "light"
export HARNESS_HOME="/path/to/coding-agent-fs-harness"
export HARNESS_BIN="$HARNESS_HOME/bin"
```

Full v2 additionally uses:

```bash
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="1"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS="1"
export HARNESS_START_MAX_AGENT_INVOCATIONS="10"
export HARNESS_DOMAIN_PROFILES=""  # optional comma-separated profile IDs
export HARNESS_MAX_LUNA_STRATEGY_FAILURES="3"
export HARNESS_MAX_LUNA_ALLOWED_PATHS="8"
export HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF="2"
export HARNESS_MAX_LUNA_COMPLEXITY_SCORE="24"
export HARNESS_MAX_LUNA_PREDICTED_ACTIONS="8"
export HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS="250000"
export HARNESS_MAX_COMPLEXITY_DECOMPOSITION_PASSES="3"
export HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES="32768"
export HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES="65536"
export HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES="32768"
export HARNESS_MIN_LUNA_NODE_PERCENT="80"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="80"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export HARNESS_MODEL_POLICY="legacy"             # legacy|luna_only
export HARNESS_ESCALATION_POLICY="legacy"        # legacy|decompose
export HARNESS_ARCHITECTURE_GUARDS="1"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export DECOMPOSITION_MODEL="gpt-5.6-sol"
export DECOMPOSITION_REASONING_EFFORT="high"
```

When pre-acceptance review is enabled, `harness-start` first grounds the
specification against current repository contracts, symbols, producers,
consumers, build targets, tests, and history. It records authority-qualified
facts for the decomposition planner. A demonstrated contradiction or missing
observable product decision stops before DAG registration with
`SPEC_CLARIFICATION_REQUIRED`; coding difficulty and repository details that
can be discovered locally are not clarification reasons. The complete report,
facts, and structured questions are written under `$REPOSITORY/spec-review/`,
while commands and watchers display only the repository-relative report name.
Revise and commit the governing specification or repository evidence, then run
`harness-start` again to obtain a fresh review.

After acceptance, the governing specification is immutable implementation
authority. Decomposition staging and task publication reject any executable
write scope that names the specification itself or one of its parent
directories. Architectural decisions belong in the durable architecture
registry; a worker cannot silently amend the accepted contract while coding.
An architecture decision may cite that accepted, committed specification as
its evidence without re-delivering the specification in the producer task's
commit. All non-specification decision artifacts retain controlled-commit
provenance requirements.

Structured requirement `Dependencies` are extracted before the reviewer is
launched. A source-declared cycle is recorded deterministically as
`CONTRADICTORY_REQUIREMENTS`, so no manager tokens are spent and no generated
IR can hide the conflict by dropping an edge. Accepted IR registration also
checks every source-declared dependency for fidelity.

For a stopped Full project, `harness-start` requires `REPOSITORY` to be a Git
worktree with a valid `HEAD` and no staged, unstaged, or non-ignored untracked
files, except untracked files beneath the harness-owned `spec-review/` and
`architecture-review/` response directories. Tracked or staged changes under
either response directory are still rejected.
It prints the exact porcelain-status entries and exits before recovery or any
agent invocation when this preflight fails. Ignored build products are not
considered dirty. A redundant start against a live manager or worker supervisor
remains idempotent and does not apply this stopped-project preflight. A
startup/reviewer/worker process without a live supervisor does not bypass
validation and is reported as an overlapping start instead.

Long initial review, decomposition, and bootstrap work can be detached safely:

```bash
harness-start --background /path/to/repository/harness.env
```

The launcher performs the clean-repository and overlap preflight, starts a new
session with closed standard input, redirects all startup output to a
project-state log, writes a durable `harness-start-background.status` record,
prints the PID/log/status paths, and returns immediately. Exit status `3` is
recorded as `SPEC_CLARIFICATION_REQUIRED`, exit status `6` is recorded as
`ARCHITECTURE_REDESIGN_REQUIRED`, and exit status `7` is `RECOVERABLE`;
other nonzero exits are `FAILED`.
Ordinary `harness-start ENV_FILE` remains synchronous for interactive use.

An accepted review also installs a normalized Specification IR: independently
testable obligations, typed semantic relations, a bounded repository inventory,
and authority-qualified repository facts. The decomposition critic must provide
an `obligation_id -> node_ids` coverage sidecar; registration rejects a missing
obligation or an unjustified DAG node. Workers and managers receive only the
obligations allocated to their node, and final Oracle PASS requires independent
evidence for every obligation. This keeps product requirements distinct from
repository-derived facts and fallible planning hints.

An independent Sol architecture-fit transaction challenges that acceptance
before DAG construction. Its accepted verdict is durable for the specification,
repository baseline, and domain-profile digest. The critic reasons
from a deterministic, byte-bounded capsule compiled from normalized IR,
accepted repository facts, exact selected source evidence, and the indexed
architecture slice. The capsule is embedded in the critic prompt; Sol may open
only one exact, bounded repository source window when that compiled evidence
leaves a decisive architecture question unresolved. A command-output limit at
this startup stage records `control/startup-recoverable.env`, preserves the
accepted specification review as the resume checkpoint, and refuses to replay
the unchanged failed input until the harness implementation or accepted inputs
change.

A genuine unresolved product contract transitions back to
`SPEC_CLARIFICATION_REQUIRED` and writes a critic report under
`$REPOSITORY/spec-review/`. If the governing sources are clear but the generated
facts, obligations, or relations are defective, the critic requests automatic
IR renormalization instead; `harness-start` reruns the reviewer once and refuses
repeated compiler churn. The renormalization limit is durable across starts,
and each startup transaction also has a hard provider-process budget. A
non-converging compiler pass enters `SPECIFICATION_NORMALIZATION_STALLED`; an
unchanged restart refuses further agent calls. Thus only missing human
authority is bounced as specification clarification; structural fitness is
handled by the separate architecture gate below.

The following Sol DAG-construction turn consumes a larger deterministic
decomposition capsule containing the complete normalized obligation and typed
relation projections plus the same selected repository and architecture
evidence. It follows the same one-source bounded fallback policy. A
command-output limit at this stage is also `RECOVERABLE`, with accepted
architecture fit retained as its resume checkpoint.

The architecture-binding Sol turn likewise receives one deterministic capsule:
the complete fixed DAG and coverage, normalized authority projections, selected
repository/index evidence, and the accepted architecture-fit decision. It may
not reopen those global files. A binding-stage output-limit hit preserves the
staged DAG as a `RECOVERABLE` resume checkpoint. If the critic instead finds
that the fixed DAG contradicts governing ownership or dependency architecture,
its diagnostic becomes a durable DAG rejection and startup enters the bounded
DAG-repair loop rather than reporting a generic failure.

The candidate schema-repair turn follows the same one-source bounded-read
policy and never emits a whole-file rewrite or generated patch into command
output. Its output-limit checkpoint preserves the rejected candidate and also
refuses an unchanged replay until the harness or accepted inputs change.
Semantic DAG/coverage repair uses targeted diagnostic identifiers under the
same policy; its recoverable checkpoint resumes from the rejected staged DAG.
No-progress fingerprints are committed only after a repair turn completes, so
a provider failure or resource guard cannot poison the next startup resume.
Submission diagnostics are captured to a file and only a bounded tail is
returned to Sol. A newly staged candidate remains durable progress even if the
enclosing agent wrapper is interrupted immediately after submission.

Before DAG registration, this dedicated Sol critic performs an evidence-backed
architecture-fit review. If the accepted feature necessarily conflicts with a
foundational ownership, transaction, migration, dependency-direction,
contract-authority, observability, critical-invariant, or resource-lifetime
boundary, it enters `ARCHITECTURE_REDESIGN_REQUIRED` instead of patching around
the conflict. Reports, structured issues, and a requirements-only redesign
brief are written beneath `$REPOSITORY/architecture-review/`. Optional cleanup,
ordinary local refactoring, missing implementation, and architectural taste are
not valid redesign blockers. Use the copy/paste report to prepare a separate
redesign harness:

```bash
harness-show-redesign-request /path/to/repository/harness.env
```

After the redesign is integrated, the changed repository baseline causes a
fresh specification and architecture-fit review. An operator can deliberately
combine redesign and feature work with an auditable waiver:

```bash
harness-start --force-decomposition /path/to/repository/harness.env
```

Force does not dismiss the finding. Registration requires one prerequisite
Terra `CROSS_COMPONENT_ARCHITECTURE` node and one open critical debt record per
redesign issue, a focused critical health gate, and dependency ordering that
keeps affected Luna work unavailable until remediation is accepted.

After architecture fit is accepted, one fresh Sol turn constructs and durably
stages only the DAG and obligation coverage. A second fresh Sol turn binds that
fixed DAG to architecture invariants, decisions, edges, health gates, and debt.
`manager-submit-decomposition` stages the complete candidate before
deterministic validation and installs all sidecars as one transaction. A
schema rejection is handled by a bounded repair-only turn. DAG/coverage
serialization omissions are repaired deterministically by binding uncovered
executable leaves to their nearest covered acceptance boundary, avoiding Sol
turns that merely rename otherwise valid leaves. The repair refuses a mapping
that would assign more than the Luna-ready two-obligation limit. Measured
complexity repair uses bounded node-replacement patches, so Sol reads and
rewrites only rejected leaves while the harness merges and globally validates
the immutable DAG. Ambiguous omitted coverage uses the same pattern: Sol emits
only a one- or two-obligation mapping for each uncovered executable leaf, and
the harness merges and validates it. DAG/coverage
validation also stages before checking and uses its own bounded repair turn.
Final Oracle audits receive one generated, bounded context capsule and are
forbidden from recursively enumerating archives, old plans, policy documents,
or rereading the same control files. This keeps global verification independent
without replaying the complete implementation history into every audit action.
If startup is
interrupted after either staging boundary, the next `harness-start` continues
without repeating earlier global model exploration. Failed detached startup
is reported explicitly as `STARTUP_FAILED` instead of looking merely stopped.

Reusable domain theory is opt-in through `HARNESS_DOMAIN_PROFILES`. A profile
resolves first from `$REPOSITORY/.harness/domain-profiles/NAME.tsv`, then from
`$HARNESS_HOME/domain-theory/NAME.tsv`. Selected profile invariants become
normalized obligations with digest provenance; unselected profiles contribute
no semantics. See `templates/domain-profile-template.tsv`. The bundled
`deterministic-multi-gpu` profile captures device-work, routing, merge, topology,
failure, fallback, and cleanup invariants and applies only when explicitly
selected.

`templates/project-plan-template.tsv` documents the exact DAG schema and
`templates/leaf-goal-task-template.md` documents the routed leaf contract.
`TEST_IMPLEMENTATION` is a first-class `LOW`/Luna leaf for unit tests, fixtures,
test helpers, and test-only build registration that leaves production contracts
unchanged.
Run `bin/harness-decomposition-metrics ENV_FILE` to write and display cost and
quality signals such as route counts, terminal leaf success, zero-gain turns,
replans, verified items, Luna's share of coding assignments, Terra decision
versus coding assignments, and manager/worker tokens per verified item. Token
accounting deduplicates resumed threads by taking their latest cumulative usage.
`bin/harness-statistics ENV_FILE` reports manager, Luna-worker, Terra-worker,
and Oracle token totals plus manager/worker and Luna/Terra processed-token
ratios. It also groups decomposition quality, route share, delivery outcomes,
zero-gain iterations, and verified Specification IR coverage.
In Full mode, `bin/harness-costs ENV_FILE` attributes resumed-thread token
deltas to specification review, decomposition, bootstrap, planning, replanning,
implementation review, Oracle validation, and worker implementation. Its report
shows costs split between scaffolding and implementation and summarized by
model. Cached input remains part of total input but is charged
at the cache-read rate instead of the ordinary input rate. The bundled
`model-pricing.tsv` contains the default USD-per-million rates and may be
replaced with `HARNESS_MODEL_PRICING_FILE`. Cache writes are excluded because
current Codex usage events do not expose cache-write token counts. Use `--tsv`
for machine-readable cost records. `harness-statistics --tsv` remains the
machine-readable delivery and raw-token report.

Every agent invocation has item, token, and wall-clock circuit breakers.
Ordinary manager and worker turns use
`HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION` (500,000 by default). The
fresh Sol decomposition transaction has its own two-million-token bound. The
atomic Specification IR compiler uses the separately
bounded `HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION`
(eight million by default) because one accepted review may normalize hundreds
of imported obligations. A failed or resource-exceeded specification-review
turn cannot make its candidate control state authoritative. Clarification
omission claims against fenced registries are checked directly against the
complete EOF-safe source region before they can be recorded.
Fresh Sol DAGs also carry a deterministic complexity vector for every node:
allocated obligation weight, bounded paths and symbols, behavioral concerns,
failure paths, ownership and concurrency boundaries, validation surfaces,
implementation-file and action estimates, predicted p95 tokens, and semantic
risk domains. A routine leaf that exceeds any Luna budget is rejected before
installation. Sol receives the measured excess and must recursively split the
node; changing labels or routing ordinary coding to Terra cannot satisfy the
validator. Terra is accepted only at an irreducible decision or integration
boundary with an explicit exception class. Observed worker tokens, actions,
output, reads, changes, duration, and outcome are retained for analysis. Only
clean successful episodes that are ultimately accepted enter executable-leaf
calibration; resource fuses, item-budget exits, and other anomalous episodes
remain visible but cannot inflate every future child. After enough clean
samples, model-specific p95 tokens per complexity point can only tighten future
predictions.

Run `bin/harness-complexity ENV_FILE` to compare each installed prediction with
observed worker episodes and model-specific completion/fuse/prediction rates.
Use `--all` to aggregate every project under the configured state root.
Run `bin/harness-decomposition-tree ENV_FILE` to display the immutable DAG as a
terminal tree with node state, complexity, configured worker route,
dependencies, deliverable, and active task route. `--compact` shows one line
per node; `--details` also shows evidence, validation, scope, symbols, and the
current criterion tree. New typed v2 plans must meet
`HARNESS_MIN_LUNA_CODING_NODE_PERCENT` (80 by default). Its denominator is
only coding-eligible nodes; Terra contract, architecture, concurrency,
ambiguity, and integration nodes do not dilute the Luna target.
For a stopped, incomplete older Full-v2 project, run
`bin/manager-reclassify-project-plan ENV_FILE` to have a fresh Sol critic
reclassify only its `PENDING` nodes under the current Luna-first policy. The
command refuses to run while harness processes are alive, preserves all DAG
structure and every `ACTIVE` or `COMPLETE` route, validates the configured
minimum pending Luna coding percentage, and stores the previous DAG plus an audit
report under `control/reclassifications/` before installing the candidate.
Measured plans intentionally reject label-only reclassification: their
structure and complexity estimates must be revised together by Sol.
With `HARNESS_PREFERRED_WORKER_ROUTE=LUNA`, typed new DAGs must classify every
node with `leaf_type`; routine coding types cannot route to Terra. Existing
immutable ten-column DAGs remain readable, but a manager may override an
inherited HIGH/TERRA route with LOW/LUNA when the executable leaf satisfies the
bounded Luna contract. Terra remains available for decision work and after the
configured number of genuinely different Luna strategies fails.

### Architecture constitution and health guards

New Full-v2 projects use `HARNESS_ARCHITECTURE_GUARDS=1` by default. This requires
leaf-goal mode and adds an immutable architecture registry above the execution
DAG. Start from `templates/architecture/` and initialize the six sidecars before
registering the DAG:

```bash
bin/manager-init-architecture ENV_FILE ARCHITECTURE_SOURCE_DIR
bin/manager-init-project-plan ENV_FILE DAG_FILE SPECIFICATION_COVERAGE_TSV
```

The registry records global invariants, explicit architecture decisions,
producer/consumer edge contracts, per-node bindings, cumulative health gates,
and accepted debt. Every plan node must have exactly one binding. Consumers
cannot start before their decisions are accepted and edge producers complete;
workers publish structured impact manifests; managers verify the affected
invariants and edges; registered checks run during acceptance. Unresolved
critical debt, expired debt, or a missing health gate blocks final completion.
Every cumulative health gate is rerun at the final boundary so a later leaf
cannot rely on stale earlier system-health evidence.

An edge compatibility command runs when its consumer is accepted. Producer
acceptance establishes the committed contract artifact and must not require a
future consumer target to exist.

Component and lane gates must use focused selectors. Broad aggregate output may
be retained as baseline evidence, but unrelated aggregate failures cannot be a
mandatory success condition. A human-owned specification can explicitly opt a
gate into whole-project success by including `HARNESS_BROAD_GATE_REQUIRED=1`
in its registered validation command. Defective installed registries can be
replaced while stopped with `harness-revise-architecture`; the command validates
the candidate against the durable DAG, preserves ledgers, and archives the
previous registry. If a defect is discovered only while reviewing a committed
worker result, the manager may use `manager-revise-architecture` to perform the
same transaction under the project lock and then retry acceptance in that turn.

Use these controlled commands during execution:

```bash
bin/manager-accept-architecture-decision ENV_FILE DECISION_ID TASK_ID EVIDENCE_FILE
bin/manager-record-debt ENV_FILE DEBT_ROW_TSV
bin/manager-resolve-debt ENV_FILE DEBT_ID EVIDENCE_FILE
bin/harness-architecture-status --details ENV_FILE
bin/harness-revise-architecture ENV_FILE ARCHITECTURE_SOURCE_DIR REVISION_NOTE_FILE
bin/manager-revise-architecture ENV_FILE TASK_ID ARCHITECTURE_SOURCE_DIR REVISION_NOTE_FILE
```

`harness-decomposition-tree --details` includes each node's invariant,
decision, edge, and health bindings. `harness-decomposition-metrics` reports
planned and observed Luna coding share, gate completion, impact manifests, and
open/critical/expired debt. New Full-v2 projects default to guarded mode.
Existing plans without architecture sidecars detect that legacy state and
remain unguarded; the environment may explicitly set `0` or `1`.

A standalone test-only request gets a cheaper path. When its typed DAG contains
exactly one dependency-free `LOW`/`LUNA` `TEST_IMPLEMENTATION` node with bounded
paths and deterministic focused validation, `manager-init-project-plan`
generates a minimal architecture profile automatically. The profile contains
one specified test obligation and one critical validation gate, but no invented
decisions, edges, or debt. All other guarded DAGs still require explicit
architecture sidecars.

The interactive Codex TUI is not used for automated workers. A root task starts
a fresh non-interactive worker thread. If the manager rejects it, the harness
records the Codex thread ID and resumes that conversation for the next revision
without leaving any process alive. Acceptance or abort clears the thread.
`Worker-Context: FRESH` requests an independent replacement, and
`HARNESS_WORKER_THREAD_MAX_REJECTIONS` rotates long-lived rejected contexts.
In leaf-goal mode, the thread is task/goal-scoped instead: each `CONTINUE`
receipt preserves the current boundary and workspace fingerprint, and the
launcher resumes that goal without waking the manager.

## How task decomposition and replanning work

The harness separates the project plan, root acceptance criteria, and worker
revisions instead of treating every agent turn as an independent task:

```text
specification
    -> project plan item
        -> immutable root assignment
            -> ordered root criteria
                -> optional append-only child criteria
                    -> one logical worker goal for the first unmet leaf
                        -> bounded internal iterations
                            -> one terminal manager review
```

For a new root, the manager must declare stable `Root-Criterion` IDs with
independently checkable evidence. A continuation must declare exactly one
`Target-Criterion`, and the publisher verifies that it is the first leaf not
already marked `PASSED`. Oversized legacy roots receive an immutable
criterion-definition sidecar when automatic replanning first decomposes them.

Each worker revision ends in one of three manager decisions:

| Decision | Meaning | What is accumulated |
|---|---|---|
| `CHECKPOINT` | The bounded increment is correct, but the root is incomplete. | Stable criterion/increment evidence, source snapshots, hashes, review history, and the live repository changes. |
| `REJECT` | The proposed increment is unsafe, regressive, out of scope, or insufficiently proven. | Assignment, result, review, rejection boundary, retained worker context, and live workspace state; nothing new is marked verified. |
| `ACCEPT` | Every root criterion passes. | The root and its project-plan item become complete. |

A rejection does not automatically revert the repository or erase the worker's
conversation. The next revision normally resumes the same root-scoped thread
and receives the manager's rejection boundary, so useful but unverified work
can be repaired. Only a checkpoint or passed criterion enters the durable
verified ledger. An explicit abort/reset remains an operator-controlled
transaction.

### Leaf-goal execution

Leaf-goal execution is enabled by default. New assignments use
`Execution-Mode: LEAF_GOAL` and identify one first-unmet leaf, its observable
success evidence, focused validation, allowed scope, baseline boundary, and
genuine hard-block conditions. See `templates/leaf-goal-task-template.md`.
Set `HARNESS_WORKER_GOAL_MODE=0` only at a clean task boundary when temporary
legacy one-turn compatibility is required.

A leaf goal has three terminal outcomes:

| Worker outcome | Manager behavior |
|---|---|
| `COMPLETE` | Independently verify it, then checkpoint the leaf or accept the root. |
| `NEEDS_DECOMPOSITION` | Preserve any verified increment, then automatically request a materially different strategy or append-only child criteria. |
| `HARD_BLOCKED` | Independently verify the leaf block, then route repository-local prerequisites to manager remediation; pause only for an evidenced human dependency. |

If useful bounded work remains, the worker publishes `Outcome: CONTINUE` with
`worker-continue-task`. That command validates task ownership, the next
iteration number, before/after boundary, actual repository fingerprint, and
required evidence sections. It archives the receipt and updates goal state;
it does not create a result file, so it cannot trigger a manager review.
Repeated materially identical receipts rotate worker context and close
continuation in favor of a `NEEDS_DECOMPOSITION` strategy handoff.
If the manager rejects a claimed `COMPLETE` outcome, a repair assignment for
the same leaf reuses its `Goal-ID`; the publisher carries forward the logical
goal's receipt ledger, iteration number, usage counters, review count, and
worker thread unless the manager explicitly requests fresh context.

Provider retries happen inside the current iteration. A process crash or
supervisor restart leaves the running assignment, lease, goal ledger, thread
record, and live repository intact. `harness-recover --reset-stale` requeues
the same task without resetting its iteration count or boundary.

`Improvement: 0%` means the coarse legacy percentage did not move; it does not
mean the attempt or its evidence was deleted. This is especially common for a
legacy root pinned at 99%, where there is no integer step before final
acceptance at 100%. Use the criterion ledger and verified-checkpoint count as
the authoritative fine-grained progress indicators.

The harness watches for non-convergence using three independent signals:

- reviewed attempts since the current convergence baseline;
- consecutive reviews with neither numeric nor checkpointed gain;
- verified increments accumulated without completing a declared criterion.

When a configured threshold is reached, the current result is archived and the
root enters `NEEDS_REPLAN`. With automatic replanning enabled, this is a
transient state: the persistent project manager must publish one continuation for the
first unmet leaf using a materially different strategy. A valid strategy
change must narrow scope, change the evidence approach, or isolate a new
bounded criterion; changing only the task title or strategy label is rejected.

The automatic budget resets whenever a checkpoint records a new stable
`Verified-Increment` or `Verified-Criterion`. Numeric progress may remain at
0% or 99%; durable evidence, not the display percentage, governs escalation.
The checkpoint-without-criterion threshold still rotates strategy, but it
cannot drive a progressing root into
`NEEDS_HUMAN`.

If the ordinary strategy budget is exhausted, or the same blocking fingerprint
survives without durable gain, the manager publishes a
`Manager-Remediation: 1` task. Its `Remediation-Scope` may include directly
implicated local prerequisite files that an ordinary worker ownership rule,
exclusive/forbidden-file list, baseline label, or earlier allowed scope
excluded. The manager acts as integration owner for that bounded repair.
Affected paths remain separately attributed baseline-remediation provenance
instead of becoming part of the feature worker's owned implementation delta.
If a checkpointed remediation exposes another prerequisite, that provenance is
carried into the next manager-remediation task. The original observable
acceptance behavior remains immutable, and the task runs with the manager model
in fresh task context.

If an existing first-unmet leaf proves broader than expected, an automatic
replan may append at least two ordered child criteria. Existing root criteria
and prior child rows are immutable: the harness always schedules the first
unmet leaf and derives parent completion from all of its children. A child that
still proves too broad may be decomposed again without rewriting its ancestors.
The durable `.criterion-decomposition.tsv` uses:

```text
parent_criterion<TAB>child_criterion<TAB>title<TAB>acceptance_evidence
```

Only automatic replanning may append it, only the current first-unmet leaf may
be refined, and child IDs must be new within the root.

The unattended transition rules are:

| Event | Result |
|---|---|
| A checkpoint records a new unique criterion or increment | Preserve it and reset zero-gain replan escalation. |
| Numeric progress is unchanged but a unique checkpoint is verified | Treat it as durable gain; 0% or 99% does not cause a stop. |
| A convergence threshold is reached | Archive the current outcome and enter transient `NEEDS_REPLAN`; the supervisor resumes the persistent manager for a different strategy. |
| The same blocker reappears after new verified evidence | Permit another bounded strategy because the prior replan produced durable gain. |
| The configured number of materially different replans produces no new verified item | Publish a visible manager-model remediation task for the directly implicated local prerequisite. |
| The same local blocker survives without verified gain | Publish a bounded manager remediation; do not classify a coding/build/integration problem as human-dependent. |
| A leaf is hard-blocked by worker scope, an exclusive/forbidden-file ownership rule, frozen baseline sources, missing private testability, or an overconstrained derived criterion | Archive that leaf attempt and publish a manager baseline-remediation task with authority over the directly implicated repository-local prerequisite. |
| Authorization, unavailable secret, external manual state, or incompatible observable product/API/data outcomes not resolved by the specification require a person | Enter `NEEDS_HUMAN`. |

No checkpoint, criterion record, archived attempt, or live workspace change is
deleted during these transitions.

## Watch the agents working

```text
`harness-watch-agents refactoring-whatever.env`

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
I’ll review task 039 against the immutable root assignment, cumulative progress checkpoint, and actual code, run the affected build and focused smoke, then accept or publish one bounded continuation.

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
The result claims the descriptor layer is host-only and validates alignment, row strides, ordering, and spans. I’m inspecting the descriptor structs, builder, tests, and status note now.

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
The status note limits the scope correctly. I’m reading the descriptor builder and tests for span validation, relative host pointers, and malformed-plan handling.

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
The descriptor builder reuses the private plan validator, so it inherits the fixed 16-byte alignment and region-order checks before constructing descriptors. I’m verifying the validation helper and then running the required validation.

```
The watcher replays the currently active attempt so its context is visible, but
does not replay archived rejection decisions from earlier runs. Checkpoint and
rejection announcements distinguish three progress scopes:
current root-leaf completion, whole-project DAG completion, and the legacy
monotonic root percentage retained for compatibility. For dynamically
decomposed roots, the root-leaf value is explicitly labeled a snapshot because
later decomposition can add leaves and change its denominator.
Use `--new-only` to suppress even the active attempt's existing messages and
show only output appended after the watcher starts. After draining the final
agent messages, the watcher exits automatically when the project completes or
pauses for human intervention.

## Example of long project running (using single master specification file)

```text
user@dev :~/configs$ harness-status project.env
Environment file: /var/home/project/configs/project.env
Project: project-name
Repository: /var/home/project
Harness root: /var/home/project/.local/state/coding-harness
Manager supervisor: running (PID 3575705)
Worker supervisor: running (PID 3575962)

PLAN ITEM                STATE        TASK ROOT        TITLE
------------------------ ------------ ---------------- -----
phase-01                 COMPLETE     001              Reflective registry
phase-02                 COMPLETE     002              Predicate IR and grounding
phase-03                 COMPLETE     003              Backward analyzer
phase-04                 ACTIVE       004              Exact search
phase-05                 PENDING      -                World-model integration
phase-06                 PENDING      -                Rule, model, and function variables
phase-07                 PENDING      -                C synthesis and widening

TASK                             STATE        PROGRESS   OWNER                        AGE       
-------------------------------- ------------ ---------- ---------------------------- ----------
003-revision-19                  ACCEPTED     100%       -                            -
002-revision-05                  ACCEPTED     100%       -                            -
001-revision-34                  ACCEPTED     100%       -                            -
004-revision-10                  RUNNING      85%        worker-20260711T220248Z-f0c1e9a9 50s

Verified checkpoints: 6

Active root evidence: 6 verified item(s); 0 automatic replan(s) since the latest durable gain.
First unmet leaf criterion: exact-search.temporal-projection

Project progress: 42% (3/7 plan items complete)
Project status: ACTIVE. Work is ready, running, or awaiting manager review.
user@dev :~/configs$ 
```


## Codex CLI extra args

The harness can append extra `codex exec` flags from your trusted `.env` file.

Use Bash arrays so each argument stays correctly quoted:

```bash
MANAGER_CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
  --config model_auto_compact_token_limit=240000
)

WORKER_CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
  --config model_auto_compact_token_limit=240000
)
```

If you want the same flags for both roles, you can also define one shared array:

```bash
CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
  --config model_auto_compact_token_limit=240000
)
```

Role-specific arrays are appended after `CODEX_EXTRA_ARGS`, so they can add more flags when needed.

## Requirements

- Linux
- Bash
- `flock`, `realpath`, `sha256sum`, `stat`, `tsort`
- Codex CLI
- Optional: `inotifywait` from `inotify-tools`
- `jq` (required to validate and classify Codex JSON Lines)
- Optional repository intelligence: `sqlite3` with FTS5, `scip-clang`, and the
  SCIP CLI. Joern and Recoll remain supplemental providers. See
  [`docs/context-closure.md`](docs/context-closure.md) for installation,
  rollout, maintenance, troubleshooting, migration, and rollback.

## Project environment file

Create a file such as `/path/to/repository/harness.env`:

```bash
export PROJECT="sample-project"
export REPOSITORY="/path/to/repository"
export SPECIFICATION="$REPOSITORY/work/specification.md"
export HARNESS_MODE="full"

export HARNESS_HOME="/opt/coding-agent-fs-harness-v5"
export HARNESS_BIN="$HARNESS_HOME/bin"
export HARNESS_ROOT="$HOME/.local/state/coding-harness"
# Optional but recommended for service launches when the Codex shebang runtime
# (for example Node.js) is outside the system service PATH.
export HARNESS_RUNTIME_PATH_PREFIX="/usr/local/node/bin"

export MANAGER_CODEX_HOME="$HOME/.codex/manager-account"
export MANAGER_CODEX_BIN="$HOME/.local/bin/codex"
MANAGER_CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
  --config model_auto_compact_token_limit=240000
)
export MANAGER_MODEL="gpt-5.6-terra"
export MANAGER_FALLBACK_MODEL="gpt-5.6-terra"
export MANAGER_REASONING_EFFORT="high"
export MANAGER_SANDBOX="workspace-write"

export DECOMPOSITION_MODEL="gpt-5.6-sol"
export DECOMPOSITION_REASONING_EFFORT="high"

export WORKER_CODEX_HOME="$HOME/.codex/worker-account"
export WORKER_CODEX_BIN="$HOME/.local/bin/codex"
WORKER_CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
  --config model_auto_compact_token_limit=240000
)
export WORKER_MODEL="gpt-5.6-luna"
export WORKER_FALLBACK_MODEL="gpt-5.6-luna"
export WORKER_REASONING_EFFORT="xhigh"
export WORKER_SANDBOX="workspace-write"

export LUNA_WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_REASONING_EFFORT="xhigh"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export TERRA_WORKER_REASONING_EFFORT="high"

export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="1"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS="1"
export HARNESS_START_MAX_AGENT_INVOCATIONS="10"
export HARNESS_DOMAIN_PROFILES=""
export HARNESS_MAX_LUNA_STRATEGY_FAILURES="3"
export HARNESS_MAX_LUNA_ALLOWED_PATHS="8"
export HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF="2"
export HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS="1"
export HARNESS_MAX_LUNA_FAILURE_PATHS="2"
export HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS="1"
export HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES="1"
export HARNESS_MAX_LUNA_VALIDATION_SURFACES="1"
export HARNESS_MAX_LUNA_IMPLEMENTATION_FILES="3"
export HARNESS_MAX_LUNA_REQUIRED_SYMBOLS="3"
export HARNESS_MAX_LUNA_PREDICTED_ACTIONS="8"
export HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS="250000"
export HARNESS_MAX_LUNA_COMPLEXITY_SCORE="24"
export HARNESS_MAX_LUNA_RISK_DOMAINS="2"
export HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT="10000"
export HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES="20"
export HARNESS_MAX_COMPLEXITY_DECOMPOSITION_PASSES="3"
export HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES="32768"
export HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES="65536"
export HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES="32768"
export HARNESS_MIN_LUNA_NODE_PERCENT="80"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="80"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export HARNESS_ARCHITECTURE_GUARDS="1"

# Repository intelligence remains disabled for compatibility until explicitly
# enabled. Advisory mode builds and measures indexes without restricting worker
# repository access.
export HARNESS_REPOSITORY_INDEX_MODE="off"       # off|advisory|required
export HARNESS_CONTEXT_CLOSURE_MODE="off"        # off|advisory|required|patch_only
# export HARNESS_COMPILE_COMMANDS="$REPOSITORY/build/compile_commands.json"
export HARNESS_SCIP_CLANG_BIN="scip-clang"
export HARNESS_SCIP_BIN="scip"
export HARNESS_SCIP_IMPORTER_BIN="$HARNESS_HOME/libexec/harness-scip-importer"
export HARNESS_JOERN_BIN="joern"
export HARNESS_JOERN_ENABLED="0"
export HARNESS_JOERN_EXECUTION_MODE="eager"       # eager|on_demand; luna_only defaults on_demand
export HARNESS_JOERN_ANALYSIS_CLASSES="call,control-flow,data-flow,mutation"
export HARNESS_JOERN_SOURCE_ROOT="."
export HARNESS_SCIP_CLANG_JOBS="1"
export HARNESS_RECOLL_BIN="recollq"
export HARNESS_RECOLL_ENABLED="0"
export HARNESS_CONTEXT_CLOSURE_MAX_BYTES="32768"
export HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS="64"
export HARNESS_CONTEXT_CLOSURE_MAX_MODULES="4"
export HARNESS_CONTEXT_CLOSURE_MAX_OWNERSHIP_BOUNDARIES="2"
export HARNESS_CONTEXT_CLOSURE_MAX_DIRECT_RELATIONSHIPS="16"
export HARNESS_CONTEXT_CLOSURE_MAX_TESTS="8"
export HARNESS_CONTEXT_CLOSURE_MAX_BUILD_TARGETS="4"
export HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS="250000"
export HARNESS_CONTEXT_EXPANSION_MAX_BYTES="16384"
export HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF="2"
export HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS="3"
export HARNESS_REPOSITORY_INDEX_RETENTION="3"
export HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES="4"

export HARNESS_POLL_SECONDS="2"
export HARNESS_WAIT_SECONDS="300"
export HARNESS_STALE_SECONDS="900"
export HARNESS_USE_INOTIFY="1"
export WORKER_HEARTBEAT_SECONDS="60"
export HARNESS_CODEX_WALL_TIMEOUT_SECONDS="1800"
export HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="0"
export HARNESS_CODEX_KILL_GRACE_SECONDS="15"
export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="80"
export HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION="14"
export HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION="14"
export HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS="2"
export HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION="500000"
export HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION="500000"
export HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS="500000"
export HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND="20000"
```

Risk domains are scored from each executable node's deliverable, acceptance
evidence, and focused validation. The full normalized obligation still drives
coverage and minimum behavioral, failure, and ownership dimensions, but its
complete vocabulary is not copied into every child; otherwise a multi-domain
parent requirement could never be recursively decomposed into Luna-ready
leaves.

The live estimate is an intentionally conservative context-amplification
circuit breaker. It samples prompt and JSONL transcript growth at agent item
boundaries, so an invocation can be terminated before Codex emits authoritative
usage at turn completion. The authoritative per-invocation check applies after
completion, and the cumulative worker-task check prevents several individually
bounded episodes from quietly making one immutable leaf pathological.

Any token circuit breaker creates a `TOKEN_USAGE_ANOMALY` pause attributed to
the affected root. Source edits, commits, reports, and checkpoints are
preserved, but the project-wide launch interlock prevents every worker, manager,
and Oracle process until the cause is inspected. Resolve it with a Markdown
note containing nonempty
`## Cause`, `## Corrective action`, and `## Safe continuation boundary`
sections:

```bash
harness-resolve-token-usage-anomaly project.env TASK_ROOT resolution.md
harness-start project.env
```

`harness-start` automatically migrates pre-5.11 token circuit breakers that
were recorded as `NEEDS_HUMAN`; the original marker is archived and the exact
root becomes `TOKEN_USAGE_ANOMALY`. The migration can also be run explicitly
and is idempotent:

```bash
harness-migrate-state project.env
```

Specification normalization retains its separately configured authoritative
post-turn allowance for very large imported specifications, but it remains
subject to the lower live-estimated circuit breaker.

The manager and worker may use the same `CODEX_HOME`, but separate account directories make account selection explicit.

`HARNESS_RUNTIME_PATH_PREFIX` is a colon-separated list of absolute directories
prepended for every harness command and child process. The harness validates
Codex script shebang dependencies at supervisor startup, so a missing `node` or
other runtime fails visibly instead of leaving a task falsely marked `RUNNING`.

The harness also reserves `/tmp/$PROJECT` as a dedicated scratch directory for manager task files, worker result reports, and manager review notes before those files are published through harness commands.

Protect the file:

```bash
chmod 600 /path/to/repository/harness.env
```

The file is trusted Bash input and is sourced by every command.

### Repository index foundation

Repository intelligence is disabled by default and does not change existing
project behavior. To build an advisory SCIP generation, first provide one
compilation database. CMake can generate it without writing into the source
tree:

```bash
cmake -S "$REPOSITORY" -B /tmp/project-context-index \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

Set `HARNESS_REPOSITORY_INDEX_MODE=advisory` and, when auto-discovery would be
ambiguous, set `HARNESS_COMPILE_COMMANDS` to that file. Then run:

```bash
harness-build-index-tools "$HARNESS_HOME/libexec"
harness-index-repository project.env
harness-index-status project.env --details
harness-context-baseline project.env
harness-index-invalidate project.env --reason "build configuration changed"
```

The builder requires a clean tracked worktree, normalizes the compilation
database, hashes recursive generated/external headers selected by its include
paths, runs `scip-clang`, validates the result with the SCIP CLI, initializes
the versioned architecture database, imports SCIP definitions, references,
relationships, structural source regions, tests, build targets/inputs, and FTS5
lexical records, and atomically publishes an immutable generation under
`HARNESS_REPOSITORY_INDEX_ROOT`. Failed generations preserve the prior project
pointer. Untracked files are not indexed. `scip lint` findings are retained as
quality evidence because some valid `scip-clang` versions omit optional local
symbol metadata; malformed protobuf or failed database integrity remains fatal.

`harness-context-baseline` summarizes existing context-capsule size, processed
tokens, agent actions, command output, source reads, repeated reads, and worker
outcomes without replaying transcript contents.

The first advisory Context Closure compiler can resolve an existing task,
context capsule, decomposition node, or explicit assignment against the current
repository index:

```bash
harness-build-context-closure project.env TASK_OR_PLAN_NODE
harness-context-closure-check project.env TASK_ID
harness-context-closure-usage project.env TASK_ID
harness-evaluate-decomposition-context project.env DAG_TSV COVERAGE_TSV - OUTPUT_DIR
harness-export-architecture-slice project.env
harness-show-context-closure project.env TASK_ID
harness-show-context-closure project.env TASK_ID --why SYMBOL_OR_PATH
harness-query-architecture project.env EXACT_SYMBOL
```

It emits a deterministic context document plus item, edge, build-target,
ownership-boundary, unresolved, provenance, quality, and suggested-child-cut
ledgers under the project state directory. Missing required structural evidence
returns `INCOMPLETE`; exceeded context, symbol, module, ownership, relationship,
test, build-target, or estimated-token budgets return
`NEEDS_FURTHER_DECOMPOSITION`. The compiler refuses stale commits, tracked
changes, changed compilation databases, changed SCIP toolchains, importer
binaries, scanner/importer logic, recursive generated-input content, and schema
content. Generated build inputs selected by a leaf are embedded as bounded,
hash-addressed read-only prerequisites even when `scip-clang` does not emit
them as repository documents.

With `HARNESS_JOERN_EXECUTION_MODE=on_demand`, the immutable SCIP/build index
does not launch a JVM. Only a leaf whose dependency classes require flow
evidence (or a concurrency/integration leaf) admits Joern. Its imported flow
graph is stored in an assignment- and worktree-digest-addressed database
overlay and reused by later closure compilations. A host-global lock admits one
Joern process at a time; `taskset`, `ActiveProcessorCount`, heap, timeout, and
nice limits remain enforced. Luna-only mode defaults to on-demand, one CPU, and
a 4096 MiB heap unless the project explicitly overrides those limits. Eager
mode retains the compatible full-index behavior and shares its GraphML export
through a digest cache.

On a new project with repository indexing enabled, `harness-start` builds or
reuses the immutable generation before the first Sol decomposition turn and
exports a compact architecture slice. Proposed Luna rows are dry-run against
the exact graph during decomposition staging. Advisory reports record measured
context bounds and cohesive build-target/source-root seams; recursive Sol repair
can use those seams without re-scanning the repository. These measurements do
not block a candidate until required mode is separately qualified.

With `HARNESS_CONTEXT_CLOSURE_MODE=advisory`, the worker launcher attempts a
fresh closure before claiming the task. A `READY` closure is embedded after the
normal bounded capsule; missing/stale indexes and incomplete/oversized closures
are recorded but do not block the worker or remove repository access. Outcomes
are appended to `logs/context-closure-events.tsv`, with complete compiler
diagnostics retained in task-specific logs. In `required` mode a non-ready Luna
closure returns to deterministic decomposition before a model launch. In
`patch_only` mode Luna receives only the compiled context in a read-only,
tool-less invocation and emits one Git patch; the harness validates the
workspace baseline, syntax, declared paths, binary/generated exclusions,
focused validation, and controlled commit. When one decisive fact is absent,
Luna can request an exact type definition, caller contract, failing assertion,
build owner, or representation writer. The trusted resolver admits only an
assignment seed or direct indexed graph neighbor, compiles a provenance-bearing
extension no larger than `HARNESS_CONTEXT_EXPANSION_MAX_BYTES`, and resumes the
same thread. `HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF` prevents exploratory or
unchanged request loops; a rejected or exhausted request returns to smaller
decomposition without enabling repository tools.

### Agent Coordination Protocol (ACP)

Luna-only mode enables ACP v1 by default. ACP generalizes the patch-only typed
fact request into negotiated task readiness while preserving strict initial
Context Closure. The worker may request one exact deterministic fact or report
a typed `SCOPE`, `PREREQUISITE`, `SPLIT`, `CHALLENGE`, or `CANCEL` boundary. A worker request is an
untrusted claim: only the deterministic broker can grant bounded read evidence,
and only manager policy can change mutation authority or append decomposition.
Sol remains the global architecture/decomposition critic over compiled evidence
and is never an implementation fallback for Luna work.

ACP state lives under `control/acp/`: `events.tsv` is the append-only protocol
ledger, evidence artifacts are content-addressed, `transactions.tsv` is the
request/outcome dataset, `discovered-graph.tsv`
preserves claimed prerequisite/split history and manager dispositions, and
`metrics.env` reports request/grant/denial counts and broker hit rate. Inspect
it without launching a model:

```bash
harness-acp-status project.env
```

The broker supports exact symbol/type definitions, callers, callees, failing
assertions, named/indexed tests, build targets and owners, concept owners, producers, consumers, and
representation writers. `SOURCE_WINDOW` adds a bounded tail window only for an
exact declared/proven path. SCIP, build-index, and on-demand Joern evidence is
queried deterministically; accepted excerpts remain subject to the per-request
and cumulative added-context limits. The same provider thread resumes after a
context grant. Structural requests terminate the ephemeral Luna process and
enter append-only manager adjudication without granting scope. Manager terminal
actions compile into explicit `GRANT_SCOPE`, `CREATE_PREREQUISITE`,
`SPLIT_TASK`, denial/cancellation, reassessment, or clarification decisions.
A suspended prerequisite records the discovered node and `X -> B` edge, runs X
without a waiting inference process, and resumes B with its saved thread after
the manager publishes the authorized continuation.

Protocol fuses detect duplicate requests, stale workspace authority, excessive
request count, context amplification, and repeated negotiation without verified
gain. They complement—and do not change—the 500,000 authoritative per-turn,
500,000 live-estimated per-turn, and 500,000 cumulative worker-task token fuses.
`harness-decomposition-metrics` includes ACP broker hit rate, manager calls
avoided, added context bytes, discovered/planned graph ratio, requests per
verified item, and the project `tokens_per_verified_facet` convergence metric.

ACP decomposition-v2 projects default to four isolated workers;
legacy/non-ACP projects remain serial. Each dependency-ready worker receives a
write capability compiled from `Allowed-Scope` and uses an immutable-base Git
worktree with private build/temp roots. Exact indexed mutation regions allow
workers to operate concurrently on disjoint symbols in the same file.

The Bash Source Code Transaction Manager (SCTM) is the sole canonical writer
for these workers. Each completed candidate becomes an immutable Git patch in
a durable FIFO transaction. SCTM takes one repository `flock`, applies the
patch with three-way context against the current HEAD, checks the exact changed
path set against the ACP capability, runs focused validation in a staging
worktree, and only then fast-forwards the canonical repository. Unrelated
same-file changes therefore compose; genuine overlapping edits return a
bounded `CONFLICT` delta without partial mutation. Transaction IDs are
idempotent, and daemon startup recovers requests abandoned before or after the
canonical fast-forward. Inspect the queue and result ledger with:

```bash
sctm-status project.env
```

The durable ledger is under
`$HARNESS_ROOT/projects/$PROJECT/control/sctm/transactions/`. ACP decomposition
v2 enables SCTM by default. `HARNESS_SCTM_SUBMIT_TIMEOUT_SECONDS` controls the
synchronous worker wait (the configured Codex wall timeout, or 3,600 seconds);
zero permits an unlimited wait while daemon liveness continues to be checked.
`HARNESS_SCTM_MAX_CONFLICT_DELTA_BYTES` bounds repair evidence (65,536 bytes by
default). The normative protocol is documented in `formats/sctm-v1.md`.

`HARNESS_WORKER_PARALLELISM=0` selects online CPU capacity capped by
`HARNESS_WORKER_PARALLELISM_HARD_MAX` (four by default), never unbounded launch.
New v2 plans compile indexed symbol mutation regions and a durable semantic
conflict graph. The scheduler greedily fills dependency-ready, conflict-free
slots; exact region authority can distinguish disjoint symbols in one file,
while architecture decisions, edge contracts, ownership, and unresolved paths
remain conservative conflicts. `harness-decomposition-metrics` and
`harness-statistics` report safe width, critical path, maximum width, control
amplification, implementation yield, and observed slot utilization.
`harness-rebuild-throughput-state ENV_FILE` backfills these sidecars for an
installed plan.

Independent completed results may be reviewed by one ephemeral manager
inference in batches of up to `HARNESS_MANAGER_BATCH_SIZE` (four by default).
Each result retains its own packet, validation, review note, terminal validator,
idempotency identity, and append-only manager-inbox transaction; a partial batch
cannot make a sibling decision authoritative.
The normative envelope is documented in `formats/acp-v1.md`.

ACP metrics also report initial/added context bytes, amplification, authority
decisions, suspensions/resumptions, capability deferrals, integrations, and the
discovered/planned edge ratio. `estimated_tokens_saved` is explicitly a
byte-based proxy for deterministic discovery displaced; actual model economics
remain measured by `tokens_per_verified_facet`.

When focused validation rejects a patch, the trusted runner rolls it back and
resumes the same thread with only normalized typed diagnostics. It permits at
most `HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS` total validation rounds and
stops early when consecutive patches produce the same semantic diagnostic set.
No repair round enables shell/repository exploration or a stronger model.

Promotion, prediction, omission, architecture, and cost-comparison reports are
available through:

```bash
harness-context-closure-promotion project.env
harness-context-closure-predictions project.env
harness-context-closure-outliers project.env
harness-context-closure-omissions project.env
harness-architecture-index project.env
harness-architecture-benchmarks project.env queries.tsv
harness-architecture-scorecard project.env
harness-compare-architecture-scorecards before.tsv after.tsv
harness-compare-context-baselines before.tsv after.tsv
```

For repositories dominated by Bash or Python, add `--source-only` to the
architecture index, benchmark, or scorecard command. Periodic architecture
rebuilds are durable, resumable, and require a separate operator approval:

```bash
harness-architecture-rebuild project.env begin core-coupling periodic-scorecard queries.tsv
harness-architecture-rebuild project.env design REBUILD_ID target-architecture.md
harness-architecture-rebuild project.env baseline REBUILD_ID behavioral-baseline.md
harness-architecture-rebuild project.env refactor-complete REBUILD_ID migration-ledger.tsv
harness-architecture-rebuild project.env recompute REBUILD_ID
harness-architecture-rebuild project.env accept REBUILD_ID operator-approval.md
```

See [the architecture rebuild lifecycle](docs/architecture-rebuild-lifecycle.md)
for phase semantics, failure recovery, evidence authority, scorecard gates, and
the required final report/debt ledger.

After each advisory worker invocation, the harness compares repository paths
observed in the bounded transcript with the compiled closure. It records used
evidence, unused candidates, paths discovered outside the closure, and changed
paths outside the closure. This is recall/precision telemetry only: implicit
compiler reads and shell indirection mean that absence from the transcript is
not proof that a context item was unnecessary.

## First initialization

```bash
/opt/coding-agent-fs-harness-v5/bin/harness-check-env /path/to/repository/harness.env
```

```bash
/opt/coding-agent-fs-harness-v5/bin/harness-init /path/to/repository/harness.env
```

Start the complete system:

```bash
/opt/coding-agent-fs-harness-v5/bin/harness-start /path/to/repository/harness.env
```

`harness-init` and `harness-start` serialize on the environment file path. A
repeated `harness-start` preserves existing state and starts only missing
supervisors.

`harness-start` performs these operations:

1. If enabled, review and normalize the specification.
2. If v2 is enabled and no plan exists, run the fresh Sol architecture-fit and decomposition critic.
3. Stop with a clarification or redesign report when implementation authority is unsafe.
4. If no manager thread exists, run one manager bootstrap turn.
5. Start the manager result watcher.
6. Start the worker task watcher and return to the shell.

After that, no manual prompt pushes are required.
Bootstrap records every specification phase or acceptance gate in an immutable
project plan. Each root task is assigned to one plan item. Accepting a root task
completes only that item, and project progress is calculated from completed plan
items rather than from whichever tasks happen to have been published.

When the final plan item is accepted, the harness records completion and both
supervisors exit automatically. A premature `--complete-project` assertion is
rejected before task acceptance, so an unfinished specification cannot be
terminated by a mistaken manager decision.

## Final Oracle audit

Set `ORACLE_MODEL` to enable a fresh, independent final audit after every plan
item has been accepted. The Oracle uses `ORACLE_CODEX_*` settings when supplied and
otherwise inherits the manager Codex environment. It verifies the original
specification, mandatory referenced documents, durable plan traceability, and
focused acceptance evidence before project completion is recorded.

Set `MAX_ORACLE_RUNS` to bound Oracle cost. `0` disables Oracle auditing; `1`
permits one completed audit; larger values permit that many completed audit
cycles. When a capped audit fails and its remediation plan is later accepted,
the harness records `COMPLETE_WITH_ORACLE_LIMIT` rather than claiming a final
Oracle `PASS`. Leave `MAX_ORACLE_RUNS` unset to preserve the legacy unbounded
audit/remediation loop. `MAX_ORACLE_RUNS` supersedes legacy `ORACLE_ENABLED`.

An Oracle `PASS` records project completion. An Oracle `FAIL` writes a
versioned additive addendum. Repository-local implementation, build,
testability, integration, scope/ownership, exclusive-file, forbidden-file, and
baseline-prerequisite repairs are `AUTOMATIC` and add durable `ORACLE-*` plan
items when still unmet. Independently verified manager-remediation paths are
separately attributed baseline provenance rather than feature-owned changes.
`HUMAN_APPROVAL` is limited to unavailable authorization, secrets, external
state transitions, or an unresolved governing choice between incompatible
observable product outcomes, and its addendum must carry explicit dependency
evidence. Addenda never replace the original specification. After resolving a
genuine project block—or correcting a legacy misclassification—run
`bin/harness-unblock-project ENV_FILE`, then restart the harness. Unblocking a
fully accepted plan automatically creates a fresh pending Oracle audit.

Transient provider and quota failures are retried within the same Oracle
invocation. A GPT-5.6 model refusal or blocked-content response gets one
immediate retry with a narrower authorized-local-audit prompt, followed by
`ORACLE_FALLBACK_MODEL` (which defaults to `MANAGER_FALLBACK_MODEL`). A terminal
local invocation failure is recorded in
`control/oracle/oracle-invocation-failed.md`; the supervisor suppresses further
attempts for that unchanged pending audit until the supervisor is restarted or
the pending audit changes. This prevents a deterministic setup error from
becoming a rapid retry loop or a false human-intervention request.

`harness-status` reports that terminal state as `INVOCATION_FAILED` /
`ORACLE_AUDIT_FAILED` instead of presenting it as an ordinary pending audit.

```bash
export ORACLE_MODEL="gpt-5.6-sol"
export MAX_ORACLE_RUNS="1"
export ORACLE_FALLBACK_MODEL="gpt-5.6-terra"
export ORACLE_REASONING_EFFORT="xhigh"
export ORACLE_SANDBOX="danger-full-access"
```

## Stop and restart

Stop both local supervisors:

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-stop /path/to/repository/harness.env
```

Restart them and preserve existing state:

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-start /path/to/repository/harness.env
```

`harness-stop` is graceful. It signals both supervisors but does not kill an
active manager or worker Codex turn. If a turn is still running after the
bounded stop wait, the command exits nonzero and reports that the supervisor
will stop after its child publishes or exits. Run `harness-status`, wait for
both supervisors to report `stopped`, and then run `harness-start`.

Supervisor lifetime lock descriptors are closed in every manager, worker,
Oracle, `inotifywait`, and polling child. A completed child therefore cannot
leave an inherited lock behind and prevent the replacement supervisor from
starting. `harness-status` reports the new supervisor PIDs after a successful
restart.

If `manager.thread` already exists, bootstrap is not repeated. Active processes
do not cause `harness-start` to reset state. Only `harness-init` offers an
explicit confirmed reset, archives the old state under `$HARNESS_ROOT/resets/`,
and creates a new project directory.

Each root task has an immutable assignment, an append-only progress history,
and a cumulative checkpoint. A correct verified increment is `CHECKPOINTED`
even when its parent root remains incomplete. Checkpoint reviews append stable
criterion/increment IDs, archive the result and evidence, and snapshot each
declared repository path. Continuations receive the recorded percentage,
verified evidence, and root-assignment paths. Consequently, stopping/restarting
the supervisors or rebooting does not restart implementation from zero.

State durability alone does not recreate processes after the machine boots.
Set `HARNESS_BOOT_RECOVERY=1` to make each explicit `harness-start` register
that environment with the user service manager; an intentional `harness-stop`
unregisters it. The generated `coding-agent-fs-harness-autostart.service`
starts only registered environments. Full mode first requeues any assignment
left in `running/` by the dead process, preserving repository edits, goal
ledgers, checkpoints, and the retained worker thread. It also repairs an
assignment archived during an interrupted completion transaction. Light mode's
existing phase reconciliation converts `*_RUNNING` to its retry-safe durable
phase before continuing. Inspect the registry with:

```bash
bin/harness-autostart status
```

For recovery before login, enable lingering for the harness account once with
`loginctl enable-linger USER`; otherwise the service starts when that user's
service manager starts at login. Parked environments are not registered until
they are actually started.

### Checkpointed increments

The manager has three ordinary review outcomes:

- `CHECKPOINT`: the bounded increment is correct and verified, while its root
  remains active;
- `ACCEPT`: every root criterion passes, completing the assigned plan item;
- `REJECT`: the increment itself is faulty, regressive, out of scope, or lacks
  evidence.

`manager-checkpoint-task` requires stable `Verified-Criterion` or
`Verified-Increment` identifiers and an explicit list of `Checkpoint-Path`
files. Paths may use repeated fields or a comma-separated field; both forms are
normalized to individual repository paths. It stores the review, result,
assignment, file snapshots, Git patch and
hash manifest under `archive/checkpoints/`. The append-only `.criteria.tsv`,
`.checkpoints.tsv`, and `.history.tsv` files under `control/progress/` remain
the recovery ledger. When checkpoint paths contain reviewed source changes,
the transaction creates a validated, path-bounded source commit attributed to
the checkpoint task. A later zero-write recovery leaf may consume that commit
within the same immutable root, but cannot claim or modify the inherited code.
Legacy checkpoints are reconciled only when the live files exactly match their
stored hash manifest. Early comma-list artifacts that recorded the list as one
deleted pseudo-path are upgraded only during a passing zero-write manager
acceptance review; the original malformed artifact is retained beside the
repaired per-file snapshots and hashes. New root assignments declare stable `Root-Criterion` IDs; for
undecomposed roots checkpoint progress is calculated from passed versus
declared criteria rather than estimated by the manager. Once a broad criterion
has append-only children, the monotonic display percentage remains compatible
with its historical value while leaf criteria and verified items provide the
authoritative fine-grained progress.

### Root worker context

`HARNESS_REUSE_WORKER_THREADS=1` (the default) retains the latest worker Codex
thread after a checkpoint or rejection. A checkpoint resets its rejection
counter because the strategy produced verified work. The next continuation of
the same immutable root uses `codex exec resume`; its new assignment and durable
progress ledger remain authoritative. No worker process waits between tasks
and no lease is reused. Acceptance and explicit abort remove retained state.

The default `HARNESS_WORKER_THREAD_MAX_REJECTIONS=8` starts a fresh thread after
eight rejected turns to limit stale-strategy anchoring and context growth. Set
it to 0 to disable count-based rotation. A manager may request an earlier fresh
context by putting `Worker-Context: FRESH` in a continuation assignment.

### Deterministic-blocker circuit breaker

The manager attaches `Blocking-Fingerprint: sha256:<output-hash>` to a
zero-improvement rejection when the same focused gate deterministically fails.
The fingerprint-specific circuit breaker is disabled by default
(`HARNESS_MAX_IDENTICAL_BLOCKERS=0`), so a manager cannot create a discretionary
human-intervention block. The general convergence guards below still apply. A
project may explicitly set a positive fingerprint threshold. At that threshold,
`manager-reject-task`
atomically archives the rejection and requests a manager-remediation task;
the local code/build blocker does not become a human-only stop.
`manager-block-task` independently verifies the configured threshold when
called directly. For a verified `HARD_BLOCKED` result it additionally requires
an explicit blocker classification. Local code/build/integration/scope classes
route to manager remediation. `LOCAL_SCOPE_PREREQUISITE` covers ordinary worker
ownership, exclusive/forbidden-file, and frozen-baseline boundaries when a
bounded integration-owner repair preserves observable behavior. Only an
evidenced authorization, secret, external state, or governing
product/specification class enters `NEEDS_HUMAN`; the product/specification
class additionally requires `Product-Decision-Evidence` naming incompatible
observable outcomes, so file ownership alone cannot trigger it.

### Convergence guards and automatic replan configuration

The decomposition lifecycle above is enforced by safe finite thresholds. Three
project settings configure the convergence signals:

```bash
export HARNESS_MAX_ROOT_ATTEMPTS="12"
export HARNESS_MAX_ZERO_GAIN_WINDOW="3"
export HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION="4"
export HARNESS_MAX_TOTAL_ROOT_REVIEWS="24"
export HARNESS_MAX_TOTAL_ROOT_REPLANS="8"
export HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION="10"
export HARNESS_MAX_ROOT_CHILD_CRITERIA="32"
export HARNESS_MAX_CRITERION_DEPTH="8"
export HARNESS_MAX_ROOT_LIFETIME_SECONDS="21600"
export HARNESS_MAX_ROOT_PROCESSED_TOKENS="100000000"
```

When any threshold is reached, the just-reviewed result is archived first and
the root enters `NEEDS_REPLAN`. The repository, checkpoint artifacts, criterion
ledger, review history, and live workspace remain intact. By default the
manager supervisor consumes this marker automatically:

`HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION` is stricter: its count survives
automatic replans and resets only when a declared root criterion is durably
checkpointed. Reaching it requires architecture/human reassessment, so changing
diagnostic text or accumulating local increments cannot keep a dead-end root
alive indefinitely.

```bash
export HARNESS_AUTO_REPLAN_ENABLED="1"
export HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN="1"
```

`HARNESS_MAX_AUTO_REPLANS_WITHOUT_CRITERION` remains a compatibility alias for
existing environment files, but now has the verified-gain semantics above.

The six monotonic root limits do not reset after an automatic replan or a local
diagnostic checkpoint. Reaching one creates
`ARCHITECTURE_REASSESSMENT_REQUIRED`, suppresses further worker, review, and
replan agent launches for that root, and records a durable alarm under the
project log directory. Revision assignments inherit the original root's scope,
architecture-decision authority, and expected file/turn bounds. A manager that
discovers an accepted dependency was wrong must record that fact with
`manager-invalidate-plan-dependency`; it may not silently expand the consumer.
After the architecture or dependency authority is repaired, an operator records
the explicit decision with `harness-resolve-architecture-reassessment ENV_FILE
TASK_ROOT RESOLUTION_NOTE_FILE`.

When reassessment proves that the active DAG node itself omitted legitimate
repair authority, stop the harness and use
`harness-revise-active-plan-node ENV_FILE CANDIDATE_DAG
REVISED_ROOT_ASSIGNMENT RESOLUTION_NOTE_FILE
[REVISED_CRITERION_DECOMPOSITION]`. The command permits only the
active node to change, preserves its identity, dependencies, deliverable,
acceptance evidence, focused validation, and ordered root criteria, and permits
only additive path and symbol authority. It validates the revised assignment,
archives the old DAG, assignment, pause marker, and resolution, then clears the
pause atomically. The next planning turn automatically uses a fresh manager
context so stale conversational scope cannot override the revised durable DAG.
The optional criterion decomposition is reserved for a proven harness-generated
invalid decomposition. It requires the exact installed decomposition digest,
documented invalidity evidence, an installed `Harness-Fix-Commit`, and (for a
multi-criterion root) `Replacement-Criterion-Parent` in the resolution note.
The command archives the old root state and resets only derived criterion,
checkpoint, replan, remediation, progress, and convergence ledgers before
starting a fresh liveness epoch; immutable root criteria remain unchanged.
Merely clearing an immutable-authority marker without revising the conflicting
authority will cause the same pause to recur. For other proven stale-manager
cases, stop the harness and run `harness-rotate-manager-context ENV_FILE
REASON_NOTE_FILE`; the next planner invocation rotates and registers the thread
without reinitializing project state.

The automatic strategy turn resumes the persistent project-scoped manager.
Durable plan, progress, criteria, checkpoint, and replan files override older
conversation context. For an oversized legacy root, the manager first installs
an immutable ordered
`.criteria-definition.tsv` containing at least two independently verifiable
remaining child milestones. It then publishes exactly one continuation for the
first unmet leaf criterion with `Worker-Context: FRESH` and a declared strategy
change: narrower scope, new evidence, or an isolated criterion. The publisher
rejects repeated strategy IDs, materially identical strategy fingerprints,
non-first targets, replacement decompositions, and a deterministic blocker
that survives without new durable evidence. When a current leaf is still too
broad, the manager may append two or more ordered child criteria to
`.criterion-decomposition.tsv`; it may never alter existing rows.

The automatic budget counts materially different replans since the latest
verified ledger item. Every unique checkpoint or passed criterion resets it,
even when `Progress-Percent` is unchanged. Exhausting that budget, or seeing an
unchanged local blocker without gain, switches to manager remediation. The
manager authors a fresh `REPAIR_PREREQUISITE` assignment, names a bounded
`Remediation-Scope`, and the task launcher executes it with `MANAGER_MODEL`.
This is explicit authority to repair directly implicated local code, build, or
integration prerequisites even when an earlier worker leaf excluded them; it
is not authority to weaken acceptance, change unrelated behavior, or modify
external systems.

If a fresh manager-remediation turn returns `NEEDS_DECOMPOSITION` because its
declared mutation scope contains no usable producer, representation, consumer,
or validation seam, rejection records
`MANAGER_REMEDIATION_SCOPE_EXHAUSTED`. The worker and goal threads are cleared,
the exhausted path set is preserved in the recovery marker, and the publisher
refuses to authorize the same path set again for the unchanged criterion. The
next Terra remediation must name the smallest evidenced adjacent seam. This
turns a truthful no-edit diagnostic into a scope transition instead of a
same-file retry loop.

`NEEDS_DECOMPOSITION` also carries a typed `Decomposition-Reason`. A
`CONTEXT_INCOMPLETE` manager remediation does not revoke otherwise-correct
write authority: it records `MANAGER_REMEDIATION_CONTEXT_INCOMPLETE`, rotates
the agent context, preserves the exact `Remediation-Scope`, and requires the
next candidate to retain all prior context paths while adding at least one
exact bounded declaration or implementation path. `SCOPE_INCOMPLETE` remains
the distinct signal that mutation authority itself must move to an adjacent
seam. Other reasons distinguish an over-broad task, a validation prerequisite,
and a resource-limited episode.

If a monotonic architecture/liveness guard pauses the root while that typed
transition is pending, the architecture marker preserves its trigger, source
task, blocker class, and exhausted path set. Resolving the liveness epoch
restores the specific exhausted-scope transition rather than replacing it with
a generic architecture-resolution replan. Successive audited
`Authorized-Additional-Scope` decisions for the same root are cumulative: the
resolver unions them with the existing override (up to four bounded paths)
rather than silently discarding authority granted by an earlier repair.

Recovery publication corrections are also bounded. If the final correction
still identifies a concrete remediation path outside immutable root authority,
the harness promotes that evidence to
`MANAGER_REMEDIATION_SCOPE_EXPANSION` instead of reporting a generic
`RECOVERY_STALLED` failure or spending another planning turn. This promotion
does not authorize the path automatically: an operator must resolve the
architecture reassessment with the exact audited `Authorized-Additional-Scope`
before manager remediation may continue.

With the default value `1`, one materially different automatic strategy is
allowed from a given verified-item baseline. If it produces a new verified
item, the budget immediately resets; if it produces no durable gain, the next
convergence trigger routes to the manager model for prerequisite repair.
Raising the setting permits more ordinary no-gain strategies before that
manager-remediation transition.

The append-only `.replans.tsv` ledger records both completed root-criterion and
total verified-item counts at each strategy change. Existing nine-column
ledgers are upgraded automatically on the next successful replan by deriving
their historical verified counts from timestamped criterion-ledger rows.
The append-only `.manager-remediations.tsv` ledger separately records every
manager blocker occurrence, its fingerprint/class/scope, and the manager model.
Together with checkpoint artifacts, it is the provenance boundary between
baseline remediation and the feature worker's owned implementation delta. A
final scope audit discloses and validates those repairs without charging them
to the ordinary worker.
The append-only `.hard-blocks.tsv` ledger records every independently reviewed
hard-block claim and whether it was routed to manager remediation or confirmed
human-dependent.

`NEEDS_HUMAN` is reserved for a documented dependency on a person: missing
authorization, an unavailable secret, an external manual state transition, or
incompatible observable product/specification outcomes that the governing
specification does not resolve. `harness-unblock-root ENV_FILE
TASK_ROOT` remains the explicit operator action for such a boundary. Legacy
`NEEDS_HUMAN` markers created solely by the old no-gain/unchanged-blocker rule
are automatically reclassified to manager remediation on supervisor startup.
Legacy terminal `.blocked.md` root markers are also reconsidered on startup;
unless they already contain a valid evidenced human classification, they become
manager remediation so older worker-scope decisions do not remain terminal.

Set `HARNESS_AUTO_REPLAN_ENABLED=0` to retain manual `NEEDS_REPLAN` handling.
Set an individual convergence threshold to `0` to disable only that trigger.

A committed `CHECKPOINT` resets the zero-gain review streak even when a legacy
root's numeric progress remains pinned at 99%, because every checkpoint must
record a new stable verified criterion or increment. Criterion-free
checkpoints remain independently bounded by
`HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION`, so a stream of tiny verified
increments cannot bypass replanning indefinitely.

Plan rows must be independently acceptance-complete: split a phase into
multiple rows before assigning bounded milestones. A baseline task may require
reproducing and documenting a known failure, but must never require that failure
to pass while its scope forbids the repair.

The project plan is independently durable. If a manager accepts a task and exits
without publishing its successor, the manager supervisor detects that the plan
is incomplete and no task is active. It resumes the manager to publish exactly
one task for the first unfinished plan item. The same recovery happens after a
restart; no completed plan item or root task is replayed.

`harness-status` reports both levels explicitly, including `REPLANNING` while
the persistent manager is active, `MANAGER_REMEDIATION` while a manager-model
repair task is active, and `NEEDS_HUMAN` only at a human-only boundary. The
task table identifies `MANAGER_FIX` execution, and a durable summary reports
manager-remediation blocker occurrences, unique fingerprints, and active
tasks. A separate hard-block summary reports total claims, manager-remediation
routes, and confirmed human dependencies. For the active root it also prints the total verified-item count,
automatic replans since the latest durable gain, and the first unmet leaf
criterion. In goal mode it also reports the goal state, internal iteration
count, context generation, durable boundary, last material movement, and
workspace drift.

## State location

Print the exact harness project-state path:

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-state-path /path/to/repository/harness.env
```

For the example configuration, it is:

```text
$HOME/.local/state/coding-harness/projects/sample-project
```

The separate scratch directory for task and result markdown is:

```text
/tmp/sample-project
```

Print the source repository path separately:

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-repository-path /path/to/repository/harness.env
```

## Runtime files

```text
$HARNESS_ROOT/projects/$PROJECT/
    tasks/
        sample-project-task-002.ready.md
    running/
        sample-project-task-002.running.md
    results/
        sample-project-task-002.result.md
    archive/
        sample-project-task-001.assignment.md
        sample-project-task-001.result.md
        sample-project-task-001.accepted.md
        goal-iterations/
            sample-project-task-002/
                iteration-0001.md
        goals/
            sample-project-task-001/
                sample-project-task-001.goal
                sample-project-task-001.iterations.tsv
                sample-project-task-001.thread
                sample-project-task-001.summary.md
    control/
        manager.thread
        project-plan.tsv
        project-plan-state.tsv
        supervisor.pid
        worker-supervisor.pid
        sample-project-task-002.lease
        goals/
            sample-project-task-002.goal
            sample-project-task-002.iterations.tsv
            sample-project-task-002.thread
            sample-project-task-002.summary.md
        progress/
            sample-project-task-002.root-assignment.md
            sample-project-task-002.progress.md
            sample-project-task-002.criteria.tsv
            sample-project-task-002.checkpoints.tsv
            sample-project-task-002.history.tsv
            sample-project-task-002.criteria-definition.tsv
            sample-project-task-002.criterion-decomposition.tsv
            sample-project-task-002.replans.tsv
        sessions/
    logs/
        events.log
        supervisor.log
        worker-supervisor.log
        manager-bootstrap-*.jsonl
        manager-review-*.jsonl
        worker-task-*.jsonl
```

The criteria-definition file exists for decomposed legacy roots; the
criterion-decomposition and replan ledgers appear only after those transitions.
Goal files appear only for assignments stamped `LEAF_GOAL`. All are durable
control state, not disposable logs.

## Monitoring

Concise operational status:

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-status /path/to/repository/harness.env
```

The default view contains only current supervisors, specification state,
progress, the active root/leaf, and the project status. Use
`harness-status --full ENV_FILE` for the legacy diagnostic tables. Machine
consumers should use `--machine`; `harness-watch-many` does this automatically.

Project identity, accepted Specification IR counters, decomposition route
summary, agent configuration, and architecture profile:

```bash
harness-info /path/to/repository/harness.env
```

Cumulative delivery, decomposition-quality, and token statistics:

```bash
harness-statistics /path/to/repository/harness.env
```

Predicted versus observed per-leaf complexity and model calibration:

```bash
harness-complexity /path/to/repository/harness.env
harness-complexity --all
```

Model-aware estimated dollar cost by scaffolding phase, implementation route,
and model:

```bash
harness-costs /path/to/repository/harness.env
harness-costs --tsv /path/to/repository/harness.env
```

Highest-consuming agent episodes, with worker-only and cross-project views:

```bash
harness-token-outliers /path/to/repository/harness.env
harness-token-outliers /path/to/repository/harness.env --role worker --limit 10
harness-token-outliers --all --role worker --limit 10
```

Build and test output from bounded workers is retained under the project log
directory through `harness-run-logged`; only a size-limited diagnostic summary
enters the model transcript. Executable validation already stored in a task can
be run without shell-operator escape mistakes through:

```bash
harness-run-assigned-validation ENV_FILE TASK_ID LABEL
```

The runner configures CMake incrementally and uses `--fresh` only after a source,
generator, toolchain, or CMake-graph identity mismatch. Isolated worktrees map
logical build paths to private persistent namespaces and enable `ccache` when
installed. Successful checks produce receipts bound to repository path,
HEAD/workspace, exact command, build/cache identity, and toolchain; only an
exact identity match is reusable. Indexed build evidence can be queried without
an agent turn through `harness-build-query ENV_FILE QUERY VALUE`, where `QUERY`
is `SOURCE_TO_TARGET`, `TARGET_TO_SOURCE`, `MINIMAL_TARGET`, `TEST_SELECTOR`,
`DEPENDENCY_ARTIFACT`, or `FIRST_CAUSAL_ERROR`.

Chronological implementation history:

```bash
harness-implementation-log /path/to/repository/harness.env
harness-implementation-log --follow /path/to/repository/harness.env
```

This timeline summarizes durable specification, DAG, routing, worker,
manager, dependency, architecture, and Oracle transitions. `--all` includes
low-level lifecycle events. Use `harness-watch-agents` when raw natural-language
agent output is required.

When specification acceptance stops with `SPEC_CLARIFICATION_REQUIRED`, render
the complete current report and structured issue set as a copy/paste-ready
assignment for the specification-authoring agent:

```bash
harness-show-clarification-request /path/to/repository/harness.env
```

The output includes the untruncated problem description, incompatible
outcomes, missing decision, exact governing specification and repository,
amendment checklist, clean commit instructions, and the correct relaunch
command.

Raw unified state transitions:

```bash
tail -F "$HOME/.local/state/coding-harness/projects/sample-project/logs/events.log"
```

Worker Codex events:

```bash
tail -F "$HOME/.local/state/coding-harness/projects/sample-project/logs/worker-supervisor.log"
```

Manager Codex events:

```bash
tail -F "$HOME/.local/state/coding-harness/projects/sample-project/logs/supervisor.log"
```

Task-specific machine-readable streams are also written as `worker-task-*.jsonl` and `manager-review-*.jsonl`.
When the final audit is active, `harness-watch-agents` also displays its
`oracle-audit-*.jsonl` messages under an `ORACLE` label.
In leaf-goal mode, each newly committed receipt is announced as
`WORKER CONTINUING GOAL`; the JSONL watcher switches to each resumed worker
process while retaining the same task and goal identity.

## Validation

Run both the explicitly configured legacy regression suite and the default
leaf-goal regression suite:

```bash
bash tests/test-harness.sh
bash tests/test-leaf-goal.sh
bash tests/test-decomposition-v2.sh
bash tests/test-architecture-guards.sh
bash tests/test-autostart.sh
bash tests/test-codex-exec-jsonl.sh
bash tests/test-git-dependency.sh
bash tests/test-specification-review.sh
bash tests/test-root-liveness.sh
bash tests/test-active-plan-revision.sh
bash tests/test-repository-index.sh
bash tests/test-scip-importer.sh
bash tests/test-architecture-rebuild.sh
bash tests/test-architecture-rebuild-cli.sh
bash tests/test-module-boundaries.sh
bash tests/test-module-primitives.sh
bash tests/test-sctm.sh
bash tests/test-acp-parallel.sh
```

The leaf-goal test covers assignment validation, code-only continuation,
same-thread resume, one terminal manager result, idempotent receipts, repeated
identical-iteration rotation, archived goal state, and boundary-safe
enable/disable refusal.

The architecture-guard test covers registry/DAG cross-validation, controlled
decision evidence, edge readiness, worker impact manifests, manager review,
critical-debt blocking and resolution, milestone and final health gates,
tree/status visibility, and decomposition-quality metrics.

## Heartbeats and long tasks

The worker launcher runs a local heartbeat subprocess while Codex is active. The LLM does not need to remember to send heartbeats.

`WORKER_HEARTBEAT_SECONDS=60` means the lease is refreshed every 60 seconds.

`HARNESS_STALE_SECONDS=900` means a running worker is considered stale only after 900 seconds without a heartbeat. It is not a task-duration limit.

The non-interactive Codex wall watchdog defaults to 1800 seconds; the idle
watchdog defaults to `0` (disabled). A live invocation is also bounded to 80
started agent items. At turn completion, a processed-token delta above
2,000,000 trips the same durable resource guard. A trip terminates the process
tree, preserves workspace changes and logs, and pauses the root in
`NEEDS_HUMAN` instead of retrying it.

## Prototype validation and revisions

The manager and worker follow the repository's prototype / feature-first
policy: one affected build/compile check, one focused happy-path smoke, and one
regression test only for a bug fix. Unrelated aggregate/CTest failures are
recorded as limitations and do not become revision work.

High-progress revisions enter bounded closure mode by default at 95%. One
worker turn may make at most two evidence-backed root-scope corrections and run
the same focused acceptance smoke at most three times, rebuilding between
corrections. It stops on success, budget exhaustion, an out-of-root failure, or
a required authority/design choice. Closure mode does not authorize broad test
suites, relaxed acceptance, public API changes, speculative capacity increases,
or unrelated cleanup. Configure it with `HARNESS_CLOSURE_MODE_*` values or set
`HARNESS_CLOSURE_MODE_ENABLED=0` to retain single-attempt behavior.

Leaf-goal mode generalizes that loop across bounded Codex processes and is
enabled by default:

```bash
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS="3"
export HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS="8"
export HARNESS_GOAL_PROCESS_MAX_FIXES="3"
export HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS="4"
export HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED="1"
```

`HARNESS_GOAL_PROCESS_*` bounds one process, not the logical goal. Reaching a
bound publishes a continuation rather than claiming completion. With semantic
continuation review enabled, every `CONTINUE` closes the current episode. A
fresh, compact manager turn compares its evidence and next action to the
assigned criterion and authority. `SAME_CRITERION` starts a fresh worker
context; an invalidated premise, upstream prerequisite, or out-of-authority
next action publishes `NEEDS_DECOMPOSITION` with all work preserved. This
limits context growth without prescribing shell commands or limiting the total
amount of implementation work. Closure mode remains a separate compatibility
path for legacy assignments.

Correct increments are checkpointed rather than rejected. A zero-improvement
result may still record a stable verified increment. The rolling zero-gain,
checkpoint-without-criterion, and total-attempt guards periodically rotate
strategy and context; they escalate only when materially different strategies
stop adding durable verified evidence. Cumulative percentage progress remains
monotonic, while the verified-item ledger records smaller root-scoped gains;
unrelated repairs contribute neither.

## Provider retry policy

The JSONL runner classifies provider failures before any model fallback. It
prefers structured error codes and HTTP statuses when Codex supplies them, then
uses narrow matching against error events and stderr for current CLI errors
that contain only a message.

Two unlimited retry cadences apply:

- Provider capacity, HTTP 429/rate limits, temporary server failures, and
  network failures retry every 60 seconds.
- Account usage-window or quota exhaustion preserves state, reports that quota
  is unavailable, and probes again every 300 seconds until a turn succeeds.

The policy applies to:

- manager bootstrap;
- manager result review;
- manager next-item planning;
- worker task execution.
- every internal leaf-goal iteration.

Configure it in the environment file:

```bash
export HARNESS_PROVIDER_RETRY_SECONDS="60"
export HARNESS_QUOTA_RETRY_SECONDS="300"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="60"
export HARNESS_SUPERVISOR_START_TIMEOUT_SECONDS="120"
export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="80"
export HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION="14"
export HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION="14"
export HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS="2"
export HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION="500000"
export HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION="500000"
export HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS="500000"
```

`HARNESS_AGENT_MIN_INTERVAL_SECONDS` is a project-wide launch throttle shared
by managers, workers, and oracles. Its state persists across supervisor
restarts, so an accidental event loop cannot bypass the interval by restarting
the harness. Different projects retain independent clocks and can continue to
run in parallel.

`HARNESS_SUPERVISOR_START_TIMEOUT_SECONDS` bounds launcher readiness, not the
supervisor lifetime. The default allows large decomposition DAGs to rebuild
their conflict and throughput sidecars before publishing the manager PID, so a
healthy slow startup does not suppress the worker-supervisor launch.

Provider retries are always unlimited. Each probe receives a separate JSONL,
stderr, classification, and final-message log with an `attempt-NNN` suffix.
`HARNESS_CAPACITY_RETRY_SECONDS` remains a compatibility alias for the transient
delay, but new configurations should use `HARNESS_PROVIDER_RETRY_SECONDS`.
The legacy `HARNESS_CAPACITY_MAX_RETRIES` value is ignored; provider retries are
unlimited by design.

The worker heartbeat remains active during the retry delay, so the claimed task
does not become stale. The worker keeps the same task ownership session and
resumes the attempt's Codex thread when one was created. The manager resumes its
persistent manager thread.

At the worker completion transaction, harmless report-shape omissions are
normalized into the canonical result headings while preserving the original
worker text. `Status: COMPLETED` describes the publication transaction, not root
acceptance; a worker-authored `BLOCKED`, `PARTIAL`, or similar assessment is
retained as `Worker-Reported-Status` while the canonical transaction status is
added. A conflicting task identity is still rejected. This keeps independently
verified implementation progress checkpointable instead of treating report
wording or a missing Markdown heading as zero engineering gain.

Authentication/account-disable errors, invalid configuration, sandbox failures,
malformed output, protocol violations, partial-edit failures, and actual agent
failures remain terminal and create the existing human-intervention alerts.

## Other failure policy

A terminal worker failure leaves the task in `RUNNING` state and writes:

```text
control/PROJECT-task-ID.worker-failed.md
```

Inspect the task log and then reset it explicitly:

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-reset-task /path/to/repository/harness.env TASK_ID --force
```

The worker supervisor detects the newly restored ready task and performs one new invocation.

A terminal or non-provider manager failure writes a manager failure file and requires explicit requeue through `harness-requeue-result`.

## Upgrade from v3 with an existing ready task

The state directory is compatible. Stop the v3 manager supervisor first, exit the interactive worker TUI, update `harness.env` with the v4 variables, and start v4.

```bash
/opt/coding-agent-fs-harness-v3/bin/harness-supervisor-stop /path/to/repository/harness.env
```

Update at least:

```bash
export HARNESS_HOME="/opt/coding-agent-fs-harness-v4.5"
export HARNESS_BIN="$HARNESS_HOME/bin"
export MANAGER_CODEX_HOME="$HOME/.codex/manager-account"
export MANAGER_CODEX_BIN="$HOME/.local/bin/codex"
export WORKER_CODEX_HOME="$HOME/.codex/worker-account"
export WORKER_CODEX_BIN="$HOME/.local/bin/codex"
export WORKER_MODEL="gpt-5.4-mini"
export WORKER_REASONING_EFFORT="high"
export WORKER_SANDBOX="danger-full-access"
```

Then:

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-check-env /path/to/repository/harness.env
```

```bash
/opt/coding-agent-fs-harness-v4.5/bin/harness-start /path/to/repository/harness.env
```

If task `002` is already `READY`, the v4 worker supervisor claims it automatically.

## Important concurrency rule

Do not run an interactive worker Codex session against the same ready/running task while the worker supervisor is active. The worker supervisor is the task owner.

You may inspect JSONL logs passively. Stop the supervisors before manually resuming and modifying an automated manager thread.

## Reliability fixes in 4.1

Version 4.1 closes two filesystem coordination races:

1. Both supervisors use a bounded `inotifywait` timeout and rescan their queues after an event or timeout. A task or result created during the scan-to-watch gap can therefore remain unnoticed for at most `HARNESS_POLL_SECONDS`.
2. A result is reviewable only after the worker completion transaction has archived the assignment and removed the lease. If a worker writes directly into `results/`, `worker-invoke-task` normalizes that file through `worker-complete-task` after Codex exits. The manager supervisor ignores the incomplete intermediate state.

The committed worker-result invariant is:

```text
results/PROJECT-task-ID.result.md exists
running/PROJECT-task-ID.running.md does not exist
control/PROJECT-task-ID.lease does not exist
archive/PROJECT-task-ID.assignment.md exists
```

`manager-invoke-result` checks the same invariant independently before starting an expensive manager model turn.

## Reliability fixes in 4.2

Version 4.2 adds automatic recovery from temporary provider failures and account
usage-window exhaustion. Worker ownership and heartbeats remain valid across
the wait. Manager review preserves the result and thread and checks whether an
accept/reject action was committed before retrying, preventing duplicate
manager actions after a late stream failure.

Event-log entries include:

```text
WORKER_PROVIDER_WAIT kind=transient|quota
WORKER_PROVIDER_RETRY_STARTED kind=transient|quota
MANAGER_PROVIDER_WAIT kind=transient|quota
MANAGER_PROVIDER_RETRY_STARTED kind=transient|quota
MANAGER_PLAN_PROVIDER_WAIT kind=transient|quota
MANAGER_BOOTSTRAP_PROVIDER_WAIT kind=transient|quota
```

## Validated Git delivery and dependency waiting

`HARNESS_AGENT_COMMITS_ENABLED=1` is the default. During an owned worker turn,
`harness-commit-source ENV TASK SESSION MESSAGE PATH...` commits only explicit
task-scope source and related text paths. It refuses generated/build paths,
object files, binaries, ignored files, submodules, undeclared paths, a dirty
index, and binary diffs. `harness-publish-branch` publishes only the current
HEAD, only to a branch declared by the assignment or governing specification,
and only by fast-forward from any existing target. Agents never run direct Git
index or history mutation commands.

Cross-harness Git prerequisites use `WAITING_DEPENDENCY`. The manager or worker
publishes a machine-readable requirements TSV plus a supplier specification.
The active plan item then waits without an LLM process, manager review,
checkpoint, progress increment, or replan-budget charge. A producer publishes
its validated source commit/branch; `harness-supply-dependency` imports that
commit into the consumer repository without touching its worktree. The
supervisor wakes the plan item only after every target ref, required ancestry,
and required committed path validates. Missing mandatory refs therefore cannot
complete preflight, unlock integration, or become repeated durable gain.

## Increment lifecycle in 4.3

Version 4.3 separates verified incremental delivery from final root acceptance.
`manager-checkpoint-task` records correct partial work as `CHECKPOINTED`, saves
scoped source snapshots and Git evidence, appends stable criterion/increment
ledgers, and leaves the parent plan item active. Manager retries recognize the
checkpoint transaction idempotently.

Finite root-attempt, rolling zero-gain, and checkpoint-without-criterion guards
now pause non-converging roots in `NEEDS_REPLAN`. The pause occurs only after
the current result has been archived. Resuming a replanned root records a new
convergence baseline, so its next bounded strategy receives a fresh budget
without deleting prior history.

## Resumable decomposition and gain-aware replanning in 4.4

Version 4.4 makes root criteria executable lifecycle state rather than prompt
advice. New roots must declare stable `Root-Criterion` IDs. Continuations of a
decomposed root must name the first unmet leaf with `Target-Criterion`. Legacy
roots receive an immutable criterion-definition sidecar during automatic
replanning. An unexpectedly broad leaf can gain append-only ordered children,
including nested children, without replacing the original root inventory.

`NEEDS_REPLAN` is an automatic bounded transition, not an overnight stop. Its
strategy budget is based on the durable verified-item ledger rather than the
coarse percentage or only completed parent criteria. Every unique
`Verified-Increment` or `Verified-Criterion` resets escalation; repeated
strategies without new evidence and repository-local hard blocks or Oracle
scope conflicts route to manager remediation. Human intervention remains
explicit and requires authority, secret, external-state, or governing
product/specification evidence.

Supervisor children now close manager and worker lifetime-lock descriptors.
Graceful stop/restart therefore preserves an active turn without allowing that
turn, a polling sleep, or `inotifywait` to strand the old supervisor lock.

## Leaf-goal workers in 4.5

Version 4.5 makes a logical worker goal the default lifecycle above individual
`codex exec`
processes. `worker-continue-task` commits validated, idempotent iteration
receipts; `worker-invoke-task` resumes the goal until a terminal outcome; and
the persistent manager is invoked only for that terminal result. Goal state,
iteration ledger, compact summary, and thread metadata are durable and exposed
through status, watch, and recovery commands.

Automatic replanning now remains in the project-scoped manager conversation.
A `NEEDS_DECOMPOSITION` terminal result routes directly to the existing
append-only decomposition machinery, while verified partial work is
checkpointed before the strategy handoff. An independently verified
`HARD_BLOCKED` outcome is fail-closed at the leaf boundary, then classified:
repository-local prerequisites route to manager remediation and only a
documented human dependency pauses the project.

Goal mode is enabled by default for newly published assignments. New
configurations should leave the default in place or set
`HARNESS_WORKER_GOAL_MODE=1` explicitly. To upgrade an existing project that
has an active legacy assignment:

1. Keep `HARNESS_WORKER_GOAL_MODE=0` until its ready, running, or review
   transaction is resolved.
2. Stop at the resulting clean task boundary and set
   `HARNESS_WORKER_GOAL_MODE=1`.
3. Run `harness-check-env`, then restart the harness. The next manager
   assignment is stamped `LEAF_GOAL`.

Do not toggle the flag over an existing assignment. The worker refuses to claim
a legacy assignment while goal mode is enabled, and refuses to claim a goal
assignment after it is disabled. To use the legacy compatibility path, finish
or explicitly
abort/reconcile the active goal, stop at the next clean boundary, set the flag
to `0`, and restart. No existing v4.4 state is migrated automatically.
