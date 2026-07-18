#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/coding-harness-v4.2-test.XXXXXX)"
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

printf '{"type":"thread.started","thread_id":"%s"}\n' "${resume_thread_id:-mock-thread-001}"
printf '{"type":"turn.started"}\n'
HARNESS_BIN="$(value HARNESS_BIN)"
final_message="done"
if [[ "$kind" == bootstrap ]]; then
	plan="$(mktemp)"
	printf 'phase-1\tMock first phase\nphase-2\tMock second phase\n' > "$plan"
	"$HARNESS_BIN/manager-init-project-plan" "$ENV_FILE" "$plan" >/dev/null
	tmp="$(mktemp)"
	printf '# Task\n\nTask-ID: 001\n\nMock first task.\n' > "$tmp"
	"$HARNESS_BIN/manager-publish-task" "$ENV_FILE" 001 "$tmp" phase-1 >/dev/null
	rm -f "$tmp" "$plan"
elif [[ "$kind" == plan ]]; then
	tmp="$(mktemp)"
	printf '# Task\n\nTask-ID: 002\n\nMock second task.\n' > "$tmp"
	"$HARNESS_BIN/manager-publish-task" "$ENV_FILE" 002 "$tmp" phase-2 >/dev/null
	rm -f "$tmp"
elif [[ "$kind" == review ]]; then
	TASK_ID="$(value TASK_ID)"
	if [[ "$TASK_ID" == 002 && "$count" == 1 ]]; then
		final_message="review-left-pending"
	elif [[ "$TASK_ID" == 002 && "$count" == 2 ]]; then
		note="$(mktemp)"
		cat > "$note" <<NOTE
# Manager Review Record

Task-ID: $TASK_ID
Decision: ACCEPT

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
	final_message="$(printf '# Task Result\n\nTask-ID: %s\nStatus: COMPLETED\n\n## Summary\n\nMock implementation.\n\n## Modified files\n\n- mock-file\n\n## Implemented behavior\n\n- Mock behavior.\n\n## Validation performed\n\nMock test passed.\n\n## Deviations from assignment\n\nNone.\n\n## Remaining concerns\n\nNone.\n\n## Worker assessment\n\nReady for manager review.\n' "$TASK_ID")"
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
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
ENV
chmod 600 "$TEST_ROOT/harness.env"

"$HARNESS_BIN/harness-check-env" "$TEST_ROOT/harness.env" > "$TEST_ROOT/check-env.out"
grep -q 'Codex wall timeout seconds: 0 (0 means unlimited)' "$TEST_ROOT/check-env.out"
grep -q 'Codex idle timeout seconds: 0 (0 means unlimited)' "$TEST_ROOT/check-env.out"
grep -q 'Deterministic blocker circuit breaker: disabled' "$TEST_ROOT/check-env.out"
grep -q 'Rejected-root worker thread reuse: enabled' "$TEST_ROOT/check-env.out"
grep -q 'Worker thread rejection rotation: 8 retained rejections' "$TEST_ROOT/check-env.out"
grep -q 'Bounded closure mode: enabled at 95% (2 fixes, 3 focused-smoke runs)' "$TEST_ROOT/check-env.out"
grep -q 'revisions remain automatic unless the circuit breaker is explicitly enabled' "$TEST_ROOT/check-env.out"
grep -q 'Transient provider retry seconds: 1 (retries unlimited)' "$TEST_ROOT/check-env.out"
grep -q 'Quota retry seconds: 1 (retries unlimited)' "$TEST_ROOT/check-env.out"
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
grep -q 'SUPERVISOR_REVIEW_LEFT_UNCOMMITTED task=002' "$EVENTS"
grep -q 'WORKER_SUPERVISOR_TRIGGER task=001' "$EVENTS"
grep -q 'WORKER_DIRECT_RESULT_NORMALIZED task=001' "$EVENTS"
grep -q 'WORKER_LAST_MESSAGE_RESULT_NORMALIZED task=002' "$EVENTS"
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
printf '# Task\n\nTask-ID: %s\n' "$task_id" > "$fixture_task"
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
printf '# Task\n\nTask-ID: 004\n' > "$fixture_task"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 004 "$fixture_task" fixture-004 >/dev/null
rm -f "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-004.ready.md"
for revision in 01 02 03 04 05 06 07 08 09 10; do
	printf 'Improvement-Percent: 0%%\n' > "$TEST_ROOT/state/projects/testproj/archive/testproj-task-004-revision-$revision.rejected.md"
done
revision_task="$TEST_ROOT/revision-task.md"
printf '# Task\n' > "$revision_task"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 004-revision-11 "$revision_task" >/dev/null
grep -q '^Starting-Progress: 0%$' "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-004-revision-11.ready.md"
watch_output="$TEST_ROOT/watch-agents.out"
timeout 2 "$HARNESS_BIN/harness-watch-agents" "$TEST_ROOT/harness.env" > "$watch_output" 2>&1 &
watch_pid=$!
sleep 0.3
printf 'Progress-Percent: 0%%\nImprovement-Percent: 0%%\n' > "$TEST_ROOT/state/projects/testproj/archive/testproj-task-004-revision-12.rejected.md"
wait "$watch_pid" || true
grep -q 'MANAGER REJECTED task=004-revision-12' "$watch_output"
! grep -q 'MANAGER REJECTED task=004-revision-10' "$watch_output"
grep -q 'Improvement: 0%' "$watch_output"
rm -f "$TEST_ROOT/state/projects/testproj/tasks/testproj-task-004-revision-11.ready.md"
sed -i 's/^fixture-004\tACTIVE\t004\t/fixture-004\tCOMPLETE\t004\t/' \
	"$TEST_ROOT/state/projects/testproj/control/project-plan-state.tsv"

# Cumulative progress is durable and is injected into each continuation.
progress_task="$TEST_ROOT/progress-task.md"
printf '# Task\n\nTask-ID: 005\n\nImplement one prototype feature.\n' > "$progress_task"
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
"$HARNESS_BIN/harness-status" "$TEST_ROOT/harness.env" > "$TEST_ROOT/progress-status.out"
grep -Eq '005-revision-01 +READY +50%' "$TEST_ROOT/progress-status.out"
expected_task_order=$'003\n002\n001\n005-revision-01'
actual_task_order="$(awk '$1 ~ /^(001|002|003|005-revision-01)$/ {print $1}' \
	"$TEST_ROOT/progress-status.out")"
[[ "$actual_task_order" == "$expected_task_order" ]]
tail -n 1 "$TEST_ROOT/progress-status.out" | grep -Eq '^Project progress: [0-9]+% \([0-9]+/[0-9]+ plan items complete\)$'

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

# An opt-in circuit breaker still works, but the blocking command independently
# refuses an early intervention before the configured fingerprint threshold.
CIRCUIT_ROOT="$TEST_ROOT/circuit"
mkdir -p "$CIRCUIT_ROOT/repo" "$CIRCUIT_ROOT/manager-home" "$CIRCUIT_ROOT/worker-home"
printf 'test specification\n' > "$CIRCUIT_ROOT/repo/spec.md"
cat > "$CIRCUIT_ROOT/harness.env" <<ENV
export PROJECT="circuitproj"
export REPOSITORY="$CIRCUIT_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$CIRCUIT_ROOT/state"
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
printf '# Task\n\nTask-ID: 001\n' > "$CIRCUIT_ROOT/task.md"
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
[[ "$circuit_output" == *.blocked.md ]]
[[ -f "$CIRCUIT_ROOT/state/projects/circuitproj/archive/circuitproj-task-001-revision-01.blocked.md" ]]
[[ -f "$CIRCUIT_ROOT/state/projects/circuitproj/control/progress/circuitproj-task-001.blocked.md" ]]
grep -q 'TASK_CIRCUIT_BREAKER task=001-revision-01' \
	"$CIRCUIT_ROOT/state/projects/circuitproj/logs/events.log"

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
export HARNESS_ROOT="$CONTEXT_ROOT/state"
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
printf '# Task\n\nTask-ID: 001\n' > "$CONTEXT_ROOT/task.md"
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

printf '# Task\n\nTask-ID: 001-revision-03\nWorker-Context: FRESH\n' > \
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

ORACLE_ROOT="$TEST_ROOT/oracle"
mkdir -p "$ORACLE_ROOT/repo" "$ORACLE_ROOT/manager-home" "$ORACLE_ROOT/worker-home"
printf 'test specification\n' > "$ORACLE_ROOT/repo/spec.md"
cat > "$ORACLE_ROOT/harness.env" <<ENV
export PROJECT="oracleproj"
export REPOSITORY="$ORACLE_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$ORACLE_ROOT/state"
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
export HARNESS_ROOT="$ORACLE_RETRY_ROOT/state"
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

ORACLE_FAIL_ROOT="$TEST_ROOT/oracle-fail"
mkdir -p "$ORACLE_FAIL_ROOT/repo" "$ORACLE_FAIL_ROOT/manager-home" "$ORACLE_FAIL_ROOT/worker-home"
printf 'test specification\n' > "$ORACLE_FAIL_ROOT/repo/spec.md"
cat > "$ORACLE_FAIL_ROOT/harness.env" <<ENV
export PROJECT="oraclefailproj"
export REPOSITORY="$ORACLE_FAIL_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$ORACLE_FAIL_ROOT/state"
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

printf 'All v4.2 harness tests passed.\n'
