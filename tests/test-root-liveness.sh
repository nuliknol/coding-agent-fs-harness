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

audit_output="$("$HARNESS_BIN/harness-audit-root-liveness" "$TEST_ROOT/harness.env" consumer)"
reassessment="$project/control/progress/livenessproj-task-consumer.architecture-reassessment-required.md"
[[ "$audit_output" == "$reassessment" ]]
grep -Fqx 'Category: TOTAL_ROOT_REVIEWS' "$reassessment"
grep -Fqx 'Total-Root-Reviews: 2' "$reassessment"
grep -Fq 'Project status: ARCHITECTURE_REASSESSMENT_REQUIRED.' \
	< <("$HARNESS_BIN/harness-status" --machine "$TEST_ROOT/harness.env")

cat > "$TEST_ROOT/resolution.md" <<'MD'
The operator reviewed the bounded evidence and approved a revised architecture boundary.
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" consumer "$TEST_ROOT/resolution.md" >/dev/null
[[ ! -f "$reassessment" ]]
[[ -f "$project/control/progress/livenessproj-task-consumer.needs-replan.md" ]]
[[ -f "$project/control/progress/livenessproj-task-consumer.liveness-epoch.env" ]]
(
	source "$TEST_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_liveness_epoch_delta consumer reviewed_attempts "$(root_reviewed_attempt_count consumer)")" == 0 ]]
	[[ "$(root_liveness_epoch_delta consumer total_replans "$(root_total_replan_count consumer)")" == 0 ]]
)
"$HARNESS_BIN/harness-unblock-root" "$TEST_ROOT/harness.env" consumer >/dev/null
find "$project/archive/architecture-reassessments" -type f -name '*.resolved.md' | grep -q .
# An explicit operator architecture epoch may raise a budget; automatic
# replanning itself never changes or resets it.
sed -i 's/HARNESS_MAX_TOTAL_ROOT_REVIEWS="2"/HARNESS_MAX_TOTAL_ROOT_REVIEWS="3"/' \
	"$TEST_ROOT/harness.env"

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
Focused-Validation: cmake --build build
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

cmake --build build
MD
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
	-e 's/cmake --build build/cmake --build build --target consumer_smoke/g' \
	"$TEST_ROOT/generated-validation-revision.md" > "$TEST_ROOT/cmake-target-alias-revision.md"
target_alias_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-06 "$TEST_ROOT/cmake-target-alias-revision.md")"
target_alias_ready="$project/tasks/livenessproj-task-consumer-revision-06.ready.md"
[[ "$target_alias_output" == "$target_alias_ready" ]]
grep -Fqx 'Focused-Validation: cmake --build build --target liveness_consumer_smoke' "$target_alias_ready"
grep -Fqx 'cmake --build build --target liveness_consumer_smoke' "$target_alias_ready"
grep -Fq 'CMAKE_TARGET_ALIAS_NORMALIZED root=consumer task=consumer-revision-06 requested=consumer_smoke registered=liveness_consumer_smoke' \
	"$project/logs/events.log"
rm -f "$target_alias_ready"

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
grep -Fq 'Project progress: 0% (0/2 plan items complete)' \
	< <("$HARNESS_BIN/harness-status" --machine "$TEST_ROOT/harness.env")

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
Authorized-Additional-Scope: src/companion.c

The companion implementation is the audited owner of the already-authorized public header contract.
MD
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" "$scope_root" "$TEST_ROOT/scope-resolution.md" >/dev/null
scope_override="$project/control/progress/livenessproj-task-$scope_root.architecture-scope-override.env"
grep -Fqx 'additional_scope=src/companion.c' "$scope_override"
grep -Fqx 'authorized_for=manager_remediation' "$scope_override"

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
Allowed-Scope: src/root.c,src/companion.c
Expected-Max-Implementation-Files: 1
MD
effective_files="$(bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	source "$1/lib/harness-git-commit.sh"
	source "$1/lib/harness-checkpoint-commit.sh"
	checkpoint_effective_commit_max_files scopeexp-revision-02 "$3"
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env" "$TEST_ROOT/scope-remediation-assignment.md")"
[[ "$effective_files" == 2 ]]

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
[[ "$effective_files" == 2 ]]

printf 'root liveness and dependency invalidation tests passed\n'
