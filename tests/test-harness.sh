#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/coding-harness-v4.4-test.XXXXXX)"
cleanup()
{
	"$HARNESS_BIN/harness-stop" "$TEST_ROOT/harness.env" >/dev/null 2>&1 || true
	if [[ "${KEEP_TEST_ROOT:-0}" == 1 ]]; then
		printf 'Preserved failed test state: %s\n' "$TEST_ROOT" >&2
	else
		rm -rf "$TEST_ROOT"
	fi
}
trap cleanup EXIT

mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'test specification\n' > "$TEST_ROOT/repo/spec.md"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" add spec.md
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid commit -qm baseline
ARGS_LOG="$TEST_ROOT/mock-codex-args.log"
export ARGS_LOG

cat > "$TEST_ROOT/mock-codex" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
prompt="$(cat)"
printf '%s\n' "$*" >> "$ARGS_LOG"
last_message_file=""
capture_next=0
resume_thread_id=""
capture_resume=0
for arg in "$@"; do
	if [[ "$capture_resume" == 1 ]]; then
		resume_thread_id="$arg"
		capture_resume=0
		continue
	fi
	if [[ "$capture_next" == 1 ]]; then
		last_message_file="$arg"
		capture_next=0
		continue
	fi
	if [[ "$arg" == "--output-last-message" ]]; then
		capture_next=1
	elif [[ "$arg" == "resume" ]]; then
		capture_resume=1
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
	if [[ "$(value REVIEW_STATE_CHANGED)" == 1 ]]; then
		printf '%s\n' "$prompt" | grep -q 'perform a fresh review; do not dismiss the event as a duplicate'
		[[ -z "$resume_thread_id" ]]
	fi
elif printf '%s' "$prompt" | grep -q 'The root hit a convergence guard'; then
	kind="replan"
	key="replan-$(value TASK_ROOT)"
elif printf '%s' "$prompt" | grep -q 'The previous root task is resolved'; then
	kind="plan"
	key="plan"
elif printf '%s' "$prompt" | grep -q 'The task is already claimed by this launcher'; then
	kind="worker"
	key="worker-$(value TASK_ID)"
elif printf '%s' "$prompt" | grep -q 'You are the final Oracle auditor'; then
	kind="oracle"
	key="oracle-$(value AUDIT_ID)"
fi
counter="$HARNESS_ROOT/mock-counts/$key"
count=0
[[ ! -f "$counter" ]] || count="$(cat "$counter")"
count=$((count + 1))
printf '%s\n' "$count" > "$counter"

# Exercise automatic transient-provider retry once in all three invocation paths:
# manager bootstrap, worker task 001, and manager review task 001.
if [[ "$count" == 1 && ( "$key" == bootstrap || "$key" == worker-001 || "$key" == review-001 ) ]]; then
	printf '{"type":"error","code":"model_capacity","message":"Selected model is at capacity. Please try a different model."}\n'
	printf '{"type":"turn.failed","error":{"code":"model_capacity","message":"Selected model is at capacity. Please try a different model."}}\n'
	exit 1
fi

# Exercise account usage-window recovery in both a planning turn and worker.
if [[ "$count" == 1 && ( "$key" == plan || "$key" == worker-002 ) ]]; then
	printf '{"type":"turn.failed","error":{"code":"usage_limit_reached","message":"Usage limit reached; resets later."}}\n'
	exit 1
fi

# Exercise Oracle recovery from the exact model-service moderation wording that
# previously left a completed project indefinitely pending. The first failure
# must narrow the prompt; the second must switch to the configured fallback.
if [[ "$key" == oracle-1 && "$count" -le 2 ]]; then
	if [[ "$count" == 2 ]]; then
		printf '%s\n' "$prompt" | grep -q '^Retry scope: this is authorized, benign software-quality verification'
	fi
	printf '%s\n' '{"type":"turn.failed","error":{"message":"This content was flagged for possible cybersecurity risk. To get authorized for security work, join the Trusted Access for Cyber program."}}'
	exit 1
fi

started_thread_id="${resume_thread_id:-mock-thread-001}"
if [[ "$kind" == review && "$(value REVIEW_STATE_CHANGED)" == 1 ]]; then
	started_thread_id="mock-thread-rotated"
fi
printf '{"type":"thread.started","thread_id":"%s"}\n' "$started_thread_id"
printf '{"type":"turn.started"}\n'
HARNESS_BIN="$(value HARNESS_BIN)"
final_message="done"
if [[ "$kind" == bootstrap ]]; then
	plan="$(mktemp)"
	printf 'phase-1\tMock first phase\nphase-2\tMock second phase\n' > "$plan"
	"$HARNESS_BIN/manager-init-project-plan" "$ENV_FILE" "$plan" >/dev/null
	tmp="$(mktemp)"
	printf '# Task\n\nTask-ID: 001\nRoot-Criterion: mock.001\n\nMock first task.\n' > "$tmp"
	"$HARNESS_BIN/manager-publish-task" "$ENV_FILE" 001 "$tmp" phase-1 >/dev/null
	rm -f "$tmp" "$plan"
elif [[ "$kind" == plan ]]; then
	tmp="$(mktemp)"
	printf '# Task\n\nTask-ID: 002\nRoot-Criterion: mock.002\n\nMock second task.\n' > "$tmp"
	"$HARNESS_BIN/manager-publish-task" "$ENV_FILE" 002 "$tmp" phase-2 >/dev/null
	rm -f "$tmp"
elif [[ "$kind" == replan ]]; then
	printf '%s\n' "$prompt" | grep -Fq 'one aggregate transcript budget'
	printf '%s\n' "$prompt" | grep -Fq 'a custom literal cap greater than either configured maximum is forbidden'
	TASK_ROOT="$(value TASK_ROOT)"
	TASK_ID="$(value EXPECTED_TASK_ID)"
	RECOVERY_MODE="$(value RECOVERY_MODE)"
	TASK_OUTPUT="$(value TASK_OUTPUT)"
	CRITERIA_OUTPUT="$(value CRITERIA_OUTPUT)"
	CRITERIA_DEFINITION_FILE="$(value CRITERIA_DEFINITION_FILE)"
	CRITERION_LEDGER_FILE="$(value CRITERION_LEDGER_FILE)"
	TRIGGER_TASK="$(value TRIGGER_TASK)"
	criteria_arg=()
	if [[ ! -f "$CRITERIA_DEFINITION_FILE" ]]; then
		printf 'criterion_id\ttitle\tacceptance_evidence\nlegacy.first\tFirst bounded legacy milestone\tfocused first evidence\nlegacy.final\tFinal bounded legacy milestone\tfocused final evidence\n' > "$CRITERIA_OUTPUT"
		criteria_source="$CRITERIA_OUTPUT"
		criteria_arg=("$CRITERIA_OUTPUT")
	else
		criteria_source="$CRITERIA_DEFINITION_FILE"
	fi
	target="$(awk -F '\t' -v ledger="$CRITERION_LEDGER_FILE" '
		BEGIN {
			while ((getline line < ledger) > 0) {
				split(line, fields, "\t")
				if (fields[2] == "PASSED") passed[fields[1]] = 1
			}
		}
		NR > 1 && !passed[$1] {print $1; exit}
	' "$criteria_source")"
	publish_flag="--auto-replan"
	strategy_change="ISOLATE_CRITERION"
	strategy_id="mock.strategy.$count"
	remediation_metadata=""
	if [[ "$RECOVERY_MODE" == MANAGER_REMEDIATION ]]; then
		printf '%s\n' "$prompt" | grep -Fq 'If an equivalent target already exists, correct the focused validation command'
		publish_flag="--manager-remediation"
		strategy_change="REPAIR_PREREQUISITE"
		strategy_id="mock.manager-remediation.$count"
		remediation_metadata=$'Manager-Remediation: 1\nBlocker-Class: LOCAL_CODE_PREREQUISITE\nRemediation-Scope: src/mock-blocking-prerequisite.c'
	fi
	cat > "$TASK_OUTPUT" <<TASK
# Task Assignment

Task-ID: $TASK_ID
Task-Root: $TASK_ROOT
Target-Criterion: $target
Worker-Context: FRESH
Replan-Strategy-ID: $strategy_id
Strategy-Change: $strategy_change
Supersedes-Task: $TRIGGER_TASK
$remediation_metadata

## Objective

Isolate only $target with a new focused evidence boundary.

## Acceptance criteria

- The focused criterion passes independently.

## Validation commands

mock-focused-$count
TASK
	"$HARNESS_BIN/manager-publish-task" "$ENV_FILE" "$TASK_ID" "$TASK_OUTPUT" \
		"$publish_flag" "${criteria_arg[@]}" >/dev/null
elif [[ "$kind" == review ]]; then
	TASK_ID="$(value TASK_ID)"
	if [[ "$TASK_ID" == 002 && "$count" == 1 ]]; then
		final_message="review-left-pending"
	elif [[ "$TASK_ID" == 002 && "$count" == 2 ]]; then
		# Change durable review state during the manager invocation but leave
		# the result pending. The supervisor must schedule one fresh review
		# instead of suppressing the post-change fingerprint.
		plan_state="$HARNESS_ROOT/projects/$PROJECT/control/project-plan-state.tsv"
		awk -F '\t' 'BEGIN {OFS=FS} $1 == "phase-2" {$4="2026-08-12T20:01:00Z"} {print}' \
			"$plan_state" > "$plan_state.tmp"
		mv "$plan_state.tmp" "$plan_state"
		final_message="review-revised-state-left-pending"
	elif [[ "$TASK_ID" == 002 && "$count" == 3 ]]; then
		note="$(mktemp)"
		cat > "$note" <<NOTE
# Manager Review Record

Task-ID: $TASK_ID
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: mock.$TASK_ID

## Specification comparison
Mock specification comparison.

## Acceptance-criteria verification
- [PASS] mock criterion — mocked review evidence

## Feature verification
- [PASS] mock feature — mocked focused test evidence

## Validation executed
- [PASS] mock-test — exit status 0

## Scope and regression review
Mock scope review.

## Conclusion
All required behavior was independently verified. Accept.
NOTE
		"$HARNESS_BIN/manager-accept-task" "$ENV_FILE" "$TASK_ID" "$note" --complete-project >/dev/null
		rm -f "$note"
	else
	note="$(mktemp)"
	cat > "$note" <<NOTE
# Manager Review Record

Task-ID: $TASK_ID
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: mock.$TASK_ID

## Specification comparison
Mock specification comparison.

## Acceptance-criteria verification
- [PASS] mock criterion — mocked review evidence

## Feature verification
- [PASS] mock feature — mocked focused test evidence

## Validation executed
- [PASS] mock-test — exit status 0

## Scope and regression review
Mock scope review.

## Conclusion
All required behavior was independently verified. Accept.
NOTE
	if [[ "$TASK_ID" == 001 ]]; then
		if "$HARNESS_BIN/manager-accept-task" "$ENV_FILE" "$TASK_ID" "$note" --complete-project >/dev/null 2>&1; then
			printf 'premature project completion was incorrectly accepted\n' >&2
			exit 90
		fi
	fi
	"$HARNESS_BIN/manager-accept-task" "$ENV_FILE" "$TASK_ID" "$note" >/dev/null
	rm -f "$note"
	fi
elif [[ "$kind" == worker ]]; then
	TASK_ID="$(value TASK_ID)"
	SESSION="$(value SESSION)"
	if [[ "$TASK_ID" == 002 ]]; then
		# A useful worker report with noncanonical metadata/headings must be
		# normalized at completion rather than rejected later as zero gain.
		final_message=$'# Worker Result\n\nStatus: BLOCKED\n\nImplemented and validated the bounded task.\n'
	else
		final_message="$(printf '# Task Result\n\nTask-ID: %s\nStatus: COMPLETED\n\n## Summary\n\nMock implementation.\n\n## Modified files\n\n- mock-file\n\n## Implemented behavior\n\n- Mock behavior.\n\n## Validation performed\n\nMock test passed.\n\n## Deviations from assignment\n\nNone.\n\n## Remaining concerns\n\nNone.\n\n## Worker assessment\n\nReady for manager review.\n' "$TASK_ID")"
	fi
	if [[ "$TASK_ID" == 001 ]]; then
		# Deliberately expose a result directly. worker-invoke-task must normalize
		# it through worker-complete-task before manager review can begin.
		result="$HARNESS_ROOT/projects/$PROJECT/results/$PROJECT-task-$TASK_ID.result.md"
		printf '%s\n' "$final_message" > "$result"
	fi
	sleep 0.5
elif [[ "$kind" == oracle ]]; then
	verdict="$(mktemp)"
	cat > "$verdict" <<'VERDICT'
# Oracle Audit Verdict

Decision: PASS

## Traceability verification

All original requirements are accounted for.

## Acceptance verification

All acceptance checks passed.

## Findings

None.

## Conclusion

The implementation is compliant.
VERDICT
	"$HARNESS_BIN/oracle-complete-audit" "$ENV_FILE" "$verdict" >/dev/null
	rm -f "$verdict"
	final_message="Oracle audit passed."
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
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$TEST_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
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
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
ENV
chmod 600 "$TEST_ROOT/harness.env"

"$HARNESS_BIN/harness-check-env" "$TEST_ROOT/harness.env" > "$TEST_ROOT/check-env.out"
grep -q 'Codex wall timeout seconds: 1800 (0 means unlimited)' "$TEST_ROOT/check-env.out"
grep -q 'Codex idle timeout seconds: 0 (0 means unlimited)' "$TEST_ROOT/check-env.out"
grep -q 'Deterministic blocker circuit breaker: disabled' "$TEST_ROOT/check-env.out"
grep -q 'Root-attempt replanning guard: 12 reviewed attempts' "$TEST_ROOT/check-env.out"
grep -q 'Zero-gain replanning guard: 3 consecutive reviews' "$TEST_ROOT/check-env.out"
grep -q 'Checkpoint convergence guard: 4 verified increments without a completed criterion' "$TEST_ROOT/check-env.out"
grep -q 'Automatic persistent-manager replanning: enabled (1 strategy change(s) without durable verified gain)' "$TEST_ROOT/check-env.out"
grep -q 'Rejected-root worker thread reuse: enabled' "$TEST_ROOT/check-env.out"
grep -q 'Worker thread rejection rotation: 8 retained rejections' "$TEST_ROOT/check-env.out"
grep -q 'Bounded closure mode: enabled at 95% (2 fixes, 3 focused-smoke runs)' "$TEST_ROOT/check-env.out"
grep -q 'broad criteria may gain append-only children; roots resume by first-unmet leaf; leaf-goal CONTINUE receipts remain worker-internal; verified gain resets bounded automatic-replan escalation' "$TEST_ROOT/check-env.out"
grep -q 'Transient provider retry seconds: 1 (retries unlimited)' "$TEST_ROOT/check-env.out"
grep -q 'Quota retry seconds: 1 (retries unlimited)' "$TEST_ROOT/check-env.out"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
[[ -d "/tmp/testproj" ]]
printf 'must block startup\n' > "$TEST_ROOT/repo/untracked-before-start.txt"
if "$HARNESS_BIN/harness-start" "$TEST_ROOT/harness.env" \
	>"$TEST_ROOT/dirty-start.out" 2>"$TEST_ROOT/dirty-start.err"; then
	printf 'harness-start accepted a non-ignored untracked file\n' >&2
	exit 1
fi
grep -Fq '?? untracked-before-start.txt' "$TEST_ROOT/dirty-start.err"
grep -Fq 'repository has staged, unstaged, or non-ignored untracked files' \
	"$TEST_ROOT/dirty-start.err"
test ! -e "$TEST_ROOT/state/mock-counts/bootstrap"
rm -f "$TEST_ROOT/repo/untracked-before-start.txt"

# A parent orchestration shell may mention several harness commands and
# environment paths in one command string. Those strings are not active
# environment-bound harness argv entries and must not block detached starts.
bash -lc "sleep 30 # $HARNESS_BIN/harness-start --background $TEST_ROOT/harness.env" &
orchestrator_pid=$!
sleep 0.2
if bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	env_has_running_processes
' bash "$HARNESS_HOME" "$TEST_ROOT/harness.env"; then
	printf 'orchestration command text was mistaken for a live harness process\n' >&2
	kill "$orchestrator_pid" 2>/dev/null || true
	exit 1
fi
kill "$orchestrator_pid" 2>/dev/null || true
wait "$orchestrator_pid" 2>/dev/null || true

bash -c 'while true; do sleep 1; done' \
	"$HARNESS_BIN/manager-review-specification" "$TEST_ROOT/harness.env" &
overlap_pid=$!
sleep 0.2
if "$HARNESS_BIN/harness-start" "$TEST_ROOT/harness.env" \
	>"$TEST_ROOT/overlap-start.out" 2>"$TEST_ROOT/overlap-start.err"; then
	printf 'harness-start accepted an agent process without a live supervisor\n' >&2
	kill "$overlap_pid" 2>/dev/null || true
	exit 1
fi
kill "$overlap_pid" 2>/dev/null || true
wait "$overlap_pid" 2>/dev/null || true
grep -Fq 'refusing duplicate harness-start while no project supervisor owns these processes' \
	"$TEST_ROOT/overlap-start.err"
test ! -e "$TEST_ROOT/state/mock-counts/bootstrap"

"$HARNESS_BIN/harness-start" "$TEST_ROOT/harness.env" >/dev/null

# A manager review that returns without a durable action must be invoked once
# for an unchanged result and stable control state. A later control-state
# change wakes exactly one new review, which then completes the task.
pending_review_marker="$TEST_ROOT/state/projects/testproj/control/testproj-task-002.reviewed-event"
for _ in $(seq 1 300); do
	if [[ -f "$pending_review_marker" ]] &&
		[[ "$(awk -F= '$1=="manager_exit_status" {print $2}' "$pending_review_marker")" == 3 ]]; then
		break
	fi
	sleep 0.1
done
[[ -f "$pending_review_marker" ]]
[[ "$(cat "$TEST_ROOT/state/mock-counts/review-002")" == 1 ]]
sleep 0.8
[[ "$(cat "$TEST_ROOT/state/mock-counts/review-002")" == 1 ]]
plan_state="$TEST_ROOT/state/projects/testproj/control/project-plan-state.tsv"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "phase-2" {$4="2026-08-12T20:00:00Z"} {print}' \
	"$plan_state" > "$plan_state.tmp"
mv "$plan_state.tmp" "$plan_state"

for _ in $(seq 1 300); do
	if [[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.accepted.md" &&
		-f "$TEST_ROOT/state/projects/testproj/control/project.complete" ]] &&
		grep -Fqx 'thread_id=mock-thread-rotated' \
			"$TEST_ROOT/state/projects/testproj/control/manager.thread"; then
		break
	fi
	sleep 0.1
done

EVENTS="$TEST_ROOT/state/projects/testproj/logs/events.log"
TRACE="$TEST_ROOT/state/projects/testproj/logs/trace.log"
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-001.accepted.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.accepted.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/control/project.complete" ]]
grep -Fqx 'thread_id=mock-thread-rotated' \
	"$TEST_ROOT/state/projects/testproj/control/manager.thread"
[[ ! -e "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-002.ready.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/running/testproj-task-002.running.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/results/testproj-task-002.result.md" ]]
grep -q 'MANAGER_BOOTSTRAP_PROVIDER_WAIT kind=transient' "$EVENTS"
grep -q 'MANAGER_BOOTSTRAP_PROVIDER_RETRY_STARTED kind=transient' "$EVENTS"
grep -q 'WORKER_PROVIDER_WAIT task=001.*kind=transient' "$EVENTS"
grep -q 'WORKER_PROVIDER_RETRY_STARTED task=001.*kind=transient' "$EVENTS"
grep -q 'MANAGER_PROVIDER_WAIT task=001.*kind=transient' "$EVENTS"
grep -q 'MANAGER_PROVIDER_RETRY_STARTED task=001.*kind=transient' "$EVENTS"
grep -q 'MANAGER_PLAN_PROVIDER_WAIT kind=quota' "$EVENTS"
grep -q 'MANAGER_PLAN_PROVIDER_RETRY_STARTED kind=quota' "$EVENTS"
grep -q 'WORKER_PROVIDER_WAIT task=002.*kind=quota' "$EVENTS"
grep -q 'WORKER_PROVIDER_RETRY_STARTED task=002.*kind=quota' "$EVENTS"
grep -q 'MANAGER_REVIEW_LEFT_PENDING task=002' "$EVENTS"
grep -q 'SUPERVISOR_REVIEW_LEFT_UNCOMMITTED task=002.*retry=suppressed_until_state_change' "$EVENTS"
grep -q 'SUPERVISOR_REVIEW_STATE_CHANGED task=002.*retry=fresh_review' "$EVENTS"
grep -q 'MANAGER_CONTEXT_ROTATED previous=mock-thread-001 current=mock-thread-rotated reason=review_state_changed' "$EVENTS"
grep -q 'WORKER_SUPERVISOR_TRIGGER task=001' "$EVENTS"
grep -q 'WORKER_DIRECT_RESULT_NORMALIZED task=001' "$EVENTS"
grep -q 'WORKER_LAST_MESSAGE_RESULT_NORMALIZED task=002' "$EVENTS"
grep -q 'WORKER_RESULT_NORMALIZED task=002' "$EVENTS"
grep -q 'TASK_PUBLISHED task=002' "$EVENTS"
grep -q 'SUPERVISOR_PLANNING_GAP progress=50 pending=1' "$EVENTS"
grep -q 'MANAGER_PLAN_COMMITTED' "$EVENTS"
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
review_prompt="$TEST_ROOT/state/projects/testproj/control/testproj-task-001.manager-review.prompt.md"
review_digest="$TEST_ROOT/state/projects/testproj/control/testproj-task-001.worker-evidence-digest.md"
review_context="$TEST_ROOT/state/projects/testproj/control/testproj-task-001.manager-review-context.md"
accept_template="$TEST_ROOT/state/projects/testproj/control/testproj-task-001.accept-review-template.md"
checkpoint_template="$TEST_ROOT/state/projects/testproj/control/testproj-task-001.checkpoint-review-template.md"
checkpoint_criterion_template="$TEST_ROOT/state/projects/testproj/control/testproj-task-001.checkpoint-criterion-review-template.md"
[[ -f "$review_prompt" && -f "$review_digest" && -f "$review_context" ]]
[[ -f "$accept_template" && -f "$checkpoint_template" && -f "$checkpoint_criterion_template" ]]
grep -Fq "WORKER_EVIDENCE_DIGEST_FILE=$review_digest" "$review_prompt"
grep -Fq "REVIEW_CONTEXT_CAPSULE_FILE=$review_context" "$review_prompt"
grep -Fq 'The capsule is authoritative and complete for plan, DAG, IR, and architecture context' "$review_prompt"
grep -Fq 'never omit a CMake --target, replace it with an all-target build' "$review_prompt"
grep -Fq 'REMAINING_LEAF_CRITERIA=1' "$review_prompt"
grep -Fq "RECOMMENDED_PASS_REVIEW_TEMPLATE_FILE=$accept_template" "$review_prompt"
grep -Fq 'never submit, edit, or convert a checkpoint template in that case' "$review_prompt"
grep -Fq 'Do not open the global files from which it was derived.' "$review_context"
grep -Fq 'Reviewers must not open the raw worker JSONL' "$review_digest"
grep -Fq "ACCEPT_REVIEW_TEMPLATE_FILE=$accept_template" "$review_prompt"
grep -Fq "CHECKPOINT_REVIEW_TEMPLATE_FILE=$checkpoint_template" "$review_prompt"
grep -Fq "CHECKPOINT_INCREMENT_REVIEW_TEMPLATE_FILE=$checkpoint_template" "$review_prompt"
grep -Fq "CHECKPOINT_CRITERION_REVIEW_TEMPLATE_FILE=$checkpoint_criterion_template" "$review_prompt"
grep -Fqx '## Acceptance-criteria verification' "$accept_template"
grep -Fqx '## Increment verification' "$checkpoint_template"
grep -Fq 'Verified-Criterion:' "$checkpoint_criterion_template"
(( $(stat -c %s "$review_digest") <= 32768 ))
(( $(stat -c %s "$review_context") <= 65536 ))
plan_prompt="$TEST_ROOT/state/projects/testproj/control/manager-plan-next-task.prompt.md"
plan_context="$TEST_ROOT/state/projects/testproj/control/manager-plan-next-task.context.md"
[[ -f "$plan_prompt" && -f "$plan_context" ]]
grep -Fq 'Complete it in at most eight shell/tool actions' "$plan_prompt"
grep -Fq 'at most three publication calls with no more than two direct corrections' "$plan_prompt"
grep -Fq 'This planning role must not inspect repository source code' "$plan_prompt"
grep -Fq 'Never invoke a harness command with --help.' "$plan_prompt"
grep -Fq "PLAN_NODE_CONTEXT_FILE=$plan_context" "$plan_prompt"
grep -Fq 'PUBLISH_TASK_ID=' "$plan_prompt"
grep -Fq 'PUBLISH_PLAN_ITEM_ID=' "$plan_prompt"
grep -Fq 'manager-publish-planned-task' "$plan_prompt"
grep -Fq 'Do not open the global files from which it was derived.' "$plan_context"
grep -Fq 'The section named "Mandatory cross-harness Git refs"' "$plan_prompt"
grep -Fq 'Never infer a Git ref from Depends-On values' "$plan_prompt"
grep -Fqx '## Mandatory cross-harness Git refs' "$plan_context"
grep -A3 -F '## Mandatory cross-harness Git refs' "$plan_context" | grep -Fqx 'NONE'
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-001.assignment.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.assignment.md" ]]
normalized_result="$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.result.md"
grep -Fqx 'Task-ID: 002' "$normalized_result"
grep -Fqx 'Status: COMPLETED' "$normalized_result"
grep -Fqx 'Worker-Reported-Status: BLOCKED' "$normalized_result"
for heading in '## Summary' '## Modified files' '## Implemented behavior' \
	'## Validation performed' '## Deviations from assignment' \
	'## Remaining concerns' '## Worker assessment'; do
	grep -Fqx -- "$heading" "$normalized_result"
done
grep -Fq 'Implemented and validated the bounded task.' "$normalized_result"
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-001.lease" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-002.lease" ]]
first_complete_line="$(grep -n 'TASK_COMPLETED task=001' "$EVENTS" | head -n 1 | cut -d: -f1)"
first_review_line="$(grep -n 'MANAGER_REVIEW_STARTED task=001' "$EVENTS" | head -n 1 | cut -d: -f1)"
[[ -n "$first_complete_line" && -n "$first_review_line" ]]
(( first_complete_line < first_review_line ))
review_002_count="$(grep -c 'MANAGER_REVIEW_STARTED task=002' "$EVENTS")"
[[ "$review_002_count" == 3 ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/testproj-task-002.manager-failed.md" ]]

for _ in $(seq 1 100); do
	[[ ! -f "$TEST_ROOT/state/projects/testproj/control/supervisor.pid" && ! -f "$TEST_ROOT/state/projects/testproj/control/worker-supervisor.pid" ]] && break
	sleep 0.1
done
[[ ! -f "$TEST_ROOT/state/projects/testproj/control/supervisor.pid" ]]
[[ ! -f "$TEST_ROOT/state/projects/testproj/control/worker-supervisor.pid" ]]
grep -q 'SUPERVISOR_PROJECT_COMPLETED task=002' "$EVENTS"
grep -q 'WORKER_SUPERVISOR_PROJECT_COMPLETED task=002' "$EVENTS"

# The natural-language watcher stops on durable project completion instead of
# remaining as a tail-like process after both supervisors have exited.
completed_watch_output="$TEST_ROOT/watch-agents-completed.out"
HARNESS_WATCH_POLL_SECONDS=0.05 timeout 2 \
	"$HARNESS_BIN/harness-watch-agents" "$TEST_ROOT/harness.env" \
	> "$completed_watch_output" 2>&1
grep -q 'Watcher exiting: project completed.' "$completed_watch_output"

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

# A late sibling result for a root already accepted by another revision is not
# a new review decision. It is archived as SUPERSEDED without invoking the
# manager model, and a legacy stalled marker cannot pause the project.
late_task=002-revision-07
late_base="testproj-task-$late_task"
cp "$TEST_ROOT/state/projects/testproj/archive/testproj-task-002.assignment.md" \
	"$TEST_ROOT/state/projects/testproj/archive/$late_base.assignment.md"
printf '# Late duplicate result\n' > \
	"$TEST_ROOT/state/projects/testproj/results/$late_base.result.md"
printf '# Manager Review Stalled\n' > \
	"$TEST_ROOT/state/projects/testproj/control/$late_base.manager-review-stalled.md"
rm -f "$TEST_ROOT/state/projects/testproj/control/project.complete"
"$HARNESS_BIN/harness-status" --full "$TEST_ROOT/harness.env" > \
	"$TEST_ROOT/superseded-before-status.out"
! grep -q '^Project status: REVIEW_STALLED\.' \
	"$TEST_ROOT/superseded-before-status.out"
manager_calls_before="$(wc -l < "$ARGS_LOG")"
"$HARNESS_BIN/manager-invoke-result" "$TEST_ROOT/harness.env" "$late_task" >/dev/null
manager_calls_after="$(wc -l < "$ARGS_LOG")"
[[ "$manager_calls_after" == "$manager_calls_before" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/results/$late_base.result.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/$late_base.superseded-result.md" ]]
[[ -f "$TEST_ROOT/state/projects/testproj/archive/$late_base.superseded.md" ]]
[[ ! -e "$TEST_ROOT/state/projects/testproj/control/$late_base.manager-review-stalled.md" ]]
grep -q '^Superseded-By: 002$' \
	"$TEST_ROOT/state/projects/testproj/archive/$late_base.superseded.md"
grep -q 'MANAGER_REVIEW_SUPERSEDED_WITHOUT_AGENT task=002-revision-07' "$EVENTS"

# Continue with isolated low-level command tests after the completed end-to-end
# plan by extending this disposable fixture with three pending items.
rm -f "$TEST_ROOT/state/projects/testproj/control/project.complete"
printf 'fixture-003\tMalformed acceptance fixture\nfixture-004\tUnlimited revision fixture\nfixture-005\tCumulative progress fixture\n' \
	>> "$TEST_ROOT/state/projects/testproj/control/project-plan.tsv"
printf 'fixture-003\tPENDING\t-\t1970-01-01T00:00:00Z\nfixture-004\tPENDING\t-\t1970-01-01T00:00:00Z\nfixture-005\tPENDING\t-\t1970-01-01T00:00:00Z\n' \
	>> "$TEST_ROOT/state/projects/testproj/control/project-plan-state.tsv"

# A manager cannot accept a malformed worker report or an unstructured review
# note, even when the result completion transaction itself is valid.
task_id=003
base="testproj-task-$task_id"
result="$TEST_ROOT/state/projects/testproj/results/$base.result.md"
assignment="$TEST_ROOT/state/projects/testproj/archive/$base.assignment.md"
fixture_task="$TEST_ROOT/fixture-003.md"
printf '# Task\n\nTask-ID: %s\nRoot-Criterion: fixture.remaining\n' "$task_id" > "$fixture_task"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" "$task_id" "$fixture_task" fixture-003 >/dev/null
mv "$TEST_ROOT/state/projects/testproj/tasks/$base.ready.md" "$assignment"
printf 'Task-ID: %s\nStatus: COMPLETED\n' "$task_id" > "$result"
note="$TEST_ROOT/bad-review.md"
printf 'Task-ID: %s\nDecision: ACCEPT\n' "$task_id" > "$note"
if "$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" "$task_id" "$note" >/dev/null 2>&1; then
	printf 'Expected malformed worker report to be rejected.\n' >&2
	exit 1
fi
cat > "$result" <<RESULT
Task-ID: $task_id
Status: COMPLETED

## Summary

Mock implementation.

## Modified files

- mock-file

## Implemented behavior

- Mock behavior.

## Validation performed

Mock test passed.

## Deviations from assignment

None.

## Remaining concerns

None.

## Worker assessment

Ready for manager review.
RESULT
if "$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" "$task_id" "$note" >/dev/null 2>&1; then
	printf 'Expected unstructured manager review record to be rejected.\n' >&2
	exit 1
fi
cat > "$note" <<NOTE
# Manager Review Record

Task-ID: $task_id
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: fixture.remaining

## Specification comparison
Mock specification comparison.

## Acceptance-criteria verification
- [PASS] mock criterion — mocked review evidence

## Feature verification
- [PASS] mock feature — mocked focused test evidence

## Validation executed
- [PASS] mock-test — exit status 0

## Scope and regression review
Mock scope review.

## Conclusion
All required behavior was independently verified. Accept.
NOTE
"$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" "$task_id" "$note" >/dev/null

# Revisions without a deterministic blocker fingerprint remain available; the
# circuit breaker applies only to repeated identical zero-gain gate evidence.
fixture_task="$TEST_ROOT/fixture-004.md"
printf '# Task\n\nTask-ID: 004\nRoot-Criterion: fixture.remaining\n' > "$fixture_task"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 004 "$fixture_task" fixture-004 >/dev/null
rm -f "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-004.ready.md"
for revision in 01 02 03 04 05 06 07 08 09 10; do
	printf 'Improvement-Percent: 0%%\n' > "$TEST_ROOT/state/projects/testproj/archive/testproj-task-004-revision-$revision.rejected.md"
done
revision_task="$TEST_ROOT/revision-task.md"
printf '# Task\n\nTarget-Criterion: fixture.remaining\n' > "$revision_task"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 004-revision-11 "$revision_task" >/dev/null
grep -q '^Starting-Progress: 0%$' "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-004-revision-11.ready.md"
watch_output="$TEST_ROOT/watch-agents.out"
progress_dir="$TEST_ROOT/state/projects/testproj/control/progress"
cat > "$progress_dir/testproj-task-004.criterion-decomposition.tsv" <<'TSV'
parent_criterion	child_criterion	title	acceptance_evidence
fixture.remaining	fixture.first	First bounded fixture	first fixture evidence passes
fixture.remaining	fixture.second	Second bounded fixture	second fixture evidence passes
TSV
cat > "$progress_dir/testproj-task-004.criteria.tsv" <<'TSV'
item_id	state	verified_by	evidence_sha256	updated_at
fixture.first	PASSED	004-revision-13	sha256:test	1970-01-01T00:00:00Z
TSV
timeout 2 "$HARNESS_BIN/harness-watch-agents" "$TEST_ROOT/harness.env" > "$watch_output" 2>&1 &
watch_pid=$!
sleep 0.3
printf 'Progress-Percent: 0%%\nImprovement-Percent: 0%%\n' > "$TEST_ROOT/state/projects/testproj/archive/testproj-task-004-revision-12.rejected.md"
cat > "$TEST_ROOT/state/projects/testproj/archive/testproj-task-004-revision-13.checkpointed.md" <<'NOTE'
Progress-Percent: 0%
Improvement-Percent: 0%
Verified-Criterion: fixture.first
NOTE
wait "$watch_pid" || true
grep -q 'MANAGER REJECTED task=004-revision-12' "$watch_output"
! grep -q 'MANAGER REJECTED task=004-revision-10' "$watch_output"
grep -q 'Improvement: 0%' "$watch_output"
grep -q 'MANAGER CHECKPOINTED task=004-revision-13' "$watch_output"
grep -q 'Root leaf progress: 1/2 (50% snapshot)' "$watch_output"
grep -Eq 'Project plan progress: [0-9]+/[0-9]+ \([0-9]+%\)' "$watch_output"
grep -q 'Legacy root progress: 0%' "$watch_output"
grep -q 'Durable checkpoint gain: 1 criterion(s), 0 increment(s)' "$watch_output"
grep -q 'Legacy improvement: 0%' "$watch_output"
! grep -q 'Cumulative progress:' "$watch_output"
rm -f "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-004-revision-11.ready.md"
sed -i 's/^fixture-004\tACTIVE\t004\t/fixture-004\tCOMPLETE\t004\t/' \
	"$TEST_ROOT/state/projects/testproj/control/project-plan-state.tsv"

# Cumulative progress is durable and is injected into each continuation.
progress_task="$TEST_ROOT/progress-task.md"
printf '# Task\n\nTask-ID: 005\nRoot-Criterion: fixture.remaining\n\nImplement one prototype feature.\n' > "$progress_task"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 005 "$progress_task" fixture-005 >/dev/null
progress_dir="$TEST_ROOT/state/projects/testproj/control/progress"
progress_file="$progress_dir/testproj-task-005.progress.md"
root_assignment="$progress_dir/testproj-task-005.root-assignment.md"
grep -q '^Progress-Percent: 0%$' "$progress_file"
cmp -s "$progress_task" "$root_assignment"
mv "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-005.ready.md" \
	"$TEST_ROOT/state/projects/testproj/archive/testproj-task-005.assignment.md"
printf 'worker result\n' > "$TEST_ROOT/state/projects/testproj/results/testproj-task-005.result.md"
progress_note="$TEST_ROOT/progress-review.md"
cat > "$progress_note" <<'NOTE'
# Manager Review Record

Task-ID: 005
Decision: REJECT
Progress-Percent: 50%
Improvement-Percent: 50%

## Completed and verified root criteria

- Registry storage works — focused smoke passed.

## Remaining root criteria

- Add projection.
NOTE
"$HARNESS_BIN/manager-reject-task" "$TEST_ROOT/harness.env" 005 "$progress_note" >/dev/null
grep -q '^Progress-Percent: 50%$' "$progress_file"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 005-revision-01 "$revision_task" >/dev/null
continuation="$TEST_ROOT/state/projects/testproj/tasks/testproj-task-005-revision-01.ready.md"
grep -q '^Task-Root: 005$' "$continuation"
grep -q '^Starting-Progress: 50%$' "$continuation"
grep -q 'Preserve all previously verified work' "$continuation"
"$HARNESS_BIN/harness-status" --full "$TEST_ROOT/harness.env" > "$TEST_ROOT/progress-status.out"
grep -Eq '005-revision-01 +READY +WORKER +50%' "$TEST_ROOT/progress-status.out"
expected_task_order=$'003\n002\n001\n005-revision-01'
actual_task_order="$(awk '$1 ~ /^(001|002|003|005-revision-01)$/ {print $1}' \
	"$TEST_ROOT/progress-status.out")"
[[ "$actual_task_order" == "$expected_task_order" ]]
tail -n 2 "$TEST_ROOT/progress-status.out" | sed -n '1p' |
	grep -Eq '^Project progress: [0-9]+% \([0-9]+/[0-9]+ plan items complete\)$'
tail -n 1 "$TEST_ROOT/progress-status.out" |
	grep -q '^Project status: ACTIVE\.'

# With the default disabled circuit breaker, even an explicit low-level block
# request is refused and the normal rejection/continuation path remains open.
mv "$continuation" \
	"$TEST_ROOT/state/projects/testproj/archive/testproj-task-005-revision-01.assignment.md"
printf 'worker result\n' > \
	"$TEST_ROOT/state/projects/testproj/results/testproj-task-005-revision-01.result.md"
disabled_block_note="$TEST_ROOT/disabled-block-review.md"
cat > "$disabled_block_note" <<'NOTE'
Progress-Percent: 50%
Improvement-Percent: 0%
Blocking-Fingerprint: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
NOTE
if "$HARNESS_BIN/manager-block-task" "$TEST_ROOT/harness.env" 005-revision-01 \
	"$disabled_block_note" >"$TEST_ROOT/disabled-block.out" 2>"$TEST_ROOT/disabled-block.err"; then
	printf 'Expected disabled deterministic blocker to refuse a direct block.\n' >&2
	exit 1
fi
grep -q 'deterministic task blocking is disabled' "$TEST_ROOT/disabled-block.err"
"$HARNESS_BIN/manager-reject-task" "$TEST_ROOT/harness.env" 005-revision-01 \
	"$disabled_block_note" >/dev/null
[[ ! -e "$progress_dir/testproj-task-005.blocked.md" ]]
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 005-revision-02 \
	"$revision_task" >/dev/null
[[ -f "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-005-revision-02.ready.md" ]]
rm -f "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-005-revision-02.ready.md"

# An opt-in deterministic threshold still refuses early intervention. Once
# reached, ordinary rejection is archived and manager remediation is requested
# instead of converting the local coding blocker into a human-only stop.
CIRCUIT_ROOT="$TEST_ROOT/circuit"
mkdir -p "$CIRCUIT_ROOT/repo" "$CIRCUIT_ROOT/manager-home" "$CIRCUIT_ROOT/worker-home"
printf 'test specification\n' > "$CIRCUIT_ROOT/repo/spec.md"
cat > "$CIRCUIT_ROOT/harness.env" <<ENV
export PROJECT="circuitproj"
export REPOSITORY="$CIRCUIT_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$CIRCUIT_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$CIRCUIT_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$CIRCUIT_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_MAX_IDENTICAL_BLOCKERS="2"
ENV
chmod 600 "$CIRCUIT_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$CIRCUIT_ROOT/harness.env" >/dev/null
printf 'P0\tCircuit breaker fixture\n' > "$CIRCUIT_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$CIRCUIT_ROOT/harness.env" \
	"$CIRCUIT_ROOT/plan.tsv" >/dev/null
printf '# Task\n\nTask-ID: 001\nRoot-Criterion: fixture.remaining\nTarget-Criterion: fixture.remaining\n' > "$CIRCUIT_ROOT/task.md"
"$HARNESS_BIN/manager-publish-task" "$CIRCUIT_ROOT/harness.env" 001 \
	"$CIRCUIT_ROOT/task.md" P0 >/dev/null
mv "$CIRCUIT_ROOT/state/projects/circuitproj/tasks/circuitproj-task-001.ready.md" \
	"$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001.assignment.md"
printf 'worker result\n' > \
	"$CIRCUIT_ROOT/state/projects/circuitproj/results/circuitproj-task-001.result.md"
cat > "$CIRCUIT_ROOT/review-001.md" <<'NOTE'
Progress-Percent: 0%
Improvement-Percent: 0%
Blocking-Fingerprint: sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
NOTE
if "$HARNESS_BIN/manager-block-task" "$CIRCUIT_ROOT/harness.env" 001 \
	"$CIRCUIT_ROOT/review-001.md" >"$CIRCUIT_ROOT/early-block.out" 2>"$CIRCUIT_ROOT/early-block.err"; then
	printf 'Expected an early opt-in block to be refused.\n' >&2
	exit 1
fi
grep -q 'configured threshold: 1/2' "$CIRCUIT_ROOT/early-block.err"
"$HARNESS_BIN/manager-reject-task" "$CIRCUIT_ROOT/harness.env" 001 \
	"$CIRCUIT_ROOT/review-001.md" >/dev/null
"$HARNESS_BIN/manager-publish-task" "$CIRCUIT_ROOT/harness.env" 001-revision-01 \
	"$CIRCUIT_ROOT/task.md" >/dev/null
mv "$CIRCUIT_ROOT/state/projects/circuitproj/tasks/circuitproj-task-001-revision-01.ready.md" \
	"$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-01.assignment.md"
printf 'worker result\n' > \
	"$CIRCUIT_ROOT/state/projects/circuitproj/results/circuitproj-task-001-revision-01.result.md"
circuit_output="$("$HARNESS_BIN/manager-reject-task" "$CIRCUIT_ROOT/harness.env" \
	001-revision-01 "$CIRCUIT_ROOT/review-001.md")"
[[ "$circuit_output" == *.needs-replan.md ]]
[[ -f "$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-01.rejected.md" ]]
[[ ! -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.blocked.md" ]]
grep -q '^Trigger-Outcome: DETERMINISTIC_BLOCKER$' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"
grep -q 'TASK_CIRCUIT_BREAKER_MANAGER_REMEDIATION task=001-revision-01' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/logs/events.log"

# Once escalation is already using manager remediation, the same blocker may
# not recursively generate unlimited Terra leaves. Three identical remediation
# rejections require architecture reassessment, and an explicit resolution
# starts a fresh blocker epoch.
rm -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"
for revision in 02 03 04; do
	assignment="$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-$revision.assignment.md"
	result="$CIRCUIT_ROOT/state/projects/circuitproj/results/circuitproj-task-001-revision-$revision.result.md"
	cat > "$assignment" <<MD
Task-ID: 001-revision-$revision
Task-Root: 001
Manager-Remediation: 1
MD
	printf 'worker result\n' > "$result"
	remediation_output="$("$HARNESS_BIN/manager-reject-task" "$CIRCUIT_ROOT/harness.env" \
		"001-revision-$revision" "$CIRCUIT_ROOT/review-001.md")"
	if [[ "$revision" != 04 ]]; then
		[[ "$remediation_output" != *.architecture-reassessment-required.md ]]
		rm -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"
	fi
done
remediation_reassessment="$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.architecture-reassessment-required.md"
[[ "$remediation_output" == "$remediation_reassessment" ]]
grep -Fqx 'Category: REPEATED_MANAGER_REMEDIATION_BLOCKER' "$remediation_reassessment"
grep -q 'TASK_CIRCUIT_BREAKER_ARCHITECTURE_REASSESSMENT task=001-revision-04' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/logs/events.log"
printf 'The repeated blocker was inspected and the next strategy must use the corrected focused boundary.\n' \
	> "$CIRCUIT_ROOT/remediation-resolution.md"
"$HARNESS_BIN/harness-resolve-architecture-reassessment" "$CIRCUIT_ROOT/harness.env" 001 \
	"$CIRCUIT_ROOT/remediation-resolution.md" >/dev/null
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-05.assignment.md" <<'MD'
Task-ID: 001-revision-05
Task-Root: 001
Manager-Remediation: 1
MD
printf 'worker result\n' > \
	"$CIRCUIT_ROOT/state/projects/circuitproj/results/circuitproj-task-001-revision-05.result.md"
post_resolution_output="$("$HARNESS_BIN/manager-reject-task" "$CIRCUIT_ROOT/harness.env" \
	001-revision-05 "$CIRCUIT_ROOT/review-001.md")"
[[ "$post_resolution_output" != *.architecture-reassessment-required.md ]]
[[ ! -f "$remediation_reassessment" ]]
rm -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"

# A machine resource fuse is a decomposition/context failure, not evidence of
# a repository-local prerequisite. Preserve that type in the durable marker so
# automatic recovery cannot silently promote it to manager remediation.
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-06.assignment.md" <<'MD'
Task-ID: 001-revision-06
Task-Root: 001
MD
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/results/circuitproj-task-001-revision-06.result.md" <<'RESULT'
# Worker Task Result

Goal-Outcome: NEEDS_DECOMPOSITION
Resource-Guard: ITEM_LIMIT
RESULT
cat > "$CIRCUIT_ROOT/resource-review.md" <<'NOTE'
Progress-Percent: 0%
Improvement-Percent: 0%
Blocking-Fingerprint: sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
NOTE
resource_output="$("$HARNESS_BIN/manager-reject-task" "$CIRCUIT_ROOT/harness.env" \
	001-revision-06 "$CIRCUIT_ROOT/resource-review.md")"
[[ "$resource_output" == *.needs-replan.md ]]
grep -Fqx 'Trigger-Outcome: RESOURCE_NEEDS_DECOMPOSITION' "$resource_output"
grep -q 'ITEM_LIMIT fuse' "$resource_output"
rm -f "$resource_output"

# Resource-fused episodes that changed an already-dirty workspace are not
# identical no-progress failures. Even when a manager repeats one stale
# Blocking-Fingerprint, machine-owned content fingerprints keep the episodes
# distinct and route the preserved source change to fresh verification.
for revision in 07 08 09; do
	assignment="$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-$revision.assignment.md"
	result="$CIRCUIT_ROOT/state/projects/circuitproj/results/circuitproj-task-001-revision-$revision.result.md"
	cat > "$assignment" <<MD
Task-ID: 001-revision-$revision
Task-Root: 001
MD
	case "$revision" in
		07) workspace_hash="1111111111111111111111111111111111111111111111111111111111111111" ;;
		08) workspace_hash="2222222222222222222222222222222222222222222222222222222222222222" ;;
		09) workspace_hash="3333333333333333333333333333333333333333333333333333333333333333" ;;
	esac
	cat > "$result" <<RESULT
# Worker Task Result

Goal-Outcome: NEEDS_DECOMPOSITION
Resource-Guard: ITEM_LIMIT
Workspace-Changed: 1
Workspace-Fingerprint-Before: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workspace-Fingerprint-After: sha256:$workspace_hash
RESULT
	progress_resource_output="$("$HARNESS_BIN/manager-reject-task" "$CIRCUIT_ROOT/harness.env" \
		"001-revision-$revision" "$CIRCUIT_ROOT/resource-review.md")"
	[[ "$progress_resource_output" == *.needs-replan.md ]]
	grep -Fqx 'Trigger-Outcome: RESOURCE_PROGRESS_NEEDS_VERIFICATION' "$progress_resource_output"
	[[ ! -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.architecture-reassessment-required.md" ]]
	rm -f "$progress_resource_output"
done
grep -q 'TASK_RESOURCE_BLOCKING_FINGERPRINT_NORMALIZED task=001-revision-09.*workspace_changed=1' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/logs/events.log"
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.architecture-reassessment-required.md" <<'MARKER'
# Architecture Reassessment Required

Project: circuitproj
Task-Root: 001
Triggered-By: 001-revision-06
Category: REPEATED_RESOURCE_DECOMPOSITION_FAILURE
MARKER
printf 'The resource failure was inspected; preserve work and split the executable leaf.\n' \
	> "$CIRCUIT_ROOT/resource-resolution.md"
"$HARNESS_BIN/harness-resolve-architecture-reassessment" "$CIRCUIT_ROOT/harness.env" 001 \
	"$CIRCUIT_ROOT/resource-resolution.md" >/dev/null
grep -Fqx 'Trigger-Outcome: RESOURCE_NEEDS_DECOMPOSITION' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"
rm -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"

# Rejecting a worker-reported hard boundary must not resume the same coding
# thread or republish the same narrow implementation leaf. Route one fresh
# manager-owned scope diagnostic even when the reviewer did not accept the
# worker's hard-block proof.
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-10.assignment.md" <<'MD'
Task-ID: 001-revision-10
Task-Root: 001
Allowed-Scope: src/narrow-provider.c
MD
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/results/circuitproj-task-001-revision-10.result.md" <<'RESULT'
# Worker Task Result

Goal-Outcome: HARD_BLOCKED
RESULT
mkdir -p "$CIRCUIT_ROOT/state/projects/circuitproj/control/goals"
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/control/goals/circuitproj-task-001-revision-10.goal" <<'GOAL'
task_id=001-revision-10
task_root=001
goal_id=hard-boundary-goal
state=REVIEW
thread_id=worker-thread-must-rotate
thread_context=resumed
manager_reviews=0
GOAL
hard_reject_output="$("$HARNESS_BIN/manager-reject-task" "$CIRCUIT_ROOT/harness.env" \
	001-revision-10 "$CIRCUIT_ROOT/resource-review.md")"
[[ "$hard_reject_output" == *.needs-replan.md ]]
grep -Fqx 'Trigger-Outcome: HARD_BLOCK_SCOPE_DIAGNOSTIC' "$hard_reject_output"
grep -Fqx 'Blocker-Class: LOCAL_SCOPE_PREREQUISITE' "$hard_reject_output"
grep -Fq 'adjacent contract or implementation authority outside src/narrow-provider.c' \
	"$hard_reject_output"
grep -Fqx 'thread_id=' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/control/goals/circuitproj-task-001-revision-10.goal"
grep -Fqx 'thread_context=rejected-boundary-requires-fresh-context' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/control/goals/circuitproj-task-001-revision-10.goal"
rm -f "$hard_reject_output"

# An operator who independently confirms preserved source movement may request
# verification rather than another implementation/decomposition episode.
cat > "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.architecture-reassessment-required.md" <<'MARKER'
# Architecture Reassessment Required

Project: circuitproj
Task-Root: 001
Triggered-By: 001-revision-09
Category: REPEATED_RESOURCE_DECOMPOSITION_FAILURE
MARKER
cat > "$CIRCUIT_ROOT/resource-progress-resolution.md" <<'RESOLUTION'
Resolution-Action: VERIFY_PRESERVED_WORKSPACE

The preserved bounded diff was independently inspected and must be verified before further edits.
RESOLUTION
"$HARNESS_BIN/harness-resolve-architecture-reassessment" "$CIRCUIT_ROOT/harness.env" 001 \
	"$CIRCUIT_ROOT/resource-progress-resolution.md" >/dev/null
grep -Fqx 'Trigger-Outcome: RESOURCE_PROGRESS_NEEDS_VERIFICATION' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"
rm -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.needs-replan.md"

# A verified leaf hard block caused by repository-local scope is archived as a
# failed leaf attempt and routed to manager remediation. It must never create a
# terminal root block merely because the worker's Allowed-Scope was too narrow.
HARD_ROOT="$TEST_ROOT/local-hard-block"
mkdir -p "$HARD_ROOT/repo" "$HARD_ROOT/manager-home" "$HARD_ROOT/worker-home"
printf 'test specification\n' > "$HARD_ROOT/repo/spec.md"
cat > "$HARD_ROOT/harness.env" <<ENV
export PROJECT="hardblockproj"
export REPOSITORY="$HARD_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$HARD_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$HARD_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$HARD_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
ENV
chmod 600 "$HARD_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$HARD_ROOT/harness.env" >/dev/null
printf 'P0\tLocal hard-block fixture\n' > "$HARD_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$HARD_ROOT/harness.env" \
	"$HARD_ROOT/plan.tsv" >/dev/null
cat > "$HARD_ROOT/task.md" <<'TASK'
# Task

Task-ID: 001
Root-Criterion: fixture.local-hard-block
Target-Criterion: fixture.local-hard-block
TASK
"$HARNESS_BIN/manager-publish-task" "$HARD_ROOT/harness.env" 001 \
	"$HARD_ROOT/task.md" P0 >/dev/null
hard_project="$HARD_ROOT/state/projects/hardblockproj"
hard_progress="$hard_project/control/progress"
mv "$hard_project/tasks/hardblockproj-task-001.ready.md" \
	"$hard_project/archive/hardblockproj-task-001.assignment.md"
cat > "$hard_project/results/hardblockproj-task-001.result.md" <<'RESULT'
# Task Result

Goal-Outcome: HARD_BLOCKED
RESULT
cat > "$HARD_ROOT/review.md" <<'NOTE'
Progress-Percent: 0%
Improvement-Percent: 0%
Blocker-Class: LOCAL_SCOPE_PREREQUISITE
Remediation-Scope: src/private-provider.c tests/focused-provider-smoke.c
NOTE
hard_block_output="$("$HARNESS_BIN/manager-block-task" "$HARD_ROOT/harness.env" \
	001 "$HARD_ROOT/review.md" 'worker scope excludes the required private test seam')"
[[ "$hard_block_output" == *.needs-replan.md ]]
[[ -f "$hard_project/archive/hardblockproj-task-001.rejected.md" ]]
[[ -f "$hard_project/archive/hardblockproj-task-001.rejected-result.md" ]]
[[ ! -f "$hard_progress/hardblockproj-task-001.blocked.md" ]]
[[ ! -f "$hard_progress/hardblockproj-task-001.needs-human.md" ]]
grep -q '^Trigger-Outcome: HARD_BLOCKED_LOCAL$' \
	"$hard_progress/hardblockproj-task-001.needs-replan.md"
grep -q '^Blocker-Class: LOCAL_SCOPE_PREREQUISITE$' \
	"$hard_progress/hardblockproj-task-001.needs-replan.md"
grep -q '^Remediation-Scope: src/private-provider.c tests/focused-provider-smoke.c$' \
	"$hard_progress/hardblockproj-task-001.needs-replan.md"
grep -q $'\t001\t001\tLOCAL_SCOPE_PREREQUISITE\tMANAGER_REMEDIATION\t' \
	"$hard_progress/hardblockproj-task-001.hard-blocks.tsv"
cat > "$hard_project/control/manager.thread" <<'THREAD'
thread_id=hard-block-manager-thread
THREAD
cat > "$hard_progress/hardblockproj-task-001.criteria-definition.tsv" <<'TSV'
criterion_id	title	acceptance_evidence
fixture.local-hard-block	Local hard-block fixture	focused repository-local remediation passes
TSV
"$HARNESS_BIN/manager-auto-replan-root" "$HARD_ROOT/harness.env" 001 >/dev/null
hard_remediation="$hard_project/tasks/hardblockproj-task-001-revision-01.ready.md"
[[ -f "$hard_remediation" ]]
grep -q '^Manager-Remediation: 1$' "$hard_remediation"
grep -q '^Strategy-Change: REPAIR_PREREQUISITE$' "$hard_remediation"
grep -q '^Supersedes-Task: 001$' "$hard_remediation"
"$HARNESS_BIN/harness-status" --full "$HARD_ROOT/harness.env" > "$HARD_ROOT/status.out"
grep -q 'Project status: MANAGER_REMEDIATION.' "$HARD_ROOT/status.out"
grep -q 'Manager remediation blockers: 1 occurrence(s), 0 unique fingerprint(s); 1 active task(s).' \
	"$HARD_ROOT/status.out"
grep -q 'Hard-block claims: 1 occurrence(s); 1 routed to manager remediation; 0 confirmed human-dependent.' \
	"$HARD_ROOT/status.out"

# If a manager remediation checkpoints a useful repair but exposes another
# directly implicated prerequisite, the next recovery must remain manager
# baseline remediation instead of losing provenance as an ordinary feature
# continuation.
mv "$hard_remediation" \
	"$hard_project/archive/hardblockproj-task-001-revision-01.assignment.md"
cat > "$hard_project/results/hardblockproj-task-001-revision-01.result.md" <<'RESULT'
# Task Result

Task-ID: 001-revision-01
Status: COMPLETED
Goal-Outcome: NEEDS_DECOMPOSITION

## Summary

The first baseline prerequisite is repaired and the next one is isolated.

## Modified files

None in this fixture.

## Implemented behavior

The manager remediation advanced the focused boundary.

## Validation performed

The focused fixture validation passed.

## Deviations from assignment

None.

## Remaining concerns

One directly implicated prerequisite remains.

## Worker assessment

The useful repair should be checkpointed before manager remediation continues.
RESULT
cat > "$HARD_ROOT/remediation-checkpoint-review.md" <<'NOTE'
# Manager Review Record

Task-ID: 001-revision-01
Decision: CHECKPOINT_INCREMENT
Progress-Percent: 0%
Improvement-Percent: 0%
Verified-Increment: fixture local hard block baseline repair
Checkpoint-Path: NONE

## Specification comparison

The baseline repair preserves the observable fixture requirement.

## Increment verification

- [PASS] baseline repair — the focused boundary advanced

## Validation executed

- [PASS] focused fixture — exit status 0

## Scope and regression review

The repair remains separately attributed manager remediation.

## Remaining root criteria

The original focused criterion remains pending.

## Conclusion

Checkpoint the repair and continue manager remediation.
NOTE
remediation_checkpoint_output="$("$HARNESS_BIN/manager-checkpoint-task" \
	"$HARD_ROOT/harness.env" 001-revision-01 \
	"$HARD_ROOT/remediation-checkpoint-review.md")"
[[ "$remediation_checkpoint_output" == *.needs-replan.md ]]
grep -Fqx 'Decision: CHECKPOINT' \
	"$hard_project/archive/checkpoints/hardblockproj-task-001-revision-01/review.md"
grep -Eq '^Verified-Increment: 001-revision-01\.increment\.fixture-local-hard-block-baseline-repair\.[0-9a-f]{8}$' \
	"$hard_project/archive/checkpoints/hardblockproj-task-001-revision-01/review.md"
grep -q '^Trigger-Outcome: MANAGER_REMEDIATION_CONTINUATION$' \
	"$hard_progress/hardblockproj-task-001.needs-replan.md"
grep -q '^Blocker-Class: LOCAL_CODE_PREREQUISITE$' \
	"$hard_progress/hardblockproj-task-001.needs-replan.md"
grep -q '^Remediation-Scope: src/mock-blocking-prerequisite.c$' \
	"$hard_progress/hardblockproj-task-001.needs-replan.md"
"$HARNESS_BIN/manager-auto-replan-root" "$HARD_ROOT/harness.env" 001 >/dev/null
hard_remediation_continuation="$hard_project/tasks/hardblockproj-task-001-revision-02.ready.md"
[[ -f "$hard_remediation_continuation" ]]
grep -q '^Manager-Remediation: 1$' "$hard_remediation_continuation"
grep -q '^Strategy-Change: REPAIR_PREREQUISITE$' "$hard_remediation_continuation"
grep -q '^Supersedes-Task: 001-revision-01$' "$hard_remediation_continuation"

# A terminal pause requires an enumerated human dependency and concrete
# evidence; it uses NEEDS_HUMAN rather than the legacy root-block marker.
printf 'human hard-block assignment\n' > \
	"$hard_project/archive/hardblockproj-task-human-001.assignment.md"
cat > "$hard_project/results/hardblockproj-task-human-001.result.md" <<'RESULT'
# Task Result

Goal-Outcome: HARD_BLOCKED
RESULT
cat > "$HARD_ROOT/human-review.md" <<'NOTE'
Progress-Percent: 0%
Improvement-Percent: 0%
Blocker-Class: HUMAN_AUTHORIZATION
Human-Dependency-Evidence: release approval must be granted by the repository owner
NOTE
human_block_output="$("$HARNESS_BIN/manager-block-task" "$HARD_ROOT/harness.env" \
	human-001 "$HARD_ROOT/human-review.md" 'repository owner release approval is unavailable')"
[[ "$human_block_output" == *.needs-human.md ]]
[[ -f "$hard_project/archive/hardblockproj-task-human-001.blocked.md" ]]
[[ ! -f "$hard_progress/hardblockproj-task-human-001.blocked.md" ]]
grep -q '^Blocker-Class: HUMAN_AUTHORIZATION$' \
	"$hard_progress/hardblockproj-task-human-001.needs-human.md"
"$HARNESS_BIN/harness-status" --full "$HARD_ROOT/harness.env" > "$HARD_ROOT/human-status.out"
grep -q 'Hard-block claims: 2 occurrence(s); 1 routed to manager remediation; 1 confirmed human-dependent.' \
	"$HARD_ROOT/human-status.out"

# Product/specification escalation must identify incompatible observable
# outcomes. A file-ownership or scope-only claim cannot pass this gate.
printf 'product hard-block assignment\n' > \
	"$hard_project/archive/hardblockproj-task-product-001.assignment.md"
cat > "$hard_project/results/hardblockproj-task-product-001.result.md" <<'RESULT'
# Task Result

Goal-Outcome: HARD_BLOCKED
RESULT
cat > "$HARD_ROOT/product-review.md" <<'NOTE'
Progress-Percent: 0%
Improvement-Percent: 0%
Blocker-Class: HUMAN_PRODUCT_SPECIFICATION
Human-Dependency-Evidence: two behaviors appear to conflict
NOTE
if "$HARNESS_BIN/manager-block-task" "$HARD_ROOT/harness.env" \
	product-001 "$HARD_ROOT/product-review.md" \
	'product behavior is unresolved' >"$HARD_ROOT/product-invalid.out" \
	2>"$HARD_ROOT/product-invalid.err"; then
	printf 'scope-only HUMAN_PRODUCT_SPECIFICATION unexpectedly passed validation\n' >&2
	exit 1
fi
grep -q 'HUMAN_PRODUCT_SPECIFICATION requires Product-Decision-Evidence' \
	"$HARD_ROOT/product-invalid.err"
cat >> "$HARD_ROOT/product-review.md" <<'NOTE'
Product-Decision-Evidence: public API returns legacy values or normalized values, and the specification does not choose between them
Governing-Specification-Search: exact bounded search for the public API return contract found no governing choice
NOTE
product_block_output="$("$HARNESS_BIN/manager-block-task" "$HARD_ROOT/harness.env" \
	product-001 "$HARD_ROOT/product-review.md" 'product behavior is unresolved')"
[[ "$product_block_output" == *.needs-human.md ]]
grep -q '^Product-Decision-Evidence: public API returns legacy values or normalized values' \
	"$hard_project/archive/hardblockproj-task-product-001.blocked.md"

# A genuine authority dependency remains terminal for the output watcher, even
# though deterministic local blockers no longer use that state.
(
	source "$CIRCUIT_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	mark_root_needs_human 001 001-revision-01 \
		'missing authorization requires an operator decision' >/dev/null
)
blocked_watch_output="$CIRCUIT_ROOT/watch-agents-blocked.out"
HARNESS_WATCH_POLL_SECONDS=0.05 timeout 2 \
	"$HARNESS_BIN/harness-watch-agents" "$CIRCUIT_ROOT/harness.env" \
	> "$blocked_watch_output" 2>&1
grep -q 'Watcher exiting: project paused for human intervention.' \
	"$blocked_watch_output"

# Rejected revisions retain one root-scoped Codex thread, high-progress
# continuations receive bounded closure mode, rotation starts a fresh thread,
# and acceptance clears the retained state.
CONTEXT_ROOT="$TEST_ROOT/context"
mkdir -p "$CONTEXT_ROOT/repo" "$CONTEXT_ROOT/manager-home" "$CONTEXT_ROOT/worker-home"
printf 'test specification\n' > "$CONTEXT_ROOT/repo/spec.md"
cat > "$CONTEXT_ROOT/harness.env" <<ENV
export PROJECT="contextproj"
export REPOSITORY="$CONTEXT_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$CONTEXT_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$CONTEXT_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$CONTEXT_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_HEARTBEAT_SECONDS="1"
export HARNESS_WORKER_THREAD_MAX_REJECTIONS="2"
export HARNESS_CLOSURE_MODE_MIN_PROGRESS="95"
export HARNESS_CLOSURE_MODE_MAX_FIXES="2"
export HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS="3"
ENV
chmod 600 "$CONTEXT_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$CONTEXT_ROOT/harness.env" >/dev/null
printf 'P0\tPersistent worker context fixture\n' > "$CONTEXT_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$CONTEXT_ROOT/harness.env" \
	"$CONTEXT_ROOT/plan.tsv" >/dev/null
printf '# Task\n\nTask-ID: 001\nRoot-Criterion: fixture.remaining\nTarget-Criterion: fixture.remaining\n' > "$CONTEXT_ROOT/task.md"
"$HARNESS_BIN/manager-publish-task" "$CONTEXT_ROOT/harness.env" 001 \
	"$CONTEXT_ROOT/task.md" P0 >/dev/null
mv "$CONTEXT_ROOT/state/projects/contextproj/tasks/contextproj-task-001.ready.md" \
	"$CONTEXT_ROOT/state/projects/contextproj/archive/contextproj-task-001.assignment.md"
printf 'worker result\n' > \
	"$CONTEXT_ROOT/state/projects/contextproj/results/contextproj-task-001.result.md"
printf '%s\n' '{"type":"thread.started","thread_id":"context-thread-001"}' \
	'{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}' > \
	"$CONTEXT_ROOT/state/projects/contextproj/logs/worker-task-001-20260717T000000Z-attempt-001.jsonl"
cat > "$CONTEXT_ROOT/reject-001.md" <<'NOTE'
Progress-Percent: 99%
Improvement-Percent: 99%
NOTE
"$HARNESS_BIN/manager-reject-task" "$CONTEXT_ROOT/harness.env" 001 \
	"$CONTEXT_ROOT/reject-001.md" >/dev/null
context_thread="$CONTEXT_ROOT/state/projects/contextproj/control/progress/contextproj-task-001.worker-thread"
grep -q '^thread_id=context-thread-001$' "$context_thread"
grep -q '^rejection_count=1$' "$context_thread"

"$HARNESS_BIN/manager-publish-task" "$CONTEXT_ROOT/harness.env" 001-revision-01 \
	"$CONTEXT_ROOT/task.md" >/dev/null
"$HARNESS_BIN/worker-invoke-task" "$CONTEXT_ROOT/harness.env" 001-revision-01 >/dev/null
context_prompt="$CONTEXT_ROOT/state/projects/contextproj/control/contextproj-task-001-revision-01.worker.prompt.md"
grep -q '^WORKER_CONTEXT_MODE=resumed$' "$context_prompt"
grep -q '^CLOSURE_MODE=1$' "$context_prompt"
grep -q '^CLOSURE_MAX_FIXES=2$' "$context_prompt"
grep -q '^CLOSURE_MAX_SMOKE_RUNS=3$' "$context_prompt"
grep -Fq 'An unbounded contextual search such as rg -C N PATTERN FILES is prohibited' "$context_prompt"
grep 'worker-task-001-revision-01' "$ARGS_LOG" | grep -q 'resume context-thread-001'
cat > "$CONTEXT_ROOT/reject-revision.md" <<'NOTE'
Progress-Percent: 99%
Improvement-Percent: 0%
Blocking-Fingerprint: sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
NOTE
"$HARNESS_BIN/manager-reject-task" "$CONTEXT_ROOT/harness.env" 001-revision-01 \
	"$CONTEXT_ROOT/reject-revision.md" >/dev/null
grep -q '^thread_id=context-thread-001$' "$context_thread"
grep -q '^rejection_count=2$' "$context_thread"

"$HARNESS_BIN/manager-publish-task" "$CONTEXT_ROOT/harness.env" 001-revision-02 \
	"$CONTEXT_ROOT/task.md" >/dev/null
"$HARNESS_BIN/worker-invoke-task" "$CONTEXT_ROOT/harness.env" 001-revision-02 >/dev/null
rotation_prompt="$CONTEXT_ROOT/state/projects/contextproj/control/contextproj-task-001-revision-02.worker.prompt.md"
grep -q '^WORKER_CONTEXT_MODE=fresh$' "$rotation_prompt"
grep -q '^WORKER_CONTEXT_REASON=rejection_rotation_limit$' "$rotation_prompt"
if grep 'worker-task-001-revision-02' "$ARGS_LOG" | grep -q 'resume '; then
	printf 'Expected rejection-count rotation to launch a fresh worker thread.\n' >&2
	exit 1
fi
"$HARNESS_BIN/manager-reject-task" "$CONTEXT_ROOT/harness.env" 001-revision-02 \
	"$CONTEXT_ROOT/reject-revision.md" >/dev/null

printf '# Task\n\nTask-ID: 001-revision-03\nTarget-Criterion: fixture.remaining\nWorker-Context: FRESH\n' > \
	"$CONTEXT_ROOT/fresh-task.md"
"$HARNESS_BIN/manager-publish-task" "$CONTEXT_ROOT/harness.env" 001-revision-03 \
	"$CONTEXT_ROOT/fresh-task.md" >/dev/null
"$HARNESS_BIN/worker-invoke-task" "$CONTEXT_ROOT/harness.env" 001-revision-03 >/dev/null
fresh_prompt="$CONTEXT_ROOT/state/projects/contextproj/control/contextproj-task-001-revision-03.worker.prompt.md"
grep -q '^WORKER_CONTEXT_MODE=fresh$' "$fresh_prompt"
grep -q '^WORKER_CONTEXT_REASON=assignment_requested_fresh$' "$fresh_prompt"
cat > "$CONTEXT_ROOT/accept.md" <<'NOTE'
# Manager Review Record

Task-ID: 001-revision-03
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: fixture.remaining

## Specification comparison
Mock specification comparison.

## Acceptance-criteria verification
- [PASS] persistent context criterion — mocked evidence

## Feature verification
- [PASS] bounded closure behavior — mocked focused evidence

## Validation executed
- [PASS] mock-test — exit status 0

## Scope and regression review
Mock scope review.

## Conclusion
All required behavior was independently verified. Accept.
NOTE
"$HARNESS_BIN/manager-accept-task" "$CONTEXT_ROOT/harness.env" 001-revision-03 \
	"$CONTEXT_ROOT/accept.md" >/dev/null
[[ ! -e "$context_thread" ]]
grep -q 'WORKER_THREAD_RETAINED task=001-revision-01' \
	"$CONTEXT_ROOT/state/projects/contextproj/logs/events.log"
grep -q 'WORKER_THREAD_CLEARED task=001-revision-03' \
	"$CONTEXT_ROOT/state/projects/contextproj/logs/events.log"

# A verified checkpoint is evidence-backed gain even when the numeric progress
# percentage cannot move. It must break a zero-gain rejection streak, while
# subsequent zero-gain rejections still accumulate to the configured limit.
ZERO_GAIN_ROOT="$TEST_ROOT/zero-gain-streak"
zero_gain_progress="$ZERO_GAIN_ROOT/state/projects/zerogain/control/progress"
mkdir -p "$zero_gain_progress"
cat > "$zero_gain_progress/zerogain-task-001.history.tsv" <<'TSV'
updated_at	task_id	decision	progress_percent	improvement_percent	review_sha256
2026-01-01T00:00:00Z	001	REJECT	99	0	-
2026-01-01T00:01:00Z	001-revision-01	REJECT	99	0	-
2026-01-01T00:02:00Z	001-revision-02	CHECKPOINT	99	0	-
2026-01-01T00:03:00Z	001-revision-03	REJECT	99	0	-
TSV
cat > "$zero_gain_progress/zerogain-task-001.convergence-baseline" <<'BASELINE'
reviewed_attempts=1
history_rows=1
checkpoint_rows=0
resumed_at=2026-01-01T00:00:30Z
BASELINE
(
	export PROJECT=zerogain
	export HARNESS_ROOT="$ZERO_GAIN_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_zero_gain_streak 001)" == 1 ]]
)
cat >> "$zero_gain_progress/zerogain-task-001.history.tsv" <<'TSV'
2026-01-01T00:04:00Z	001-revision-04	REJECT	99	0	-
2026-01-01T00:05:00Z	001-revision-05	REJECT	99	0	-
TSV
(
	export PROJECT=zerogain
	export HARNESS_ROOT="$ZERO_GAIN_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_zero_gain_streak 001)" == 3 ]]
)

# Correct partial work is checkpointed rather than rejected. Checkpoints keep
# the parent plan item active, preserve scoped workspace content and append-only
# evidence, and pause in NEEDS_REPLAN after a configured convergence threshold.
CHECKPOINT_ROOT="$TEST_ROOT/checkpoint"
mkdir -p "$CHECKPOINT_ROOT/repo" "$CHECKPOINT_ROOT/manager-home" "$CHECKPOINT_ROOT/worker-home"
printf 'test specification\n' > "$CHECKPOINT_ROOT/repo/spec.md"
printf 'base\n' > "$CHECKPOINT_ROOT/repo/source.txt"
printf 'second base\n' > "$CHECKPOINT_ROOT/repo/source-two.txt"
git -C "$CHECKPOINT_ROOT/repo" init -q
git -C "$CHECKPOINT_ROOT/repo" config user.email harness@example.invalid
git -C "$CHECKPOINT_ROOT/repo" config user.name 'Harness Test'
git -C "$CHECKPOINT_ROOT/repo" add spec.md source.txt source-two.txt
git -C "$CHECKPOINT_ROOT/repo" commit -qm base
cat > "$CHECKPOINT_ROOT/harness.env" <<ENV
export PROJECT="checkpointproj"
export REPOSITORY="$CHECKPOINT_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$CHECKPOINT_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$CHECKPOINT_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$CHECKPOINT_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_MAX_ROOT_ATTEMPTS="0"
export HARNESS_MAX_ZERO_GAIN_WINDOW="0"
export HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION="2"
export HARNESS_AUTO_REPLAN_ENABLED="0"
ENV
chmod 600 "$CHECKPOINT_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$CHECKPOINT_ROOT/harness.env" >/dev/null
printf 'P0\tCheckpoint lifecycle fixture\n' > "$CHECKPOINT_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$CHECKPOINT_ROOT/harness.env" \
	"$CHECKPOINT_ROOT/plan.tsv" >/dev/null

checkpoint_worker_result()
{
	local task_id="$1" result_file="$2"
	cat > "$result_file" <<RESULT
# Task Result

Task-ID: $task_id
Status: COMPLETED

## Summary

Implemented a verified increment.

## Modified files

- source.txt

## Implemented behavior

- Added one bounded behavior.

## Validation performed

Focused validation passed.

## Deviations from assignment

None.

## Remaining concerns

Parent root remains incomplete.

## Worker assessment

Ready for checkpoint review.
RESULT
}

printf '# Task\n\nTask-ID: 001\nRoot-Criterion: compiler.registry\nRoot-Criterion: compiler.projection\nTarget-Criterion: compiler.projection\n' > "$CHECKPOINT_ROOT/task.md"
"$HARNESS_BIN/manager-publish-task" "$CHECKPOINT_ROOT/harness.env" 001 \
	"$CHECKPOINT_ROOT/task.md" P0 >/dev/null
mv "$CHECKPOINT_ROOT/state/projects/checkpointproj/tasks/checkpointproj-task-001.ready.md" \
	"$CHECKPOINT_ROOT/state/projects/checkpointproj/archive/checkpointproj-task-001.assignment.md"
printf 'criterion checkpoint\n' > "$CHECKPOINT_ROOT/repo/source.txt"
printf 'second criterion checkpoint\n' > "$CHECKPOINT_ROOT/repo/source-two.txt"
checkpoint_worker_result 001 \
	"$CHECKPOINT_ROOT/state/projects/checkpointproj/results/checkpointproj-task-001.result.md"
cat > "$CHECKPOINT_ROOT/review-001.md" <<'NOTE'
# Manager Review Record

Task-ID: 001
Decision: CHECKPOINT
Progress-Percent: 75%
Improvement-Percent: 75%
Verified-Criterion: compiler.registry
Checkpoint-Path: source.txt, source-two.txt
Debt-Recorded: explanatory prose that is not a registered debt identifier

## Specification comparison
The bounded registry criterion is complete, while the parent root remains active.

## Increment verification
- [PASS] registry increment — direct source inspection passed

## Validation executed
- [PASS] focused-check — exit status 0

## Scope and regression review
Only source.txt changed and the focused behavior remained stable.

## Remaining root criteria
Projection remains incomplete.

## Conclusion
This increment is correct and independently verified, while the root remains incomplete. Checkpoint.
NOTE
checkpoint_output="$("$HARNESS_BIN/manager-checkpoint-task" "$CHECKPOINT_ROOT/harness.env" \
	001 "$CHECKPOINT_ROOT/review-001.md")"
[[ "$checkpoint_output" == *.checkpointed.md ]]
checkpoint_project="$CHECKPOINT_ROOT/state/projects/checkpointproj"
[[ -f "$checkpoint_project/archive/checkpointproj-task-001.checkpointed.md" ]]
[[ -f "$checkpoint_project/archive/checkpoints/checkpointproj-task-001/manifest.txt" ]]
grep -q '^Progress-Percent: 50%$' \
	"$checkpoint_project/archive/checkpoints/checkpointproj-task-001/review.md"
grep -q '^Improvement-Percent: 50%$' \
	"$checkpoint_project/archive/checkpoints/checkpointproj-task-001/review.md"
grep -q '^Debt-Recorded: NONE$' \
	"$checkpoint_project/archive/checkpoints/checkpointproj-task-001/review.md"
cmp -s "$CHECKPOINT_ROOT/repo/source.txt" \
	"$checkpoint_project/archive/checkpoints/checkpointproj-task-001/files/source.txt"
cmp -s "$CHECKPOINT_ROOT/repo/source-two.txt" \
	"$checkpoint_project/archive/checkpoints/checkpointproj-task-001/files/source-two.txt"
grep -q $'^compiler.registry\tPASSED\t001\t' \
	"$checkpoint_project/control/progress/checkpointproj-task-001.criteria.tsv"
grep -q $'001\tCHECKPOINT\t50\t50\t' \
	"$checkpoint_project/control/progress/checkpointproj-task-001.history.tsv"
grep -Eq $'^P0\tACTIVE\t001\t' "$checkpoint_project/control/project-plan-state.tsv"
# A verified source checkpoint is a durable controlled commit, not merely a
# workspace patch. Later zero-write revisions may inherit that provenance
# without claiming the source mutation as their own.
git -C "$CHECKPOINT_ROOT/repo" diff --quiet HEAD -- source.txt source-two.txt
grep -q $'^controlled_source_commit=' \
	"$checkpoint_project/archive/checkpoints/checkpointproj-task-001/manifest.txt"
grep -Eq $'^[0-9a-f]+\t001\tmanager-checkpoint\t[^\t]+\tsource.txt,source-two.txt$' \
	"$checkpoint_project/control/agent-commits.tsv"
# Simulate the malformed artifact produced by releases that interpreted one
# comma-separated path field as a single deleted pseudo-path. A passing
# zero-write acceptance review upgrades it to per-file hashes and recommits the
# exact reviewed workspace under the original checkpoint task.
git -C "$CHECKPOINT_ROOT/repo" reset -q --mixed HEAD^
sed -i '1q' "$checkpoint_project/control/agent-commits.tsv"
checkpoint_artifact="$checkpoint_project/archive/checkpoints/checkpointproj-task-001"
awk '!/^path=/ && !/^controlled_source_commit=/' "$checkpoint_artifact/manifest.txt" \
	> "$checkpoint_artifact/manifest.txt.tmp"
printf 'path=source.txt,source-two.txt\ttype=deleted\n' >> "$checkpoint_artifact/manifest.txt.tmp"
mv "$checkpoint_artifact/manifest.txt.tmp" "$checkpoint_artifact/manifest.txt"
printf 'source.txt,source-two.txt\n' > "$checkpoint_artifact/checkpoint-paths.txt"
cp "$checkpoint_project/archive/checkpointproj-task-001.assignment.md" \
	"$checkpoint_project/archive/checkpointproj-task-001-revision-99.assignment.md"
if grep -q '^Expected-Max-Implementation-Files:' \
	"$checkpoint_project/archive/checkpointproj-task-001-revision-99.assignment.md"; then
	sed -i 's/^Expected-Max-Implementation-Files:.*/Expected-Max-Implementation-Files: 0/' \
		"$checkpoint_project/archive/checkpointproj-task-001-revision-99.assignment.md"
else
	printf 'Expected-Max-Implementation-Files: 0\n' >> \
		"$checkpoint_project/archive/checkpointproj-task-001-revision-99.assignment.md"
fi
printf 'Decision: ACCEPT\n' > "$CHECKPOINT_ROOT/legacy-accept-review.md"
(
	source "$CHECKPOINT_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	export HARNESS_AGENT_COMMITS_ENABLED=1
	source "$HARNESS_HOME/lib/harness-git-commit.sh"
	source "$HARNESS_HOME/lib/harness-checkpoint-commit.sh"
	checkpoint_reconcile_root_source_provenance 001-revision-99 \
		"$CHECKPOINT_ROOT/legacy-accept-review.md"
)
git -C "$CHECKPOINT_ROOT/repo" diff --quiet HEAD -- source.txt source-two.txt
test -f "$checkpoint_artifact/legacy-comma-path-artifact/manifest.txt"
grep -q '^legacy_comma_path_repaired_by_review_sha256=' "$checkpoint_artifact/manifest.txt"
grep -q $'^path=source.txt\ttype=file\t' "$checkpoint_artifact/manifest.txt"
grep -q $'^path=source-two.txt\ttype=file\t' "$checkpoint_artifact/manifest.txt"
(
	source "$CHECKPOINT_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	architecture_evidence_has_root_provenance 001-revision-01 source.txt
)
"$HARNESS_BIN/harness-status" --full "$CHECKPOINT_ROOT/harness.env" > "$CHECKPOINT_ROOT/status-1.out"
grep -Eq '001 +CHECKPOINTED +WORKER +50%' "$CHECKPOINT_ROOT/status-1.out"

for revision in 01 02; do
	task_id="001-revision-$revision"
	printf '# Task\n\nTask-ID: %s\nTarget-Criterion: compiler.projection\n' "$task_id" > "$CHECKPOINT_ROOT/task-$revision.md"
	"$HARNESS_BIN/manager-publish-task" "$CHECKPOINT_ROOT/harness.env" "$task_id" \
		"$CHECKPOINT_ROOT/task-$revision.md" >/dev/null
	mv "$checkpoint_project/tasks/checkpointproj-task-$task_id.ready.md" \
		"$checkpoint_project/archive/checkpointproj-task-$task_id.assignment.md"
	printf 'verified increment %s\n' "$revision" > "$CHECKPOINT_ROOT/repo/source.txt"
	checkpoint_worker_result "$task_id" \
		"$checkpoint_project/results/checkpointproj-task-$task_id.result.md"
	cat > "$CHECKPOINT_ROOT/review-$revision.md" <<NOTE
# Manager Review Record

Task-ID: $task_id
Decision: CHECKPOINT
Progress-Percent: 50%
Improvement-Percent: 0%
Verified-Increment: compiler.increment.$revision
Checkpoint-Path: source.txt

## Specification comparison
This verified increment advances the active compiler root.

## Increment verification
- [PASS] compiler increment $revision — direct source inspection passed

## Validation executed
- [PASS] focused-check — exit status 0

## Scope and regression review
Only source.txt changed and the focused behavior remained stable.

## Remaining root criteria
The next complete root criterion remains pending.

## Conclusion
This increment is correct and independently verified, while the root remains incomplete. Checkpoint.
NOTE
	checkpoint_output="$("$HARNESS_BIN/manager-checkpoint-task" "$CHECKPOINT_ROOT/harness.env" \
		"$task_id" "$CHECKPOINT_ROOT/review-$revision.md")"
done
[[ "$checkpoint_output" == *.needs-replan.md ]]
replan_marker="$checkpoint_project/control/progress/checkpointproj-task-001.needs-replan.md"
[[ -f "$replan_marker" ]]
grep -q 'verified increments without a completed root criterion reached the configured limit (2/2)' "$replan_marker"
(
	source "$CHECKPOINT_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_reviewed_attempt_count 001)" == 3 ]]
	[[ "$(root_reviewed_attempts_since_replan 001)" == 3 ]]
	[[ "$(root_zero_gain_streak 001)" == 0 ]]
	[[ "$(root_checkpoint_without_criterion_streak 001)" == 2 ]]
)
[[ -f "$checkpoint_project/archive/checkpointproj-task-001-revision-02.checkpointed.md" ]]
if "$HARNESS_BIN/manager-publish-task" "$CHECKPOINT_ROOT/harness.env" 001-revision-03 \
	"$CHECKPOINT_ROOT/task.md" >"$CHECKPOINT_ROOT/paused.out" 2>"$CHECKPOINT_ROOT/paused.err"; then
	printf 'Expected NEEDS_REPLAN to prevent another continuation.\n' >&2
	exit 1
fi
grep -q 'task root is paused pending replanning' "$CHECKPOINT_ROOT/paused.err"
"$HARNESS_BIN/harness-status" --full "$CHECKPOINT_ROOT/harness.env" > "$CHECKPOINT_ROOT/status-2.out"
grep -q 'Project status: NEEDS_REPLAN.' "$CHECKPOINT_ROOT/status-2.out"
grep -q 'Verified checkpoints: 3' "$CHECKPOINT_ROOT/status-2.out"
checkpoint_watch="$CHECKPOINT_ROOT/watch.out"
HARNESS_WATCH_POLL_SECONDS=0.05 timeout 2 \
	"$HARNESS_BIN/harness-watch-agents" "$CHECKPOINT_ROOT/harness.env" \
	> "$checkpoint_watch" 2>&1
grep -q 'project paused for replanning; verified checkpoints are preserved' "$checkpoint_watch"
"$HARNESS_BIN/harness-unblock-root" "$CHECKPOINT_ROOT/harness.env" 001 >/dev/null
[[ ! -f "$replan_marker" ]]
(
	source "$CHECKPOINT_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_reviewed_attempts_since_replan 001)" == 0 ]]
	[[ "$(root_zero_gain_streak 001)" == 0 ]]
	[[ "$(root_checkpoint_without_criterion_streak 001)" == 0 ]]
)
"$HARNESS_BIN/manager-publish-task" "$CHECKPOINT_ROOT/harness.env" 001-revision-03 \
	"$CHECKPOINT_ROOT/task.md" >/dev/null
[[ -f "$checkpoint_project/tasks/checkpointproj-task-001-revision-03.ready.md" ]]
mv "$checkpoint_project/tasks/checkpointproj-task-001-revision-03.ready.md" \
	"$checkpoint_project/archive/checkpointproj-task-001-revision-03.assignment.md"
printf 'completed root\n' > "$CHECKPOINT_ROOT/repo/source.txt"
git -C "$CHECKPOINT_ROOT/repo" add source.txt
git -C "$CHECKPOINT_ROOT/repo" commit -qm 'complete projection criterion'
checkpoint_worker_result 001-revision-03 \
	"$checkpoint_project/results/checkpointproj-task-001-revision-03.result.md"
cat > "$CHECKPOINT_ROOT/accept.md" <<'NOTE'
# Manager Review Record

Task-ID: 001-revision-03
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: compiler.projection

## Specification comparison
All declared root criteria are now satisfied.

## Acceptance-criteria verification
- [PASS] projection criterion — direct focused evidence passed

## Feature verification
- [PASS] complete compiler root — registry and projection evidence are present

## Validation executed
- [PASS] focused-check — exit status 0

## Scope and regression review
The complete declared root was reviewed without unrelated changes.

## Conclusion
All required behavior was independently verified. Accept.
NOTE
"$HARNESS_BIN/manager-accept-task" "$CHECKPOINT_ROOT/harness.env" 001-revision-03 \
	"$CHECKPOINT_ROOT/accept.md" >/dev/null
grep -q $'^compiler.projection\tPASSED\t001-revision-03\t' \
	"$checkpoint_project/control/progress/checkpointproj-task-001.criteria.tsv"
grep -Eq $'^P0\tCOMPLETE\t001\t' "$checkpoint_project/control/project-plan-state.tsv"
[[ -f "$checkpoint_project/archive/checkpointproj-task-001-revision-03.accepted.md" ]]

# Convergence recovery is automatic and bounded. A legacy root receives an
# immutable criterion decomposition, the fresh manager must isolate the first
# unmet criterion with a materially new strategy, and a fresh worker context is
# forced. If ordinary replans exhaust their no-gain budget, a visible
# manager-model remediation task repairs the local prerequisite; any unique
# verified increment or criterion resets the ordinary-replan budget.
AUTO_ROOT="$TEST_ROOT/auto-replan"
mkdir -p "$AUTO_ROOT/repo" "$AUTO_ROOT/manager-home" "$AUTO_ROOT/worker-home"
printf 'test specification\n' > "$AUTO_ROOT/repo/spec.md"
cat > "$AUTO_ROOT/harness.env" <<ENV
export PROJECT="autoreplanproj"
export REPOSITORY="$AUTO_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$AUTO_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$AUTO_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export MANAGER_MODEL="manager-remediation-test-model"
export WORKER_CODEX_HOME="$AUTO_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_MODEL="worker-test-model"
export HARNESS_POLL_SECONDS="0.1"
export HARNESS_USE_INOTIFY="0"
export HARNESS_AUTO_REPLAN_ENABLED="1"
export HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN="1"
ENV
chmod 600 "$AUTO_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$AUTO_ROOT/harness.env" >/dev/null
"$HARNESS_BIN/manager-register-thread" "$AUTO_ROOT/harness.env" auto-manager-thread >/dev/null
printf 'P0\tLegacy oversized root\n' > "$AUTO_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$AUTO_ROOT/harness.env" "$AUTO_ROOT/plan.tsv" >/dev/null
auto_project="$AUTO_ROOT/state/projects/autoreplanproj"
sed -i 's/^P0\tPENDING\t-/P0\tACTIVE\t001/' "$auto_project/control/project-plan-state.tsv"
auto_progress="$auto_project/control/progress"
mkdir -p "$auto_progress"
cat > "$auto_progress/autoreplanproj-task-001.root-assignment.md" <<'TASK'
# Legacy Task

Task-ID: 001

Complete an oversized legacy objective.
TASK
cat > "$auto_progress/autoreplanproj-task-001.progress.md" <<'PROGRESS'
# Root Task Progress

Project: autoreplanproj
Task-Root: 001
Progress-Percent: 99%
Improvement-Percent: 0%
Last-Reviewed-Task: 001-revision-07
PROGRESS
cat > "$auto_project/archive/autoreplanproj-task-001-revision-07.assignment.md" <<'TASK'
# Legacy continuation

Task-ID: 001-revision-07

## Objective

Retry the whole remaining legacy objective.
TASK
cat > "$auto_progress/autoreplanproj-task-001.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 001
Triggered-By: 001-revision-07
Trigger-Outcome: REJECT
Blocking-Fingerprint: -
MARKER
printf 'thread_id=stale-worker-thread\n' > "$auto_progress/autoreplanproj-task-001.worker-thread"
args_before_replan="$(wc -l < "$ARGS_LOG")"
"$HARNESS_BIN/harness-supervisor-start" "$AUTO_ROOT/harness.env" >/dev/null
for _ in $(seq 1 200); do
	[[ -f "$auto_project/tasks/autoreplanproj-task-001-revision-08.ready.md" ]] && break
	sleep 0.05
done
"$HARNESS_BIN/harness-supervisor-stop" "$AUTO_ROOT/harness.env" >/dev/null
auto_ready="$auto_project/tasks/autoreplanproj-task-001-revision-08.ready.md"
auto_definition="$auto_progress/autoreplanproj-task-001.criteria-definition.tsv"
auto_replans="$auto_progress/autoreplanproj-task-001.replans.tsv"
[[ -f "$auto_ready" ]]
[[ -f "$auto_definition" ]]
[[ "$(wc -l < "$auto_definition")" == 3 ]]
grep -q '^Target-Criterion: legacy.first$' "$auto_ready"
grep -q '^Worker-Context: FRESH$' "$auto_ready"
grep -q $'^.*\t001-revision-08\t001-revision-07\tlegacy.first\tmock.strategy.1\tISOLATE_CRITERION\tsha256:' "$auto_replans"
grep -q 'MANAGER_REPLAN_COMMITTED root=001 task=001-revision-08' "$auto_project/logs/events.log"
[[ ! -f "$auto_progress/autoreplanproj-task-001.needs-replan.md" ]]
[[ ! -f "$auto_progress/autoreplanproj-task-001.worker-thread" ]]
grep -q '^Progress-Percent: 99%$' "$auto_progress/autoreplanproj-task-001.progress.md"
args_after_replan="$(wc -l < "$ARGS_LOG")"
(( args_after_replan == args_before_replan + 1 ))
if tail -n 1 "$ARGS_LOG" | grep -q 'resume auto-manager-thread'; then
	printf 'Automatic replanning unexpectedly replayed the persistent manager context.\n' >&2
	exit 1
fi
grep -q 'MANAGER_REPLAN_STARTED root=001.*context=fresh previous_thread_id=auto-manager-thread' \
	"$auto_project/logs/events.log"
grep -q 'MANAGER_CONTEXT_ROTATED previous=auto-manager-thread current=mock-thread-001 reason=bounded_replan' \
	"$auto_project/logs/events.log"

# Hold the already-verified ready artifact outside the live queues while the
# following negative publication cases exercise deeper semantic validators.
# Production publication now correctly refuses any second live root revision.
auto_ready_held="$AUTO_ROOT/autoreplanproj-task-001-revision-08.ready.held"
mv "$auto_ready" "$auto_ready_held"

cat > "$AUTO_ROOT/nonfirst.md" <<'TASK'
# Task

Target-Criterion: legacy.final
TASK
if "$HARNESS_BIN/manager-publish-task" "$AUTO_ROOT/harness.env" 001-revision-09 \
	"$AUTO_ROOT/nonfirst.md" >"$AUTO_ROOT/nonfirst.out" 2>"$AUTO_ROOT/nonfirst.err"; then
	printf 'Expected non-first criterion continuation to be rejected.\n' >&2
	exit 1
fi
grep -q 'continuation must target the first unmet criterion: legacy.first' "$AUTO_ROOT/nonfirst.err"

cat > "$auto_progress/autoreplanproj-task-001.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 001
Triggered-By: 001-revision-08
Trigger-Outcome: REJECT
Blocking-Fingerprint: -
MARKER
sed 's/Task-ID: 001-revision-08/Task-ID: 001-revision-09/; s/mock.strategy.1/mock.strategy.label-only/; s/Strategy-Change: ISOLATE_CRITERION/Strategy-Change: NEW_EVIDENCE/; s/Supersedes-Task: 001-revision-07/Supersedes-Task: 001-revision-08/' \
	"/tmp/autoreplanproj/autoreplanproj-task-001-revision-08.auto-replan.md" \
	> "$AUTO_ROOT/materially-same.md"
if "$HARNESS_BIN/manager-publish-task" "$AUTO_ROOT/harness.env" 001-revision-09 \
	"$AUTO_ROOT/materially-same.md" --auto-replan \
	>"$AUTO_ROOT/materially-same.out" 2>"$AUTO_ROOT/materially-same.err"; then
	printf 'Expected a label-only strategy change to be rejected as materially identical.\n' >&2
	exit 1
fi
grep -q 'manager recovery is not materially different from an earlier bounded strategy' \
	"$AUTO_ROOT/materially-same.err"

# A resource fuse is machine evidence that the current leaf is too broad. When
# structural room remains, recovery cannot silently republish the same parent.
sed -i 's/Trigger-Outcome: REJECT/Trigger-Outcome: RESOURCE_NEEDS_DECOMPOSITION/' \
	"$auto_progress/autoreplanproj-task-001.needs-replan.md"
if "$HARNESS_BIN/manager-publish-task" "$AUTO_ROOT/harness.env" 001-revision-09 \
	"$AUTO_ROOT/materially-same.md" --auto-replan \
	>"$AUTO_ROOT/resource-unsplit.out" 2>"$AUTO_ROOT/resource-unsplit.err"; then
	printf 'Expected an unsplit resource-fused continuation to be rejected.\n' >&2
	exit 1
fi
grep -q 'resource-fused continuation must append at least two bounded direct children' \
	"$AUTO_ROOT/resource-unsplit.err"
sed -i 's/Trigger-Outcome: RESOURCE_NEEDS_DECOMPOSITION/Trigger-Outcome: REJECT/' \
	"$auto_progress/autoreplanproj-task-001.needs-replan.md"

# One recovery invocation may correct one rejected publication, but a third
# manager-publish-task call is refused before semantic validation can consume
# another planning round.
cat > "$auto_progress/autoreplanproj-task-001.replanning.md" <<MARKER
pid=$$
root=001
expected_task_id=001-revision-09
publish_attempts=0
max_publish_attempts=2
started_at=2026-08-15T00:00:00Z
env_file=$AUTO_ROOT/harness.env
MARKER
for publish_attempt in 1 2; do
	if "$HARNESS_BIN/manager-publish-task" "$AUTO_ROOT/harness.env" 001-revision-09 \
		"$AUTO_ROOT/materially-same.md" --auto-replan \
		>"$AUTO_ROOT/publish-attempt-$publish_attempt.out" 2>"$AUTO_ROOT/publish-attempt-$publish_attempt.err"; then
		printf 'Expected bounded recovery publication %s to remain semantically rejected.\n' "$publish_attempt" >&2
		exit 1
	fi
done
if "$HARNESS_BIN/manager-publish-task" "$AUTO_ROOT/harness.env" 001-revision-09 \
	"$AUTO_ROOT/materially-same.md" --auto-replan \
	>"$AUTO_ROOT/publish-attempt-3.out" 2>"$AUTO_ROOT/publish-attempt-3.err"; then
	printf 'Expected the third recovery publication attempt to be machine-blocked.\n' >&2
	exit 1
fi
grep -q 'manager recovery publication attempt budget exhausted (2/2)' \
	"$AUTO_ROOT/publish-attempt-3.err"
grep -q 'MANAGER_RECOVERY_PUBLISH_ATTEMPT_BLOCKED root=001 task=001-revision-09 attempts=2 limit=2' \
	"$auto_project/logs/events.log"
rm -f "$auto_progress/autoreplanproj-task-001.replanning.md"
rm -f "$auto_progress/autoreplanproj-task-001.needs-replan.md"

mv "$auto_ready_held" "$auto_ready"
mv "$auto_ready" "$auto_project/archive/autoreplanproj-task-001-revision-08.checkpointed.md"
cat > "$auto_progress/autoreplanproj-task-001.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 001
Triggered-By: 001-revision-08
Trigger-Outcome: CHECKPOINT
Blocking-Fingerprint: -
MARKER
"$HARNESS_BIN/manager-auto-replan-root" "$AUTO_ROOT/harness.env" 001 >/dev/null
grep -Fq 'Every data row in this transaction must name exactly' \
	"$auto_project/control/autoreplanproj-task-001.auto-replan.prompt.md"
grep -Fq 'do not include grandchildren' \
	"$auto_project/control/autoreplanproj-task-001.auto-replan.prompt.md"
grep -Fq 'TRIGGER_FOCUSED_VALIDATION=' \
	"$auto_project/control/autoreplanproj-task-001.auto-replan.prompt.md"
grep -Fq 'never replace it with an unqualified all-target build' \
	"$auto_project/control/autoreplanproj-task-001.auto-replan.prompt.md"
auto_remediation="$auto_project/tasks/autoreplanproj-task-001-revision-09.ready.md"
auto_remediation_ledger="$auto_progress/autoreplanproj-task-001.manager-remediations.tsv"
[[ -f "$auto_remediation" ]]
[[ ! -f "$auto_progress/autoreplanproj-task-001.needs-human.md" ]]
grep -q '^Manager-Remediation: 1$' "$auto_remediation"
grep -q '^Strategy-Change: REPAIR_PREREQUISITE$' "$auto_remediation"
grep -q '^Remediation-Scope: src/mock-blocking-prerequisite.c$' "$auto_remediation"
grep -q $'^.*\t001-revision-09\t001-revision-08\tlegacy.first\t-\tLOCAL_CODE_PREREQUISITE\tsrc/mock-blocking-prerequisite.c\tmanager-remediation-test-model$' \
	"$auto_remediation_ledger"
"$HARNESS_BIN/harness-status" --full "$AUTO_ROOT/harness.env" > "$AUTO_ROOT/remediation-status.out"
grep -Eq '^001-revision-09[[:space:]]+READY[[:space:]]+MANAGER_FIX' "$AUTO_ROOT/remediation-status.out"
grep -q 'Project status: MANAGER_REMEDIATION.' "$AUTO_ROOT/remediation-status.out"
grep -q 'Manager remediation blockers: 1 occurrence(s), 0 unique fingerprint(s); 1 active task(s).' \
	"$AUTO_ROOT/remediation-status.out"

args_before_remediation_execution="$(wc -l < "$ARGS_LOG")"
"$HARNESS_BIN/worker-invoke-task" "$AUTO_ROOT/harness.env" 001-revision-09 >/dev/null
(( $(wc -l < "$ARGS_LOG") == args_before_remediation_execution + 1 ))
tail -n 1 "$ARGS_LOG" | grep -q -- '--model manager-remediation-test-model'
grep -q '^EXECUTION_MODE=MANAGER_REMEDIATION$' \
	"$auto_project/control/autoreplanproj-task-001-revision-09.worker.prompt.md"
mv "$auto_project/results/autoreplanproj-task-001-revision-09.result.md" \
	"$auto_project/archive/autoreplanproj-task-001-revision-09.checkpointed.md"

cat > "$auto_progress/autoreplanproj-task-001.criteria.tsv" <<'TSV'
item_id	state	verified_by	evidence_sha256	updated_at
legacy.first	PASSED	001-revision-09	sha256:first	2026-07-22T00:00:00Z
TSV
(
	source "$AUTO_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_auto_replans_without_criterion 001)" == 0 ]]
)
cat > "$auto_progress/autoreplanproj-task-001.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 001
Triggered-By: 001-revision-09
Trigger-Outcome: CHECKPOINT
Blocking-Fingerprint: sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
MARKER
"$HARNESS_BIN/manager-auto-replan-root" "$AUTO_ROOT/harness.env" 001 >/dev/null
auto_ready_final="$auto_project/tasks/autoreplanproj-task-001-revision-10.ready.md"
[[ -f "$auto_ready_final" ]]
grep -q '^Target-Criterion: legacy.final$' "$auto_ready_final"
[[ "$(awk 'END {print NR}' "$auto_replans")" == 4 ]]
grep -q $'^.*\t001-revision-10\t001-revision-09\tlegacy.final\tmock.strategy.3\tISOLATE_CRITERION\tsha256:.*\tsha256:dddd.*\t1\t1$' "$auto_replans"
mv "$auto_ready_final" "$auto_project/archive/autoreplanproj-task-001-revision-10.checkpointed.md"
printf 'legacy.increment.after-replan\tVERIFIED\t001-revision-10\tsha256:increment\t2026-07-23T13:00:00Z\n' \
	>> "$auto_progress/autoreplanproj-task-001.criteria.tsv"
cat > "$auto_progress/autoreplanproj-task-001.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 001
Triggered-By: 001-revision-10
Trigger-Outcome: CHECKPOINT
Blocking-Fingerprint: sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
MARKER
"$HARNESS_BIN/manager-auto-replan-root" "$AUTO_ROOT/harness.env" 001 >/dev/null
auto_ready_after_gain="$auto_project/tasks/autoreplanproj-task-001-revision-11.ready.md"
[[ -f "$auto_ready_after_gain" ]]
grep -q '^Target-Criterion: legacy.final$' "$auto_ready_after_gain"
grep -q $'^.*\t001-revision-11\t001-revision-10\tlegacy.final\tmock.strategy.4\tISOLATE_CRITERION\tsha256:.*\tsha256:dddd.*\t1\t2$' "$auto_replans"
mv "$auto_ready_after_gain" "$auto_project/archive/autoreplanproj-task-001-revision-11.checkpointed.md"
printf 'Blocking-Fingerprint: sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\n' \
	>> "$auto_progress/autoreplanproj-task-001.progress.md"
cat > "$auto_progress/autoreplanproj-task-001.blocked.md" <<'MARKER'
# Blocked Root Task

Task-Root: 001
Blocked-By-Task: 001-revision-11
Reason: legacy worker scope excludes a repository-local prerequisite
MARKER
"$HARNESS_BIN/harness-supervisor-start" "$AUTO_ROOT/harness.env" >/dev/null
for _ in $(seq 1 200); do
	[[ -f "$auto_project/tasks/autoreplanproj-task-001-revision-12.ready.md" ]] && break
	sleep 0.05
done
"$HARNESS_BIN/harness-supervisor-stop" "$AUTO_ROOT/harness.env" >/dev/null
auto_same_blocker_remediation="$auto_project/tasks/autoreplanproj-task-001-revision-12.ready.md"
[[ -f "$auto_same_blocker_remediation" ]]
[[ ! -f "$auto_progress/autoreplanproj-task-001.blocked.md" ]]
grep -q 'LEGACY_HARD_BLOCK_RECLASSIFIED_MANAGER_REMEDIATION root=001 trigger=001-revision-11' \
	"$auto_project/logs/events.log"
grep -q '^Manager-Remediation: 1$' "$auto_same_blocker_remediation"
grep -q '^Target-Criterion: legacy.final$' "$auto_same_blocker_remediation"
grep -q $'^.*\t001-revision-12\t001-revision-11\tlegacy.final\tsha256:dddd.*\tLOCAL_CODE_PREREQUISITE\t' \
	"$auto_remediation_ledger"
"$HARNESS_BIN/harness-status" --full "$AUTO_ROOT/harness.env" > "$AUTO_ROOT/same-blocker-remediation-status.out"
grep -q 'Manager remediation blockers: 2 occurrence(s), 1 unique fingerprint(s); 1 active task(s).' \
	"$AUTO_ROOT/same-blocker-remediation-status.out"
grep -q 'Hard-block claims: 1 occurrence(s); 1 routed to manager remediation; 0 confirmed human-dependent.' \
	"$AUTO_ROOT/same-blocker-remediation-status.out"

# A broad immutable leaf can be refined only by appending ordered children.
# The original parent remains in the root inventory and scheduling advances
# through the new leaves without rewriting prior evidence.
DECOMP_ROOT="$TEST_ROOT/child-decomposition"
mkdir -p "$DECOMP_ROOT/repo" "$DECOMP_ROOT/manager-home" "$DECOMP_ROOT/worker-home"
printf 'test specification\n' > "$DECOMP_ROOT/repo/spec.md"
cat > "$DECOMP_ROOT/harness.env" <<ENV
export PROJECT="decompproj"
export REPOSITORY="$DECOMP_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$DECOMP_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$DECOMP_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$DECOMP_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_AUTO_REPLAN_ENABLED="1"
export HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN="1"
ENV
chmod 600 "$DECOMP_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$DECOMP_ROOT/harness.env" >/dev/null
printf 'P0\tBroad criterion\n' > "$DECOMP_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$DECOMP_ROOT/harness.env" "$DECOMP_ROOT/plan.tsv" >/dev/null
cat > "$DECOMP_ROOT/root.md" <<'TASK'
# Task

Task-ID: 001
Root-Criterion: broad.parent
Root-Criterion: final.parent

Implement the broad root.
TASK
"$HARNESS_BIN/manager-publish-task" "$DECOMP_ROOT/harness.env" 001 \
	"$DECOMP_ROOT/root.md" P0 >/dev/null
decomp_project="$DECOMP_ROOT/state/projects/decompproj"
mv "$decomp_project/tasks/decompproj-task-001.ready.md" \
	"$decomp_project/archive/decompproj-task-001.assignment.md"
decomp_progress="$decomp_project/control/progress"
cat > "$decomp_progress/decompproj-task-001.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 001
Triggered-By: 001
Trigger-Outcome: CHECKPOINT
Blocking-Fingerprint: -
MARKER
cat > "$DECOMP_ROOT/children.tsv" <<'TSV'
parent_criterion	child_criterion	title	acceptance_evidence
broad.parent	broad.parse	Parse tranche	focused parse smoke
broad.parent	broad.emit	Emit tranche	focused emit smoke
TSV
cat > "$DECOMP_ROOT/replan.md" <<'TASK'
# Task Assignment

Task-ID: 001-revision-01
Task-Root: 001
Target-Criterion: broad.parse
Worker-Context: FRESH
Replan-Strategy-ID: decomp.strategy.1
Strategy-Change: ISOLATE_CRITERION
Supersedes-Task: 001

## Objective

Isolate the parse tranche of the broad parent.

## Acceptance criteria

- Focused parse evidence passes.

## Validation commands

decomp-focused-parse
TASK
"$HARNESS_BIN/manager-publish-task" "$DECOMP_ROOT/harness.env" 001-revision-01 \
	"$DECOMP_ROOT/replan.md" --auto-replan - "$DECOMP_ROOT/children.tsv" >/dev/null
decomp_file="$decomp_progress/decompproj-task-001.criterion-decomposition.tsv"
[[ "$(wc -l < "$decomp_file")" == 3 ]]
grep -q $'^broad.parent\tbroad.parse\t' "$decomp_file"
(
	source "$DECOMP_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(task_first_unmet_criterion 001)" == broad.parse ]]
	printf 'item_id\tstate\tverified_by\tevidence_sha256\tupdated_at\nbroad.parse\tPASSED\t001-revision-01\tsha256:parse\t2026-07-23T00:00:00Z\n' \
		> "$(task_criterion_ledger_file 001)"
	[[ "$(task_first_unmet_criterion 001)" == broad.emit ]]
	! task_criterion_is_passed 001 broad.parent
)

ACTIVE_ROOT="$TEST_ROOT/active"
mkdir -p "$ACTIVE_ROOT/repo" "$ACTIVE_ROOT/manager-home" "$ACTIVE_ROOT/worker-home"
printf 'test specification\n' > "$ACTIVE_ROOT/repo/spec.md"
git -C "$ACTIVE_ROOT/repo" init -q
git -C "$ACTIVE_ROOT/repo" add spec.md
git -C "$ACTIVE_ROOT/repo" -c user.name=test -c user.email=test@example.invalid commit -qm baseline
cat > "$ACTIVE_ROOT/harness.env" <<ENV
export PROJECT="activeproj"
export REPOSITORY="$ACTIVE_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$ACTIVE_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
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
export HARNESS_POLL_SECONDS="1"
export HARNESS_WAIT_SECONDS="5"
export HARNESS_STALE_SECONDS="30"
export HARNESS_USE_INOTIFY="1"
export WORKER_HEARTBEAT_SECONDS="1"
ENV
chmod 600 "$ACTIVE_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ACTIVE_ROOT/harness.env" >/dev/null
[[ -d "/tmp/activeproj" ]]
"$HARNESS_BIN/harness-supervisor-start" "$ACTIVE_ROOT/harness.env" >/dev/null
"$HARNESS_BIN/worker-supervisor-start" "$ACTIVE_ROOT/harness.env" >/dev/null
printf 'thread_id=existing-thread\n' > "$ACTIVE_ROOT/state/projects/activeproj/control/manager.thread"
sleep 0.2
for supervisor_pid_file in \
	"$ACTIVE_ROOT/state/projects/activeproj/control/supervisor.pid" \
	"$ACTIVE_ROOT/state/projects/activeproj/control/worker-supervisor.pid"; do
	supervisor_pid="$(cat "$supervisor_pid_file")"
	while IFS= read -r child_pid; do
		[[ -z "$child_pid" || ! -e "/proc/$child_pid/fd/8" ]] || {
			printf 'Supervisor child %s inherited the lifetime lock descriptor.\n' "$child_pid" >&2
			exit 1
		}
	done < <(pgrep -P "$supervisor_pid" 2>/dev/null || true)
done

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

"$HARNESS_BIN/harness-start" "$ACTIVE_ROOT/harness.env" >"$ACTIVE_ROOT/start-resume.out" 2>"$ACTIVE_ROOT/start-resume.err"
grep -q 'preserving all state and progress' "$ACTIVE_ROOT/start-resume.out"
grep -q 'Manager thread already exists' "$ACTIVE_ROOT/start-resume.out"
[[ -f "$ACTIVE_ROOT/state/projects/activeproj/control/supervisor.pid" ]]
sleep 1
! grep -q 'SUPERVISOR_FATAL.*wait' "$ACTIVE_ROOT/state/projects/activeproj/logs/events.log"

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
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$INACTIVE_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
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

# An unchanged manager planning gap may consume at most one model invocation.
# Changing durable planning state clears the circuit and permits one new try.
PLAN_GAP_ROOT="$TEST_ROOT/planning-gap"
mkdir -p "$PLAN_GAP_ROOT/repo" "$PLAN_GAP_ROOT/manager-home" "$PLAN_GAP_ROOT/worker-home"
printf 'test specification\n' > "$PLAN_GAP_ROOT/repo/spec.md"
cat > "$PLAN_GAP_ROOT/pending-manager" <<'PENDING_MANAGER'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$1"
count_file="$HARNESS_ROOT/manager-plan-count"
count=0
[[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
printf '%s\n' "$((count + 1))" > "$count_file"
exit 3
PENDING_MANAGER
chmod +x "$PLAN_GAP_ROOT/pending-manager"
cat > "$PLAN_GAP_ROOT/harness.env" <<ENV
export PROJECT="planninggapproj"
export REPOSITORY="$PLAN_GAP_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$PLAN_GAP_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$PLAN_GAP_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$PLAN_GAP_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_MANAGER_PLAN_INVOKER="$PLAN_GAP_ROOT/pending-manager"
export HARNESS_POLL_SECONDS="1"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$PLAN_GAP_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$PLAN_GAP_ROOT/harness.env" >/dev/null
printf 'P0\tPlanning circuit-breaker test\n' > "$PLAN_GAP_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$PLAN_GAP_ROOT/harness.env" "$PLAN_GAP_ROOT/plan.tsv" >/dev/null
"$HARNESS_BIN/harness-supervisor-start" "$PLAN_GAP_ROOT/harness.env" >/dev/null
for _ in $(seq 1 50); do
	[[ -f "$PLAN_GAP_ROOT/state/manager-plan-count" ]] && break
	sleep 0.1
done
sleep 2
"$HARNESS_BIN/harness-supervisor-stop" "$PLAN_GAP_ROOT/harness.env" >/dev/null
[[ "$(cat "$PLAN_GAP_ROOT/state/manager-plan-count")" == 1 ]]
plan_gap_project="$PLAN_GAP_ROOT/state/projects/planninggapproj"
grep -q '^State-Fingerprint: sha256:' "$plan_gap_project/control/manager-plan-stalled.md"
"$HARNESS_BIN/harness-status" --full "$PLAN_GAP_ROOT/harness.env" > "$PLAN_GAP_ROOT/status.out"
grep -Fq 'Project status: PLANNING_STALLED.' "$PLAN_GAP_ROOT/status.out"
printf '# operator repaired planning metadata\n' >> "$plan_gap_project/control/project-plan.tsv"
"$HARNESS_BIN/harness-supervisor-start" "$PLAN_GAP_ROOT/harness.env" >/dev/null
for _ in $(seq 1 50); do
	[[ "$(cat "$PLAN_GAP_ROOT/state/manager-plan-count")" == 2 ]] && break
	sleep 0.1
done
sleep 2
"$HARNESS_BIN/harness-supervisor-stop" "$PLAN_GAP_ROOT/harness.env" >/dev/null
[[ "$(cat "$PLAN_GAP_ROOT/state/manager-plan-count")" == 2 ]]

ORACLE_ROOT="$TEST_ROOT/oracle"
mkdir -p "$ORACLE_ROOT/repo" "$ORACLE_ROOT/manager-home" "$ORACLE_ROOT/worker-home"
printf 'test specification\n' > "$ORACLE_ROOT/repo/spec.md"
cat > "$ORACLE_ROOT/harness.env" <<ENV
export PROJECT="oracleproj"
export REPOSITORY="$ORACLE_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$ORACLE_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$ORACLE_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$ORACLE_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export ORACLE_MODEL="gpt-5.6-sol"
ENV
chmod 600 "$ORACLE_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ORACLE_ROOT/harness.env" >/dev/null
printf 'P0\tOracle completion test\n' > "$ORACLE_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$ORACLE_ROOT/harness.env" "$ORACLE_ROOT/plan.tsv" >/dev/null
sed -i 's/^P0\tPENDING/P0\tCOMPLETE/' "$ORACLE_ROOT/state/projects/oracleproj/control/project-plan-state.tsv"
mkdir -p "$ORACLE_ROOT/state/projects/oracleproj/control/oracle"
printf '# Oracle Audit Pending\n\nProject: oracleproj\n\nAudit-ID: 1\n' > "$ORACLE_ROOT/state/projects/oracleproj/control/oracle/oracle.pending.md"
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"Oracle focused acceptance check is running."}}' > "$ORACLE_ROOT/state/projects/oracleproj/logs/oracle-audit-1-20260714T000000Z-attempt-001.jsonl"
timeout 2 "$HARNESS_BIN/harness-watch-agents" "$ORACLE_ROOT/harness.env" > "$ORACLE_ROOT/watch.out" 2>&1 || true
grep -q 'ORACLE task=final-audit-1' "$ORACLE_ROOT/watch.out"
grep -q 'Oracle focused acceptance check is running.' "$ORACLE_ROOT/watch.out"
cat > "$ORACLE_ROOT/verdict-pass.md" <<'VERDICT'
# Oracle Audit Verdict

Decision: PASS

## Traceability verification

All original requirements are accounted for.

## Acceptance verification

All acceptance checks passed.

## Findings

None.

## Conclusion

The implementation is compliant.
VERDICT
"$HARNESS_BIN/oracle-invoke-final-audit" "$ORACLE_ROOT/harness.env" >/dev/null
oracle_prompt="$ORACLE_ROOT/state/projects/oracleproj/control/oracle-audit-1.prompt.md"
grep -q 'at least one `Original-Requirement-ID: ...`' "$oracle_prompt"
grep -q '`Remediation-Authority: AUTOMATIC`' "$oracle_prompt"
grep -q '`HUMAN_APPROVAL`' "$oracle_prompt"
grep -Fq 'Read ORACLE_CONTEXT_CAPSULE exactly once.' "$oracle_prompt"
grep -Fq 'do not read repository inventories, prior wave or master plans' "$oracle_prompt"
oracle_capsule="$ORACLE_ROOT/state/projects/oracleproj/control/oracle-audit-1.context.md"
grep -Fq '# Bounded Final Oracle Context' "$oracle_capsule"
grep -Fq '## Executable acceptance boundaries' "$oracle_capsule"
grep -q 'exclusive-file.*baseline-prerequisite repair' "$oracle_prompt"
grep -q '^Human-Dependency-Class: HUMAN_AUTHORIZATION|HUMAN_SECRET|HUMAN_EXTERNAL_STATE|HUMAN_PRODUCT_SPECIFICATION$' "$oracle_prompt"
[[ "$(cat "$ORACLE_ROOT/state/mock-counts/oracle-1")" == 3 ]]
grep -q 'ORACLE_TERRA_NARROW_RETRY audit_id=1 classification=model_refusal_or_blocked_content attempt=2' \
	"$ORACLE_ROOT/state/projects/oracleproj/logs/events.log"
grep -q 'ORACLE_MODEL_FALLBACK audit_id=1 classification=model_refusal_or_blocked_content attempt=3 model=gpt-5.6-terra' \
	"$ORACLE_ROOT/state/projects/oracleproj/logs/events.log"
[[ -f "$ORACLE_ROOT/state/projects/oracleproj/control/project.complete" ]]
[[ ! -f "$ORACLE_ROOT/state/projects/oracleproj/control/oracle/oracle.pending.md" ]]

# A deterministic Oracle launcher failure is attempted only once per unchanged
# pending audit during one supervisor run. Provider retries remain internal to
# oracle-invoke-final-audit.
ORACLE_RETRY_ROOT="$TEST_ROOT/oracle-retry"
mkdir -p "$ORACLE_RETRY_ROOT/repo" "$ORACLE_RETRY_ROOT/manager-home" \
	"$ORACLE_RETRY_ROOT/worker-home"
printf 'test specification\n' > "$ORACLE_RETRY_ROOT/repo/spec.md"
cat > "$ORACLE_RETRY_ROOT/failing-oracle" <<'FAIL_ORACLE'
#!/usr/bin/env bash
set -Eeuo pipefail
env_file="$1"
source "$env_file"
count_file="$HARNESS_ROOT/oracle-invocation-count"
count=0
[[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
printf '%s\n' "$((count + 1))" > "$count_file"
exit 7
FAIL_ORACLE
chmod +x "$ORACLE_RETRY_ROOT/failing-oracle"
cat > "$ORACLE_RETRY_ROOT/harness.env" <<ENV
export PROJECT="oracleretryproj"
export REPOSITORY="$ORACLE_RETRY_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$ORACLE_RETRY_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$ORACLE_RETRY_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$ORACLE_RETRY_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export ORACLE_MODEL="gpt-5.6-sol"
export HARNESS_ORACLE_INVOKER="$ORACLE_RETRY_ROOT/failing-oracle"
export HARNESS_POLL_SECONDS="1"
ENV
chmod 600 "$ORACLE_RETRY_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ORACLE_RETRY_ROOT/harness.env" >/dev/null
printf 'P0\tOracle retry suppression test\n' > "$ORACLE_RETRY_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$ORACLE_RETRY_ROOT/harness.env" \
	"$ORACLE_RETRY_ROOT/plan.tsv" >/dev/null
sed -i 's/^P0\tPENDING/P0\tCOMPLETE/' \
	"$ORACLE_RETRY_ROOT/state/projects/oracleretryproj/control/project-plan-state.tsv"
mkdir -p "$ORACLE_RETRY_ROOT/state/projects/oracleretryproj/control/oracle"
printf '# Oracle Audit Pending\n\nProject: oracleretryproj\n\nAudit-ID: 1\n' > \
	"$ORACLE_RETRY_ROOT/state/projects/oracleretryproj/control/oracle/oracle.pending.md"
"$HARNESS_BIN/harness-supervisor-start" "$ORACLE_RETRY_ROOT/harness.env" >/dev/null
for _ in $(seq 1 50); do
	[[ -f "$ORACLE_RETRY_ROOT/state/oracle-invocation-count" ]] && break
	sleep 0.1
done
sleep 2
"$HARNESS_BIN/harness-supervisor-stop" "$ORACLE_RETRY_ROOT/harness.env" >/dev/null
[[ "$(cat "$ORACLE_RETRY_ROOT/state/oracle-invocation-count")" == 1 ]]
oracle_failure_alert="$ORACLE_RETRY_ROOT/state/projects/oracleretryproj/control/oracle/oracle-invocation-failed.md"
grep -q '^Exit-Status: 7$' "$oracle_failure_alert"
[[ "$(grep -c 'SUPERVISOR_ORACLE_FAILED' \
	"$ORACLE_RETRY_ROOT/state/projects/oracleretryproj/logs/events.log")" == 1 ]]
"$HARNESS_BIN/harness-status" --full "$ORACLE_RETRY_ROOT/harness.env" > "$ORACLE_RETRY_ROOT/status.out"
grep -Fq "Oracle audit: INVOCATION_FAILED ($oracle_failure_alert)" "$ORACLE_RETRY_ROOT/status.out"
grep -Fq 'Project status: ORACLE_AUDIT_FAILED.' "$ORACLE_RETRY_ROOT/status.out"
! grep -q '^Oracle audit: PENDING$' "$ORACLE_RETRY_ROOT/status.out"

ORACLE_FAIL_ROOT="$TEST_ROOT/oracle-fail"
mkdir -p "$ORACLE_FAIL_ROOT/repo" "$ORACLE_FAIL_ROOT/manager-home" "$ORACLE_FAIL_ROOT/worker-home"
printf 'test specification\n' > "$ORACLE_FAIL_ROOT/repo/spec.md"
cat > "$ORACLE_FAIL_ROOT/harness.env" <<ENV
export PROJECT="oraclefailproj"
export REPOSITORY="$ORACLE_FAIL_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$ORACLE_FAIL_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$ORACLE_FAIL_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$ORACLE_FAIL_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export ORACLE_MODEL="gpt-5.6-sol"
ENV
chmod 600 "$ORACLE_FAIL_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ORACLE_FAIL_ROOT/harness.env" >/dev/null
printf 'P0\tOracle remediation test\n' > "$ORACLE_FAIL_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$ORACLE_FAIL_ROOT/harness.env" "$ORACLE_FAIL_ROOT/plan.tsv" >/dev/null
sed -i 's/^P0\tPENDING/P0\tCOMPLETE/' "$ORACLE_FAIL_ROOT/state/projects/oraclefailproj/control/project-plan-state.tsv"
mkdir -p "$ORACLE_FAIL_ROOT/state/projects/oraclefailproj/control/oracle"
printf '# Oracle Audit Pending\n\nProject: oraclefailproj\n\nAudit-ID: 1\n' > "$ORACLE_FAIL_ROOT/state/projects/oraclefailproj/control/oracle/oracle.pending.md"
sed 's/Decision: PASS/Decision: FAIL/; s/None\./A required behavior is incomplete./; s/The implementation is compliant./Remediation is required./' "$ORACLE_ROOT/verdict-pass.md" > "$ORACLE_FAIL_ROOT/verdict-fail.md"
{
	printf '# Specification Addendum\n\n'
	printf 'Original-Requirement-ID: REQ-ORACLE-1\n'
	printf 'Remediation-Authority: AUTOMATIC\n\n'
	printf 'The original requirement remains authoritative. This addendum adds the missing remediation.\n\n'
	printf '## Harness plan items\n\n'
	printf 'ORACLE-001-01\tImplement and verify the missing behavior\n'
} > "$ORACLE_FAIL_ROOT/addendum.md"
"$HARNESS_BIN/oracle-complete-audit" "$ORACLE_FAIL_ROOT/harness.env" "$ORACLE_FAIL_ROOT/verdict-fail.md" "$ORACLE_FAIL_ROOT/addendum.md" >/dev/null
grep -Fqx $'ORACLE-001-01\tImplement and verify the missing behavior' "$ORACLE_FAIL_ROOT/state/projects/oraclefailproj/control/project-plan.tsv"
grep -Eq $'^ORACLE-001-01\tPENDING\t-' "$ORACLE_FAIL_ROOT/state/projects/oraclefailproj/control/project-plan-state.tsv"
[[ ! -f "$ORACLE_FAIL_ROOT/state/projects/oraclefailproj/control/project.complete" ]]
[[ ! -f "$ORACLE_FAIL_ROOT/state/projects/oraclefailproj/control/oracle/oracle.pending.md" ]]

ORACLE_HUMAN_ROOT="$TEST_ROOT/oracle-human"
mkdir -p "$ORACLE_HUMAN_ROOT/repo" "$ORACLE_HUMAN_ROOT/manager-home" \
	"$ORACLE_HUMAN_ROOT/worker-home"
printf 'test specification\n' > "$ORACLE_HUMAN_ROOT/repo/spec.md"
cat > "$ORACLE_HUMAN_ROOT/harness.env" <<ENV
export PROJECT="oraclehumanproj"
export REPOSITORY="$ORACLE_HUMAN_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$ORACLE_HUMAN_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$ORACLE_HUMAN_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$ORACLE_HUMAN_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export ORACLE_MODEL="gpt-5.6-sol"
ENV
chmod 600 "$ORACLE_HUMAN_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ORACLE_HUMAN_ROOT/harness.env" >/dev/null
printf 'P0\tOracle human-dependency validation test\n' > "$ORACLE_HUMAN_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$ORACLE_HUMAN_ROOT/harness.env" \
	"$ORACLE_HUMAN_ROOT/plan.tsv" >/dev/null
sed -i 's/^P0\tPENDING/P0\tCOMPLETE/' \
	"$ORACLE_HUMAN_ROOT/state/projects/oraclehumanproj/control/project-plan-state.tsv"
mkdir -p "$ORACLE_HUMAN_ROOT/state/projects/oraclehumanproj/control/oracle"
printf '# Oracle Audit Pending\n\nProject: oraclehumanproj\n\nAudit-ID: 1\n' > \
	"$ORACLE_HUMAN_ROOT/state/projects/oraclehumanproj/control/oracle/oracle.pending.md"
sed 's/Decision: PASS/Decision: FAIL/; s/None\\./A governing product decision is unresolved./; s/The implementation is compliant./A governing decision is required./' \
	"$ORACLE_ROOT/verdict-pass.md" > "$ORACLE_HUMAN_ROOT/verdict-fail.md"
cat > "$ORACLE_HUMAN_ROOT/addendum.md" <<'ADDENDUM'
# Oracle Audit Addendum

Original-Requirement-ID: REQ-ORACLE-HUMAN-1
Remediation-Authority: HUMAN_APPROVAL
Human-Dependency-Class: LOCAL_SCOPE_PREREQUISITE
Human-Dependency-Evidence: a worker-exclusive file must be repaired
ADDENDUM
if "$HARNESS_BIN/oracle-complete-audit" "$ORACLE_HUMAN_ROOT/harness.env" \
	"$ORACLE_HUMAN_ROOT/verdict-fail.md" "$ORACLE_HUMAN_ROOT/addendum.md" \
	>"$ORACLE_HUMAN_ROOT/local-scope.out" 2>"$ORACLE_HUMAN_ROOT/local-scope.err"; then
	printf 'Oracle scope-only HUMAN_APPROVAL unexpectedly passed validation.\n' >&2
	exit 1
fi
grep -q 'repository-local scope, ownership, build, testability, integration, and baseline prerequisites are AUTOMATIC' \
	"$ORACLE_HUMAN_ROOT/local-scope.err"
[[ -f "$ORACLE_HUMAN_ROOT/state/projects/oraclehumanproj/control/oracle/oracle.pending.md" ]]
[[ ! -f "$ORACLE_HUMAN_ROOT/state/projects/oraclehumanproj/control/project.blocked.md" ]]
sed -i 's/Human-Dependency-Class: LOCAL_SCOPE_PREREQUISITE/Human-Dependency-Class: HUMAN_PRODUCT_SPECIFICATION/; s/a worker-exclusive file must be repaired/the governing specification does not choose an observable behavior/' \
	"$ORACLE_HUMAN_ROOT/addendum.md"
if "$HARNESS_BIN/oracle-complete-audit" "$ORACLE_HUMAN_ROOT/harness.env" \
	"$ORACLE_HUMAN_ROOT/verdict-fail.md" "$ORACLE_HUMAN_ROOT/addendum.md" \
	>"$ORACLE_HUMAN_ROOT/product-missing.out" 2>"$ORACLE_HUMAN_ROOT/product-missing.err"; then
	printf 'Oracle product HUMAN_APPROVAL without outcome evidence unexpectedly passed validation.\n' >&2
	exit 1
fi
grep -q 'must contain exactly one Product-Decision-Evidence line' \
	"$ORACLE_HUMAN_ROOT/product-missing.err"
printf '%s\n' 'Product-Decision-Evidence: public API returns legacy values or normalized values, and the specification does not choose between them' \
	>> "$ORACLE_HUMAN_ROOT/addendum.md"
"$HARNESS_BIN/oracle-complete-audit" "$ORACLE_HUMAN_ROOT/harness.env" \
	"$ORACLE_HUMAN_ROOT/verdict-fail.md" "$ORACLE_HUMAN_ROOT/addendum.md" >/dev/null
oracle_human_project="$ORACLE_HUMAN_ROOT/state/projects/oraclehumanproj"
grep -q '^Human-Dependency-Class: HUMAN_PRODUCT_SPECIFICATION$' \
	"$oracle_human_project/control/project.blocked.md"
grep -q '^Product-Decision-Evidence: public API returns legacy values or normalized values' \
	"$oracle_human_project/control/project.blocked.md"
"$HARNESS_BIN/harness-unblock-project" "$ORACLE_HUMAN_ROOT/harness.env" \
	> "$ORACLE_HUMAN_ROOT/unblock.out"
[[ ! -f "$oracle_human_project/control/project.blocked.md" ]]
grep -q '^Audit-ID: 2$' "$oracle_human_project/control/oracle/oracle.pending.md"
grep -q '^Triggered-By-Task: oracle-unblock-1$' \
	"$oracle_human_project/control/oracle/oracle.pending.md"
grep -q 'fresh Oracle audit is pending' "$ORACLE_HUMAN_ROOT/unblock.out"
grep -q 'PROJECT_UNBLOCKED source=operator-oracle-retry prior_audit_id=1 oracle_requeued=1' \
	"$oracle_human_project/logs/events.log"
"$HARNESS_BIN/harness-status" --full "$ORACLE_HUMAN_ROOT/harness.env" \
	> "$ORACLE_HUMAN_ROOT/status.out"
grep -q '^Oracle audit: PENDING$' "$ORACLE_HUMAN_ROOT/status.out"
grep -Fq 'Project status: ORACLE_AUDIT.' "$ORACLE_HUMAN_ROOT/status.out"

ORACLE_BUDGET_ROOT="$TEST_ROOT/oracle-budget"
mkdir -p "$ORACLE_BUDGET_ROOT/repo" "$ORACLE_BUDGET_ROOT/manager-home" \
	"$ORACLE_BUDGET_ROOT/worker-home"
printf 'test specification\n' > "$ORACLE_BUDGET_ROOT/repo/spec.md"
cat > "$ORACLE_BUDGET_ROOT/harness.env" <<ENV
export PROJECT="oraclebudgetproj"
export REPOSITORY="$ORACLE_BUDGET_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_ROOT="$ORACLE_BUDGET_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$ORACLE_BUDGET_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$ORACLE_BUDGET_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export ORACLE_MODEL="gpt-5.6-sol"
export MAX_ORACLE_RUNS="1"
ENV
chmod 600 "$ORACLE_BUDGET_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ORACLE_BUDGET_ROOT/harness.env" >/dev/null
printf 'P0\tOracle audit budget test\n' > "$ORACLE_BUDGET_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$ORACLE_BUDGET_ROOT/harness.env" \
	"$ORACLE_BUDGET_ROOT/plan.tsv" >/dev/null
sed -i 's/^P0\tPENDING/P0\tCOMPLETE/' \
	"$ORACLE_BUDGET_ROOT/state/projects/oraclebudgetproj/control/project-plan-state.tsv"
bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	ensure_project
	mark_project_awaiting_oracle budget-seed
' bash "$HARNESS_HOME" "$ORACLE_BUDGET_ROOT/harness.env"
oracle_budget_project="$ORACLE_BUDGET_ROOT/state/projects/oraclebudgetproj"
grep -q '^Audit-ID: 1$' "$oracle_budget_project/control/oracle/oracle.pending.md"
sed 's/Decision: PASS/Decision: FAIL/; s/None\./A bounded remediation is required./; s/The implementation is compliant./A bounded remediation is required./' \
	"$ORACLE_ROOT/verdict-pass.md" > "$ORACLE_BUDGET_ROOT/verdict-fail.md"
cat > "$ORACLE_BUDGET_ROOT/addendum.md" <<'ADDENDUM'
# Oracle Audit Addendum

Original-Requirement-ID: REQ-ORACLE-BUDGET-1
Remediation-Authority: AUTOMATIC

## Harness plan items
ORACLE-BUDGET-01	Implement the bounded remediation
ADDENDUM
"$HARNESS_BIN/oracle-complete-audit" "$ORACLE_BUDGET_ROOT/harness.env" \
	"$ORACLE_BUDGET_ROOT/verdict-fail.md" "$ORACLE_BUDGET_ROOT/addendum.md" >/dev/null
sed -i 's/^ORACLE-BUDGET-01\tPENDING/ORACLE-BUDGET-01\tCOMPLETE/' \
	"$oracle_budget_project/control/project-plan-state.tsv"
"$HARNESS_BIN/harness-supervisor" "$ORACLE_BUDGET_ROOT/harness.env" >/dev/null
[[ -f "$oracle_budget_project/control/project.complete" ]]
[[ -f "$oracle_budget_project/control/oracle/oracle-run-limit.md" ]]
[[ ! -f "$oracle_budget_project/control/oracle/oracle.pending.md" ]]
grep -q '^Max-Oracle-Runs: 1$' "$oracle_budget_project/control/oracle/oracle-run-limit.md"
grep -q 'ORACLE_AUDIT_LIMIT_REACHED max_runs=1 completed_runs=1' \
	"$oracle_budget_project/logs/events.log"
"$HARNESS_BIN/harness-status" --full "$ORACLE_BUDGET_ROOT/harness.env" > "$ORACLE_BUDGET_ROOT/status.out"
grep -q '^Oracle audit: RUN_LIMIT_REACHED ' "$ORACLE_BUDGET_ROOT/status.out"
grep -q '^Project status: COMPLETE_WITH_ORACLE_LIMIT\.' "$ORACLE_BUDGET_ROOT/status.out"

printf 'All v4.4 harness tests passed.\n'
