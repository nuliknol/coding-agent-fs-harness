#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-acp-parallel.XXXXXX)"
cleanup()
{
	git -C "$TEST_ROOT/repo" worktree prune >/dev/null 2>&1 || true
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'ACP parallel integration specification\n' > "$TEST_ROOT/repo/spec.md"
printf 'base-a\n' > "$TEST_ROOT/repo/a.txt"
printf 'base-b\n' > "$TEST_ROOT/repo/b.txt"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name test
git -C "$TEST_ROOT/repo" config user.email test@example.invalid
git -C "$TEST_ROOT/repo" add .
git -C "$TEST_ROOT/repo" commit -qm baseline

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT=acpparallel
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_MODE=full
export HARNESS_HOME="$ROOT"
export HARNESS_BIN="$ROOT/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN=/bin/true
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN=/bin/true
export HARNESS_ACP_ENABLED=1
export HARNESS_WORKER_PARALLELISM=4
export HARNESS_WORKER_PARALLELISM_HARD_MAX=4
export HARNESS_WORKER_ISOLATION_MODE=worktree
export HARNESS_DECOMPOSITION_V2=0
export HARNESS_SPECIFICATION_REVIEW_ENABLED=0
export HARNESS_WORKER_GOAL_MODE=0
export HARNESS_ARCHITECTURE_GUARDS=0
export HARNESS_AGENT_MIN_INTERVAL_SECONDS=0
export MAX_ORACLE_RUNS=0
ENV
chmod 600 "$TEST_ROOT/harness.env"
"$ROOT/bin/harness-init" "$TEST_ROOT/harness.env" >/dev/null
project="$TEST_ROOT/state/projects/acpparallel"

for task in a b; do
	cat > "$project/tasks/acpparallel-task-$task.ready.md" <<TASK
# Task Assignment

Task-ID: $task
Task-Root: $task
Allowed-Scope: $task.txt
Context-Paths: $task.txt
Required-Symbols: -
Focused-Validation: grep -Fqx task-$task $task.txt
Expected-Max-Implementation-Files: 1
TASK
done

cat > "$TEST_ROOT/mock-worker" <<'WORKER'
#!/usr/bin/env bash
set -Eeuo pipefail
env_file="$1"; task_id="$2"
session="$($HARNESS_BIN/harness-new-session "$env_file" "worker-$task_id")"
claim="$($HARNESS_BIN/worker-claim-task "$env_file" "$task_id" "$session")"
task_file="$(sed -n 's/^TASK_FILE=//p' <<< "$claim")"
source "$env_file"
PROJECT_TMP_DIR="$HARNESS_TASK_TMP_DIR"
printf 'task-%s\n' "$task_id" >> "$REPOSITORY/$task_id.txt"
message="$PROJECT_TMP_DIR/commit-message"
result="$PROJECT_TMP_DIR/result.md"
mkdir -p "$PROJECT_TMP_DIR"
printf 'Implement %s\n' "$task_id" > "$message"
"$HARNESS_BIN/harness-commit-source" "$env_file" "$task_id" "$session" "$message" "$task_id.txt" >/dev/null
cat > "$result" <<RESULT
# Worker Task Result

Task-ID: $task_id
Status: COMPLETED

## Summary

Implemented isolated task $task_id.

## Modified files

$task_id.txt

## Implemented behavior

Added task marker.

## Validation performed

Focused validation is delegated to the integration barrier.

## Deviations from assignment

None.

## Remaining concerns

None.

## Worker assessment

COMPLETE.
RESULT
"$HARNESS_BIN/worker-complete-task" "$env_file" "$task_id" "$session" "$result" >/dev/null
WORKER
chmod 700 "$TEST_ROOT/mock-worker"

printf 'export HARNESS_WORKER_INVOKER=%q\n' "$TEST_ROOT/mock-worker" >> "$TEST_ROOT/harness.env"
"$ROOT/bin/worker-supervisor" "$TEST_ROOT/harness.env" > "$TEST_ROOT/worker-supervisor.log" 2>&1 &
supervisor_pid=$!
for _ in $(seq 1 200); do
	[[ -f "$project/control/acp/integration/a.integrated.env" &&
		-f "$project/control/acp/integration/b.integrated.env" ]] && break
	if ! kill -0 "$supervisor_pid" 2>/dev/null; then
		cat "$TEST_ROOT/worker-supervisor.log" >&2
		exit 1
	fi
	sleep 0.05
done
kill -TERM "$supervisor_pid"
wait "$supervisor_pid" 2>/dev/null || true

grep -Fqx task-a "$TEST_ROOT/repo/a.txt"
grep -Fqx task-b "$TEST_ROOT/repo/b.txt"
[[ -f "$project/control/acp/integration/a.integrated.env" ]]
[[ -f "$project/control/acp/integration/b.integrated.env" ]]
[[ ! -e "$project/control/acp/capability-leases/a.lease.env" ]]
[[ ! -e "$project/control/acp/capability-leases/b.lease.env" ]]
grep -Fq $'INTEGRATED\tSCOPE\tWRITE' "$project/control/acp/events.tsv"
git -C "$TEST_ROOT/repo" diff --quiet
git -C "$TEST_ROOT/repo" diff --cached --quiet

printf 'ACP parallel integration tests passed.\n'
