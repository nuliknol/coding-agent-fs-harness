# Coding Agent Filesystem Harness v4.2 (for Codex CLI)

A local, event-driven two-agent coding harness for Linux.

- A strong manager model decomposes the specification and reviews results.
- A cheaper worker model implements one bounded task at a time.
- Ordinary Bash supervisors watch filesystem mailboxes.
- No model remains alive while waiting.
- Git commits remain manual.
- One trusted `.env` file configures the complete project, harness installation, state directory, accounts, models, and timing.

## Process model

```text
manager-bootstrap
    -> one manager Codex turn publishes task 001
    -> manager exits

worker-supervisor (local Bash, no tokens)
    -> detects task 001
    -> launches one worker `codex exec`
    -> worker implements, publishes result, exits

manager-supervisor (local Bash, no tokens)
    -> detects result 001
    -> resumes manager Codex thread
    -> manager accepts/rejects and publishes the next task
    -> manager exits

worker-supervisor
    -> detects the next task
    -> repeats
```

The interactive Codex TUI is not used for automated workers. A fresh non-interactive worker thread is created for each task. This prevents an idle worker prompt and avoids accumulating the entire project history in one worker context.



## Watch the agents working

`harness-watch-agents refactoring-whatever.env`

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
I’ll review task 039 against the archived assignment and actual code, run focused and full validation, then accept or reject and publish one bounded follow-up.

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
The result claims the descriptor layer is host-only and validates alignment, row strides, ordering, and spans. I’m inspecting the descriptor structs, builder, tests, and status note now.

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
The status note limits the scope correctly. I’m reading the descriptor builder and tests for span validation, relative host pointers, and malformed-plan handling.

[MANAGER task=039-phase8-gpu-proof-device-buffer-descriptor]
The descriptor builder reuses the private plan validator, so it inherits the fixed 16-byte alignment and region-order checks before constructing descriptors. I’m verifying the validation helper and then running the required validation.



## Requirements

- Linux
- Bash
- `flock`, `realpath`, `sha256sum`, `stat`
- Codex CLI
- Optional: `inotifywait` from `inotify-tools`
- Optional: `jq` for easier JSONL inspection

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
export MANAGER_MODEL="gpt-5.5"
export MANAGER_REASONING_EFFORT="high"
export MANAGER_SANDBOX="danger-full-access"

export WORKER_CODEX_HOME="$HOME/.codex/worker-account"
export WORKER_CODEX_BIN="$HOME/.local/bin/codex"
export WORKER_MODEL="gpt-5.4-mini"
export WORKER_REASONING_EFFORT="high"
export WORKER_SANDBOX="danger-full-access"

export HARNESS_POLL_SECONDS="2"
export HARNESS_WAIT_SECONDS="300"
export HARNESS_STALE_SECONDS="900"
export HARNESS_USE_INOTIFY="1"
export WORKER_HEARTBEAT_SECONDS="60"
```

The manager and worker may use the same `CODEX_HOME`, but separate account directories make account selection explicit.

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

`harness-init` and `harness-start` serialize on the environment file path. A second concurrent invocation against the same `ENV_FILE` is rejected instead of racing.

`harness-start` performs these operations:

1. If no manager thread exists, run one manager bootstrap turn.
2. Start the manager result watcher.
3. Start the worker task watcher.
4. Return to the shell.

After that, no manual prompt pushes are required.

## Stop and restart

Stop both local supervisors:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-stop /path/to/repository/harness.env
```

Restart them and preserve existing state:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-start /path/to/repository/harness.env
```

If `manager.thread` already exists, bootstrap is not repeated.
If a harness process for the same `ENV_FILE` is already active, `harness-init` and `harness-start` prompt for confirmation before resetting the existing project state. Confirming the reset stops the supervisors, archives the previous project state under `$HARNESS_ROOT/resets/`, and recreates a fresh project directory.

## State location

Print the exact harness project-state path:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-state-path /path/to/repository/harness.env
```

For the example configuration, it is:

```text
$HOME/.local/state/coding-harness/projects/sample-project
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
        supervisor.pid
        worker-supervisor.pid
        sample-project-task-002.lease
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

## Heartbeats and long tasks

The worker launcher runs a local heartbeat subprocess while Codex is active. The LLM does not need to remember to send heartbeats.

`WORKER_HEARTBEAT_SECONDS=60` means the lease is refreshed every 60 seconds.

`HARNESS_STALE_SECONDS=900` means a running worker is considered stale only after 900 seconds without a heartbeat. It is not a task-duration limit.

## Capacity retry policy

The harness automatically retries only the confirmed transient Codex error:

```text
Selected model is at capacity. Please try a different model.
```

The default policy waits 60 seconds and launches a fresh Codex process. It applies to:

- manager bootstrap;
- manager result review;
- worker task execution.

Configure it in the environment file:

```bash
export HARNESS_CAPACITY_RETRY_SECONDS="60"
export HARNESS_CAPACITY_MAX_RETRIES="0"
```

`HARNESS_CAPACITY_MAX_RETRIES=0` means unlimited retries. A positive number limits the number of automatic retries. Each attempt receives a separate JSONL and final-message log with an `attempt-NNN` suffix.

The worker heartbeat remains active during the retry delay, so the claimed task does not become stale. The worker keeps the same task ownership session but starts a fresh Codex context. The manager resumes its persistent manager thread.

The retry is deliberately narrow: test failures, authentication errors, invalid configuration, protocol violations, and other process failures are not retried automatically.

## Other failure policy

A non-capacity worker failure leaves the task in `RUNNING` state and writes:

```text
control/PROJECT-task-ID.worker-failed.md
```

Inspect the task log and then reset it explicitly:

```bash
/opt/coding-agent-fs-harness-v4.2/bin/harness-reset-task /path/to/repository/harness.env TASK_ID --force
```

The worker supervisor detects the newly restored ready task and performs one new invocation.

A non-capacity manager failure writes a manager failure file and requires explicit requeue through `harness-requeue-result`.

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

Version 4.2 adds automatic recovery from temporary model congestion. On the exact capacity error, the invocation wrapper waits `HARNESS_CAPACITY_RETRY_SECONDS` and starts a fresh Codex process. Worker ownership and heartbeats remain valid across the wait. Manager review checks whether an accept/reject action was committed before retrying, preventing duplicate manager actions after a late stream failure.

Event-log entries include:

```text
WORKER_CAPACITY_RETRY_SCHEDULED
WORKER_CAPACITY_RETRY_STARTED
MANAGER_CAPACITY_RETRY_SCHEDULED
MANAGER_CAPACITY_RETRY_STARTED
MANAGER_BOOTSTRAP_CAPACITY_RETRY_SCHEDULED
MANAGER_BOOTSTRAP_CAPACITY_RETRY_STARTED
```
