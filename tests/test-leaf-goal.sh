#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/coding-harness-leaf-goal-test.XXXXXX)"
cleanup()
{
	if [[ "${KEEP_TEST_ROOT:-0}" == 1 ]]; then
		printf 'Preserved failed test state: %s\n' "$TEST_ROOT" >&2
	else
		rm -rf "$TEST_ROOT"
	fi
}
trap cleanup EXIT

mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'leaf goal test specification\n' > "$TEST_ROOT/repo/spec.md"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name 'Harness Test'
git -C "$TEST_ROOT/repo" config user.email 'harness@example.invalid'
git -C "$TEST_ROOT/repo" add spec.md
git -C "$TEST_ROOT/repo" commit -qm baseline

ARGS_LOG="$TEST_ROOT/mock-args.log"
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
	if [[ "$capture_next" == 1 ]]; then
		last_message_file="$arg"
		capture_next=0
	elif [[ "$capture_resume" == 1 ]]; then
		resume_thread_id="$arg"
		capture_resume=0
	elif [[ "$arg" == --output-last-message ]]; then
		capture_next=1
	elif [[ "$arg" == resume ]]; then
		capture_resume=1
	fi
done
value()
{
	local key="$1"
	printf '%s\n' "$prompt" | awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}'
}
ENV_FILE="$(value ENV_FILE)"
HARNESS_BIN="$(value HARNESS_BIN)"
TASK_ID="$(value TASK_ID)"
SESSION="$(value SESSION)"
GOAL_ID="$(value GOAL_ID)"
GOAL_STATE_FILE="$(value GOAL_STATE_FILE)"
PROJECT_TMP_DIR="$(value PROJECT_TMP_DIR)"
source "$ENV_FILE"
if printf '%s\n' "$prompt" | grep -q 'You are the final Oracle auditor'; then
	AUDIT_ID="$(value AUDIT_ID)"
	verdict="$PROJECT_TMP_DIR/goal-oracle-verdict.md"
	cat > "$verdict" <<'VERDICT'
# Oracle Audit Verdict

Decision: PASS

## Traceability verification

Both leaf criteria have durable evidence.

## Acceptance verification

The accepted root and project plan are complete.

## Findings

None.

## Conclusion

The goal-mode canary is acceptance-complete.
VERDICT
	"$HARNESS_BIN/oracle-complete-audit" "$ENV_FILE" "$verdict" >/dev/null
	[[ -z "$last_message_file" ]] || printf 'oracle passed\n' > "$last_message_file"
	printf '{"type":"thread.started","thread_id":"goal-oracle-thread"}\n'
	printf '{"type":"item.completed","item":{"type":"agent_message","text":"oracle passed"}}\n'
	printf '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}\n'
	exit 0
fi
count_file="$HARNESS_ROOT/goal-mock-count"
count=0
[[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"

if (( count == 1 )); then
	printf '{"type":"turn.failed","error":{"code":"model_capacity","message":"temporary provider capacity"}}\n'
	exit 1
fi
printf '{"type":"thread.started","thread_id":"%s"}\n' "${resume_thread_id:-goal-thread-001}"
printf '{"type":"turn.started"}\n'
if (( count == 2 )); then
	before_boundary="$(awk -F= '$1 == "last_boundary" {sub(/^[^=]*=/, ""); print; exit}' "$GOAL_STATE_FILE")"
	before_workspace="$(awk -F= '$1 == "last_workspace" {sub(/^[^=]*=/, ""); print; exit}' "$GOAL_STATE_FILE")"
	printf 'implemented leaf behavior\n' > "$REPOSITORY/goal-output.txt"
	after_workspace="$("$HARNESS_BIN/harness-workspace-fingerprint" "$ENV_FILE")"
	bad_receipt="$PROJECT_TMP_DIR/bad-goal-receipt.md"
	cat > "$bad_receipt" <<BAD
# Worker Goal Iteration

Task-ID: $TASK_ID
Goal-ID: $GOAL_ID
Iteration: 1
Outcome: CONTINUE
Boundary-Before: $before_boundary
Boundary-After: focused-validation-ready
Workspace-Fingerprint-Before: $before_workspace
Workspace-Fingerprint-After: sha256:bad

## Progress made

Implemented the focused behavior.

## Validation performed

Affected build passed.

## Next bounded action

Run the focused validation.

## Scope check

Stayed inside the assigned file.
BAD
	if "$HARNESS_BIN/worker-continue-task" "$ENV_FILE" "$TASK_ID" "$SESSION" "$bad_receipt" >/dev/null 2>&1; then
		printf 'invalid workspace fingerprint was accepted\n' >&2
		exit 91
	fi
	receipt="$PROJECT_TMP_DIR/goal-receipt.md"
	sed "s/Workspace-Fingerprint-After: sha256:bad/Workspace-Fingerprint-After: $after_workspace/" \
		"$bad_receipt" > "$receipt"
	"$HARNESS_BIN/worker-continue-task" "$ENV_FILE" "$TASK_ID" "$SESSION" "$receipt" >/dev/null
	final_message='goal iteration committed'
else
	final_message="$(printf '# Task Result\n\nTask-ID: %s\nStatus: COMPLETED\nGoal-ID: %s\nGoal-Outcome: COMPLETE\n\n## Summary\n\nLeaf goal completed across two worker turns.\n\n## Modified files\n\n- goal-output.txt\n\n## Implemented behavior\n\nFocused behavior is present.\n\n## Validation performed\n\nFocused validation passed.\n\n## Deviations from assignment\n\nNone.\n\n## Remaining concerns\n\nNone.\n\n## Worker assessment\n\nGoal success evidence passes.\n' "$TASK_ID" "$GOAL_ID")"
fi
[[ -z "$last_message_file" ]] || printf '%s\n' "$final_message" > "$last_message_file"
printf '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}\n'
printf '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}\n'
MOCK
chmod 755 "$TEST_ROOT/mock-codex"

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="goalproj"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export ORACLE_MODEL="mock-oracle"
export ORACLE_CODEX_HOME="$TEST_ROOT/manager-home"
export ORACLE_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS="3"
export HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS="8"
export HARNESS_GOAL_PROCESS_MAX_FIXES="3"
export HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS="4"
export WORKER_HEARTBEAT_SECONDS="1"
export HARNESS_USE_INOTIFY="0"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
ENV
chmod 600 "$TEST_ROOT/harness.env"

"$HARNESS_BIN/harness-check-env" "$TEST_ROOT/harness.env" > "$TEST_ROOT/check-env.out"
grep -q 'Worker leaf-goal mode: enabled (3 identical iterations, context rotation every 8 iterations)' "$TEST_ROOT/check-env.out"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
printf 'P0\tLeaf goal behavior\n' > "$TEST_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" "$TEST_ROOT/plan.tsv" >/dev/null

cat > "$TEST_ROOT/invalid-task.md" <<'TASK'
# Invalid Goal Task

Task-ID: 001
Execution-Mode: LEAF_GOAL
Root-Criterion: goal.behavior
Root-Criterion: goal.validation
Target-Criterion: goal.behavior
TASK
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 \
	"$TEST_ROOT/invalid-task.md" P0 >"$TEST_ROOT/invalid.out" 2>"$TEST_ROOT/invalid.err"; then
	printf 'goal assignment missing required fields was accepted\n' >&2
	exit 1
fi
grep -q 'goal-mode assignment must contain exactly one Goal-ID line' "$TEST_ROOT/invalid.err"

cat > "$TEST_ROOT/task.md" <<'TASK'
# Leaf Goal Task

Task-ID: 001
Task-Root: 001
Execution-Mode: LEAF_GOAL
Goal-ID: goal.001.behavior
Root-Criterion: goal.behavior
Root-Criterion: goal.validation
Target-Criterion: goal.behavior
Goal-Success-Evidence: goal-output.txt exists and the focused validation passes
Focused-Validation: test -s goal-output.txt
Allowed-Scope: goal-output.txt
Baseline-Boundary: goal-output-missing
Hard-Block-Conditions: explicit specification conflict or unavailable required external authority

## Objective

Implement the focused goal behavior.

## Acceptance criteria

- The focused output exists.

## Validation commands

test -s goal-output.txt
TASK
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/task.md" P0 >/dev/null
project_dir="$TEST_ROOT/state/projects/goalproj"
goal_state="$project_dir/control/goals/goalproj-task-001.goal"
goal_ledger="$project_dir/control/goals/goalproj-task-001.iterations.tsv"
[[ -f "$goal_state" && -f "$goal_ledger" ]]
grep -q '^state=READY$' "$goal_state"

"$HARNESS_BIN/worker-invoke-task" "$TEST_ROOT/harness.env" 001 >/dev/null
result="$project_dir/results/goalproj-task-001.result.md"
[[ -f "$result" ]]
grep -Fqx 'Goal-Outcome: COMPLETE' "$result"
grep -q '^state=REVIEW$' "$goal_state"
grep -q '^iteration_count=1$' "$goal_state"
grep -q '^process_turns=3$' "$goal_state"
grep -q '^cumulative_input_tokens=2$' "$goal_state"
grep -q '^cumulative_output_tokens=2$' "$goal_state"
[[ "$(wc -l < "$goal_ledger")" == 2 ]]
iteration_receipt="$project_dir/archive/goal-iterations/goalproj-task-001/iteration-0001.md"
[[ -f "$iteration_receipt" ]]
[[ "$(cat "$TEST_ROOT/state/goal-mock-count")" == 3 ]]
[[ "$(wc -l < "$ARGS_LOG")" == 3 ]]
tail -n 1 "$ARGS_LOG" | grep -q 'resume goal-thread-001'
grep -q 'WORKER_PROVIDER_WAIT task=001.*kind=transient' "$project_dir/logs/events.log"
grep -q 'WORKER_GOAL_CONTINUED task=001 goal=goal.001.behavior iteration=1' "$project_dir/logs/events.log"
grep -q 'WORKER_GOAL_RESUMING task=001 goal=goal.001.behavior iteration=1' "$project_dir/logs/events.log"
[[ "$(find "$project_dir/results" -type f -name '*.result.md' | wc -l)" == 1 ]]

"$HARNESS_BIN/harness-status" "$TEST_ROOT/harness.env" > "$TEST_ROOT/status.out"
grep -q 'Worker leaf-goal mode: enabled' "$TEST_ROOT/status.out"
grep -q 'Active worker goal: goal.001.behavior (REVIEW)' "$TEST_ROOT/status.out"
grep -q 'Internal iterations: 1' "$TEST_ROOT/status.out"
grep -q 'Cumulative processed tokens (not current context size): input=2 output=2' "$TEST_ROOT/status.out"

cat > "$TEST_ROOT/checkpoint.md" <<'NOTE'
# Manager Review Record

Task-ID: 001
Decision: CHECKPOINT
Progress-Percent: 50%
Improvement-Percent: 50%
Verified-Criterion: goal.behavior
Checkpoint-Path: goal-output.txt

## Specification comparison
The leaf behavior matches the assignment.

## Increment verification
- [PASS] focused output — goal-output.txt exists

## Validation executed
- [PASS] test -s goal-output.txt — exit status 0

## Scope and regression review
Only the allowed output file changed.

## Remaining root criteria
The focused validation leaf remains.

## Conclusion
The first leaf is complete and independently verified. Checkpoint.
NOTE
"$HARNESS_BIN/manager-checkpoint-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/checkpoint.md" >/dev/null
grep -q '^state=CHECKPOINTED$' "$goal_state"
[[ -f "$project_dir/archive/goals/goalproj-task-001/goalproj-task-001.goal" ]]

cat > "$TEST_ROOT/revision.md" <<'TASK'
# Leaf Goal Validation Task

Task-ID: 001-revision-01
Task-Root: 001
Execution-Mode: LEAF_GOAL
Goal-ID: goal.001.validation
Target-Criterion: goal.validation
Goal-Success-Evidence: the focused validation of goal-output.txt passes
Focused-Validation: test -s goal-output.txt
Allowed-Scope: goal-output.txt validation only
Baseline-Boundary: behavior-checkpointed-validation-unreviewed
Hard-Block-Conditions: explicit specification conflict or unavailable required external authority

## Objective

Complete the second leaf through focused validation.

## Acceptance criteria

- The focused validation passes.

## Validation commands

test -s goal-output.txt
TASK
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001-revision-01 \
	"$TEST_ROOT/revision.md" >/dev/null
"$HARNESS_BIN/worker-invoke-task" "$TEST_ROOT/harness.env" 001-revision-01 >/dev/null
revision_result="$project_dir/results/goalproj-task-001-revision-01.result.md"
revision_state="$project_dir/control/goals/goalproj-task-001-revision-01.goal"
[[ -f "$revision_result" ]]
grep -Fqx 'Goal-ID: goal.001.validation' "$revision_result"
grep -Fqx 'Goal-Outcome: COMPLETE' "$revision_result"
grep -q '^iteration_count=0$' "$revision_state"
[[ "$(cat "$TEST_ROOT/state/goal-mock-count")" == 4 ]]

cat > "$TEST_ROOT/accept.md" <<'NOTE'
# Manager Review Record

Task-ID: 001-revision-01
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: goal.validation

## Specification comparison
Both ordered leaf criteria now pass.

## Acceptance-criteria verification
- [PASS] focused validation — the output is present and nonempty

## Feature verification
- [PASS] complete root — behavior and validation evidence are durable

## Validation executed
- [PASS] test -s goal-output.txt — exit status 0

## Scope and regression review
The validation-only leaf did not broaden implementation scope.

## Conclusion
All required behavior was independently verified. Accept.
NOTE
"$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" 001-revision-01 \
	"$TEST_ROOT/accept.md" >/dev/null
grep -q '^state=ACCEPTED$' "$revision_state"
[[ -f "$project_dir/control/oracle/oracle.pending.md" ]]
"$HARNESS_BIN/oracle-invoke-final-audit" "$TEST_ROOT/harness.env" >/dev/null
[[ -f "$project_dir/control/project.complete" ]]

# A manager rejection of an unverified COMPLETE outcome preserves the logical
# goal's thread, counters, receipts, and live workspace in the repair revision.
REPAIR_ROOT="$TEST_ROOT/goal-repair"
mkdir -p "$REPAIR_ROOT/repo" "$REPAIR_ROOT/manager-home" "$REPAIR_ROOT/worker-home"
printf 'goal repair specification\n' > "$REPAIR_ROOT/repo/spec.md"
cat > "$REPAIR_ROOT/harness.env" <<ENV
export PROJECT="goalrepair"
export REPOSITORY="$REPAIR_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$REPAIR_ROOT/state"
export MANAGER_CODEX_HOME="$REPAIR_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$REPAIR_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
ENV
chmod 600 "$REPAIR_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$REPAIR_ROOT/harness.env" >/dev/null
printf 'P0\tRepairable goal\n' > "$REPAIR_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$REPAIR_ROOT/harness.env" "$REPAIR_ROOT/plan.tsv" >/dev/null
sed 's/goal.001.behavior/goal.repair.behavior/g' "$TEST_ROOT/task.md" > "$REPAIR_ROOT/task.md"
"$HARNESS_BIN/manager-publish-task" "$REPAIR_ROOT/harness.env" 001 "$REPAIR_ROOT/task.md" P0 >/dev/null
"$HARNESS_BIN/worker-invoke-task" "$REPAIR_ROOT/harness.env" 001 >/dev/null
cat > "$REPAIR_ROOT/reject.md" <<'NOTE'
# Manager Review Record

Task-ID: 001
Decision: REJECT
Progress-Percent: 0%
Improvement-Percent: 0%
Blocking-Fingerprint: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

The claimed completion lacks independent acceptance evidence. Preserve the implementation and repair the same leaf goal.
NOTE
"$HARNESS_BIN/manager-reject-task" "$REPAIR_ROOT/harness.env" 001 "$REPAIR_ROOT/reject.md" >/dev/null
repair_project="$REPAIR_ROOT/state/projects/goalrepair"
rejected_goal_state="$repair_project/control/goals/goalrepair-task-001.goal"
grep -q '^state=REJECTED$' "$rejected_goal_state"
cat > "$REPAIR_ROOT/revision.md" <<'TASK'
# Repair Leaf Goal

Task-ID: 001-revision-01
Task-Root: 001
Execution-Mode: LEAF_GOAL
Goal-ID: goal.repair.behavior
Target-Criterion: goal.behavior
Goal-Success-Evidence: goal-output.txt exists and independent focused evidence passes
Focused-Validation: test -s goal-output.txt
Allowed-Scope: goal-output.txt
Baseline-Boundary: manager-rejected-unverified-completion
Hard-Block-Conditions: explicit specification conflict only

## Objective

Repair and prove the same first leaf.

## Acceptance criteria

- Independent focused evidence passes.

## Validation commands

test -s goal-output.txt
TASK
"$HARNESS_BIN/manager-publish-task" "$REPAIR_ROOT/harness.env" 001-revision-01 \
	"$REPAIR_ROOT/revision.md" >/dev/null
repair_goal_state="$repair_project/control/goals/goalrepair-task-001-revision-01.goal"
grep -q '^resumed_from_task=001$' "$repair_goal_state"
grep -q '^iteration_count=1$' "$repair_goal_state"
grep -q '^manager_reviews=1$' "$repair_goal_state"
grep -q '^thread_id=goal-thread-001$' "$repair_goal_state"
grep -q '^thread_context=manager-rejected-resume$' "$repair_goal_state"
[[ "$(wc -l < "$repair_project/control/goals/goalrepair-task-001-revision-01.iterations.tsv")" == 2 ]]
"$HARNESS_BIN/harness-abort-task" "$REPAIR_ROOT/harness.env" 001-revision-01 'test cleanup' >/dev/null

# Goal-mode configuration changes are boundary-safe: neither enabling it over
# a ready legacy task nor disabling it over a ready goal task may claim/mutate
# that assignment.
LEGACY_ROOT="$TEST_ROOT/legacy-toggle"
mkdir -p "$LEGACY_ROOT/repo" "$LEGACY_ROOT/manager-home" "$LEGACY_ROOT/worker-home"
printf 'legacy specification\n' > "$LEGACY_ROOT/repo/spec.md"
cat > "$LEGACY_ROOT/harness.env" <<ENV
export PROJECT="legacytoggle"
export REPOSITORY="$LEGACY_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$LEGACY_ROOT/state"
export MANAGER_CODEX_HOME="$LEGACY_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$LEGACY_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_WORKER_GOAL_MODE="0"
ENV
chmod 600 "$LEGACY_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$LEGACY_ROOT/harness.env" >/dev/null
printf 'P0\tLegacy task\n' > "$LEGACY_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$LEGACY_ROOT/harness.env" "$LEGACY_ROOT/plan.tsv" >/dev/null
cat > "$LEGACY_ROOT/task.md" <<'TASK'
# Legacy Task

Task-ID: 001
Root-Criterion: legacy.behavior

## Objective

Exercise legacy boundary safety.
TASK
"$HARNESS_BIN/manager-publish-task" "$LEGACY_ROOT/harness.env" 001 "$LEGACY_ROOT/task.md" P0 >/dev/null
printf 'export HARNESS_WORKER_GOAL_MODE="1"\n' >> "$LEGACY_ROOT/harness.env"
if "$HARNESS_BIN/worker-invoke-task" "$LEGACY_ROOT/harness.env" 001 \
	>"$LEGACY_ROOT/invoke.out" 2>"$LEGACY_ROOT/invoke.err"; then
	printf 'goal mode was enabled over a ready legacy assignment\n' >&2
	exit 1
fi
grep -q 'refusing to claim a legacy assignment' "$LEGACY_ROOT/invoke.err"
[[ -f "$LEGACY_ROOT/state/projects/legacytoggle/tasks/legacytoggle-task-001.ready.md" ]]
[[ ! -e "$LEGACY_ROOT/state/projects/legacytoggle/running/legacytoggle-task-001.running.md" ]]

ROTATE_ROOT="$TEST_ROOT/goal-rotation"
mkdir -p "$ROTATE_ROOT/repo" "$ROTATE_ROOT/manager-home" "$ROTATE_ROOT/worker-home"
printf 'goal rotation specification\n' > "$ROTATE_ROOT/repo/spec.md"
cat > "$ROTATE_ROOT/harness.env" <<ENV
export PROJECT="goalrotate"
export REPOSITORY="$ROTATE_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$ROTATE_ROOT/state"
export MANAGER_CODEX_HOME="$ROTATE_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$ROTATE_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS="1"
export HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS="8"
ENV
chmod 600 "$ROTATE_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$ROTATE_ROOT/harness.env" >/dev/null
printf 'P0\tRotating goal\n' > "$ROTATE_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$ROTATE_ROOT/harness.env" "$ROTATE_ROOT/plan.tsv" >/dev/null
sed 's/goalproj/goalrotate/g; s/goal.001.behavior/goal.rotate.behavior/g' \
	"$TEST_ROOT/task.md" > "$ROTATE_ROOT/task.md"
"$HARNESS_BIN/manager-publish-task" "$ROTATE_ROOT/harness.env" 001 "$ROTATE_ROOT/task.md" P0 >/dev/null
rotation_session="$("$HARNESS_BIN/harness-new-session" "$ROTATE_ROOT/harness.env" worker)"
"$HARNESS_BIN/worker-claim-task" "$ROTATE_ROOT/harness.env" 001 "$rotation_session" >/dev/null
rotation_project="$ROTATE_ROOT/state/projects/goalrotate"
rotation_state="$rotation_project/control/goals/goalrotate-task-001.goal"
rotation_boundary="$(awk -F= '$1 == "last_boundary" {sub(/^[^=]*=/, ""); print}' "$rotation_state")"
rotation_workspace="$(awk -F= '$1 == "last_workspace" {sub(/^[^=]*=/, ""); print}' "$rotation_state")"
cat > "$ROTATE_ROOT/iteration-1.md" <<ITERATION
# Worker Goal Iteration

Task-ID: 001
Goal-ID: goal.rotate.behavior
Iteration: 1
Outcome: CONTINUE
Boundary-Before: $rotation_boundary
Boundary-After: $rotation_boundary
Workspace-Fingerprint-Before: $rotation_workspace
Workspace-Fingerprint-After: $rotation_workspace

## Progress made

Captured one new focused trace.

## Validation performed

The focused trace was inspected.

## Next bounded action

Use the trace to choose the next correction.

## Scope check

No file or behavior outside the goal was touched.
ITERATION
"$HARNESS_BIN/worker-continue-task" "$ROTATE_ROOT/harness.env" 001 \
	"$rotation_session" "$ROTATE_ROOT/iteration-1.md" >/dev/null
sed 's/Iteration: 1/Iteration: 2/' "$ROTATE_ROOT/iteration-1.md" > "$ROTATE_ROOT/iteration-2.md"
"$HARNESS_BIN/worker-continue-task" "$ROTATE_ROOT/harness.env" 001 \
	"$rotation_session" "$ROTATE_ROOT/iteration-2.md" >/dev/null
grep -q '^state=STRATEGY_REVIEW$' "$rotation_state"
grep -q '^strategy_review_required=1$' "$rotation_state"
grep -q '^context_generation=1$' "$rotation_state"
grep -q '^thread_context=rotation-requested$' "$rotation_state"
"$HARNESS_BIN/worker-continue-task" "$ROTATE_ROOT/harness.env" 001 \
	"$rotation_session" "$ROTATE_ROOT/iteration-2.md" >/dev/null
[[ "$(wc -l < "$rotation_project/control/goals/goalrotate-task-001.iterations.tsv")" == 3 ]]
sed 's/Iteration: 2/Iteration: 3/' "$ROTATE_ROOT/iteration-2.md" > "$ROTATE_ROOT/iteration-3.md"
if "$HARNESS_BIN/worker-continue-task" "$ROTATE_ROOT/harness.env" 001 \
	"$rotation_session" "$ROTATE_ROOT/iteration-3.md" >/dev/null 2>&1; then
	printf 'continuation remained open after identical-iteration strategy review\n' >&2
	exit 1
fi
printf 'uncommitted recovered work\n' > "$ROTATE_ROOT/repo/recovered-work.txt"
"$HARNESS_BIN/harness-recover" "$ROTATE_ROOT/harness.env" > "$ROTATE_ROOT/recover.out"
grep -q 'ACTIVE_GOAL task=001.*workspace-drift=yes' "$ROTATE_ROOT/recover.out"
"$HARNESS_BIN/harness-reset-task" "$ROTATE_ROOT/harness.env" 001 --force >/dev/null
printf 'export HARNESS_WORKER_GOAL_MODE="0"\n' >> "$ROTATE_ROOT/harness.env"
if "$HARNESS_BIN/worker-invoke-task" "$ROTATE_ROOT/harness.env" 001 \
	>"$ROTATE_ROOT/invoke.out" 2>"$ROTATE_ROOT/invoke.err"; then
	printf 'goal mode was disabled over an active goal assignment\n' >&2
	exit 1
fi
grep -q 'refusing to claim an active LEAF_GOAL' "$ROTATE_ROOT/invoke.err"
[[ -f "$rotation_project/tasks/goalrotate-task-001.ready.md" ]]
[[ ! -e "$rotation_project/running/goalrotate-task-001.running.md" ]]

# A terminal decomposition request preserves a verified diagnostic checkpoint
# and immediately enters the existing automatic replan/decomposition path.
DECOMP_ROOT="$TEST_ROOT/goal-decomposition"
mkdir -p "$DECOMP_ROOT/repo" "$DECOMP_ROOT/manager-home" "$DECOMP_ROOT/worker-home"
printf 'goal decomposition specification\n' > "$DECOMP_ROOT/repo/spec.md"
cat > "$DECOMP_ROOT/harness.env" <<ENV
export PROJECT="goaldecomp"
export REPOSITORY="$DECOMP_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$DECOMP_ROOT/state"
export MANAGER_CODEX_HOME="$DECOMP_ROOT/manager-home"
export MANAGER_CODEX_BIN="$TEST_ROOT/mock-codex"
export WORKER_CODEX_HOME="$DECOMP_ROOT/worker-home"
export WORKER_CODEX_BIN="$TEST_ROOT/mock-codex"
export HARNESS_WORKER_GOAL_MODE="1"
ENV
chmod 600 "$DECOMP_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$DECOMP_ROOT/harness.env" >/dev/null
printf 'P0\tDecomposed goal\n' > "$DECOMP_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$DECOMP_ROOT/harness.env" "$DECOMP_ROOT/plan.tsv" >/dev/null
cat > "$DECOMP_ROOT/task.md" <<'TASK'
# Goal Requiring Decomposition

Task-ID: 001
Task-Root: 001
Execution-Mode: LEAF_GOAL
Goal-ID: goal.decomposition.original
Root-Criterion: broad.behavior
Root-Criterion: final.validation
Target-Criterion: broad.behavior
Goal-Success-Evidence: the broad behavior passes focused validation
Focused-Validation: focused-broad-smoke
Allowed-Scope: broad behavior implementation
Baseline-Boundary: broad-boundary-unisolated
Hard-Block-Conditions: explicit specification conflict only

## Objective

Isolate the broad behavior.

## Acceptance criteria

- The remaining work is independently verifiable.

## Validation commands

focused-broad-smoke
TASK
"$HARNESS_BIN/manager-publish-task" "$DECOMP_ROOT/harness.env" 001 \
	"$DECOMP_ROOT/task.md" P0 >/dev/null
decomp_session="$("$HARNESS_BIN/harness-new-session" "$DECOMP_ROOT/harness.env" worker)"
"$HARNESS_BIN/worker-claim-task" "$DECOMP_ROOT/harness.env" 001 "$decomp_session" >/dev/null
cat > "$DECOMP_ROOT/result.md" <<'RESULT'
# Task Result

Task-ID: 001
Status: COMPLETED
Goal-ID: goal.decomposition.original
Goal-Outcome: NEEDS_DECOMPOSITION

## Summary

The diagnostic isolated two independently verifiable remaining branches.

## Modified files

None.

## Implemented behavior

No implementation completion is claimed.

## Validation performed

The focused diagnostic was captured.

## Deviations from assignment

The original leaf is too broad for one success boundary.

## Remaining concerns

Append ordered children and schedule the first.

## Worker assessment

NEEDS_DECOMPOSITION.
RESULT
"$HARNESS_BIN/worker-complete-task" "$DECOMP_ROOT/harness.env" 001 \
	"$decomp_session" "$DECOMP_ROOT/result.md" >/dev/null
cat > "$DECOMP_ROOT/checkpoint.md" <<'NOTE'
# Manager Review Record

Task-ID: 001
Decision: CHECKPOINT
Progress-Percent: 0%
Improvement-Percent: 0%
Verified-Increment: broad.behavior.branch-isolation
Checkpoint-Path: NONE

## Specification comparison
The diagnostic truthfully isolates the remaining broad criterion.

## Increment verification
- [PASS] branch isolation — two independent acceptance boundaries were identified

## Validation executed
- [PASS] focused diagnostic — captured without changing production files

## Scope and regression review
No repository file changed.

## Remaining root criteria
The broad behavior requires append-only child criteria, followed by final validation.

## Conclusion
The diagnostic increment is correct and independently verified. Checkpoint.
NOTE
decomp_checkpoint_output="$("$HARNESS_BIN/manager-checkpoint-task" \
	"$DECOMP_ROOT/harness.env" 001 "$DECOMP_ROOT/checkpoint.md")"
[[ "$decomp_checkpoint_output" == *.needs-replan.md ]]
decomp_project="$DECOMP_ROOT/state/projects/goaldecomp"
[[ -f "$decomp_project/control/progress/goaldecomp-task-001.needs-replan.md" ]]
grep -q 'Trigger-Outcome: GOAL_NEEDS_DECOMPOSITION' \
	"$decomp_project/control/progress/goaldecomp-task-001.needs-replan.md"
grep -q '^state=CHECKPOINTED$' "$decomp_project/control/goals/goaldecomp-task-001.goal"

printf 'Leaf-goal harness tests passed.\n'
