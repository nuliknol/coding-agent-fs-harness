#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/coding-harness-v4.2-test.XXXXXX)"
trap '"$HARNESS_BIN/harness-stop" "$TEST_ROOT/harness.env" >/dev/null 2>&1 || true; rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'test specification\n' > "$TEST_ROOT/repo/spec.md"

cat > "$TEST_ROOT/mock-codex" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
prompt="$(cat)"
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
	note="$(mktemp)"
	printf 'Mock accepted.\n' > "$note"
	"$HARNESS_BIN/manager-accept-task" "$ENV_FILE" "$TASK_ID" "$note" >/dev/null
	rm -f "$note"
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
export MANAGER_MODEL="gpt-5.5"
export MANAGER_REASONING_EFFORT="high"
export MANAGER_SANDBOX="danger-full-access"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
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
"$HARNESS_BIN/harness-start" "$TEST_ROOT/harness.env" >/dev/null

for _ in $(seq 1 300); do
	[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.accepted.md" ]] && break
	sleep 0.1
done

EVENTS="$TEST_ROOT/state/projects/testproj/logs/events.log"
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-001.accepted.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.accepted.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-002.ready.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/running/testproj-task-002.running.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/results/testproj-task-002.result.md" ]]
grep -q 'MANAGER_BOOTSTRAP_CAPACITY_RETRY_SCHEDULED' "$EVENTS"
grep -q 'MANAGER_BOOTSTRAP_CAPACITY_RETRY_STARTED' "$EVENTS"
grep -q 'WORKER_CAPACITY_RETRY_SCHEDULED task=001' "$EVENTS"
grep -q 'WORKER_CAPACITY_RETRY_STARTED task=001' "$EVENTS"
grep -q 'MANAGER_CAPACITY_RETRY_SCHEDULED task=001' "$EVENTS"
grep -q 'MANAGER_CAPACITY_RETRY_STARTED task=001' "$EVENTS"
grep -q 'WORKER_SUPERVISOR_TRIGGER task=001' "$EVENTS"
grep -q 'WORKER_DIRECT_RESULT_NORMALIZED task=001' "$EVENTS"
grep -q 'WORKER_LAST_MESSAGE_RESULT_NORMALIZED task=002' "$EVENTS"
grep -q 'TASK_PUBLISHED task=002' "$EVENTS"
grep -q 'TASK_ACCEPTED task=002' "$EVENTS"
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-001.assignment.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.assignment.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-001.lease" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-002.lease" ]]
first_complete_line="$(grep -n 'TASK_COMPLETED task=001' "$EVENTS" | head -n 1 | cut -d: -f1)"
first_review_line="$(grep -n 'MANAGER_REVIEW_STARTED task=001' "$EVENTS" | head -n 1 | cut -d: -f1)"
[[ -n "$first_complete_line" && -n "$first_review_line" ]]
(( first_complete_line < first_review_line ))

printf 'All v4.2 harness tests passed.\n'
