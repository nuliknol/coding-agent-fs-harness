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
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name Harness-Test
git -C "$TEST_ROOT/repo" config user.email harness@example.invalid
git -C "$TEST_ROOT/repo" add spec.md
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
publish_output="$("$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" \
	consumer-revision-03 "$TEST_ROOT/expanded-revision.md")"
[[ "$publish_output" == "$reassessment" ]]
grep -Fqx 'Category: IMMUTABLE_ROOT_AUTHORITY' "$reassessment"
[[ ! -f "$project/tasks/livenessproj-task-consumer-revision-03.ready.md" ]]
"$HARNESS_BIN/harness-resolve-architecture-reassessment" \
	"$TEST_ROOT/harness.env" consumer "$TEST_ROOT/resolution.md" >/dev/null

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

printf 'root liveness and dependency invalidation tests passed\n'
