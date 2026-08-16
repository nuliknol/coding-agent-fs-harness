#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-decomposition-v2.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\n" "$TEST_ROOT" >&2' EXIT
else
	trap 'rm -rf -- "$TEST_ROOT"' EXIT
fi

mkdir -p "$TEST_ROOT/repo/src" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'Implement one focused behavior.\n' > "$TEST_ROOT/repo/spec.md"
printf 'int target_symbol(void) { return 0; }\n' > "$TEST_ROOT/repo/src/a.c"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" add spec.md src/a.c
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="decompv2"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="$TEST_ROOT/repo/spec.md"
export harness_mode="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$TEST_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export MANAGER_MODEL="gpt-5.6-terra"
export WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_MIN_LUNA_NODE_PERCENT="50"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"

"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null

cat > "$TEST_ROOT/invalid-measured-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
planner-one	-	-	Group work	Children exist	printf PASS	src/a.c	-	DECOMPOSITION	HIGH	SOL	1	0	0	0	1	0	2	30000	-
planner-two	-	planner-one	Group more work	Children exist	printf PASS	src/a.c	-	DECOMPOSITION	HIGH	SOL	1	0	0	0	1	0	2	30000	-
PLAN
if (
	source "$HARNESS_HOME/lib/harness-common.sh"
	validate_decomposition_measured_schema_file "$TEST_ROOT/invalid-measured-plan.tsv"
) > "$TEST_ROOT/invalid-measured-plan.out" 2>&1; then
	printf 'measured schema accepted non-executable Sol grouping rows\n' >&2
	exit 1
fi
grep -Fq 'node=planner-one has non-executable leaf_type=DECOMPOSITION' "$TEST_ROOT/invalid-measured-plan.out"
grep -Fq 'node=planner-one has non-executable worker_route=SOL' "$TEST_ROOT/invalid-measured-plan.out"
grep -Fq 'node=planner-two has non-executable leaf_type=DECOMPOSITION' "$TEST_ROOT/invalid-measured-plan.out"
grep -Fq 'node=planner-two has non-executable worker_route=SOL' "$TEST_ROOT/invalid-measured-plan.out"

# Prompt construction uses an interpolated heredoc. Literal shell backticks in
# prose must not accidentally execute commands while the prompt is generated.
set +e
"$HARNESS_BIN/manager-decomposition-critic" "$TEST_ROOT/harness.env" \
	>"$TEST_ROOT/critic-prompt.out" 2>"$TEST_ROOT/critic-prompt.err"
critic_prompt_status=$?
set -e
(( critic_prompt_status != 0 ))
! grep -Fq 'command not found' "$TEST_ROOT/critic-prompt.err"
grep -Fq 'regex that requires a trailing newline character' \
	"$TEST_ROOT/state/projects/decompv2/control/manager-decomposition-critic.prompt.md"
grep -Fq 'Preserve specification-declared component ownership and principal source paths.' \
	"$TEST_ROOT/state/projects/decompv2/control/manager-decomposition-critic.prompt.md"
grep -Fq 'Never convert argument arity into record count' \
	"$TEST_ROOT/state/projects/decompv2/control/manager-decomposition-critic.prompt.md"
grep -R -Fqx 'role=decomposition' "$TEST_ROOT/state/projects/decompv2/logs"/*.classification
grep -R -Fqx 'model=gpt-5.6-sol' "$TEST_ROOT/state/projects/decompv2/logs"/*.classification

cat > "$TEST_ROOT/broad-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
broad	-	-	Implement one bounded stage	Owned stage passes	./semantic-smoke --computing-all	src/a.c	target_symbol	LOCAL_IMPLEMENTATION	LOW	LUNA
PLAN
if "$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" \
	"$TEST_ROOT/broad-plan.tsv" > "$TEST_ROOT/broad-plan.out" 2>&1; then
	printf 'decomposition accepted an unrelated aggregate as mandatory focused validation\n' >&2
	exit 1
fi
grep -Fq 'plan node broad focused_validation uses a broad aggregate as a mandatory success condition' \
	"$TEST_ROOT/broad-plan.out"
cat > "$TEST_ROOT/plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
n1	-	-	Implement target_symbol locally	target_symbol returns one	test "$(./focused-smoke)" = 1	src/a.c	target_symbol	LOCAL_IMPLEMENTATION	LOW	LUNA
n2	-	n1	Integrate target_symbol with its caller	focused integration smoke passes	./integration-smoke	src/a.c,src/caller.c	target_symbol,call_target	INTEGRATION	MEDIUM	TERRA
PLAN
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" "$TEST_ROOT/plan.tsv" >/dev/null

project_dir="$TEST_ROOT/state/projects/decompv2"
cmp -s "$TEST_ROOT/plan.tsv" "$project_dir/control/project-decomposition-v2.tsv"
grep -Eq $'^n1\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"

cat > "$TEST_ROOT/task.md" <<'TASK'
# Leaf-Goal Task Assignment

Project: decompv2
Task-ID: 001
Task-Root: 001
Starting-Progress: 0%
Status: READY
Execution-Mode: LEAF_GOAL
Goal-ID: n1.goal
Target-Criterion: n1.done
Goal-Success-Evidence: target_symbol returns one
Focused-Validation: test "$(./focused-smoke)" = 1
Allowed-Scope: src/a.c
Baseline-Boundary: target_symbol currently returns zero
Hard-Block-Conditions: NONE
Leaf-Type: LOCAL_IMPLEMENTATION
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: -
Deliverable: Implement target_symbol locally
Required-Symbols: target_symbol
Context-Paths: src/a.c
Architecture-Decisions: NONE
Expected-Max-Implementation-Files: 1
Expected-Max-Worker-Turns: 2
Root-Criterion: n1.done

## Objective

Make target_symbol return one.

## Acceptance criteria

- The focused evidence passes.

## Validation commands

```text
./focused-smoke
```
TASK
cat > "$project_dir/control/specification-coverage.tsv" <<'COVERAGE'
obligation_id	node_ids	evidence_plan
REQ-CROSS-NODE	n1,n2	Both bounded nodes jointly establish the requirement.
COVERAGE
sed -e 's/^Target-Criterion: n1.done$/Target-Criterion: REQ-CROSS-NODE/' \
	-e 's/^Root-Criterion: n1.done$/Root-Criterion: REQ-CROSS-NODE/' \
	"$TEST_ROOT/task.md" > "$TEST_ROOT/cross-node-criterion-task.md"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 \
	"$TEST_ROOT/cross-node-criterion-task.md" n1 > "$TEST_ROOT/cross-node-criterion.out" 2>&1; then
	printf 'cross-node specification obligation was accepted as one root criterion\n' >&2
	exit 1
fi
grep -Fq 'Root-Criterion REQ-CROSS-NODE is a cross-node specification obligation allocated to n1,n2' \
	"$TEST_ROOT/cross-node-criterion.out"
rm -f "$project_dir/control/specification-coverage.tsv"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/task.md" n1 >/dev/null

grep -Eq $'^n1\tACTIVE\t001\t' "$project_dir/control/project-plan-state.tsv"
capsule="$project_dir/control/context-capsules/decompv2-task-001.md"
grep -Fqx 'Worker-Route: LUNA' "$capsule"
grep -Fqx 'Context-Paths: src/a.c' "$capsule"
grep -Fqx '## Required symbol locations' "$capsule"
grep -Fqx -- '- `target_symbol`: `src/a.c:1`' "$capsule"
grep -Fqx 'Architecture-Decisions: NONE' "$capsule"
grep -Fqx 'Validation-Class: FOCUSED' "$capsule"
grep -Fqx 'Validation-Output-Policy: CAPTURE_SUMMARY' "$capsule"
grep -Fqx 'Decomposition-Planner-Model: gpt-5.6-sol' "$capsule"
grep -Fqx 'planner_model=gpt-5.6-sol' "$project_dir/control/decomposition-provenance.env"
info_output="$("$HARNESS_BIN/harness-info" "$TEST_ROOT/harness.env")"
grep -Fqx '  Decomposition: gpt-5.6-sol (high)' <<< "$info_output"

# Verbose validation is retained completely on disk while only a bounded
# diagnostic excerpt reaches the worker transcript.
set +e
logged_output="$("$HARNESS_BIN/harness-run-logged" "$TEST_ROOT/harness.env" 001 noisy-test -- \
	bash -c 'for i in $(seq 1 2000); do printf "compiler error line %s with repeated diagnostic text\\n" "$i"; done; exit 7')"
logged_status=$?
set -e
(( logged_status == 7 ))
grep -Fq 'VALIDATION_LOG label=noisy-test exit=7 lines=2000' <<< "$logged_output"
(( ${#logged_output} <= 40000 ))
logged_path="$(awk -F'log=' '/^VALIDATION_LOG / {print $2; exit}' <<< "$logged_output")"
test "$(wc -l < "$logged_path")" -eq 2000

# The assigned-validation runner owns the complete shell expression, so a
# logical operator cannot escape output capture in the caller's shell.
cat > "$project_dir/archive/decompv2-task-compound.assignment.md" <<'ASSIGNMENT'
Task-ID: compound
Focused-Validation: printf 'first\n' && for i in $(seq 1 2000); do printf 'second verbose line %s\n' "$i"; done
ASSIGNMENT
assigned_output="$("$HARNESS_BIN/harness-run-assigned-validation" \
	"$TEST_ROOT/harness.env" compound assigned-compound)"
grep -Fq 'VALIDATION_LOG label=assigned-compound exit=0 lines=2001' <<< "$assigned_output"
(( ${#assigned_output} <= 40000 ))
assigned_path="$(awk -F'log=' '/^VALIDATION_LOG / {print $2; exit}' <<< "$assigned_output")"
test "$(wc -l < "$assigned_path")" -eq 2001

# Outlier ranking distinguishes authoritative and estimated worker episodes and
# exposes command-output amplification without replaying command contents.
cat > "$project_dir/logs/worker-task-synthetic-20260814T000000Z-attempt-001.jsonl" <<'JSON'
{"type":"thread.started","thread_id":"synthetic-thread"}
{"type":"turn.started"}
{"type":"item.started","item":{"type":"command_execution","command":"build"}}
{"type":"item.completed","item":{"type":"command_execution","command":"build","aggregated_output":"1234567890","exit_code":0}}
JSON
cat > "$project_dir/logs/worker-task-synthetic-20260814T000000Z-attempt-001.classification" <<CLASS
classification=agent_estimated_token_budget_exceeded
role=worker_luna
model=gpt-5.6-luna
invocation_processed_delta=0
estimated_processed_tokens=750000
item_started_count=1
resume_requested=0
git_head_changed=0
CLASS
outliers="$("$HARNESS_BIN/harness-token-outliers" "$TEST_ROOT/harness.env" --role worker --limit 1)"
grep -Fq $'750000\tdecompv2\tsynthetic\tworker_luna\tgpt-5.6-luna\testimated' <<< "$outliers"
grep -Fq $'\t1\t1\t10\t10\t0\t0\tgpt-5.6-sol\t' <<< "$outliers"
tree_output="$("$HARNESS_BIN/harness-decomposition-tree" --ascii "$TEST_ROOT/harness.env")"
grep -Fqx 'Routes: LUNA=1 (50%)  TERRA=1 (50%)  configured Luna minimum=50%' <<< "$tree_output"
grep -Fq '|-- n1 [ACTIVE] type=LOCAL_IMPLEMENTATION complexity=LOW route=LUNA' <<< "$tree_output"
grep -Fq 'task: 001 [READY] route=LUNA' <<< "$tree_output"
grep -Fq '`-- n2 [PENDING] type=INTEGRATION complexity=MEDIUM route=TERRA' <<< "$tree_output"
tree_details="$("$HARNESS_BIN/harness-decomposition-tree" --details --ascii "$TEST_ROOT/harness.env")"
grep -Fq 'evidence: target_symbol returns one' <<< "$tree_details"
grep -Fq 'validation: test "$(./focused-smoke)" = 1' <<< "$tree_details"
grep -Fq 'n1.done [PENDING]' <<< "$tree_details"
metrics_output="$("$HARNESS_BIN/harness-decomposition-metrics" "$TEST_ROOT/harness.env")"
grep -Fqx $'nodes_total\t2' <<< "$metrics_output"
grep -Fqx $'luna_assignments\t0' <<< "$metrics_output"
test -s "$project_dir/control/decomposition-metrics.tsv"

grep -Eq $'^n2\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"

# Read-only evidence and architecture leaves may explicitly authorize zero
# implementation files. Zero is a hard no-edit budget, not a missing value.
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2readonly"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/read-only-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/read-only-harness.env"
chmod 600 "$TEST_ROOT/read-only-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/read-only-harness.env" >/dev/null
cat > "$TEST_ROOT/read-only-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
evidence	-	-	Record existing authority evidence	Named authority is independently recorded	FOCUSED: inspect target_symbol	src/a.c	target_symbol	CROSS_COMPONENT_ARCHITECTURE	HIGH	TERRA
PLAN
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/read-only-harness.env" \
	"$TEST_ROOT/read-only-plan.tsv" >/dev/null
cat > "$TEST_ROOT/read-only-task.md" <<'TASK'
Execution-Mode: LEAF_GOAL
Goal-ID: evidence.goal
Target-Criterion: evidence.recorded
Goal-Success-Evidence: Model-authored paraphrase that must be replaced
Focused-Validation: `test -f src/a.c`; retain the output and report the result.
Allowed-Scope: src/a.c
Baseline-Boundary: Existing source is read-only.
Hard-Block-Conditions: Any implementation edit is forbidden.
Leaf-Type: CROSS_COMPONENT_ARCHITECTURE
Complexity-Class: HIGH
Worker-Route: TERRA
Depends-On: -
Deliverable: Record existing authority evidence
Required-Symbols: target_symbol
Context-Paths: src/a.c
Architecture-Decisions: NONE
Mandatory-Git-Refs: refs/heads/internal-task-id-must-not-be-a-ref
Expected-Max-Implementation-Files: 0
Expected-Max-Worker-Turns: 1
## Objective

Record bounded read-only evidence without editing source.
TASK
if "$HARNESS_BIN/manager-publish-planned-task" "$TEST_ROOT/read-only-harness.env" \
	"$TEST_ROOT/read-only-task.md" >"$TEST_ROOT/read-only-invalid-validation.out" 2>&1; then
	printf 'Markdown-wrapped validation was published as an executable command\n' >&2
	exit 1
fi
grep -Fq 'Focused-Validation must be one machine-executable shell command' \
	"$TEST_ROOT/read-only-invalid-validation.out"
sed -i 's#^Focused-Validation:.*#Focused-Validation: test -f src/a.c#' \
	"$TEST_ROOT/read-only-task.md"
"$HARNESS_BIN/manager-publish-planned-task" "$TEST_ROOT/read-only-harness.env" \
	"$TEST_ROOT/read-only-task.md" >/dev/null
grep -Fqx 'Expected-Max-Implementation-Files: 0' \
	"$TEST_ROOT/read-only-state/projects/decompv2readonly/tasks/decompv2readonly-task-evidence.ready.md"
grep -Fqx 'Goal-Success-Evidence: Named authority is independently recorded' \
	"$TEST_ROOT/read-only-state/projects/decompv2readonly/tasks/decompv2readonly-task-evidence.ready.md"
grep -Fqx 'Focused-Validation: test -f src/a.c' \
	"$TEST_ROOT/read-only-state/projects/decompv2readonly/tasks/decompv2readonly-task-evidence.ready.md"
grep -Fqx 'Root-Criterion: evidence.recorded' \
	"$TEST_ROOT/read-only-state/projects/decompv2readonly/tasks/decompv2readonly-task-evidence.ready.md"
grep -Fqx 'Mandatory-Git-Refs: -' \
	"$TEST_ROOT/read-only-state/projects/decompv2readonly/tasks/decompv2readonly-task-evidence.ready.md"
read_only_session="$("$HARNESS_BIN/harness-new-session" "$TEST_ROOT/read-only-harness.env" worker)"
"$HARNESS_BIN/worker-claim-task" "$TEST_ROOT/read-only-harness.env" evidence \
	"$read_only_session" >/dev/null
printf 'int target_symbol(void) { return 2; }\n' > "$TEST_ROOT/repo/src/a.c"
printf 'Invalid zero-write commit attempt.\n' > "$TEST_ROOT/read-only-message.txt"
if "$HARNESS_BIN/harness-commit-source" "$TEST_ROOT/read-only-harness.env" evidence \
	"$read_only_session" "$TEST_ROOT/read-only-message.txt" src/a.c \
	> "$TEST_ROOT/read-only-commit.out" 2>&1; then
	printf 'zero-write task committed source despite its implementation-file budget\n' >&2
	exit 1
fi
grep -Fq 'source commit would exceed Expected-Max-Implementation-Files (1/0)' \
	"$TEST_ROOT/read-only-commit.out"
git -C "$TEST_ROOT/repo" restore --worktree -- src/a.c

# A resource fuse that observes durable source progress must schedule a
# read-only verification transaction. Recovery planners sometimes copy the
# parent's implementation-file count into that transaction; publication must
# normalize the execution vector to zero rather than burning every correction
# attempt on stale, non-semantic metadata.
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2verification"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/verification-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/verification-harness.env"
chmod 600 "$TEST_ROOT/verification-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/verification-harness.env" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/verification-harness.env" \
	"$TEST_ROOT/plan.tsv" >/dev/null
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/verification-harness.env" 001 \
	"$TEST_ROOT/task.md" n1 >/dev/null
verification_project="$TEST_ROOT/verification-state/projects/decompv2verification"
mv "$verification_project/tasks/decompv2verification-task-001.ready.md" \
	"$verification_project/archive/decompv2verification-task-001.checkpointed.md"
# Exhausted Luna implementation strategies apply to the whole root. The
# required zero-write verification stays bounded, but must route to fresh Terra
# instead of being normalized back to a prohibited fourth Luna strategy.
for failed_revision in 90 91 92; do
	cat > "$verification_project/archive/decompv2verification-task-001-revision-$failed_revision.assignment.md" <<'FAILED_ASSIGNMENT'
Worker-Route: LUNA
FAILED_ASSIGNMENT
	cat > "$verification_project/archive/decompv2verification-task-001-revision-$failed_revision.result.md" <<'FAILED_RESULT'
Goal-Outcome: NEEDS_DECOMPOSITION
FAILED_RESULT
done
cat > "$verification_project/control/progress/decompv2verification-task-001.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Task-Root: 001
Triggered-By: 001
Trigger-Outcome: RESOURCE_PROGRESS_NEEDS_VERIFICATION
Blocking-Fingerprint: sha256:verification
MARKER
sed \
	-e 's/^Task-ID: 001$/Task-ID: 001-revision-01/' \
	-e 's/^Goal-ID: n1.goal$/Goal-ID: n1.verify/' \
	-e 's/^Leaf-Type: LOCAL_IMPLEMENTATION$/Leaf-Type: VERIFICATION_ONLY/' \
	-e 's/^Expected-Max-Implementation-Files: 1$/Expected-Max-Implementation-Files: 2/' \
	-e '/^Root-Criterion: n1.done$/a Replan-Strategy-ID: verify.progress\nStrategy-Change: NEW_EVIDENCE\nSupersedes-Task: 001' \
	"$TEST_ROOT/task.md" > "$TEST_ROOT/verification-recovery-task.md"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/verification-harness.env" \
	001-revision-01 "$TEST_ROOT/verification-recovery-task.md" --auto-replan >/dev/null
verification_ready="$verification_project/tasks/decompv2verification-task-001-revision-01.ready.md"
grep -Fqx 'Leaf-Type: VERIFICATION_ONLY' "$verification_ready"
grep -Fqx 'Expected-Max-Implementation-Files: 0' "$verification_ready"
grep -Fqx 'Worker-Route: TERRA' "$verification_ready"
grep -Fqx 'Complexity-Class: HIGH' "$verification_ready"
grep -Fqx 'Terra-Exception: IRREDUCIBLE_CROSS_BOUNDARY' "$verification_ready"
grep -Fq 'RESOURCE_PROGRESS_VERIFICATION_VECTOR_NORMALIZED root=001 task=001-revision-01 expected_files=0' \
	"$verification_project/logs/events.log"
grep -Eq 'RECOVERY_(TERRA_ESCALATION|EXHAUSTED_LUNA_ROUTE)_NORMALIZED root=001 task=001-revision-01 .*luna_failures=3.*exception=IRREDUCIBLE_CROSS_BOUNDARY' \
	"$verification_project/logs/events.log"

# Decomposition TSV fields are canonicalized at registration. In particular,
# generated validation commands may contain harmless surrounding whitespace,
# while assignment metadata is necessarily parsed without it. Both forms must
# resolve to one durable value so a valid node remains publishable.
{
	printf '%s\n' $'node_id\tparent_id\tdepends_on\tdeliverable\tacceptance_evidence\tfocused_validation\tallowed_paths\trequired_symbols\tleaf_type\tcomplexity_class\tworker_route'
	printf '%s\n' $' ws1 \t - \t - \t Implement whitespace-safe target \t target_symbol returns one \t  test "$(./focused-smoke)" = 1  \t src/a.c \t target_symbol \t LOCAL_IMPLEMENTATION \t LOW \t LUNA '
} > "$TEST_ROOT/whitespace-plan.tsv"
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2whitespace"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/whitespace-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/whitespace-harness.env"
chmod 600 "$TEST_ROOT/whitespace-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/whitespace-harness.env" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/whitespace-harness.env" \
	"$TEST_ROOT/whitespace-plan.tsv" >/dev/null
whitespace_dir="$TEST_ROOT/whitespace-state/projects/decompv2whitespace"
grep -Fqx $'ws1\t-\t-\tImplement whitespace-safe target\ttarget_symbol returns one\ttest "$(./focused-smoke)" = 1\tsrc/a.c\ttarget_symbol\tLOCAL_IMPLEMENTATION\tLOW\tLUNA' \
	"$whitespace_dir/control/project-decomposition-v2.tsv"
# Simulate a plan installed by an older harness version, before registration
# canonicalized fields. Lookup must normalize this durable legacy value too.
awk -F '\t' 'BEGIN {OFS="\t"} NR == 2 {$6="  " $6 "  "} {print}' \
	"$whitespace_dir/control/project-decomposition-v2.tsv" > "$whitespace_dir/control/project-decomposition-v2.tsv.tmp"
mv "$whitespace_dir/control/project-decomposition-v2.tsv.tmp" \
	"$whitespace_dir/control/project-decomposition-v2.tsv"
sed \
	-e 's/Project: decompv2/Project: decompv2whitespace/' \
	-e 's/Goal-ID: n1.goal/Goal-ID: ws1.goal/' \
	-e 's/Deliverable: Implement target_symbol locally/Deliverable: Implement whitespace-safe target/' \
	"$TEST_ROOT/task.md" > "$TEST_ROOT/whitespace-task.md"
sed '/^Architecture-Decisions:/a Validation-Class: CLEAN_GLOBAL' \
	"$TEST_ROOT/whitespace-task.md" > "$TEST_ROOT/whitespace-global-task.md"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/whitespace-harness.env" ws1 \
	"$TEST_ROOT/whitespace-global-task.md" ws1 >"$TEST_ROOT/whitespace-global.out" 2>&1; then
	printf 'Luna leaf unexpectedly accepted CLEAN_GLOBAL validation\n' >&2
	exit 1
fi
grep -Fq 'CLEAN_GLOBAL validation requires a Terra INTEGRATION leaf' "$TEST_ROOT/whitespace-global.out"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/whitespace-harness.env" ws1 \
	"$TEST_ROOT/whitespace-task.md" ws1 >/dev/null
grep -Eq $'^ws1\tACTIVE\tws1\t' "$whitespace_dir/control/project-plan-state.tsv"

cat > "$TEST_ROOT/reclassified-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
n1	-	-	Implement target_symbol locally	target_symbol returns one	test "$(./focused-smoke)" = 1	src/a.c	target_symbol	LOCAL_IMPLEMENTATION	LOW	LUNA
n2	-	n1	Integrate target_symbol with its caller	focused integration smoke passes	./integration-smoke	src/a.c,src/caller.c	target_symbol,call_target	MECHANICAL_API	LOW	LUNA
PLAN
reclass_output="$("$HARNESS_BIN/manager-reclassify-project-plan" "$TEST_ROOT/harness.env" \
	--install "$TEST_ROOT/reclassified-plan.tsv")"
grep -Fqx 'Reclassified 1 pending nodes: LUNA=1, TERRA=0 (100% Luna).' <<< "$reclass_output"
cmp -s "$TEST_ROOT/reclassified-plan.tsv" "$project_dir/control/project-decomposition-v2.tsv"
grep -Eq $'^n1\tACTIVE\t001\t' "$project_dir/control/project-plan-state.tsv"
grep -Eq $'^n2\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"
grep -Fqx $'n1\t-\t-\tImplement target_symbol locally\ttarget_symbol returns one\ttest "$(./focused-smoke)" = 1\tsrc/a.c\ttarget_symbol\tLOCAL_IMPLEMENTATION\tLOW\tLUNA' \
	"$project_dir/control/project-decomposition-v2.tsv"
grep -Fqx $'n2\t-\tn1\tIntegrate target_symbol with its caller\tfocused integration smoke passes\t./integration-smoke\tsrc/a.c,src/caller.c\ttarget_symbol,call_target\tMECHANICAL_API\tLOW\tLUNA' \
	"$project_dir/control/project-decomposition-v2.tsv"
test "$(find "$project_dir/control/reclassifications" -name '*-decomposition-before-*.tsv' | wc -l)" -eq 1
grep -R -Fqx 'pending_luna_percent=100' "$project_dir/control/reclassifications"/*-reclassification-*.env

cat > "$TEST_ROOT/bad-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
bad	-	-	Bad Luna route	evidence	focused-test	src/a.c	target_symbol	LOCAL_IMPLEMENTATION	MEDIUM	LUNA
PLAN
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2bad"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/bad-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/bad-harness.env"
chmod 600 "$TEST_ROOT/bad-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/bad-harness.env" >/dev/null
if "$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/bad-harness.env" \
	"$TEST_ROOT/bad-plan.tsv" >/dev/null 2>&1; then
	printf 'invalid medium-complexity Luna node was accepted\n' >&2
	exit 1
fi

cat > "$TEST_ROOT/terra-heavy-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
terra-only	-	-	Resolved local implementation	evidence	focused-test	src/a.c	target_symbol	LOCAL_IMPLEMENTATION	LOW	TERRA
PLAN
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2terraheavy"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/terra-heavy-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/terra-heavy-harness.env"
chmod 600 "$TEST_ROOT/terra-heavy-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/terra-heavy-harness.env" >/dev/null
if "$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/terra-heavy-harness.env" \
	"$TEST_ROOT/terra-heavy-plan.tsv" >/dev/null 2>&1; then
	printf 'DAG below the configured Luna minimum was accepted\n' >&2
	exit 1
fi

cat > "$TEST_ROOT/low-terra-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
t1	-	-	Implement target_symbol locally	target_symbol returns one	test "$(./focused-smoke)" = 1	src/a.c	target_symbol	LOCAL_IMPLEMENTATION	LOW	TERRA
t2	-	-	Add focused target_symbol fixture	fixture passes	./fixture-smoke	src/fixture.c	target_fixture	LOCAL_IMPLEMENTATION	LOW	LUNA
PLAN
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2lowterra"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/low-terra-state\"|" \
	-e 's/export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"/export HARNESS_PREFERRED_WORKER_ROUTE="TERRA"/' \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/low-terra-harness.env"
chmod 600 "$TEST_ROOT/low-terra-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/low-terra-harness.env" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/low-terra-harness.env" \
	"$TEST_ROOT/low-terra-plan.tsv" >/dev/null
sed -i 's/export HARNESS_PREFERRED_WORKER_ROUTE="TERRA"/export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"/' \
	"$TEST_ROOT/low-terra-harness.env"
sed \
	-e 's/Project: decompv2/Project: decompv2lowterra/' \
	-e 's/Goal-ID: n1.goal/Goal-ID: t1.goal/' \
	-e 's/Worker-Route: LUNA/Worker-Route: TERRA/' \
	"$TEST_ROOT/task.md" > "$TEST_ROOT/low-terra-task.md"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/low-terra-harness.env" 001 \
	"$TEST_ROOT/low-terra-task.md" t1 >/dev/null 2>&1; then
	printf 'resolved LOW local implementation was allowed to bypass Luna\n' >&2
	exit 1
fi

# Existing immutable ten-column DAGs may override an inherited HIGH/TERRA route
# when the manager proves the executable root leaf satisfies the Luna contract.
cat > "$TEST_ROOT/legacy-route-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	complexity_class	worker_route
t1	-	-	Implement target_symbol locally	target_symbol returns one	test "$(./focused-smoke)" = 1	src/a.c	target_symbol	HIGH	TERRA
t2	-	t1	Add focused target_symbol fixture	fixture passes	./fixture-smoke	src/fixture.c	target_fixture	LOW	LUNA
PLAN
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2legacyroute"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/legacy-route-state\"|" \
	-e 's/export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"/export HARNESS_PREFERRED_WORKER_ROUTE="TERRA"/' \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/legacy-route-harness.env"
chmod 600 "$TEST_ROOT/legacy-route-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/legacy-route-harness.env" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/legacy-route-harness.env" \
	"$TEST_ROOT/legacy-route-plan.tsv" >/dev/null
sed -i 's/export HARNESS_PREFERRED_WORKER_ROUTE="TERRA"/export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"/' \
	"$TEST_ROOT/legacy-route-harness.env"
sed \
	-e 's/Project: decompv2/Project: decompv2legacyroute/' \
	-e 's/Goal-ID: n1.goal/Goal-ID: t1.goal/' \
	"$TEST_ROOT/task.md" > "$TEST_ROOT/legacy-route-task.md"
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/legacy-route-harness.env" 001 \
	"$TEST_ROOT/legacy-route-task.md" t1 >/dev/null
grep -Fqx 'Worker-Route: LUNA' \
	"$TEST_ROOT/legacy-route-state/projects/decompv2legacyroute/tasks/decompv2legacyroute-task-001.ready.md"

# A Luna leaf may authorize a bounded capsule containing source, fixture,
# build-registration, and validation paths while retaining the independent
# five-implementation-file budget. Six path groups must not deadlock planning.
cat > "$TEST_ROOT/six-path-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
six	-	-	Implement one bounded six-path concern	focused six-path smoke passes	./six-path-smoke	src/a.c,src/b.c,include/a.h,tests/a.c,tests/fixture.dat,CMakeLists.txt	target_symbol	LOCAL_IMPLEMENTATION	LOW	LUNA
PLAN
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2six"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/six-path-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/six-path-harness.env"
chmod 600 "$TEST_ROOT/six-path-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/six-path-harness.env" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/six-path-harness.env" \
	"$TEST_ROOT/six-path-plan.tsv" >/dev/null
cat > "$TEST_ROOT/six-path-task.md" <<'TASK'
# Leaf-Goal Task Assignment

Project: decompv2six
Task-ID: 001
Task-Root: 001
Starting-Progress: 0%
Status: READY
Execution-Mode: LEAF_GOAL
Goal-ID: six.goal
Target-Criterion: six.done
Goal-Success-Evidence: focused six-path smoke passes
Focused-Validation: ./six-path-smoke
Allowed-Scope: src/a.c,src/b.c,include/a.h,tests/a.c,tests/fixture.dat,CMakeLists.txt
Baseline-Boundary: bounded six-path concern is incomplete
Hard-Block-Conditions: NONE
Leaf-Type: LOCAL_IMPLEMENTATION
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: -
Deliverable: Implement one bounded six-path concern
Required-Symbols: target_symbol
Context-Paths: src/a.c,src/b.c,include/a.h,tests/a.c,tests/fixture.dat,CMakeLists.txt
Architecture-Decisions: NONE
Expected-Max-Implementation-Files: 5
Expected-Max-Worker-Turns: 3
Root-Criterion: six.done

## Objective

Implement the bounded concern.

## Acceptance criteria

- The focused smoke passes.

## Validation commands

```text
./six-path-smoke
```
TASK
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/six-path-harness.env" 001 \
	"$TEST_ROOT/six-path-task.md" six >/dev/null
grep -Fqx 'Worker-Route: LUNA' \
	"$TEST_ROOT/six-path-state/projects/decompv2six/tasks/decompv2six-task-001.ready.md"

# The same public bin/ entry points must dispatch an explicit Light project to
# the namespaced implementation without requiring a second checkout.
printf 'prototype policy\n' > "$TEST_ROOT/policy.md"
cat > "$TEST_ROOT/light.env" <<ENV
export PROJECT="dispatchlight"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="$TEST_ROOT/repo/spec.md"
export DEVELOPMENT_POLICY="$TEST_ROOT/policy.md"
export HARNESS_MODE="light"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_ROOT="$TEST_ROOT/light-state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export ORACLE_CODEX_BIN="/bin/true"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/light.env"
light_check="$("$HARNESS_BIN/harness-check-env" "$TEST_ROOT/light.env")"
grep -Fq 'Project: dispatchlight' <<< "$light_check"
light_init="$("$HARNESS_BIN/harness-init" "$TEST_ROOT/light.env")"
grep -Fq 'Harness mode: light' <<< "$light_init"
light_status="$("$HARNESS_BIN/harness-status" "$TEST_ROOT/light.env")"
grep -Fq 'Harness mode: light' <<< "$light_status"

# The shared watcher must dispatch every environment independently. A Full
# project in the same directory must not force the Light status loader (or vice
# versa), and the project name must remain untruncated.
mkdir -p "$TEST_ROOT/watch-mixed" "$TEST_ROOT/watch-light"
cp "$TEST_ROOT/harness.env" "$TEST_ROOT/watch-mixed/full.env"
cp "$TEST_ROOT/light.env" "$TEST_ROOT/watch-mixed/light.env"
cp "$TEST_ROOT/light.env" "$TEST_ROOT/watch-light/light.env"
# A large trace directory used to make the newest-file pipelines terminate
# with SIGPIPE under `set -o pipefail`, truncating every later watcher row.
for index in $(seq -w 1 1200); do
	printf '{"type":"item.completed"}\n' > "$project_dir/logs/watch-regression-$index.jsonl"
done
mixed_watch="$(COLUMNS=100 LINES=24 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/watch-mixed")"
grep -Eq '^decompv2 +\| *0\| w/stopped +\| 0/2' <<< "$mixed_watch"
grep -Eq '^dispatchlight +\| *0\| m/stopped' <<< "$mixed_watch"
! grep -q 'CONFIGURATION ERROR' <<< "$mixed_watch"
! awk 'length($0) > 100 {bad=1} END {exit bad}' <<< "$mixed_watch"
printf 'operator decision required\n' > \
	"$project_dir/control/progress/decompv2-task-n1.needs-human.md"
human_watch="$(COLUMNS=100 LINES=24 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/watch-mixed")"
grep -Eq '^decompv2 +\| *0\| paused' <<< "$human_watch"
! grep -q $'\033\[' <<< "$human_watch"
human_watch_max_row_lines="$(awk '
	NR <= 2 { next }
	/^[^[:space:]]/ { if (height > maximum) maximum=height; height=1; next }
	{ height++ }
	END { if (height > maximum) maximum=height; print maximum+0 }
' <<< "$human_watch")"
(( human_watch_max_row_lines <= 3 ))
human_watch_color="$(HARNESS_WATCH_COLOR=always COLUMNS=100 LINES=24 \
	"$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/watch-mixed")"
grep -Eq $'^decompv2 +\| *0\| \033\[31mpaused\033\[0m +\|' <<< "$human_watch_color"
! grep -Fq $'\033[7m' <<< "$human_watch_color"
# Stopped supervisors are an intentional operator-controlled state, not an
# irregular harness condition, and must remain visually normal.
grep -Eq '^dispatchlight +\| *0\| m/stopped' <<< "$human_watch_color"
! grep -Eq $'dispatchlight +\| *0\| \033\[31mm/stopped' <<< "$human_watch_color"
rm -f -- "$project_dir/control/progress/decompv2-task-n1.needs-human.md"
light_watch="$(COLUMNS=100 LINES=24 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/watch-light")"
grep -q '^dispatchlight ' <<< "$light_watch"
! grep -q 'CONFIGURATION ERROR' <<< "$light_watch"

printf 'task_id=decompv2-task-n2\n' > "$project_dir/control/project.complete"
done_watch="$(COLUMNS=100 LINES=200 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/watch-mixed")"
grep -Eq '^decompv2 +\| *0\| done +\| [0-9]+/2 +\| *$' <<< "$done_watch"
done_watch_bad_rows="$(awk '
	NR <= 2 { next }
	/^[^[:space:]]/ {
		if (is_done && height != 1) bad++
		height=1
		is_done=($0 ~ /\|[[:space:]]*done[[:space:]]*\|/)
		next
	}
	{ height++ }
	END { if (is_done && height != 1) bad++; print bad+0 }
' <<< "$done_watch")"
(( done_watch_bad_rows == 0 ))
rm -f -- "$project_dir/control/project.complete"

printf 'decomposition v2 tests passed\n'
