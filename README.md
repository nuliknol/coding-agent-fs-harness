# Coding Agent Filesystem Harness v4.2 (for Codex CLI)

A local, event-driven two-agent coding harness for Linux.

- A strong manager model decomposes the specification and reviews results.
- A cheaper worker model implements one bounded task at a time.
- Ordinary Bash supervisors watch filesystem mailboxes.
- No codex process remains alive while waiting (no tokens consumed).
- Git commits remain manual (or spec-driven).
- One trusted `.env` file configures the complete project, harness installation, state directory, accounts, models, and timing.
- Manager and worker scratch task/result markdown lives under `/tmp/$PROJECT`.

## Process model

```text
manager-bootstrap
    -> records the complete specification plan
    -> publishes one task for the first plan item
    -> manager exits

worker-supervisor (local Bash, no tokens)
    -> detects task 001
    -> launches one worker `codex exec`
    -> worker implements, publishes result, exits

manager-supervisor (local Bash, no tokens)
    -> detects result 001
    -> resumes manager Codex thread
    -> manager accepts/rejects and publishes the next task
    -> if acceptance leaves a planning gap, resumes a dedicated planning turn
    -> manager exits

worker-supervisor
    -> detects the next task
    -> repeats
```

The interactive Codex TUI is not used for automated workers. A root task starts
a fresh non-interactive worker thread. If the manager rejects it, the harness
records the Codex thread ID and resumes that conversation for the next revision
without leaving any process alive. Acceptance or abort clears the thread.
`Worker-Context: FRESH` requests an independent replacement, and
`HARNESS_WORKER_THREAD_MAX_REJECTIONS` rotates long-lived rejected contexts.



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
does not replay archived rejection decisions from earlier runs. Use
`--new-only` to suppress even the active attempt's existing messages and show
only output appended after the watcher starts.

## Example of long project running (using single master specification file)
user@dev :~/configs$ harness-status project.env
Environment file: /var/home/project/configs/project.env
Project: project-name
Repository: /var/home/project
Harness root: /var/home/project/.local/state/coding-harness
Manager supervisor: running (PID 3575705)
Worker supervisor: running (PID 3575962)
Project progress: 42% (3/7 plan items complete)

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
user@dev :~/configs$ 


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
- `flock`, `realpath`, `sha256sum`, `stat`
- Codex CLI
- Optional: `inotifywait` from `inotify-tools`
- `jq` (required to validate and classify Codex JSON Lines)

## Project environment file

Create a file such as `/path/to/repository/harness.env`:

```bash
export PROJECT="sample-project"
export REPOSITORY="/path/to/repository"
export SPECIFICATION="$REPOSITORY/work/specification.md"

export HARNESS_HOME="/opt/coding-agent-fs-harness-v4.2"
export HARNESS_BIN="$HARNESS_HOME/bin"
export HARNESS_ROOT="$HOME/.local/state/coding-harness"

export MANAGER_CODEX_HOME="$HOME/.codex/manager-account"
export MANAGER_CODEX_BIN="$HOME/.local/bin/codex"
MANAGER_CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
  --config model_auto_compact_token_limit=240000
)
export MANAGER_MODEL="gpt-5.5"
export MANAGER_FALLBACK_MODEL="gpt-5.5"
export MANAGER_REASONING_EFFORT="high"
export MANAGER_SANDBOX="workspace-write"

export WORKER_CODEX_HOME="$HOME/.codex/worker-account"
export WORKER_CODEX_BIN="$HOME/.local/bin/codex"
WORKER_CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
  --config model_auto_compact_token_limit=240000
)
export WORKER_MODEL="gpt-5.4-mini"
export WORKER_FALLBACK_MODEL="gpt-5.4-mini"
export WORKER_REASONING_EFFORT="high"
export WORKER_SANDBOX="workspace-write"

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

The harness also reserves `/tmp/$PROJECT` as a dedicated scratch directory for manager task files, worker result reports, and manager review notes before those files are published through harness commands.

Protect the file:

```bash
chmod 600 /path/to/repository/harness.env
```

The file is trusted Bash input and is sourced by every command.

## First initialization

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-check-env /path/to/repository/harness.env
```

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-init /path/to/repository/harness.env
```

Start the complete system:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-start /path/to/repository/harness.env
```

`harness-init` and `harness-start` serialize on the environment file path. A
repeated `harness-start` preserves existing state and starts only missing
supervisors.

`harness-start` performs these operations:

1. If no manager thread exists, run one manager bootstrap turn.
2. Start the manager result watcher.
3. Start the worker task watcher.
4. Return to the shell.

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

An Oracle `PASS` records project completion. An Oracle `FAIL` writes a
versioned additive addendum: bounded remediation of an existing requirement may
be marked `AUTOMATIC` and adds durable `ORACLE-*` plan items; new scope or a
conflict with the original specification must be marked `HUMAN_APPROVAL` and
blocks the project. Addenda never replace the original specification.
After approving that block and making the necessary human-directed change, run
`bin/harness-unblock-project ENV_FILE`, then restart the harness.

Transient provider and quota failures are retried within the same Oracle
invocation. A terminal local invocation failure is recorded in
`control/oracle/oracle-invocation-failed.md`; the supervisor suppresses further
attempts for that unchanged pending audit until the supervisor is restarted or
the pending audit changes. This prevents a deterministic setup error from
becoming a rapid retry loop or a false human-intervention request.

```bash
export ORACLE_MODEL="gpt-5.6-sol"
export ORACLE_REASONING_EFFORT="xhigh"
export ORACLE_SANDBOX="danger-full-access"
```

## Stop and restart

Stop both local supervisors:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-stop /path/to/repository/harness.env
```

Restart them and preserve existing state:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-start /path/to/repository/harness.env
```

If `manager.thread` already exists, bootstrap is not repeated. Active processes
do not cause `harness-start` to reset state. Only `harness-init` offers an
explicit confirmed reset, archives the old state under `$HARNESS_ROOT/resets/`,
and creates a new project directory.

Each root task has an immutable assignment and a cumulative progress checkpoint.
Manager reviews update `Progress-Percent` and `Improvement-Percent`; revision
assignments automatically receive the recorded starting percentage, completed
evidence, and root-assignment paths. Consequently, stopping/restarting the
supervisors or rebooting does not restart implementation from zero.

### Rejected-root worker context

`HARNESS_REUSE_WORKER_THREADS=1` (the default) retains the latest worker Codex
thread only when `manager-reject-task` commits a rejection. The next revision
of the same immutable root uses `codex exec resume`; its new assignment and
durable progress checkpoint remain authoritative. No worker process waits
between tasks and no lease is reused. Acceptance and explicit abort remove the
retained thread state.

The default `HARNESS_WORKER_THREAD_MAX_REJECTIONS=8` starts a fresh thread after
eight rejected turns to limit stale-strategy anchoring and context growth. Set
it to 0 to disable count-based rotation. A manager may request an earlier fresh
context by putting `Worker-Context: FRESH` in a continuation assignment.

### Deterministic-blocker circuit breaker

The manager attaches `Blocking-Fingerprint: sha256:<output-hash>` to a
zero-improvement rejection when the same focused gate deterministically fails.
The circuit breaker is disabled by default
(`HARNESS_MAX_IDENTICAL_BLOCKERS=0`), so revisions remain automatic and a
manager cannot create a discretionary human-intervention block. A project may
explicitly set a positive threshold. At that threshold, `manager-reject-task`
atomically archives the result as `BLOCKED` and prevents another continuation;
`manager-block-task` independently verifies the configured threshold and
matching archived fingerprints, so it cannot be used to block early. Use
`harness-unblock-root ENV_FILE TASK_ROOT` after correcting the condition or
changing the task authority, scope, or plan.

Plan rows must be independently acceptance-complete: split a phase into
multiple rows before assigning bounded milestones. A baseline task may require
reproducing and documenting a known failure, but must never require that failure
to pass while its scope forbids the repair.

The project plan is independently durable. If a manager accepts a task and exits
without publishing its successor, the manager supervisor detects that the plan
is incomplete and no task is active. It resumes the manager to publish exactly
one task for the first unfinished plan item. The same recovery happens after a
restart; no completed plan item or root task is replayed.

`harness-status` reports both levels explicitly: project completion across the
plan and cumulative completion of each current root task.

## State location

Print the exact harness project-state path:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-state-path /path/to/repository/harness.env
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
/opt/coding-agent-fs-harness-v4.2/bin/harness-repository-path /path/to/repository/harness.env
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
    control/
        manager.thread
        project-plan.tsv
        project-plan-state.tsv
        supervisor.pid
        worker-supervisor.pid
        sample-project-task-002.lease
        progress/
            sample-project-task-002.root-assignment.md
            sample-project-task-002.progress.md
        sessions/
    logs/
        events.log
        supervisor.log
        worker-supervisor.log
        manager-bootstrap-*.jsonl
        manager-review-*.jsonl
        worker-task-*.jsonl
```

## Monitoring

Status:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-status /path/to/repository/harness.env
```

Unified state transitions:

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

Revisions are unlimited. A zero-improvement result causes a narrower or changed
strategy, not a terminal human-intervention state. Cumulative progress is
monotonic and only root-task acceptance criteria count toward it; unrelated
repairs contribute 0%.

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

Configure it in the environment file:

```bash
export HARNESS_PROVIDER_RETRY_SECONDS="60"
export HARNESS_QUOTA_RETRY_SECONDS="300"
```

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
/opt/coding-agent-fs-harness-v4.2/bin/harness-reset-task /path/to/repository/harness.env TASK_ID --force
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
export HARNESS_HOME="/opt/coding-agent-fs-harness-v4.2"
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
/opt/coding-agent-fs-harness-v4.2/bin/harness-check-env /path/to/repository/harness.env
```

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-start /path/to/repository/harness.env
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
