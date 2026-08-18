#!/usr/bin/env bash

set -Eeuo pipefail
TEST_ROOT="$(mktemp -d /tmp/coding-harness-root-liveness.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\\n" "$TEST_ROOT" >&2' EXIT
else
	trap 'rm -rf -- "$TEST_ROOT"' EXIT
fi
HARNESS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'bounded root liveness test\n' > "$TEST_ROOT/repo/spec.md"
mkdir -p "$TEST_ROOT/repo/src/consumer"
printf 'int consumer_smoke(void) { return 0; }\n' > "$TEST_ROOT/repo/src/consumer/smoke.c"
printf 'int remediation_fixture(void) { return 0; }\n' > "$TEST_ROOT/repo/remediation.c"
cat > "$TEST_ROOT/repo/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(liveness C)
add_executable(liveness_consumer_smoke src/consumer/smoke.c)
add_executable(other_smoke src/consumer/smoke.c)
CMAKE
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name Harness-Test
git -C "$TEST_ROOT/repo" config user.email harness@example.invalid
git -C "$TEST_ROOT/repo" add spec.md CMakeLists.txt src/consumer/smoke.c remediation.c
git -C "$TEST_ROOT/repo" commit -qm initial
cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="livenessproj"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_DECOMPOSITION_V2="0"
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_MAX_TOTAL_ROOT_REVIEWS="2"
export HARNESS_MAX_TOTAL_ROOT_REPLANS="8"
export HARNESS_MAX_ROOT_CHILD_CRITERIA="32"
export HARNESS_MAX_CRITERION_DEPTH="8"
export HARNESS_MAX_ROOT_LIFETIME_SECONDS="86400"
export HARNESS_MAX_ROOT_PROCESSED_TOKENS="100000000"
ENV
chmod 600 "$TEST_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
project="$TEST_ROOT/state/projects/livenessproj"

cat > "$project/control/project-plan.tsv" <<'TSV'
# item_id	title
UPSTREAM	Accepted upstream contract
CONSUMER	Consumer implementation
TSV
cat > "$project/control/project-plan-state.tsv" <<'TSV'
# item_id	status	task_root	updated_at
UPSTREAM	COMPLETE	upstream	2026-01-01T00:00:00Z
CONSUMER	ACTIVE	consumer	2026-01-01T00:00:01Z
TSV
cat > "$project/control/project-decomposition-v2.tsv" <<'TSV'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	complexity_class	worker_route	leaf_type
UPSTREAM	-	-	contract	contract accepted	true	src/upstream	-	LOW	LUNA	LOCAL_IMPLEMENTATION
CONSUMER	-	UPSTREAM	consumer	consumer passes	true	src/consumer	-	LOW	LUNA	LOCAL_IMPLEMENTATION
TSV
mkdir -p "$project/control/progress" "$project/archive"
cat > "$project/control/progress/livenessproj-task-consumer.root-assignment.md" <<'MD'
Task-ID: consumer
Task-Root: consumer
Root-Criterion: consumer.validation
Focused-Validation: cmake -S . -B build && cmake --build build --target liveness_consumer_smoke
Allowed-Scope: src/consumer
Architecture-Decisions: NONE
Expected-Max-Implementation-Files: 2
Expected-Max-Worker-Turns: 2
MD

# A verified parent increment plus a newly declared child criterion authorizes
# a bounded LOW/LUNA implementation continuation even while the parent node's
# final produced architecture decision remains proposed until root completion.
cat > "$project/control/progress/livenessproj-task-bounded-child.criteria.tsv" <<'TSV'
item_id	state	verified_by	evidence_sha256	updated_at
bounded-child.contract	VERIFIED	bounded-child-revision-01	sha256:test	2026-01-01T00:00:00Z
TSV
cat > "$TEST_ROOT/bounded-child-assignment.md" <<'MD'
Task-ID: bounded-child-revision-02
Task-Root: bounded-child
Target-Criterion: bounded-child.acceptance.implementation
Architecture-Decisions: NONE
MD
cat > "$TEST_ROOT/bounded-child-decomposition.tsv" <<'TSV'
parent_criterion	child_criterion	title	acceptance_evidence
bounded-child.acceptance	bounded-child.acceptance.implementation	Implement bounded child	Focused validation passes
bounded-child.acceptance	bounded-child.acceptance.validation	Validate bounded child	Independent validation passes
TSV
bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	recovery_candidate_targets_verified_child bounded-child "$3" "$4"
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env" "$TEST_ROOT/bounded-child-assignment.md" \
	"$TEST_ROOT/bounded-child-decomposition.tsv"
sed -i 's/^Architecture-Decisions: NONE$/Architecture-Decisions: ADR-unresolved/' \
	"$TEST_ROOT/bounded-child-assignment.md"
if bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	recovery_candidate_targets_verified_child bounded-child "$3" "$4"
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env" "$TEST_ROOT/bounded-child-assignment.md" \
	"$TEST_ROOT/bounded-child-decomposition.tsv"; then
	printf 'unresolved architecture-producing child was incorrectly Luna-authorized\n' >&2
	exit 1
fi

# Stateful restarts preserve tracked implementation changes that fall within
# the registered DAG, while retaining the strict untracked-file boundary used
# for fresh starts and specification handoff.
printf '/* preserved harness work */\n' >> "$TEST_ROOT/repo/src/consumer/smoke.c"
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; require_resumable_repository_start_state' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env"

# A live manager-remediation result may authorize a bounded path outside the
# original DAG node. Restart validation must preserve that work while still
# refusing unrelated historical scope.
printf '/* preserved audited remediation */\n' >> "$TEST_ROOT/repo/remediation.c"
if bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; require_resumable_repository_start_state' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env" >"$TEST_ROOT/remediation-before.out" 2>"$TEST_ROOT/remediation-before.err"; then
	printf 'stateful restart accepted remediation scope without a live artifact\n' >&2
	exit 1
fi
mkdir -p "$project/results"
cat > "$project/results/livenessproj-task-consumer-revision-00.result.md" <<'MD'
Task-ID: consumer-revision-00
Task-Root: consumer
Goal-Outcome: COMPLETE
MD
cat > "$project/archive/livenessproj-task-consumer-revision-00.assignment.md" <<'MD'
Task-ID: consumer-revision-00
Task-Root: consumer
Allowed-Scope: remediation.c
Remediation-Scope: remediation.c
MD
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; require_resumable_repository_start_state' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env"
rm -f "$project/results/livenessproj-task-consumer-revision-00.result.md"
cat > "$project/control/progress/livenessproj-task-consumer.needs-replan.md" <<'MD'
# Root Task Needs Replanning

Task-Root: consumer
Trigger-Outcome: MANAGER_REMEDIATION_CONTINUATION
Remediation-Scope: remediation.c
Context-Paths: remediation.c,unrelated-read-only.c
MD
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; require_resumable_repository_start_state' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env"
rm -f "$project/control/progress/livenessproj-task-consumer.needs-replan.md"
printf 'not attributable to the DAG\n' > "$TEST_ROOT/repo/untracked-restart.txt"
if bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; require_resumable_repository_start_state' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env" >"$TEST_ROOT/restart.out" 2>"$TEST_ROOT/restart.err"; then
	printf 'stateful restart accepted an unrelated untracked file\n' >&2
	exit 1
fi
grep -Fq 'repository has non-ignored untracked files' "$TEST_ROOT/restart.err"
rm -f "$TEST_ROOT/repo/untracked-restart.txt"

# Reaching a structural decomposition ceiling prevents only another child
# split. It must not block execution or replanning at the deepest existing
# leaf; manager-publish-task separately rejects a candidate that would exceed
# either structural limit.
cat > "$project/control/progress/livenessproj-task-depthlimit.root-assignment.md" <<'MD'
Task-ID: depthlimit
Task-Root: depthlimit
Root-Criterion: depth.c0
MD
cat > "$project/control/progress/livenessproj-task-depthlimit.criterion-decomposition.tsv" <<'TSV'
parent_criterion	child_criterion	title	acceptance_evidence
depth.c0	depth.c1	depth 1	pass 1
depth.c1	depth.c2	depth 2	pass 2
depth.c2	depth.c3	depth 3	pass 3
depth.c3	depth.c4	depth 4	pass 4
depth.c4	depth.c5	depth 5	pass 5
depth.c5	depth.c6	depth 6	pass 6
depth.c6	depth.c7	depth 7	pass 7
depth.c7	depth.c8	depth 8	pass 8
TSV
depth_reason="$(bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	HARNESS_MAX_ROOT_CHILD_CRITERIA=8
	HARNESS_MAX_CRITERION_DEPTH=8
	root_liveness_violation_reason depthlimit || true
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env")"
[[ -z "$depth_reason" ]]
cat > "$project/archive/livenessproj-task-consumer-revision-01.accepted.md" <<'MD'
Task-ID: consumer-revision-01
Task-Root: consumer
MD
cat > "$project/archive/livenessproj-task-consumer-revision-02.checkpointed.md" <<'MD'
Task-ID: consumer-revision-02
Task-Root: consumer
MD

# Legacy epoch files from earlier releases are audit snapshots only. They may
# not subtract prior attempts from the lifetime acceptance-boundary budget.
cat > "$project/control/progress/livenessproj-task-consumer.liveness-epoch.env" <<'ENV'
reviewed_attempts=2
criterionless_reviews=0
total_replans=0
lifetime_seconds=0
processed_tokens=0
source=legacy-active-plan-repair
ENV

# A generic monotonic liveness pause must not erase a more specific pending
# exhausted-scope transition. Architecture resolution opens a fresh budget
# epoch but still owes the adjacent-scope remediation.
bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	mark_root_needs_replan consumer-revision-02 \
		"the declared remediation path contains no required consumer" \
		MANAGER_REMEDIATION_SCOPE_EXHAUSTED LOCAL_CODE_PREREQUISITE \
		src/exhausted-provider.c >/dev/null
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env"

audit_output="$("$HARNESS_BIN/harness-audit-root-liveness" "$TEST_ROOT/harness.env" consumer)"
reassessment="$project/control/progress/livenessproj-task-consumer.architecture-reassessment-required.md"
[[ "$audit_output" == "$reassessment" ]]
grep -Fqx 'Category: TOTAL_ROOT_REVIEWS' "$reassessment"
grep -Fqx 'Total-Root-Reviews: 2' "$reassessment"
grep -Fqx 'Pending-Replan-Trigger: MANAGER_REMEDIATION_SCOPE_EXHAUSTED' "$reassessment"
grep -Fqx 'Pending-Replan-Remediation-Scope: src/exhausted-provider.c' "$reassessment"
grep -Fq 'Project status: ARCHITECTURE_REASSESSMENT_REQUIRED.' \
	< <("$HARNESS_BIN/harness-status" --machine "$TEST_ROOT/harness.env")
grep -Eq '^Active root progress: [0-9]+% \([0-9]+ verified item\(s\)\)\.$' \
	< <("$HARNESS_BIN/harness-status" --machine "$TEST_ROOT/harness.env")

# A root-local architecture fuse must not make an independent runnable root
# disappear from project status or the multi-root scheduler view.
cat > "$project/tasks/livenessproj-task-independent.ready.md" <<'MD'
Task-ID: independent
Task-Root: independent
Worker-Route: LUNA
MD
grep -Fq 'Project status: ACTIVE_WITH_PAUSED_ROOTS.' \
	< <("$HARNESS_BIN/harness-status" --machine "$TEST_ROOT/harness.env")
rm -f "$project/tasks/livenessproj-task-independent.ready.md"
cat > "$project/control/progress/livenessproj-task-independent.replanning.md" <<'MD'
Task-Root: independent
MD
grep -Fq 'Project status: ACTIVE_WITH_PAUSED_ROOTS.' \
	< <("$HARNESS_BIN/harness-status" --machine "$TEST_ROOT/harness.env")
rm -f "$project/control/progress/livenessproj-task-independent.replanning.md"

cat > "$TEST_ROOT/resolution.md" <<'MD'
The operator reviewed the bounded evidence and approved a revised architecture boundary.
MD
if "$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" consumer "$TEST_ROOT/resolution.md" \
	>"$TEST_ROOT/liveness-resolution.out" 2>"$TEST_ROOT/liveness-resolution.err"; then
	printf 'unchanged acceptance boundary reset lifetime liveness\n' >&2
	exit 1
fi
grep -Fq 'incident resolution cannot reset unchanged liveness' \
	"$TEST_ROOT/liveness-resolution.err"
[[ -f "$reassessment" ]]

# A confirmed harness defect may be rearmed only through an installed,
# operator-audited fix commit. Raw histories stay in place while the active
# bounded epoch restarts at their current values.
bug_root=bugroot
for revision in 01 02; do
	cat > "$project/archive/livenessproj-task-$bug_root-revision-$revision.accepted.md" <<MD
Task-ID: $bug_root-revision-$revision
Task-Root: $bug_root
MD
done
sed -i 's/CONSUMER\tACTIVE\tconsumer/CONSUMER\tACTIVE\tbugroot/' \
	"$project/control/project-plan-state.tsv"
sed 's/consumer/bugroot/g' \
	"$project/control/progress/livenessproj-task-consumer.root-assignment.md" > \
	"$project/control/progress/livenessproj-task-$bug_root.root-assignment.md"
cat > "$project/archive/livenessproj-task-$bug_root-revision-02.assignment.md" <<'MD'
Task-ID: bugroot-revision-02
Task-Root: bugroot
Manager-Remediation: 1
Blocker-Class: LOCAL_CODE_PREREQUISITE
Remediation-Scope: src/consumer/smoke.c
Context-Paths: src/consumer/smoke.c
MD
cat > "$project/archive/livenessproj-task-$bug_root-revision-02.rejected-result.md" <<'MD'
# Rejected Task Result

Task-ID: bugroot-revision-02
Task-Root: bugroot
Goal-Outcome: NEEDS_DECOMPOSITION
Decomposition-Reason: VALIDATION_PREREQUISITE
MD
bug_marker="$project/control/progress/livenessproj-task-$bug_root.architecture-reassessment-required.md"
cat > "$bug_marker" <<MD
# Architecture Reassessment Required

Project: livenessproj
Task-Root: $bug_root
Triggered-By: $bug_root-revision-02
Category: TOTAL_ROOT_REVIEWS
MD
harness_fix_commit="$(git -C "$HARNESS_HOME" rev-parse HEAD)"
cat > "$TEST_ROOT/bug-resolution.md" <<MD
Resolution-Action: REARM_AFTER_HARNESS_BUG
Harness-Fix-Commit: $harness_fix_commit

The bounded retry loop was caused by the installed harness defect and the fix
was regression-tested before this explicit rearm.
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" "$bug_root" "$TEST_ROOT/bug-resolution.md" >/dev/null
bug_epoch="$project/control/progress/livenessproj-task-$bug_root.liveness-epoch.env"
grep -Fqx 'authorized_reset=1' "$bug_epoch"
grep -Fqx 'budget_scope=harness-bug-corrected-boundary' "$bug_epoch"
grep -Fqx "fix_commit=$harness_fix_commit" "$bug_epoch"
[[ "$(bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; root_liveness_epoch_delta "$3" reviewed_attempts "$(root_reviewed_attempt_count "$3")"' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env" "$bug_root")" == 0 ]]
bug_replan="$project/control/progress/livenessproj-task-$bug_root.needs-replan.md"
grep -Fqx 'Trigger-Outcome: MANAGER_REMEDIATION_SCOPE_EXHAUSTED' "$bug_replan"
grep -Fqx 'Remediation-Scope: src/consumer/smoke.c' "$bug_replan"
grep -Fqx 'Inferred-Pending-Replan-Trigger: MANAGER_REMEDIATION_SCOPE_EXHAUSTED' \
	"$project"/archive/architecture-reassessments/livenessproj-task-bugroot.*.resolved.md
cat > "$bug_marker" <<MD
# Architecture Reassessment Required

Project: livenessproj
Task-Root: $bug_root
Triggered-By: $bug_root-revision-02
Category: TOTAL_ROOT_REVIEWS
MD
if "$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" "$bug_root" "$TEST_ROOT/bug-resolution.md" >/dev/null 2>&1; then
	printf 'the same harness fix commit rearmed one root twice\n' >&2
	exit 1
fi
rm -f "$bug_marker" "$bug_replan"
sed -i 's/CONSUMER\tACTIVE\tbugroot/CONSUMER\tACTIVE\tconsumer/' \
	"$project/control/project-plan-state.tsv"

# A tokens-without-gain investigation has a separate audited rearm. It resets
# only the efficiency comparison boundary after an installed harness fix and
# cannot silently reset the root's other monotonic liveness budgets.
efficiency_root=efficiencyroot
efficiency_marker="$project/control/progress/livenessproj-task-$efficiency_root.architecture-reassessment-required.md"
cat > "$efficiency_marker" <<MD
# Architecture Reassessment Required

Project: livenessproj
Task-Root: $efficiency_root
Triggered-By: $efficiency_root-revision-03
Category: TOKENS_WITHOUT_VERIFIED_GAIN
MD
efficiency_tokens="$project/control/progress/livenessproj-task-$efficiency_root.tokens.tsv"
printf 'recorded_at\ttask_id\trole\tthread_id\tinput_tokens\toutput_tokens\tprocessed_delta\n' > "$efficiency_tokens"
printf 'now\t%s-revision-03\tworker_luna\tthread\t0\t600\t600\n' "$efficiency_root" >> "$efficiency_tokens"
cat > "$project/control/progress/livenessproj-task-$efficiency_root.efficiency-baseline.env" <<'ENV'
processed_tokens=0
verified_facets=0
agent_episodes=0
ENV
cat > "$TEST_ROOT/efficiency-resolution.md" <<MD
Resolution-Action: REARM_EFFICIENCY_AFTER_HARNESS_BUG
Harness-Fix-Commit: $harness_fix_commit

The trusted patch transaction was corrected and regression-tested.
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" "$efficiency_root" "$TEST_ROOT/efficiency-resolution.md" >/dev/null
efficiency_baseline="$project/control/progress/livenessproj-task-$efficiency_root.efficiency-baseline.env"
grep -Fqx 'processed_tokens=600' "$efficiency_baseline"
grep -Fqx 'agent_episodes=1' "$efficiency_baseline"
grep -Fqx "harness_fix_commit=$harness_fix_commit" "$efficiency_baseline"
[[ ! -f "$project/control/progress/livenessproj-task-$efficiency_root.liveness-epoch.env" ]]
cat > "$efficiency_marker" <<MD
# Architecture Reassessment Required

Project: livenessproj
Task-Root: $efficiency_root
Triggered-By: $efficiency_root-revision-03
Category: TOKENS_WITHOUT_VERIFIED_GAIN
MD
if "$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" "$efficiency_root" "$TEST_ROOT/efficiency-resolution.md" >/dev/null 2>&1; then
	printf 'the same harness fix commit rearmed one efficiency boundary twice\n' >&2
	exit 1
fi
rm -f "$efficiency_marker"

# Raising a governing lifetime limit is explicit operator authority; unlike an
# epoch subtraction, it remains visible in configuration and status.
sed -i 's/HARNESS_MAX_TOTAL_ROOT_REVIEWS="2"/HARNESS_MAX_TOTAL_ROOT_REVIEWS="3"/' \
	"$TEST_ROOT/harness.env"
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" consumer "$TEST_ROOT/resolution.md" >/dev/null
[[ ! -f "$reassessment" ]]
[[ -f "$project/control/progress/livenessproj-task-consumer.needs-replan.md" ]]
grep -Fqx 'Trigger-Outcome: MANAGER_REMEDIATION_SCOPE_EXHAUSTED' \
	"$project/control/progress/livenessproj-task-consumer.needs-replan.md"
grep -Fqx 'Remediation-Scope: src/exhausted-provider.c' \
	"$project/control/progress/livenessproj-task-consumer.needs-replan.md"

# Typed closure and Luna-policy transitions retain their complete recovery
# authority across a liveness investigation instead of becoming generic
# ARCHITECTURE_REASSESSMENT_RESOLVED replans.
for typed_root in closureroot migrationroot; do
	sed "s/consumer/$typed_root/g" \
		"$project/control/progress/livenessproj-task-consumer.root-assignment.md" > \
		"$project/control/progress/livenessproj-task-$typed_root.root-assignment.md"
done
sed -i 's/CONSUMER\tACTIVE\tconsumer/CONSUMER\tACTIVE\tclosureroot/' \
	"$project/control/project-plan-state.tsv"
closure_marker="$project/control/progress/livenessproj-task-closureroot.architecture-reassessment-required.md"
cat > "$closure_marker" <<'MD'
# Architecture Reassessment Required

Project: livenessproj
Task-Root: closureroot
Triggered-By: closureroot-revision-02
Category: STATE_OSCILLATION
Pending-Replan-Trigger: CONTEXT_CLOSURE_REPAIR
Pending-Replan-Triggered-By: closureroot-revision-01
Pending-Replan-Closure-Condition: INDEX_EVIDENCE_MISSING
Pending-Replan-Closure-Repair-Action: REFRESH_INDEX_OR_OVERLAY
Pending-Replan-Closure-Repair-Provider: scip
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" closureroot "$TEST_ROOT/resolution.md" >/dev/null
closure_replan="$project/control/progress/livenessproj-task-closureroot.needs-replan.md"
grep -Fqx 'Trigger-Outcome: CONTEXT_CLOSURE_REPAIR' "$closure_replan"
grep -Fqx 'Closure-Condition: INDEX_EVIDENCE_MISSING' "$closure_replan"
grep -Fqx 'Closure-Repair-Action: REFRESH_INDEX_OR_OVERLAY' "$closure_replan"
grep -Fqx 'Closure-Repair-Provider: scip' "$closure_replan"
sed -i 's/CONSUMER\tACTIVE\tclosureroot/CONSUMER\tACTIVE\tmigrationroot/' \
	"$project/control/project-plan-state.tsv"
migration_marker="$project/control/progress/livenessproj-task-migrationroot.architecture-reassessment-required.md"
cat > "$migration_marker" <<'MD'
# Architecture Reassessment Required

Project: livenessproj
Task-Root: migrationroot
Triggered-By: migrationroot-revision-02
Category: STATE_OSCILLATION
Pending-Replan-Trigger: LUNA_ONLY_POLICY_MIGRATION
Pending-Replan-Triggered-By: migrationroot-revision-01
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" migrationroot "$TEST_ROOT/resolution.md" >/dev/null
grep -Fqx 'Trigger-Outcome: LUNA_ONLY_POLICY_MIGRATION' \
	"$project/control/progress/livenessproj-task-migrationroot.needs-replan.md"
sed -i 's/CONSUMER\tACTIVE\tmigrationroot/CONSUMER\tACTIVE\tconsumer/' \
	"$project/control/project-plan-state.tsv"
(
	source "$TEST_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_liveness_epoch_delta consumer reviewed_attempts "$(root_reviewed_attempt_count consumer)")" == 2 ]]
	[[ "$(root_liveness_epoch_delta consumer total_replans "$(root_total_replan_count consumer)")" == 0 ]]
)
"$HARNESS_BIN/harness-unblock-root" "$TEST_ROOT/harness.env" consumer >/dev/null
find "$project/archive/architecture-reassessments" -type f -name '*.resolved.md' | grep -q .
cat > "$TEST_ROOT/expanded-revision.md" <<'MD'
# Unauthorized Scope Expansion

Task-ID: consumer-revision-03
Task-Root: consumer
Execution-Mode: LEAF_GOAL
Goal-ID: consumer.scope-expansion
Target-Criterion: consumer.validation
Goal-Success-Evidence: deterministic validation passes
Focused-Validation: true
Allowed-Scope: src/consumer,src/foreign
Baseline-Boundary: accepted consumer root
Hard-Block-Conditions: explicit external authority only

## Objective

Expand beyond the immutable root scope.

## Acceptance criteria

- Deterministic validation passes.

## Validation commands

true
MD
set +e
publish_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-03 "$TEST_ROOT/expanded-revision.md")"
publish_status=$?
set -e
[[ "$publish_status" -eq 6 ]]
[[ "$publish_output" == "$reassessment" ]]
grep -Fqx 'Category: IMMUTABLE_ROOT_AUTHORITY' "$reassessment"
[[ ! -f "$project/tasks/livenessproj-task-consumer-revision-03.ready.md" ]]
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" consumer "$TEST_ROOT/resolution.md" >/dev/null
[[ -f "$project/control/progress/livenessproj-task-consumer.needs-replan.md" ]]
"$HARNESS_BIN/harness-unblock-root" "$TEST_ROOT/harness.env" consumer >/dev/null

# A read-only continuation may inspect additional repository evidence, but it
# must retain the immutable root's write scope and must not trigger an
# architecture reassessment merely because a model copied context paths into
# Allowed-Scope.
sed -i 's/HARNESS_DECOMPOSITION_V2="0"/HARNESS_DECOMPOSITION_V2="1"/' \
	"$TEST_ROOT/harness.env"
cat > "$TEST_ROOT/read-only-expanded-revision.md" <<'MD'
# Read-only Evidence Expansion

Task-ID: consumer-revision-04
Task-Root: consumer
Execution-Mode: LEAF_GOAL
Goal-ID: consumer.read-only-evidence
Target-Criterion: consumer.validation
Goal-Success-Evidence: deterministic validation passes
Focused-Validation: true
Allowed-Scope: src/consumer,docs/additional-evidence.md
Baseline-Boundary: accepted consumer root
Hard-Block-Conditions: explicit external authority only
Leaf-Type: DOCUMENTATION
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: UPSTREAM
Deliverable: consumer
Required-Symbols: -
Context-Paths: src/consumer,docs/additional-evidence.md
Architecture-Decisions: NONE
Validation-Class: FOCUSED
Expected-Max-Implementation-Files: 0
Expected-Max-Worker-Turns: 1

## Objective

Read additional evidence without changing repository files.

## Acceptance criteria

- Deterministic validation passes.

## Validation commands

true
MD
read_only_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-04 "$TEST_ROOT/read-only-expanded-revision.md")"
read_only_ready="$project/tasks/livenessproj-task-consumer-revision-04.ready.md"
if [[ "$read_only_output" != "$read_only_ready" ]]; then
	cat "$read_only_output" >&2
	exit 1
fi
grep -Fqx 'Allowed-Scope: src/consumer' "$read_only_ready"
[[ ! -f "$reassessment" ]]
rm -f "$read_only_ready"

# Generated build trees are validation context, not writable source authority;
# execution budgets are clamped to the immutable root ceiling instead of
# creating a false architecture reassessment.
cat > "$TEST_ROOT/generated-validation-revision.md" <<'MD'
# Generated Validation Recovery

Task-ID: consumer-revision-05
Task-Root: consumer
Execution-Mode: LEAF_GOAL
Goal-ID: consumer.generated-validation
Target-Criterion: consumer.validation
Goal-Success-Evidence: deterministic validation passes
Focused-Validation: cmake -S . -B build && cmake --build build
Allowed-Scope: build
Baseline-Boundary: accepted consumer root
Hard-Block-Conditions: explicit external authority only
Leaf-Type: LOCAL_IMPLEMENTATION
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: UPSTREAM
Deliverable: consumer
Required-Symbols: -
Context-Paths: build,src/consumer
Architecture-Decisions: NONE
Validation-Class: FOCUSED
Expected-Max-Implementation-Files: 3
Expected-Max-Worker-Turns: 3

## Objective

Run the generated validation target without broadening source authority.

## Acceptance criteria

- Deterministic validation passes.

## Validation commands

cmake -S . -B build && cmake --build build
MD
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-05 "$TEST_ROOT/generated-validation-revision.md" \
	>"$TEST_ROOT/global-focused.out" 2>"$TEST_ROOT/global-focused.err"; then
	printf 'unqualified all-target build unexpectedly accepted as FOCUSED validation\n' >&2
	exit 1
fi
grep -Fq 'FOCUSED validation cannot run an unqualified CMake all-target build' \
	"$TEST_ROOT/global-focused.err"
sed -i 's/cmake --build build/cmake --build build --target liveness_consumer_smoke/g' \
	"$TEST_ROOT/generated-validation-revision.md"
generated_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-05 "$TEST_ROOT/generated-validation-revision.md")"
generated_ready="$project/tasks/livenessproj-task-consumer-revision-05.ready.md"
[[ "$generated_output" == "$generated_ready" ]]
grep -Fqx 'Allowed-Scope: src/consumer' "$generated_ready"
grep -Fqx 'Expected-Max-Implementation-Files: 2' "$generated_ready"
grep -Fqx 'Expected-Max-Worker-Turns: 2' "$generated_ready"
[[ ! -f "$reassessment" ]]
rm -f "$generated_ready"

# A recovery planner may omit a repository target's stable namespace while
# naming an otherwise unique literal CMake target. Normalize that mechanical
# alias before publication so a nonexistent target cannot consume worker and
# review turns or cause false scope expansion.
sed \
	-e 's/consumer-revision-05/consumer-revision-06/g' \
	-e 's/consumer.generated-validation/consumer.cmake-target-alias/' \
	-e 's/liveness_consumer_smoke/consumer_smoke/g' \
	"$TEST_ROOT/generated-validation-revision.md" > "$TEST_ROOT/cmake-target-alias-revision.md"
target_alias_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-06 "$TEST_ROOT/cmake-target-alias-revision.md")"
target_alias_ready="$project/tasks/livenessproj-task-consumer-revision-06.ready.md"
[[ "$target_alias_output" == "$target_alias_ready" ]]
grep -Fqx 'Focused-Validation: cmake -S . -B build && cmake --build build --target liveness_consumer_smoke' "$target_alias_ready"
grep -Fqx 'cmake -S . -B build && cmake --build build --target liveness_consumer_smoke' "$target_alias_ready"
grep -Fq 'CMAKE_TARGET_ALIAS_NORMALIZED root=consumer task=consumer-revision-06 requested=consumer_smoke registered=liveness_consumer_smoke' \
	"$project/logs/events.log"
rm -f "$target_alias_ready"

# A manager correction may move the executable immutable-root command into
# Validation-Command while leaving a descriptive Focused-Validation field.
# Normalize that exact trusted command mechanically instead of spending another
# model action reversing the field-shape mistake.
sed \
	-e 's/consumer-revision-05/consumer-revision-11/g' \
	-e 's/consumer.generated-validation/consumer.validation-field-normalization/' \
	-e 's|^Focused-Validation:.*|Focused-Validation: FOCUSED: run the immutable consumer smoke boundary|' \
	"$TEST_ROOT/generated-validation-revision.md" > "$TEST_ROOT/validation-field-normalized-revision.md"
sed -i '/^Focused-Validation:/a Validation-Command: cmake -S . -B build && cmake --build build --target liveness_consumer_smoke' \
	"$TEST_ROOT/validation-field-normalized-revision.md"
validation_field_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-11 "$TEST_ROOT/validation-field-normalized-revision.md")"
validation_field_ready="$project/tasks/livenessproj-task-consumer-revision-11.ready.md"
[[ "$validation_field_output" == "$validation_field_ready" ]]
grep -Fqx 'Focused-Validation: cmake -S . -B build && cmake --build build --target liveness_consumer_smoke' \
	"$validation_field_ready"
grep -Fq 'FOCUSED_VALIDATION_NORMALIZED root=consumer task=consumer-revision-11 source=immutable-root-validation' \
	"$project/logs/events.log"
rm -f "$validation_field_ready"

# Recovery coding leaves must be implementation-ready before they consume an
# agent invocation. Review descriptors and unresolved discovery objectives are
# planning work, while directly executed CMake binaries must be built by the
# same focused validation command.
sed \
	-e 's/consumer-revision-05/consumer-revision-07/g' \
	-e 's|Focused-Validation: cmake -S . -B build && cmake --build build --target liveness_consumer_smoke|Focused-Validation: FOCUSED: rg -n consumer_smoke src/consumer/smoke.c|' \
	-e 's|cmake --build build --target liveness_consumer_smoke|rg -n consumer_smoke src/consumer/smoke.c|g' \
	"$TEST_ROOT/generated-validation-revision.md" > "$TEST_ROOT/descriptive-coding-revision.md"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-07 "$TEST_ROOT/descriptive-coding-revision.md" \
	>"$TEST_ROOT/descriptive-coding.out" 2>&1; then
	printf 'coding recovery accepted a source-audit review descriptor as validation\n' >&2
	exit 1
fi
grep -Fq 'Focused-Validation must be one machine-executable shell command' \
	"$TEST_ROOT/descriptive-coding.out"

sed \
	-e 's/consumer-revision-05/consumer-revision-08/g' \
	-e 's/Run the generated validation target/Determine the exact caller contract and run the generated validation target/' \
	"$TEST_ROOT/generated-validation-revision.md" > "$TEST_ROOT/exploratory-coding-revision.md"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-08 "$TEST_ROOT/exploratory-coding-revision.md" \
	>"$TEST_ROOT/exploratory-coding.out" 2>&1; then
	printf 'coding recovery accepted an unresolved discovery objective\n' >&2
	exit 1
fi
grep -Fq 'Objective still delegates interface/contract discovery' \
	"$TEST_ROOT/exploratory-coding.out"

sed \
	-e 's/consumer-revision-05/consumer-revision-09/g' \
	-e 's|cmake --build build --target liveness_consumer_smoke|cmake --build build --target liveness_consumer_smoke \&\& /tmp/build/other_smoke|g' \
	"$TEST_ROOT/generated-validation-revision.md" > "$TEST_ROOT/mismatched-binary-revision.md"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-09 "$TEST_ROOT/mismatched-binary-revision.md" \
	>"$TEST_ROOT/mismatched-binary.out" 2>&1; then
	printf 'focused validation executed an unbuilt CMake target\n' >&2
	exit 1
fi
grep -Fq 'executes CMake target other_smoke directly but does not build that exact target' \
	"$TEST_ROOT/mismatched-binary.out"

# A stale planning turn cannot publish a second revision while another
# revision of the same root is ready for execution.
cp "$TEST_ROOT/generated-validation-revision.md" "$TEST_ROOT/concurrent-revision.md"
sed -i 's/consumer-revision-05/consumer-revision-07/g' "$TEST_ROOT/concurrent-revision.md"
cp "$TEST_ROOT/generated-validation-revision.md" "$generated_ready"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-07 "$TEST_ROOT/concurrent-revision.md" >"$TEST_ROOT/concurrent.out" 2>"$TEST_ROOT/concurrent.err"; then
	printf 'concurrent root revision unexpectedly published\n' >&2
	exit 1
fi
grep -Fq 'task root already has an active ready, running, or review artifact' "$TEST_ROOT/concurrent.err"
rm -f "$generated_ready"

cat > "$TEST_ROOT/invalidation.md" <<'MD'
The consumer's deterministic validation disproves the accepted upstream serialization contract.
MD
"$HARNESS_BIN/manager-invalidate-plan-dependency" "$TEST_ROOT/harness.env" \
	consumer-revision-03 UPSTREAM "$TEST_ROOT/invalidation.md" >/dev/null
[[ -f "$reassessment" ]]
grep -Fqx 'Category: ACCEPTED_DEPENDENCY_INVALIDATED' "$reassessment"
invalidation="$project/control/plan-invalidations/UPSTREAM--consumer.invalidated.md"
[[ -f "$invalidation" ]]
grep -Fqx 'Consumer-Plan-Item: CONSUMER' "$invalidation"
grep -Fq 'Project progress: 0.0% (0/2 plan items complete)' \
	< <("$HARNESS_BIN/harness-status" --machine "$TEST_ROOT/harness.env")

# Modern roots have immutable criteria in their assignments. If a recovery
# planner passes a typed child-decomposition TSV as argument five without the
# legacy '-' placeholder, normalize it as decomposition input rather than
# misclassifying it as a forbidden root-criteria replacement.
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" consumer "$TEST_ROOT/resolution.md" >/dev/null
cat > "$TEST_ROOT/argument-normalized-decomposition.tsv" <<'TSV'
parent_criterion	child_criterion	title	acceptance_evidence
consumer.validation	consumer.validation.implementation	Implement consumer	Focused implementation validation passes
consumer.validation	consumer.validation.acceptance	Validate consumer	Independent acceptance validation passes
TSV
cat > "$TEST_ROOT/argument-normalized-revision.md" <<'MD'
Task-ID: consumer-revision-10
Task-Root: consumer
Target-Criterion: consumer.validation.implementation
Worker-Context: FRESH
Replan-Strategy-ID: argument-normalized-child-decomposition
Strategy-Change: NARROW_SCOPE
Supersedes-Task: consumer-revision-03
Execution-Mode: LEAF_GOAL
Goal-ID: consumer.argument-normalized
Goal-Success-Evidence: focused consumer implementation validation passes
Focused-Validation: cmake -S . -B build && cmake --build build --target liveness_consumer_smoke
Allowed-Scope: src/consumer
Baseline-Boundary: preserve accepted upstream behavior
Hard-Block-Conditions: external product authority only
Leaf-Type: LOCAL_IMPLEMENTATION
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: UPSTREAM
Deliverable: consumer
Required-Symbols: -
Context-Paths: src/consumer,build
Architecture-Decisions: NONE
Validation-Class: FOCUSED
Expected-Max-Implementation-Files: 2
Expected-Max-Worker-Turns: 2

## Objective

Implement the bounded consumer child.

## Acceptance criteria

- Focused consumer validation passes.

## Validation commands

cmake -S . -B build && cmake --build build --target liveness_consumer_smoke
MD
argument_normalized_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-10 "$TEST_ROOT/argument-normalized-revision.md" --auto-replan \
	"$TEST_ROOT/argument-normalized-decomposition.tsv")"
[[ "$argument_normalized_output" == "$project/tasks/livenessproj-task-consumer-revision-10.ready.md" ]]
grep -Fq 'RECOVERY_DECOMPOSITION_ARGUMENT_NORMALIZED root=consumer task=consumer-revision-10' \
	"$project/logs/events.log"
grep -Fqx $'consumer.validation\tconsumer.validation.implementation\tImplement consumer\tFocused implementation validation passes' \
	"$project/control/progress/livenessproj-task-consumer.criterion-decomposition.tsv"
rm -f "$argument_normalized_output"

# Replanning and diagnostic checkpoints cannot reset this monotonic boundary.
# Only a checkpoint containing a completed root criterion resets the count.
printf 'export HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION="3"\n' >> "$TEST_ROOT/harness.env"
cat > "$project/control/progress/livenessproj-task-criterionless.root-assignment.md" <<'MD'
Task-ID: criterionless
Task-Root: criterionless
Root-Criterion: criterionless.acceptance
MD
cat > "$project/control/progress/livenessproj-task-criterionless.history.tsv" <<'TSV'
updated_at	task_id	decision	progress_percent	improvement_percent	review_sha256
2026-01-01T00:00:00Z	criterionless	CHECKPOINT	0	0	-
2026-01-01T00:01:00Z	criterionless-revision-01	REJECT	0	0	-
2026-01-01T00:02:00Z	criterionless-revision-02	CHECKPOINT	0	0	-
TSV
cat > "$project/control/progress/livenessproj-task-criterionless.checkpoints.tsv" <<'TSV'
checkpointed_at	task_id	criterion_count	increment_count	progress_percent	improvement_percent	review_sha256	artifact_directory
2026-01-01T00:00:00Z	criterionless	0	1	0	0	-	-
2026-01-01T00:02:00Z	criterionless-revision-02	0	1	0	0	-	-
TSV
criterionless_marker="$("$HARNESS_BIN/harness-audit-root-liveness" "$TEST_ROOT/harness.env" criterionless)"
grep -Fqx 'Category: NO_CRITERION_PROGRESS' "$criterionless_marker"
grep -Fqx 'Reviews-Without-Criterion: 3' "$criterionless_marker"

# A typed manager-remediation decomposition request is still subordinate to
# root liveness. It must pause at the monotonic boundary rather than bypassing
# the guard and recursively publishing another Terra remediation.
for revision in 01 02 03; do
	cat > "$project/archive/livenessproj-task-remediationlimit-revision-$revision.rejected.md" <<MD
# Rejected Task

Task-ID: remediationlimit-revision-$revision
Task-Root: remediationlimit
MD
done
cat > "$project/archive/livenessproj-task-remediationlimit-revision-04.assignment.md" <<'MD'
Task-ID: remediationlimit-revision-04
Task-Root: remediationlimit
Manager-Remediation: 1
Blocker-Class: LOCAL_CODE_PREREQUISITE
Remediation-Scope: src/consumer/smoke.c
Allowed-Scope: src/consumer/smoke.c
Context-Paths: src/consumer/smoke.c
MD
cat > "$project/results/livenessproj-task-remediationlimit-revision-04.result.md" <<'MD'
# Task Result

Task-ID: remediationlimit-revision-04
Task-Root: remediationlimit
Goal-Outcome: NEEDS_DECOMPOSITION
Decomposition-Reason: CONTEXT_INCOMPLETE
MD
cat > "$TEST_ROOT/remediation-limit-review.md" <<'MD'
Progress-Percent: 0%
Improvement-Percent: 0%
MD
remediation_limit_output="$("$HARNESS_BIN/manager-reject-task" "$TEST_ROOT/harness.env" \
	remediationlimit-revision-04 "$TEST_ROOT/remediation-limit-review.md")"
[[ "$remediation_limit_output" == \
	"$project/control/progress/livenessproj-task-remediationlimit.architecture-reassessment-required.md" ]]
grep -Fqx 'Category: TOTAL_ROOT_REVIEWS' "$remediation_limit_output"
grep -Fqx 'Pending-Replan-Trigger: MANAGER_REMEDIATION_CONTEXT_INCOMPLETE' \
	"$remediation_limit_output"
grep -Fqx 'Pending-Replan-Triggered-By: remediationlimit-revision-04' \
	"$remediation_limit_output"
grep -Fqx 'Pending-Replan-Blocker-Class: LOCAL_CODE_PREREQUISITE' \
	"$remediation_limit_output"
grep -Fqx 'Pending-Replan-Remediation-Scope: src/consumer/smoke.c' \
	"$remediation_limit_output"
grep -Fqx 'Pending-Replan-Context-Paths: src/consumer/smoke.c' \
	"$remediation_limit_output"
[[ ! -f "$project/control/progress/livenessproj-task-remediationlimit.needs-replan.md" ]]

# An operator-audited manager remediation may persist only the exact bounded
# additional source path named by the architecture resolution.
scope_root=scopeexp
scope_marker="$project/control/progress/livenessproj-task-$scope_root.architecture-reassessment-required.md"
cat > "$scope_marker" <<'MD'
# Architecture Reassessment Required

Project: livenessproj
Task-Root: scopeexp
Triggered-By: scopeexp-revision-01
Category: MANAGER_REMEDIATION_SCOPE_EXPANSION
MD
cat > "$TEST_ROOT/scope-resolution.md" <<'MD'
Authorized-Additional-Scope: remediation.c

The companion implementation is the audited owner of the already-authorized public header contract.
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" "$scope_root" "$TEST_ROOT/scope-resolution.md" >/dev/null
scope_override="$project/control/progress/livenessproj-task-$scope_root.architecture-scope-override.env"
grep -Fqx 'additional_scope=remediation.c' "$scope_override"
grep -Fqx 'authorized_for=manager_remediation' "$scope_override"
# A later audited adjacent seam augments the durable authority instead of
# replacing the first one. Otherwise a multi-step remediation oscillates
# between already-approved producer and consumer paths.
cat > "$scope_marker" <<'MD'
# Architecture Reassessment Required

Project: livenessproj
Task-Root: scopeexp
Triggered-By: scopeexp-revision-02
Category: MANAGER_REMEDIATION_SCOPE_EXPANSION
MD
cat > "$TEST_ROOT/scope-resolution-second.md" <<'MD'
Authorized-Additional-Scope: src/consumer/smoke.c

The adjacent consumer is the second independently audited remediation seam.
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" "$scope_root" "$TEST_ROOT/scope-resolution-second.md" >/dev/null
grep -Fqx 'additional_scope=remediation.c,src/consumer/smoke.c' "$scope_override"
# The exact preserved tracked change is now attributable on restart even after
# the reassessment marker itself has been archived.
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; require_resumable_repository_start_state' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env"

# The same audited extra mutation authority must expand the controlled-commit
# ceiling. Otherwise review succeeds but the commit transaction is impossible.
cat > "$project/control/progress/livenessproj-task-$scope_root.root-assignment.md" <<'MD'
Task-ID: scopeexp
Task-Root: scopeexp
Allowed-Scope: src/root.c
Expected-Max-Implementation-Files: 1
MD
cat > "$TEST_ROOT/scope-remediation-assignment.md" <<'MD'
Task-ID: scopeexp-revision-02
Task-Root: scopeexp
Manager-Remediation: 1
Allowed-Scope: src/root.c,remediation.c
Expected-Max-Implementation-Files: 1
MD
effective_files="$(bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	source "$1/lib/harness-git-commit.sh"
	source "$1/lib/harness-checkpoint-commit.sh"
	checkpoint_effective_commit_max_files scopeexp-revision-02 "$3"
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env" "$TEST_ROOT/scope-remediation-assignment.md")"
[[ "$effective_files" == 3 ]]

# The root-level allowance remains relevant after the remediation. An ordinary
# continuation cannot mutate the extra path unless its own scope says so, but
# prior audited commits must not make its cumulative ceiling impossible.
cat > "$TEST_ROOT/scope-followup-assignment.md" <<'MD'
Task-ID: scopeexp-revision-03
Task-Root: scopeexp
Allowed-Scope: src/root.c
Expected-Max-Implementation-Files: 1
MD
effective_files="$(bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	source "$1/lib/harness-git-commit.sh"
	source "$1/lib/harness-checkpoint-commit.sh"
	checkpoint_effective_commit_max_files scopeexp-revision-03 "$3"
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env" "$TEST_ROOT/scope-followup-assignment.md")"
[[ "$effective_files" == 3 ]]

printf 'root liveness and dependency invalidation tests passed\n'
