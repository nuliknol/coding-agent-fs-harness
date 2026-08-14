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
- Focused closure mode: high-progress tasks receive a bounded
  diagnose-correct-rebuild-smoke budget instead of unbounded revision churn.
- Independent final audit: an optional fresh Oracle checks specification
  traceability and may create bounded remediation plan items.
- Filesystem observability: assignments, results, reviews, JSONL streams,
  checkpoints, progress, and lifecycle events remain inspectable on disk.
- Safe restart and recovery: supervisor restarts preserve plans, task state,
  checkpoints, retained threads, and completed evidence; child processes do
  not inherit supervisor lifetime locks.
- Explicit runtime configuration: one trusted `.env` selects repositories,
  state, accounts, models, timing, and child-process runtime paths.
- Validated Git delivery: implementation agents commit task-owned source and
  related text artifacts by default; generated output, binaries, ignored files,
  unrelated paths, and direct model-driven Git history mutations are rejected.

## Process model

```text
manager-decomposition-critic (Full v2, fresh Terra context)
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
export HARNESS_DOMAIN_PROFILES=""  # optional comma-separated profile IDs
export HARNESS_MAX_LUNA_STRATEGY_FAILURES="3"
export HARNESS_MAX_LUNA_ALLOWED_PATHS="8"
export HARNESS_MIN_LUNA_NODE_PERCENT="80"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="80"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export HARNESS_ARCHITECTURE_GUARDS="1"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
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

For a stopped Full project, `harness-start` requires `REPOSITORY` to be a Git
worktree with a valid `HEAD` and no staged, unstaged, or non-ignored untracked
files. It prints the exact porcelain-status entries and exits before recovery
or any agent invocation when this preflight fails. Ignored build products are
not considered dirty. A redundant start against a live manager or worker
supervisor remains idempotent and does not apply this stopped-project
preflight. A startup/reviewer/worker process without a live supervisor does not
bypass validation and is reported as an overlapping start instead.

An accepted review also installs a normalized Specification IR: independently
testable obligations, typed semantic relations, a bounded repository inventory,
and authority-qualified repository facts. The decomposition critic must provide
an `obligation_id -> node_ids` coverage sidecar; registration rejects a missing
obligation or an unjustified DAG node. Workers and managers receive only the
obligations allocated to their node, and final Oracle PASS requires independent
evidence for every obligation. This keeps product requirements distinct from
repository-derived facts and fallible planning hints.

The independent decomposition critic challenges that acceptance before it may
register a DAG. A genuine unresolved product contract transitions back to
`SPEC_CLARIFICATION_REQUIRED` and writes a critic report under
`$REPOSITORY/spec-review/`. If the governing sources are clear but the generated
facts, obligations, or relations are defective, the critic requests automatic
IR renormalization instead; `harness-start` reruns the reviewer once and refuses
repeated compiler churn. Thus only missing human authority is bounced to the
specification author.

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
zero-gain iterations, and verified Specification IR coverage. Cached input is
part of input tokens. Use `--tsv` for machine-readable metrics.
Run `bin/harness-decomposition-tree ENV_FILE` to display the immutable DAG as a
terminal tree with node state, complexity, configured worker route,
dependencies, deliverable, and active task route. `--compact` shows one line
per node; `--details` also shows evidence, validation, scope, symbols, and the
current criterion tree. New typed v2 plans must meet
`HARNESS_MIN_LUNA_CODING_NODE_PERCENT` (80 by default). Its denominator is
only coding-eligible nodes; Terra contract, architecture, concurrency,
ambiguity, and integration nodes do not dilute the Luna target.
For a stopped, incomplete Full-v2 project, run
`bin/manager-reclassify-project-plan ENV_FILE` to have a fresh Terra critic
reclassify only its `PENDING` nodes under the current Luna-first policy. The
command refuses to run while harness processes are alive, preserves all DAG
structure and every `ACTIVE` or `COMPLETE` route, validates the configured
minimum pending Luna coding percentage, and stores the previous DAG plus an audit
report under `control/reclassifications/` before installing the candidate.
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
export HARNESS_DOMAIN_PROFILES=""
export HARNESS_MAX_LUNA_STRATEGY_FAILURES="3"
export HARNESS_MAX_LUNA_ALLOWED_PATHS="8"
export HARNESS_MIN_LUNA_NODE_PERCENT="80"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="80"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export HARNESS_ARCHITECTURE_GUARDS="1"

export HARNESS_POLL_SECONDS="2"
export HARNESS_WAIT_SECONDS="300"
export HARNESS_STALE_SECONDS="900"
export HARNESS_USE_INOTIFY="1"
export WORKER_HEARTBEAT_SECONDS="60"
export HARNESS_CODEX_WALL_TIMEOUT_SECONDS="0"
export HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="0"
export HARNESS_CODEX_KILL_GRACE_SECONDS="15"
```

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

1. If v2 is enabled and no plan exists, run the fresh decomposition critic.
2. If no manager thread exists, run one manager bootstrap turn.
3. Start the manager result watcher.
4. Start the worker task watcher and return to the shell.

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
files. It stores the review, result, assignment, file snapshots, Git patch and
hash manifest under `archive/checkpoints/`. The append-only `.criteria.tsv`,
`.checkpoints.tsv`, and `.history.tsv` files under `control/progress/` remain
the recovery ledger. The live repository is never reset or rewritten by this
transaction. New root assignments declare stable `Root-Criterion` IDs; for
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
```

When any threshold is reached, the just-reviewed result is archived first and
the root enters `NEEDS_REPLAN`. The repository, checkpoint artifacts, criterion
ledger, review history, and live workspace remain intact. By default the
manager supervisor consumes this marker automatically:

```bash
export HARNESS_AUTO_REPLAN_ENABLED="1"
export HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN="1"
```

`HARNESS_MAX_AUTO_REPLANS_WITHOUT_CRITERION` remains a compatibility alias for
existing environment files, but now has the verified-gain semantics above.

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

Chronological implementation history:

```bash
harness-implementation-log /path/to/repository/harness.env
harness-implementation-log --follow /path/to/repository/harness.env
```

This timeline summarizes durable specification, DAG, routing, worker,
manager, dependency, architecture, and Oracle transitions. `--all` includes
low-level lifecycle events. Use `harness-watch-agents` when raw natural-language
agent output is required.

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

Non-interactive Codex wall and idle watchdogs default to `0` (disabled), so a
correctly progressing turn is not killed because it is slow. Set
`HARNESS_CODEX_WALL_TIMEOUT_SECONDS` or
`HARNESS_CODEX_IDLE_TIMEOUT_SECONDS` to a nonzero value only when an operator
intentionally wants such a watchdog.

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
```

`HARNESS_GOAL_PROCESS_*` bounds one process, not the logical goal. Reaching a
bound publishes a continuation rather than claiming completion. Context
rotation also preserves goal state and workspace. Closure mode remains a
separate compatibility path for legacy assignments.

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
```

`HARNESS_AGENT_MIN_INTERVAL_SECONDS` is a project-wide launch throttle shared
by managers, workers, and oracles. Its state persists across supervisor
restarts, so an accidental event loop cannot bypass the interval by restarting
the harness. Different projects retain independent clocks and can continue to
run in parallel.

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
