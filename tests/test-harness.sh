#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/coding-harness-v4.2-test.XXXXXX)"
trap '"$HARNESS_BIN/harness-stop" "$TEST_ROOT/harness.env" >/dev/null 2>&1 || true; rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'test specification\n' > "$TEST_ROOT/repo/spec.md"
ARGS_LOG="$TEST_ROOT/mock-codex-args.log"
export ARGS_LOG

cat > "$TEST_ROOT/mock-codex" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
prompt="$(cat)"
printf '%s\n' "$*" >> "$ARGS_LOG"
last_message_file=""
capture_next=0
for arg in "$@"; do
	if [[ "$capture_next" == 1 ]]; then
		last_message_file="$arg"
		capture_next=0
		continue
	fi
	if [[ "$arg" == "--output-last-message" ]]; then
		capture_next=1
	fi
done
value()
{
	local key="$1"
	printf '%s\n' "$prompt" | awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}'
}
ENV_FILE="$(value ENV_FILE)"
source "$ENV_FILE"
mkdir -p "$HARNESS_ROOT/mock-counts"

kind="unknown"
key="unknown"
if printf '%s' "$prompt" | grep -q 'This is the bootstrap turn'; then
	kind="bootstrap"
	key="bootstrap"
elif printf '%s' "$prompt" | grep -q 'A worker result is ready for review'; then
	kind="review"
	key="review-$(value TASK_ID)"
elif printf '%s' "$prompt" | grep -q 'The task is already claimed by this launcher'; then
	kind="worker"
	key="worker-$(value TASK_ID)"
fi
counter="$HARNESS_ROOT/mock-counts/$key"
count=0
[[ ! -f "$counter" ]] || count="$(cat "$counter")"
count=$((count + 1))
printf '%s\n' "$count" > "$counter"

# Exercise automatic capacity retry once in all three invocation paths:
# manager bootstrap, worker task 001, and manager review task 001.
if [[ "$count" == 1 && ( "$key" == bootstrap || "$key" == worker-001 || "$key" == review-001 ) ]]; then
	printf '{"type":"error","message":"Selected model is at capacity. Please try a different model."}\n'
	printf '{"type":"turn.failed","error":{"message":"Selected model is at capacity. Please try a different model."}}\n'
	exit 1
fi

printf '{"type":"thread.started","thread_id":"mock-thread-001"}\n'
printf '{"type":"turn.started"}\n'
HARNESS_BIN="$(value HARNESS_BIN)"
final_message="done"
if [[ "$kind" == bootstrap ]]; then
	tmp="$(mktemp)"
	printf '# Task\n\nTask-ID: 001\n\nMock first task.\n' > "$tmp"
	"$HARNESS_BIN/manager-publish-task" "$ENV_FILE" 001 "$tmp" >/dev/null
	rm -f "$tmp"
elif [[ "$kind" == review ]]; then
	TASK_ID="$(value TASK_ID)"
	if [[ "$TASK_ID" == 002 && "$count" == 1 ]]; then
		final_message="review-left-pending"
	elif [[ "$TASK_ID" == 002 && "$count" == 2 ]]; then
		note="$(mktemp)"
		printf 'Mock accepted after a pending review turn.\n' > "$note"
		"$HARNESS_BIN/manager-accept-task" "$ENV_FILE" "$TASK_ID" "$note" --complete-project >/dev/null
		rm -f "$note"
	else
	note="$(mktemp)"
	printf 'Mock accepted.\n' > "$note"
	"$HARNESS_BIN/manager-accept-task" "$ENV_FILE" "$TASK_ID" "$note" >/dev/null
	rm -f "$note"
	fi
	if [[ "$TASK_ID" == 001 ]]; then
		tmp="$(mktemp)"
		printf '# Task\n\nTask-ID: 002\n\nMock second task.\n' > "$tmp"
		"$HARNESS_BIN/manager-publish-task" "$ENV_FILE" 002 "$tmp" >/dev/null
		rm -f "$tmp"
	fi
elif [[ "$kind" == worker ]]; then
	TASK_ID="$(value TASK_ID)"
	SESSION="$(value SESSION)"
	final_message="$(printf '# Task Result\n\nTask-ID: %s\nStatus: COMPLETED\n' "$TASK_ID")"
	if [[ "$TASK_ID" == 001 ]]; then
		# Deliberately expose a result directly. worker-invoke-task must normalize
		# it through worker-complete-task before manager review can begin.
		result="$HARNESS_ROOT/projects/$PROJECT/results/$PROJECT-task-$TASK_ID.result.md"
		printf '%s\n' "$final_message" > "$result"
	fi
	sleep 0.5
else
	exit 9
fi
if [[ -n "$last_message_file" ]]; then
	printf '%s\n' "$final_message" > "$last_message_file"
fi
printf '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}\n'
printf '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}\n'
MOCK
chmod +x "$TEST_ROOT/mock-codex"

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="testproj"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
CODEX_EXTRA_ARGS=(
  --config model_context_window=272000
)
MANAGER_CODEX_EXTRA_ARGS=(
  --config model_auto_compact_token_limit=240000
)
export MANAGER_MODEL="gpt-5.5"
export MANAGER_REASONING_EFFORT="high"
export MANAGER_SANDBOX="danger-full-access"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
WORKER_CODEX_EXTRA_ARGS=(
  --config model_auto_compact_token_limit=240000
)
export WORKER_MODEL="gpt-5.4-mini"
export WORKER_REASONING_EFFORT="high"
export WORKER_SANDBOX="danger-full-access"
export HARNESS_POLL_SECONDS="0.2"
export HARNESS_WAIT_SECONDS="5"
export HARNESS_STALE_SECONDS="30"
export HARNESS_USE_INOTIFY="0"
export WORKER_HEARTBEAT_SECONDS="1"
export HARNESS_CAPACITY_RETRY_SECONDS="1"
export HARNESS_CAPACITY_MAX_RETRIES="3"
ENV
chmod 600 "$TEST_ROOT/harness.env"

"$HARNESS_BIN/harness-check-env" "$TEST_ROOT/harness.env" >/dev/null
"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
[[ -d "/tmp/testproj" ]]
"$HARNESS_BIN/harness-start" "$TEST_ROOT/harness.env" >/dev/null

for _ in $(seq 1 300); do
	if [[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.accepted.md" &&
		-f "$TEST_ROOT/state/projects/testproj/control/project.complete" ]]; then
		break
	fi
	sleep 0.1
done

EVENTS="$TEST_ROOT/state/projects/testproj/logs/events.log"
TRACE="$TEST_ROOT/state/projects/testproj/logs/trace.log"
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-001.accepted.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.accepted.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/control/project.complete" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-002.ready.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/running/testproj-task-002.running.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/results/testproj-task-002.result.md" ]]
grep -q 'MANAGER_BOOTSTRAP_CAPACITY_RETRY_SCHEDULED' "$EVENTS"
grep -q 'MANAGER_BOOTSTRAP_CAPACITY_RETRY_STARTED' "$EVENTS"
grep -q 'WORKER_CAPACITY_RETRY_SCHEDULED task=001' "$EVENTS"
grep -q 'WORKER_CAPACITY_RETRY_STARTED task=001' "$EVENTS"
grep -q 'MANAGER_CAPACITY_RETRY_SCHEDULED task=001' "$EVENTS"
grep -q 'MANAGER_CAPACITY_RETRY_STARTED task=001' "$EVENTS"
grep -q 'MANAGER_REVIEW_LEFT_PENDING task=002' "$EVENTS"
grep -q 'SUPERVISOR_REVIEW_LEFT_UNCOMMITTED task=002' "$EVENTS"
grep -q 'WORKER_SUPERVISOR_TRIGGER task=001' "$EVENTS"
grep -q 'WORKER_DIRECT_RESULT_NORMALIZED task=001' "$EVENTS"
grep -q 'WORKER_LAST_MESSAGE_RESULT_NORMALIZED task=002' "$EVENTS"
grep -q 'TASK_PUBLISHED task=002' "$EVENTS"
grep -q 'TASK_ACCEPTED task=002' "$EVENTS"
grep -q 'PROJECT_COMPLETED task=002' "$EVENTS"
grep -q 'event=SCRIPT_START' "$TRACE"
grep -q 'event=CODEX_EXEC_START' "$TRACE"
grep -q 'event=CODEX_EXEC_END' "$TRACE"
grep -q 'event=TASK_COMPLETED' "$TRACE"
grep -q 'event=TASK_ACCEPTED' "$TRACE"
grep -q 'event=PROJECT_COMPLETED' "$TRACE"
grep -q -- '--config model_context_window=272000' "$ARGS_LOG"
grep -q -- '--config model_auto_compact_token_limit=240000' "$ARGS_LOG"
grep -q -- '--add-dir /tmp/testproj' "$ARGS_LOG"
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-001.assignment.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.assignment.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-001.lease" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-002.lease" ]]
first_complete_line="$(grep -n 'TASK_COMPLETED task=001' "$EVENTS" | head -n 1 | cut -d: -f1)"
first_review_line="$(grep -n 'MANAGER_REVIEW_STARTED task=001' "$EVENTS" | head -n 1 | cut -d: -f1)"
[[ -n "$first_complete_line" && -n "$first_review_line" ]]
(( first_complete_line < first_review_line ))
review_002_count="$(grep -c 'MANAGER_REVIEW_STARTED task=002' "$EVENTS")"
[[ "$review_002_count" -ge 2 ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-002.manager-failed.md" ]]

for _ in $(seq 1 100); do
	[[ ! -f "$TEST_ROOT/state/projects/testproj/control/supervisor.pid" && ! -f "$TEST_ROOT/state/projects/testproj/control/worker-supervisor.pid" ]] && break
	sleep 0.1
done
[[ ! -f "$TEST_ROOT/state/projects/testproj/control/supervisor.pid" ]]
[[ ! -f "$TEST_ROOT/state/projects/testproj/control/worker-supervisor.pid" ]]
grep -q 'SUPERVISOR_PROJECT_COMPLETED task=002' "$EVENTS"
grep -q 'WORKER_SUPERVISOR_PROJECT_COMPLETED task=002' "$EVENTS"

task_id=002
base="testproj-task-$task_id"
result="$TEST_ROOT/state/projects/testproj/results/$base.result.md"
accepted="$TEST_ROOT/state/projects/testproj/archive/$base.accepted.md"
stale_result_archive="$TEST_ROOT/state/projects/testproj/archive/$base.accepted-stale-result.md"
printf '# Duplicate Result\n' > "$result"
"$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" "$task_id" >/dev/null
[[ -f "$accepted" ]]
[[ ! -e "$result" ]]
[[ -f "$stale_result_archive" ]]
grep -q 'TASK_ACCEPTED_STALE_RESULT_ARCHIVED task=002' "$EVENTS"

ACTIVE_ROOT="$TEST_ROOT/active"
mkdir -p "$ACTIVE_ROOT/repo" "$ACTIVE_ROOT/manager-home" "$ACTIVE_ROOT/worker-home"
printf 'test specification\n' > "$ACTIVE_ROOT/repo/spec.md"
cat > "$ACTIVE_ROOT/harness.env" <<ENV
export PROJECT="activeproj"
export REPOSITORY="$ACTIVE_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$ACTIVE_ROOT/state"
export MANAGER_CODEX_HOME="$ACTIVE_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export MANAGER_MODEL="gpt-5.5"
export MANAGER_REASONING_EFFORT="high"
export MANAGER_SANDBOX="danger-full-access"
export WORKER_CODEX_HOME="$ACTIVE_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_MODEL="gpt-5.4-mini"
export WORKER_REASONING_EFFORT="high"
export WORKER_SANDBOX="danger-full-access"
export HARNESS_POLL_SECONDS="0.2"
export HARNESS_WAIT_SECONDS="5"
export HARNESS_STALE_SECONDS="30"
export HARNESS_USE_INOTIFY="0"
export WORKER_HEARTBEAT_SECONDS="1"
ENV
chmod 600 "$ACTIVE_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ACTIVE_ROOT/harness.env" >/dev/null
[[ -d "/tmp/activeproj" ]]
"$HARNESS_BIN/harness-supervisor-start" "$ACTIVE_ROOT/harness.env" >/dev/null
"$HARNESS_BIN/worker-supervisor-start" "$ACTIVE_ROOT/harness.env" >/dev/null

LOCK_PATH="$ACTIVE_ROOT/state/control/env-locks/$(printf '%s' "$ACTIVE_ROOT/harness.env" | sha256sum | awk '{print $1}').lock"
sleep 2 &
lock_pid=$!
printf 'pid=%s\nstarted_at=%s\noperation=%s\nenv_file=%s\n' \
	"$lock_pid" '1970-01-01T00:00:00Z' 'external-test-lock' "$ACTIVE_ROOT/harness.env" > "$LOCK_PATH"
sleep 0.2
if "$HARNESS_BIN/harness-start" "$ACTIVE_ROOT/harness.env" >"$ACTIVE_ROOT/lock.out" 2>"$ACTIVE_ROOT/lock.err"; then
	printf 'Expected harness-start lock contention to fail.\n' >&2
	exit 1
fi
grep -q 'harness-start is already running' "$ACTIVE_ROOT/lock.err"
wait "$lock_pid"
rm -f "$LOCK_PATH"

if printf 'n\n' | "$HARNESS_BIN/harness-start" "$ACTIVE_ROOT/harness.env" >"$ACTIVE_ROOT/start-reset.out" 2>"$ACTIVE_ROOT/start-reset.err"; then
	printf 'Expected harness-start to reject repeated invocation without reset confirmation.\n' >&2
	exit 1
fi
grep -q 'Reset current state for' "$ACTIVE_ROOT/start-reset.err"
grep -q 'harness-start aborted because state is already active' "$ACTIVE_ROOT/start-reset.err"
[[ -f "$ACTIVE_ROOT/state/projects/activeproj/control/supervisor.pid" ]]

if ! printf 'yes\n' | "$HARNESS_BIN/harness-init" "$ACTIVE_ROOT/harness.env" >"$ACTIVE_ROOT/init-reset.out" 2>"$ACTIVE_ROOT/init-reset.err"; then
	printf 'Expected harness-init reset confirmation to succeed.\n' >&2
	exit 1
fi
grep -q 'Previous state moved to' "$ACTIVE_ROOT/init-reset.err"
[[ -d "$ACTIVE_ROOT/state/resets" ]]
[[ ! -f "$ACTIVE_ROOT/state/projects/activeproj/control/supervisor.pid" ]]
[[ ! -f "$ACTIVE_ROOT/state/projects/activeproj/control/worker-supervisor.pid" ]]

INACTIVE_ROOT="$TEST_ROOT/inactive"
mkdir -p "$INACTIVE_ROOT/repo" "$INACTIVE_ROOT/manager-home" "$INACTIVE_ROOT/worker-home"
printf 'test specification\n' > "$INACTIVE_ROOT/repo/spec.md"
cat > "$INACTIVE_ROOT/harness.env" <<ENV
export PROJECT="inactiveproj"
export REPOSITORY="$INACTIVE_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$INACTIVE_ROOT/state"
export MANAGER_CODEX_HOME="$INACTIVE_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$INACTIVE_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
ENV
chmod 600 "$INACTIVE_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$INACTIVE_ROOT/harness.env" >/dev/null
[[ -d "/tmp/inactiveproj" ]]
if "$HARNESS_BIN/harness-init" "$INACTIVE_ROOT/harness.env" >"$INACTIVE_ROOT/reinit.out" 2>"$INACTIVE_ROOT/reinit.err"; then
	printf 'Expected harness-init to refuse overwriting inactive state.\n' >&2
	exit 1
fi
grep -q 'project state already exists at' "$INACTIVE_ROOT/reinit.err"
grep -q 'rm -rf' "$INACTIVE_ROOT/reinit.err"

printf 'All v4.2 harness tests passed.\n'
