#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-git-dependency.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/repo/src" "$TEST_ROOT/repo/docs" \
	"$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'Implement and publish branch feature/test.\n' > "$TEST_ROOT/repo/spec.md"
printf 'int value(void) { return 0; }\n' > "$TEST_ROOT/repo/src/a.c"
printf 'owner note\n' > "$TEST_ROOT/repo/docs/owner.md"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name test
git -C "$TEST_ROOT/repo" config user.email test@example.invalid
git -C "$TEST_ROOT/repo" add spec.md src/a.c docs/owner.md
git -C "$TEST_ROOT/repo" commit -qm seed
seed="$(git -C "$TEST_ROOT/repo" rev-parse HEAD)"

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="gitdependency"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="$TEST_ROOT/repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export HARNESS_WORKER_GOAL_MODE="0"
export HARNESS_DECOMPOSITION_V2="0"
export HARNESS_AGENT_COMMITS_ENABLED="1"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
printf 'item1\tCommit and dependency test\n' > "$TEST_ROOT/plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" "$TEST_ROOT/plan.tsv" >/dev/null

cat > "$TEST_ROOT/task.md" <<TASK
# Task Assignment

Task-ID: 001
Task-Root: 001
Status: READY
Allowed-Scope: src/a.c;docs/report.md
Publish-Branch: feature/test
Publish-Base: $seed
Root-Criterion: source.committed

## Objective

Change and commit src/a.c.

## Acceptance criteria

- The source commit exists.

## Validation commands

true
TASK
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/task.md" item1 >/dev/null
session="$("$HARNESS_BIN/harness-new-session" "$TEST_ROOT/harness.env" worker)"
"$HARNESS_BIN/worker-claim-task" "$TEST_ROOT/harness.env" 001 "$session" >/dev/null

printf 'int value(void) { return 1; }\n' > "$TEST_ROOT/repo/src/a.c"
printf 'owner changed outside task\n' >> "$TEST_ROOT/repo/docs/owner.md"
printf 'Implement value source change.\n' > "$TEST_ROOT/message.txt"
commit_output="$("$HARNESS_BIN/harness-commit-source" "$TEST_ROOT/harness.env" 001 "$session" \
	"$TEST_ROOT/message.txt" src/a.c)"
commit="$(awk -F= '$1 == "COMMIT" {print $2}' <<< "$commit_output")"
[[ "$commit" == "$(git -C "$TEST_ROOT/repo" rev-parse HEAD)" ]]
git -C "$TEST_ROOT/repo" diff --quiet HEAD -- src/a.c
! git -C "$TEST_ROOT/repo" diff --quiet HEAD -- docs/owner.md
git -C "$TEST_ROOT/repo" diff --cached --quiet

"$HARNESS_BIN/harness-publish-branch" "$TEST_ROOT/harness.env" 001 "$session" feature/test >/dev/null
[[ "$(git -C "$TEST_ROOT/repo" rev-parse refs/heads/feature/test)" == "$commit" ]]

mkdir -p "$TEST_ROOT/repo/build"
printf 'object\n' > "$TEST_ROOT/repo/build/a.o"
if "$HARNESS_BIN/harness-commit-source" "$TEST_ROOT/harness.env" 001 "$session" \
	"$TEST_ROOT/message.txt" build/a.o >/dev/null 2>&1; then
	printf 'generated object was accepted by source commit transaction\n' >&2
	exit 1
fi
git -C "$TEST_ROOT/repo" diff --cached --quiet
if "$HARNESS_BIN/harness-commit-source" "$TEST_ROOT/harness.env" 001 "$session" \
	"$TEST_ROOT/message.txt" docs/owner.md >/dev/null 2>&1; then
	printf 'out-of-scope owner change was accepted by source commit transaction\n' >&2
	exit 1
fi
git -C "$TEST_ROOT/repo" diff --cached --quiet

# A producer publishes a source/report commit on the exact requested branch.
git clone -q "$TEST_ROOT/repo" "$TEST_ROOT/producer"
git -C "$TEST_ROOT/producer" config user.name producer
git -C "$TEST_ROOT/producer" config user.email producer@example.invalid
git -C "$TEST_ROOT/producer" checkout -qb component/a10 "$seed"
mkdir -p "$TEST_ROOT/producer/docs"
printf 'component delivery\n' > "$TEST_ROOT/producer/docs/component.md"
git -C "$TEST_ROOT/producer" add docs/component.md
git -C "$TEST_ROOT/producer" commit -qm 'publish component report'

printf 'dependency_id\ttype\ttarget_ref\tsource_hint\trequired_ancestor\trequired_path\tdescription\n' \
	> "$TEST_ROOT/requirements.tsv"
printf 'a10\tGIT_REF\trefs/heads/component/a10\t%s\t%s\tdocs/component.md\tCommitted A10 source and completion report\n' \
	"$TEST_ROOT/advisory-producer-path" "$seed" >> "$TEST_ROOT/requirements.tsv"
cat > "$TEST_ROOT/dependency-note.md" <<'NOTE'
Produce the bounded A10 implementation, run its focused validation, commit only
source and its completion report, and publish branch component/a10.
NOTE

"$HARNESS_BIN/worker-wait-dependency" "$TEST_ROOT/harness.env" 001 "$session" \
	a10-delivery "$TEST_ROOT/requirements.tsv" "$TEST_ROOT/dependency-note.md" >/dev/null
project_dir="$TEST_ROOT/state/projects/gitdependency"
grep -Eq $'^item1\tWAITING_DEPENDENCY\t001\t' "$project_dir/control/project-plan-state.tsv"
test -f "$project_dir/control/progress/gitdependency-task-001.waiting-dependency.md"
test "$(awk 'END {print NR}' "$project_dir/control/progress/gitdependency-task-001.criteria.tsv" 2>/dev/null || printf 0)" -le 1

"$HARNESS_BIN/harness-supply-dependency" "$TEST_ROOT/harness.env" a10-delivery a10 \
	"$TEST_ROOT/producer" refs/heads/component/a10 >/dev/null
bash -c 'set -Eeuo pipefail; source "$1/lib/harness-common.sh"; load_harness_env "$2"; resolve_dependency_request_if_ready "$(dependency_request_file a10-delivery)"' \
	_ "$HARNESS_HOME" "$TEST_ROOT/harness.env"
grep -Eq $'^item1\tACTIVE\t001\t' "$project_dir/control/project-plan-state.tsv"
test ! -f "$project_dir/control/progress/gitdependency-task-001.waiting-dependency.md"
test -f "$project_dir/control/dependencies/a10-delivery.resolved.md"
git -C "$TEST_ROOT/repo" cat-file -e refs/heads/component/a10:docs/component.md

printf 'Git publication and dependency waiting tests passed.\n'
