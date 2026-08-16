#!/usr/bin/env bash

set -Eeuo pipefail
TEST_ROOT="$(mktemp -d /tmp/coding-harness-active-plan-revision.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
HARNESS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
mkdir -p "$TEST_ROOT/repo/src" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'Repair the bounded runtime contract.\n' > "$TEST_ROOT/repo/spec.md"
printf 'int public_api(void);\n' > "$TEST_ROOT/repo/src/api.h"
printf 'int public_api(void) { return 0; }\n' > "$TEST_ROOT/repo/src/api.c"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" add .
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="revisionproj"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
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
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_MIN_LUNA_NODE_PERCENT="0"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="0"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"

"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
cat > "$TEST_ROOT/plan.tsv" <<'TSV'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
contract	-	-	Publish and execute the bounded API	API smoke passes	FOCUSED: run the focused API smoke	src/api.h	public_api	MECHANICAL_API	LOW	LUNA
TSV
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" "$TEST_ROOT/plan.tsv" >/dev/null

cat > "$TEST_ROOT/root.md" <<'MD'
# Task Assignment

Task-ID: contract
Task-Root: contract
Project-Plan-Item-ID: contract
Execution-Mode: LEAF_GOAL
Goal-ID: revisionproj.contract.v1
Target-Criterion: contract.header
Goal-Success-Evidence: API smoke passes
Focused-Validation: FOCUSED: run the focused API smoke
Validation-Command: ./focused-smoke
Allowed-Scope: src/api.h
Baseline-Boundary: seeded public API
Hard-Block-Conditions: NONE
Mandatory-Git-Refs: -
Leaf-Type: MECHANICAL_API
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: -
Deliverable: Publish and execute the bounded API
Required-Symbols: public_api
Context-Paths: src/api.h
Architecture-Decisions: NONE
Expected-Max-Implementation-Files: 1
Expected-Max-Worker-Turns: 2

Root-Criterion: contract.header

## Objective

Publish the API contract.

## Root acceptance criteria

Root-Criterion: contract.runtime

Run the focused API smoke.

## Acceptance criteria

- The header and runtime smoke pass.

## Validation commands

./focused-smoke
MD
sed 's/^Expected-Max-Worker-Turns: 2$/Expected-Max-Worker-Turns: 5/' \
	"$TEST_ROOT/root.md" > "$TEST_ROOT/root-overturn.md"
"$HARNESS_BIN/manager-publish-planned-task" "$TEST_ROOT/harness.env" "$TEST_ROOT/root-overturn.md" >/dev/null
project="$TEST_ROOT/state/projects/revisionproj"
grep -Fqx 'Expected-Max-Worker-Turns: 3' \
	"$project/tasks/revisionproj-task-contract.ready.md"
printf 'thread_id=stale-manager-thread\nregistered_at=2026-01-01T00:00:00Z\n' \
	> "$project/control/manager.thread"

bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; mark_root_architecture_reassessment contract IMMUTABLE_ROOT_AUTHORITY "runtime repair requires src/api.c" "focused smoke evidence" >/dev/null' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env"
marker="$project/control/progress/revisionproj-task-contract.architecture-reassessment-required.md"
[[ -f "$marker" ]]

cat > "$TEST_ROOT/revised-plan.tsv" <<'TSV'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
contract	-	-	Publish and execute the bounded API	API smoke passes	./focused-smoke --runtime	src/api.h,src/api.c	public_api	FOCUSED_BUG	MEDIUM	TERRA
TSV
sed \
	-e 's/^Allowed-Scope: src\/api.h$/Allowed-Scope: src\/api.h,src\/api.c/' \
	-e 's#^Focused-Validation: FOCUSED: run the focused API smoke$#Focused-Validation: ./focused-smoke --runtime#' \
	-e 's/^Leaf-Type: MECHANICAL_API$/Leaf-Type: FOCUSED_BUG/' \
	-e 's/^Complexity-Class: LOW$/Complexity-Class: MEDIUM/' \
	-e 's/^Worker-Route: LUNA$/Worker-Route: TERRA/' \
	-e 's/^Context-Paths: src\/api.h$/Context-Paths: src\/api.h,src\/api.c/' \
	-e 's/^Expected-Max-Implementation-Files: 1$/Expected-Max-Implementation-Files: 2/' \
	"$TEST_ROOT/root.md" > "$TEST_ROOT/revised-root.md"
printf 'The focused smoke proved that the API implementation source is part of this active acceptance boundary.\n' \
	> "$TEST_ROOT/resolution.md"

output="$("$HARNESS_BIN/harness-revise-active-plan-node" "$TEST_ROOT/harness.env" \
	"$TEST_ROOT/revised-plan.tsv" "$TEST_ROOT/revised-root.md" "$TEST_ROOT/resolution.md")"
grep -Fqx 'Revised active plan node contract for root contract.' <<< "$output"
grep -Fqx 'Preserved criteria: 2' <<< "$output"
cmp -s "$TEST_ROOT/revised-plan.tsv" "$project/control/project-decomposition-v2.tsv"
cmp -s "$TEST_ROOT/revised-root.md" "$project/control/progress/revisionproj-task-contract.root-assignment.md"
[[ ! -f "$marker" ]]
revision_archive="$(find "$project/archive/plan-node-revisions/contract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ -s "$revision_archive/project-decomposition-v2.before.tsv" ]]
[[ -s "$revision_archive/root-assignment.before.md" ]]
[[ -s "$revision_archive/architecture-reassessment.md" ]]
[[ -s "$revision_archive/resolution.md" ]]
[[ -s "$revision_archive/manager-thread.before.env" ]]
[[ -s "$project/control/manager-context-rotation-required.md" ]]
grep -Fqx "source=$revision_archive" \
	"$project/control/progress/revisionproj-task-contract.liveness-epoch.env"
grep -Fqx 'worker_route=TERRA' \
	"$project/control/progress/revisionproj-task-contract.operator-worker-route-override.env"
grep -Fqx 'old_allowed_paths=src/api.h' "$revision_archive/revision.env"
grep -Fqx 'new_allowed_paths=src/api.h,src/api.c' "$revision_archive/revision.env"
grep -Fqx 'old_focused_validation=FOCUSED: run the focused API smoke' "$revision_archive/revision.env"
grep -Fqx 'new_focused_validation=./focused-smoke --runtime' "$revision_archive/revision.env"
grep -Fqx 'incident=architecture-reassessment.md' "$revision_archive/revision.env"

# The original root assignment has served as the active-plan fixture. Move it
# out of the live queue before exercising sequential continuation publication;
# production now rejects two simultaneous live revisions of one root.
mv "$project/tasks/revisionproj-task-contract.ready.md" \
	"$project/archive/revisionproj-task-contract.checkpointed.md"

# Planning publication derives revision identity from durable state and restores
# immutable DAG metadata from the accepted root instead of trusting model prose.
sed 's#^Allowed-Scope: src/api.h,src/api.c$#Allowed-Scope: src/#' \
	"$TEST_ROOT/revised-root.md" > "$TEST_ROOT/planned-broad-scope.md"
if "$HARNESS_BIN/manager-publish-planned-task" "$TEST_ROOT/harness.env" \
	"$TEST_ROOT/planned-broad-scope.md" >"$TEST_ROOT/broad.out" 2>"$TEST_ROOT/broad.err"; then
	printf 'broad planned scope unexpectedly passed deterministic publication\n' >&2
	exit 1
fi
grep -Fq 'planned Allowed-Scope exceeds immutable root authority' "$TEST_ROOT/broad.err"
[[ ! -f "$project/control/progress/revisionproj-task-contract.architecture-reassessment-required.md" ]]

sed \
	-e 's/^Task-ID: contract$/Task-ID: invented-task-name/' \
	-e 's/^Project-Plan-Item-ID: contract$/Project-Plan-Item-ID: invented-node/' \
	-e 's/^Worker-Route: TERRA$/Worker-Route: LUNA/' \
	-e 's/^Architecture-Decisions: NONE$/Architecture-Decisions: -/' \
	-e 's/^Mandatory-Git-Refs: -$/Mandatory-Git-Refs: none/' \
	"$TEST_ROOT/revised-root.md" > "$TEST_ROOT/planned-revision.md"
printf '# stale planning marker\n' > "$project/control/manager-plan-stalled.md"
"$HARNESS_BIN/manager-publish-planned-task" "$TEST_ROOT/harness.env" \
	"$TEST_ROOT/planned-revision.md" >/dev/null
planned="$project/tasks/revisionproj-task-contract-revision-01.ready.md"
[[ -f "$planned" ]]
grep -Fqx 'Task-ID: contract-revision-01' "$planned"
grep -Fqx 'Project-Plan-Item-ID: contract' "$planned"
grep -Fqx 'Worker-Route: TERRA' "$planned"
grep -Fqx 'Leaf-Type: FOCUSED_BUG' "$planned"
grep -Fqx 'Architecture-Decisions: NONE' "$planned"
grep -Fqx 'Mandatory-Git-Refs: -' "$planned"
[[ ! -e "$project/control/manager-plan-stalled.md" ]]

printf 'active plan node revision tests passed\n'
