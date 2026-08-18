#!/usr/bin/env bash

set -Eeuo pipefail

grep -Fq 'This planning role must not inspect repository source code' \
	"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/manager-plan-next-task"
grep -Fq 'MANAGER_PLAN_UNCOMMITTED_SUCCESS_RETRY' \
	"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/manager-plan-next-task"
grep -Fq 'fresh_manager_context=1' \
	"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/manager-plan-next-task"
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
task_id="\$2"
touch "$TEST_ROOT/manager-called-\$task_id"
if [[ "\$task_id" == 004-revision-01 ]]; then
	mkdir -p "$TEST_ROOT/state/projects/raceproj/control/progress"
	cat > "$TEST_ROOT/state/projects/raceproj/control/progress/raceproj-task-004.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 004
Triggered-By: 004
Trigger-Outcome: GOAL_NEEDS_DECOMPOSITION
MARKER
	exit 3
fi
if [[ "\$task_id" == 005 ]]; then
	exit 3
fi
rm -f "$TEST_ROOT/state/projects/raceproj/results/raceproj-task-\$task_id.result.md"
SCRIPT
chmod 700 "$TEST_ROOT/manager-invoker"

cat > "$TEST_ROOT/manager-replan-invoker" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail
touch "$TEST_ROOT/manager-replan-called-\$2"
exit 70
SCRIPT
chmod 700 "$TEST_ROOT/manager-replan-invoker"

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
export HARNESS_MANAGER_REPLAN_INVOKER="$TEST_ROOT/manager-replan-invoker"
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
start_test_supervisor()
{
	setsid "$HARNESS_BIN/harness-supervisor" "$TEST_ROOT/harness.env" </dev/null \
		>> "$project/logs/supervisor.log" 2>&1 &
	local launched=$!
	for _ in $(seq 1 50); do
		[[ -f "$project/control/supervisor.pid" ]] && return 0
		kill -0 "$launched" 2>/dev/null || break
		sleep 0.1
	done
	printf 'test supervisor failed to start\n' >&2
	return 1
}
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

start_test_supervisor
sleep 2
[[ ! -e "$TEST_ROOT/manager-called-001" ]]
[[ -f "$project/results/raceproj-task-001.result.md" ]]

kill "$worker_pid"
wait "$worker_pid" 2>/dev/null || true
for _ in $(seq 1 100); do
	[[ -e "$TEST_ROOT/manager-called-001" ]] && break
	sleep 0.05
done
[[ -e "$TEST_ROOT/manager-called-001" ]]
[[ ! -f "$project/results/raceproj-task-001.result.md" ]]
[[ ! -f "$project/control/raceproj-task-001.worker-invocation-active" ]]
grep -Fq 'STALE_WORKER_INVOCATION_BARRIER_REMOVED task=001' "$project/logs/events.log"

# Reproduce the exact unlink race: the manager observes the marker, opens it,
# and worker-supervisor removes it before any second field read could occur.
# A single snapshot remains valid through unlink and must not kill the manager
# supervisor or strand the already-published result.
cat > "$project/archive/raceproj-task-002.assignment.md" <<'ASSIGNMENT'
# Task Assignment

Task-ID: 002
Task-Root: 002
ASSIGNMENT
cat > "$project/results/raceproj-task-002.result.md" <<'RESULT'
# Task Result

Task-ID: 002
Status: COMPLETED
RESULT
race_marker="$project/control/raceproj-task-002.worker-invocation-active"
cat > "$race_marker" <<'MARKER'
task_id=002
supervisor_pid=
worker_pid=
started_at=2026-08-15T00:00:00Z
MARKER
(
	inotifywait -q -e open "$race_marker" >/dev/null 2>&1
	rm -f "$race_marker"
) &
unlink_watcher=$!
for _ in $(seq 1 100); do
	[[ -e "$TEST_ROOT/manager-called-002" ]] && break
	sleep 0.05
done
wait "$unlink_watcher"
[[ -e "$TEST_ROOT/manager-called-002" ]]
[[ ! -f "$project/results/raceproj-task-002.result.md" ]]
supervisor_pid="$(awk 'NR==1 {print; exit}' "$project/control/supervisor.pid")"
kill -0 "$supervisor_pid"
! grep -Fq 'SUPERVISOR_FATAL' "$project/logs/events.log"

# A bounded automatic-replan publication failure is captured as durable
# recovery state. It must not fire the global ERR trap, kill the watcher, or
# leave status tools believing that an unreported fatal crash occurred.
mkdir -p "$project/control/progress"
cat > "$project/control/progress/raceproj-task-003.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 003
Triggered-By: 003
Trigger-Outcome: CHECKPOINT
MARKER
for _ in $(seq 1 100); do
	[[ -e "$TEST_ROOT/manager-replan-called-003" ]] && break
	sleep 0.05
done
[[ -e "$TEST_ROOT/manager-replan-called-003" ]]
[[ -f "$project/control/raceproj-task-003.manager-replan-failed.md" ]]
kill -0 "$supervisor_pid"
! grep -Fq 'SUPERVISOR_FATAL' "$project/logs/events.log"
grep -Fq 'SUPERVISOR_MANAGER_RECOVERY_FAILED root=003 status=70' "$project/logs/events.log"

# A needs-replan marker cannot race ahead of an exact revision result that is
# still awaiting a terminal manager review action. The result remains the
# authoritative transaction boundary and the replan invoker must stay idle.
cat > "$project/archive/raceproj-task-004-revision-01.assignment.md" <<'ASSIGNMENT'
# Task Assignment

Task-ID: 004-revision-01
Task-Root: 004
ASSIGNMENT
cat > "$project/results/raceproj-task-004-revision-01.result.md" <<'RESULT'
# Task Result

Task-ID: 004-revision-01
Status: COMPLETED
RESULT
for _ in $(seq 1 100); do
	[[ -e "$TEST_ROOT/manager-called-004-revision-01" ]] && break
	sleep 0.05
done
[[ -e "$TEST_ROOT/manager-called-004-revision-01" ]]
sleep 1.2
[[ -f "$project/results/raceproj-task-004-revision-01.result.md" ]]
[[ -f "$project/control/progress/raceproj-task-004.needs-replan.md" ]]
[[ -f "$project/control/raceproj-task-004-revision-01.manager-review-stalled.md" ]]
[[ ! -e "$TEST_ROOT/manager-replan-called-004" ]]
kill -0 "$supervisor_pid"
"$HARNESS_BIN/harness-supervisor-stop" "$TEST_ROOT/harness.env" >/dev/null

# A deployed review fix changes the executable review boundary even when the
# result and project artifacts are unchanged. Restarting with that new harness
# must retry the preserved result instead of retaining an obsolete stall.
cat > "$project/archive/raceproj-task-005.assignment.md" <<'ASSIGNMENT'
# Task Assignment

Task-ID: 005
Task-Root: 005
ASSIGNMENT
cat > "$project/results/raceproj-task-005.result.md" <<'RESULT'
# Task Result

Task-ID: 005
Status: COMPLETED
RESULT
start_test_supervisor
for _ in $(seq 1 100); do
	[[ -e "$project/control/raceproj-task-005.manager-review-stalled.md" ]] && break
	sleep 0.05
done
[[ -e "$project/control/raceproj-task-005.manager-review-stalled.md" ]]
"$HARNESS_BIN/harness-supervisor-stop" "$TEST_ROOT/harness.env" >/dev/null
printf '\n# deployed review fix\n' >> "$TEST_ROOT/manager-invoker"
rm -f "$TEST_ROOT/manager-called-005"
start_test_supervisor
for _ in $(seq 1 100); do
	[[ -e "$TEST_ROOT/manager-called-005" ]] && break
	sleep 0.05
done
[[ -e "$TEST_ROOT/manager-called-005" ]]
"$HARNESS_BIN/harness-supervisor-stop" "$TEST_ROOT/harness.env" >/dev/null

# A terminal worker-invoker exit must not leave a dead running assignment
# presented as useful worker activity. Preserve the transaction artifacts and
# raise the project-integrity fuse until the local defect is investigated.
cat > "$TEST_ROOT/orphan-worker-invoker" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail
session="\$("$HARNESS_BIN/harness-new-session" "\$1" worker)"
"$HARNESS_BIN/worker-claim-task" "\$1" "\$2" "\$session" >/dev/null
exit 17
SCRIPT
chmod 700 "$TEST_ROOT/orphan-worker-invoker"
printf 'export HARNESS_WORKER_INVOKER="%s"\n' "$TEST_ROOT/orphan-worker-invoker" >> "$TEST_ROOT/harness.env"
cat > "$project/tasks/raceproj-task-orphan.ready.md" <<'ASSIGNMENT'
# Task Assignment

Task-ID: orphan
Task-Root: orphan
ASSIGNMENT
"$HARNESS_BIN/worker-supervisor-start" "$TEST_ROOT/harness.env" >/dev/null
for _ in $(seq 1 100); do
	[[ -e "$project/control/project-integrity-anomaly.md" ]] && break
	sleep 0.05
done
[[ -f "$project/running/raceproj-task-orphan.running.md" ]]
[[ -f "$project/control/raceproj-task-orphan.worker-supervisor-failed.md" ]]
grep -Fqx 'Category: WORKER_TRANSACTION_ORPHANED' \
	"$project/control/project-integrity-anomaly.md"
grep -Fq 'WORKER_TRANSACTION_ORPHANED task=orphan status=17' "$project/logs/events.log"
"$HARNESS_BIN/worker-supervisor-stop" "$TEST_ROOT/harness.env" >/dev/null

printf 'supervisor result barrier tests passed.\n'
