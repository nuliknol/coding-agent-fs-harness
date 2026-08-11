#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-decomposition-v2.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

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
export HARNESS_MIN_LUNA_NODE_PERCENT="50"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"

"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
cat > "$TEST_ROOT/plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	complexity_class	worker_route
n1	-	-	Implement target_symbol locally	target_symbol returns one	test "$(./focused-smoke)" = 1	src/a.c	target_symbol	LOW	LUNA
n2	-	n1	Integrate target_symbol with its caller	focused integration smoke passes	./integration-smoke	src/a.c,src/caller.c	target_symbol,call_target	MEDIUM	TERRA
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
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/task.md" n1 >/dev/null

grep -Eq $'^n1\tACTIVE\t001\t' "$project_dir/control/project-plan-state.tsv"
capsule="$project_dir/control/context-capsules/decompv2-task-001.md"
grep -Fqx 'Worker-Route: LUNA' "$capsule"
grep -Fqx 'Context-Paths: src/a.c' "$capsule"
grep -Fqx 'Architecture-Decisions: NONE' "$capsule"
tree_output="$("$HARNESS_BIN/harness-decomposition-tree" --ascii "$TEST_ROOT/harness.env")"
grep -Fqx 'Routes: LUNA=1 (50%)  TERRA=1 (50%)  configured Luna minimum=50%' <<< "$tree_output"
grep -Fq '|-- n1 [ACTIVE] complexity=LOW route=LUNA' <<< "$tree_output"
grep -Fq 'task: 001 [READY] route=LUNA' <<< "$tree_output"
grep -Fq '`-- n2 [PENDING] complexity=MEDIUM route=TERRA' <<< "$tree_output"
tree_details="$("$HARNESS_BIN/harness-decomposition-tree" --details --ascii "$TEST_ROOT/harness.env")"
grep -Fq 'evidence: target_symbol returns one' <<< "$tree_details"
grep -Fq 'validation: test "$(./focused-smoke)" = 1' <<< "$tree_details"
grep -Fq 'n1.done [PENDING]' <<< "$tree_details"
metrics_output="$("$HARNESS_BIN/harness-decomposition-metrics" "$TEST_ROOT/harness.env")"
grep -Fqx $'nodes_total\t2' <<< "$metrics_output"
grep -Fqx $'luna_assignments\t0' <<< "$metrics_output"
test -s "$project_dir/control/decomposition-metrics.tsv"

grep -Eq $'^n2\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"

cat > "$TEST_ROOT/bad-plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	complexity_class	worker_route
bad	-	-	Bad Luna route	evidence	focused-test	src/a.c	target_symbol	MEDIUM	LUNA
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
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	complexity_class	worker_route
terra-only	-	-	Resolved local implementation	evidence	focused-test	src/a.c	target_symbol	LOW	TERRA
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
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	complexity_class	worker_route
t1	-	-	Implement target_symbol locally	target_symbol returns one	test "$(./focused-smoke)" = 1	src/a.c	target_symbol	LOW	TERRA
t2	-	-	Add focused target_symbol fixture	fixture passes	./fixture-smoke	src/fixture.c	target_fixture	LOW	LUNA
PLAN
sed \
	-e 's/export PROJECT="decompv2"/export PROJECT="decompv2lowterra"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/low-terra-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/low-terra-harness.env"
chmod 600 "$TEST_ROOT/low-terra-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/low-terra-harness.env" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/low-terra-harness.env" \
	"$TEST_ROOT/low-terra-plan.tsv" >/dev/null
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
mixed_watch="$(COLUMNS=100 LINES=24 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/watch-mixed")"
grep -Eq '^decompv2 +\| *0\| w/stopped +\| 0/2' <<< "$mixed_watch"
grep -Eq '^dispatchlight +\| *0\| m/stopped' <<< "$mixed_watch"
! grep -q 'CONFIGURATION ERROR' <<< "$mixed_watch"
! awk 'length($0) > 100 {bad=1} END {exit bad}' <<< "$mixed_watch"
light_watch="$(COLUMNS=100 LINES=24 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/watch-light")"
grep -q '^dispatchlight ' <<< "$light_watch"
! grep -q 'CONFIGURATION ERROR' <<< "$light_watch"

printf 'decomposition v2 tests passed\n'
