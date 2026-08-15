#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-result-barrier.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'result barrier specification\n' > "$TEST_ROOT/repo/spec.md"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" add spec.md
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed

cat > "$TEST_ROOT/manager-invoker" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail
touch "$TEST_ROOT/manager-called"
rm -f "$TEST_ROOT/state/projects/raceproj/results/raceproj-task-001.result.md"
SCRIPT
chmod 700 "$TEST_ROOT/manager-invoker"

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="raceproj"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$TEST_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export HARNESS_MANAGER_INVOKER="$TEST_ROOT/manager-invoker"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_DECOMPOSITION_V2="0"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_POLL_SECONDS="1"
export HARNESS_USE_INOTIFY="0"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null

project="$TEST_ROOT/state/projects/raceproj"
cat > "$project/archive/raceproj-task-001.assignment.md" <<'ASSIGNMENT'
# Task Assignment

Task-ID: 001
Task-Root: 001
ASSIGNMENT
cat > "$project/results/raceproj-task-001.result.md" <<'RESULT'
# Task Result

Task-ID: 001
Status: COMPLETED
RESULT

# Simulate worker-complete-task having published its result while the outer
# worker/Codex invocation is still alive and has not classified resource use.
sleep 20 &
worker_pid=$!
cat > "$project/control/raceproj-task-001.worker-invocation-active" <<MARKER
task_id=001
supervisor_pid=
worker_pid=$worker_pid
started_at=2026-08-15T00:00:00Z
MARKER

"$HARNESS_BIN/harness-supervisor-start" "$TEST_ROOT/harness.env" >/dev/null
sleep 2
[[ ! -e "$TEST_ROOT/manager-called" ]]
[[ -f "$project/results/raceproj-task-001.result.md" ]]

kill "$worker_pid"
wait "$worker_pid" 2>/dev/null || true
for _ in $(seq 1 100); do
	[[ -e "$TEST_ROOT/manager-called" ]] && break
	sleep 0.05
done
[[ -e "$TEST_ROOT/manager-called" ]]
[[ ! -f "$project/results/raceproj-task-001.result.md" ]]
[[ ! -f "$project/control/raceproj-task-001.worker-invocation-active" ]]
grep -Fq 'STALE_WORKER_INVOCATION_BARRIER_REMOVED task=001' "$project/logs/events.log"
"$HARNESS_BIN/harness-supervisor-stop" "$TEST_ROOT/harness.env" >/dev/null

printf 'supervisor result barrier tests passed.\n'
