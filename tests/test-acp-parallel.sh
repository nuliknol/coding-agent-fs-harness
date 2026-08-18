#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-acp-parallel.XXXXXX)"
cleanup()
{
	"$ROOT/bin/sctm-daemon-stop" "$TEST_ROOT/harness.env" >/dev/null 2>&1 || true
	git -C "$TEST_ROOT/repo" worktree prune >/dev/null 2>&1 || true
	if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
		printf 'Preserved test root: %s\n' "$TEST_ROOT" >&2
	else
		rm -rf -- "$TEST_ROOT"
	fi
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
export HARNESS_SCTM_ENABLED=1
export HARNESS_DECOMPOSITION_V2=0
export HARNESS_SPECIFICATION_REVIEW_ENABLED=0
export HARNESS_WORKER_GOAL_MODE=0
export HARNESS_ARCHITECTURE_GUARDS=0
export HARNESS_ESCALATION_POLICY=decompose
export HARNESS_AGENT_MIN_INTERVAL_SECONDS=0
export MAX_ORACLE_RUNS=0
ENV
chmod 600 "$TEST_ROOT/harness.env"
"$ROOT/bin/harness-init" "$TEST_ROOT/harness.env" >/dev/null
project="$TEST_ROOT/state/projects/acpparallel"

# Generated review IR is durable canonical authority and is intentionally not
# copied into detached worker worktrees.  Isolated workers resolve those
# sidecars through the canonical repository while code/history remain bound to
# their detached base.
mkdir -p "$TEST_ROOT/repo/spec-review" "$TEST_ROOT/authority-worktree"
printf 'obligation_id\n' > "$TEST_ROOT/repo/spec-review/obligations.tsv"
authority_dir="$(bash -c 'source "$1/lib/harness-common.sh"; REPOSITORY="$2"; HARNESS_ACP_CANONICAL_REPOSITORY="$3"; specification_review_repository_dir' \
	_ "$ROOT" "$TEST_ROOT/authority-worktree" "$TEST_ROOT/repo")"
[[ "$authority_dir" == "$TEST_ROOT/repo/spec-review" ]]

# A healthy unblocked project is the ordinary parallel-planning state.  Keep
# the three negative guard predicates in an explicit conditional so their
# expected false return cannot escape through the supervisor ERR trap.
grep -Fq 'if project_has_token_usage_anomaly || project_has_integrity_anomaly || project_is_blocked; then' \
	"$ROOT/bin/harness-supervisor"
! grep -Fq '{ project_has_token_usage_anomaly || project_has_integrity_anomaly || project_is_blocked; } && return 0' \
	"$ROOT/bin/harness-supervisor"

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
# Integration validation must receive a cohort-unique temp directory. A fixed
# task-only directory reuses CMake caches whose source root names an earlier
# detached worktree.
sed -i 's#Focused-Validation: grep -Fqx task-a a.txt#Focused-Validation: grep -Fqx task-a a.txt \&\& test "\$HARNESS_TASK_TMP_DIR" != "\$PROJECT_TMP_DIR/acp-integration/a"#' \
	"$project/tasks/acpparallel-task-a.ready.md"
sed -i 's#Focused-Validation: grep -Fqx task-b b.txt#Focused-Validation: grep -Fqx task-b b.txt \&\& test "\$HARNESS_TASK_TMP_DIR" != "\$PROJECT_TMP_DIR/acp-integration/b"#' \
	"$project/tasks/acpparallel-task-b.ready.md"
cat > "$project/tasks/acpparallel-task-c.ready.md" <<'TASK'
# Task Assignment

Task-ID: c
Task-Root: c
Allowed-Scope: -
Context-Paths: -
Required-Symbols: -
Focused-Validation: FOCUSED: bounded read-only evidence
Leaf-Type: VERIFICATION_ONLY
Expected-Max-Implementation-Files: 0
TASK
cat > "$project/tasks/acpparallel-task-e.ready.md" <<'TASK'
# Task Assignment

Task-ID: e
Task-Root: e
Allowed-Scope: b.txt
Context-Paths: b.txt
Required-Symbols: -
Focused-Validation: /bin/false
Expected-Max-Implementation-Files: 1
TASK
cat > "$project/tasks/acpparallel-task-d.ready.md" <<'TASK'
# Task Assignment

Task-ID: d
Task-Root: d
Allowed-Scope: a.txt
Context-Paths: a.txt
Required-Symbols: -
Focused-Validation: grep -Fqx base-a a.txt
Expected-Max-Implementation-Files: 1
TASK

cat > "$TEST_ROOT/mock-worker" <<'WORKER'
#!/usr/bin/env bash
set -Eeuo pipefail
env_file="$1"; task_id="$2"
session="$($HARNESS_BIN/harness-new-session "$env_file" "worker-$task_id")"
claim="$($HARNESS_BIN/worker-claim-task "$env_file" "$task_id" "$session")"
task_file="$(sed -n 's/^TASK_FILE=//p' <<< "$claim")"
source "$env_file"
PROJECT_TMP_DIR="$HARNESS_TASK_TMP_DIR"
[[ "${HARNESS_TASK_TMP_DIR##*/}" =~ ^$task_id-[0-9]+$ ]]
if [[ "$task_id" == c ]]; then
	[[ "${HARNESS_ACP_READ_ONLY_VERIFICATION:-0}" == 1 ]]
	result="$PROJECT_TMP_DIR/result.md"
	mkdir -p "$PROJECT_TMP_DIR"
	cat > "$result" <<RESULT
# Worker Task Result

Task-ID: c
Status: COMPLETED

## Summary

Verified the isolated baseline without mutation.

## Modified files

None.

## Implemented behavior

Recorded read-only evidence.

## Validation performed

Baseline repository observation passed.

## Deviations from assignment

None.

## Remaining concerns

None.

## Worker assessment

COMPLETE.
RESULT
	"$HARNESS_BIN/worker-complete-task" "$env_file" "$task_id" "$session" "$result" >/dev/null
	exit 0
fi
if [[ "$task_id" == e ]]; then
	result="$PROJECT_TMP_DIR/result.md"
	mkdir -p "$PROJECT_TMP_DIR"
	cat > "$result" <<RESULT
# Worker Task Result

Task-ID: e
Status: COMPLETED
Goal-Outcome: NEEDS_DECOMPOSITION

## Summary

No source candidate was produced.

## Modified files

None.

## Implemented behavior

None.

## Validation performed

No candidate validation is applicable.

## Deviations from assignment

The task needs decomposition.

## Remaining concerns

The parent leaf is too broad.

## Worker assessment

NEEDS_DECOMPOSITION.
RESULT
	"$HARNESS_BIN/worker-complete-task" "$env_file" "$task_id" "$session" "$result" >/dev/null
	exit 0
fi
if [[ "$task_id" == d ]]; then
	"$HARNESS_BIN/worker-return-context-repair" "$env_file" "$task_id" "$session" \
		CLOSURE_BUILD_UNAVAILABLE REFRESH_INDEX_OR_OVERLAY repository-index \
		generated-inputs-changed >/dev/null
	exit 0
fi
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
		-f "$project/control/acp/integration/b.integrated.env" &&
		-f "$project/results/acpparallel-task-c.result.md" &&
		-f "$project/results/acpparallel-task-e.result.md" &&
		-f "$project/control/acpparallel-task-d.context-closure-repair.env" &&
		! -e "$project/control/acpparallel-task-d.worker-invocation-active" &&
		! -e "$project/control/acpparallel-task-e.worker-invocation-active" ]] && break
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
grep -Fqx 'status=APPLIED' "$project/control/sctm/transactions/tx-a-"*/result
grep -Fqx 'status=APPLIED' "$project/control/sctm/transactions/tx-b-"*/result
[[ ! -e "$project/control/acp/capability-leases/a.lease.env" ]]
[[ ! -e "$project/control/acp/capability-leases/b.lease.env" ]]
grep -Fq $'INTEGRATED\tSCOPE\tWRITE' "$project/control/acp/events.tsv"
grep -Fq $'CAPABILITY_ACQUIRED\tSCOPE\tREAD' "$project/control/acp/events.tsv"
grep -Fq $'VERIFIED\tSCOPE\tREAD' "$project/control/acp/events.tsv"
[[ ! -e "$project/control/acp/integration/c.integrated.env" ]]
[[ ! -e "$project/control/acp/integration/d.integrated.env" ]]
[[ ! -e "$project/control/acp/integration/e.integrated.env" ]]
[[ ! -e "$project/control/project-integrity-anomaly.md" ]]
grep -Fq 'ACP_CONTEXT_CLOSURE_REPAIR_RETURNED task=d' "$project/logs/events.log"
grep -Fq 'ACP_NO_SOURCE_CANDIDATE_RETURNED task=e' "$project/logs/events.log"
git -C "$TEST_ROOT/repo" diff --quiet
git -C "$TEST_ROOT/repo" diff --cached --quiet

printf 'ACP parallel integration tests passed.\n'
