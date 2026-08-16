#!/usr/bin/env bash

set -Eeuo pipefail
TEST_ROOT="$(mktemp -d /tmp/coding-harness-manager-rotation.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
HARNESS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'manager context rotation test\n' > "$TEST_ROOT/repo/spec.md"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name Harness-Test
git -C "$TEST_ROOT/repo" config user.email harness@example.invalid
git -C "$TEST_ROOT/repo" add spec.md
git -C "$TEST_ROOT/repo" commit -qm initial
cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="rotationproj"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_DECOMPOSITION_V2="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
project="$TEST_ROOT/state/projects/rotationproj"
cat > "$project/control/project-plan.tsv" <<'TSV'
# item_id	title
NODE1	Active node
TSV
cat > "$project/control/project-plan-state.tsv" <<'TSV'
# item_id	status	task_root	updated_at
NODE1	ACTIVE	root1	2026-01-01T00:00:00Z
TSV
cat > "$project/control/progress/rotationproj-task-root1.root-assignment.md" <<'MD'
Task-ID: root1
Task-Root: root1
Root-Criterion: root1.acceptance
MD
touch -d '2 hours ago' "$project/control/progress/rotationproj-task-root1.root-assignment.md"
printf 'manager-thread-id=test-manager-thread\n' > "$project/control/manager.thread"
printf 'Project: rotationproj\n' > "$project/control/manager-plan-stalled.md"
printf 'stale planning context was inspected and may be replaced\n' > "$TEST_ROOT/reason.md"
epoch="$project/control/progress/rotationproj-task-root1.liveness-epoch.env"
cat > "$epoch" <<'ENV'
reviewed_attempts=7
criterionless_reviews=6
total_replans=5
lifetime_seconds=100
processed_tokens=200
source=legacy-context-rotation
ENV
epoch_before="$(sha256sum "$epoch" | awk '{print $1}')"

"$HARNESS_BIN/harness-rotate-manager-context" \
	"$TEST_ROOT/harness.env" "$TEST_ROOT/reason.md" >/dev/null

[[ ! -f "$project/control/manager-plan-stalled.md" ]]
[[ -s "$epoch" ]]
[[ "$(sha256sum "$epoch" | awk '{print $1}')" == "$epoch_before" ]]
(
	source "$TEST_ROOT/harness.env"
	source "$HARNESS_HOME/lib/harness-common.sh"
	[[ "$(root_liveness_epoch_delta root1 lifetime_seconds "$(root_lifetime_seconds root1)")" -ge 7100 ]]
)
grep -Fq 'MANAGER_CONTEXT_ROTATION_LIVENESS_PRESERVED scope=lifetime-root-acceptance-boundary' \
	"$project/logs/events.log"

printf 'manager context rotation tests passed\n'
