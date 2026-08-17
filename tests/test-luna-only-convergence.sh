#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/luna-only-convergence-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/repo" "$TMP/codex-home"
printf 'test specification\n' > "$TMP/repo/spec.md"
printf 'int target(void) { return 0; }\n' > "$TMP/repo/target.c"
git -C "$TMP/repo" init -q
git -C "$TMP/repo" add .
git -C "$TMP/repo" -c user.name=test -c user.email=test@example.invalid commit -qm baseline

cat > "$TMP/harness.env" <<ENV
export PROJECT="lunaconvergence"
export REPOSITORY="$TMP/repo"
export SPECIFICATION="$TMP/repo/spec.md"
export HARNESS_HOME="$ROOT"
export HARNESS_BIN="$ROOT/bin"
export HARNESS_ROOT="$TMP/state"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_BIN="/bin/true"
export MANAGER_CODEX_HOME="$TMP/codex-home"
export WORKER_CODEX_HOME="$TMP/codex-home"
export HARNESS_MODEL_POLICY="luna_only"
export HARNESS_ESCALATION_POLICY="decompose"
export HARNESS_AUTO_REPLAN_ENABLED="1"
ENV
chmod 600 "$TMP/harness.env"
"$ROOT/bin/harness-init" "$TMP/harness.env" >/dev/null

project="$TMP/state/projects/lunaconvergence"
ready="$project/tasks/lunaconvergence-task-001.ready.md"
cat > "$ready" <<'TASK'
# Task

Task-ID: 001
Worker-Route: LUNA
Allowed-Scope: target.c
Context-Paths: target.c
Required-Symbols: target
TASK
chmod 600 "$ready"
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; initialize_task_progress 001 "$3"' \
	_ "$ROOT" "$TMP/harness.env" "$ready"
session="$("$ROOT/bin/harness-new-session" "$TMP/harness.env" worker)"
"$ROOT/bin/worker-claim-task" "$TMP/harness.env" 001 "$session" >/dev/null

marker="$("$ROOT/bin/worker-return-context-repair" "$TMP/harness.env" 001 "$session" \
	INDEX_EVIDENCE_MISSING REFRESH_INDEX_OR_OVERLAY scip unresolved-required-evidence)"
test -f "$marker"
test -f "$project/archive/lunaconvergence-task-001.assignment.md"
test ! -e "$project/running/lunaconvergence-task-001.running.md"
test ! -e "$project/control/lunaconvergence-task-001.lease"
test ! -e "$project/results/lunaconvergence-task-001.result.md"
grep -Fqx 'Trigger-Outcome: CONTEXT_CLOSURE_REPAIR' "$marker"
grep -Fqx 'Closure-Condition: INDEX_EVIDENCE_MISSING' "$marker"
grep -Fqx 'Closure-Repair-Action: REFRESH_INDEX_OR_OVERLAY' "$marker"
grep -Fqx 'Closure-Repair-Provider: scip' "$marker"
repair="$project/control/lunaconvergence-task-001.context-closure-repair.env"
grep -Fqx 'state=CLOSURE_REPAIR' "$repair"
grep -Fqx 'repair_action=REFRESH_INDEX_OR_OVERLAY' "$repair"

# Replaying the same completed transaction is idempotent and preserves the
# original marker rather than creating a new revision or result.
test "$("$ROOT/bin/worker-return-context-repair" "$TMP/harness.env" 001 "$session" \
	INDEX_EVIDENCE_MISSING REFRESH_INDEX_OR_OVERLAY scip unresolved-required-evidence)" = "$marker"
test "$(find "$project/results" -type f | wc -l)" -eq 0

# A stopped project can migrate an already-published pre-policy Terra task
# without resetting its root. The assignment is archived and automatic Luna
# decomposition resumes from the existing first-unmet criterion.
legacy_ready="$project/tasks/lunaconvergence-task-002.ready.md"
cat > "$legacy_ready" <<'TASK'
# Pre-policy task

Task-ID: 002
Worker-Route: TERRA
Allowed-Scope: target.c
Context-Paths: target.c
Required-Symbols: target
Root-Criterion: root-002.acceptance
Root-Criterion: root-002.validation
TASK
chmod 600 "$legacy_ready"
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; initialize_task_progress 002 "$3"' \
	_ "$ROOT" "$TMP/harness.env" "$legacy_ready"

# An unreviewed result from a pre-policy manager-remediation assignment is not
# accepted during migration. Its workspace is retained as tracked-overlay
# evidence, while the result itself is archived with explicit unaccepted
# provenance and the root returns to mandatory Luna decomposition.
legacy_result_assignment="$project/archive/lunaconvergence-task-004.assignment.md"
cat > "$legacy_result_assignment" <<'TASK'
# Pre-policy manager remediation

Task-ID: 004
Worker-Route: LUNA
Manager-Remediation: 1
Allowed-Scope: target.c
Context-Paths: target.c
Required-Symbols: target
Root-Criterion: root-004.acceptance
TASK
chmod 600 "$legacy_result_assignment"
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; initialize_task_progress 004 "$3"' \
	_ "$ROOT" "$TMP/harness.env" "$legacy_result_assignment"
cat > "$project/results/lunaconvergence-task-004.result.md" <<'RESULT'
# Unreviewed result

Task-ID: 004
Goal-Outcome: COMPLETE
Workspace-Changed: 1
RESULT
chmod 600 "$project/results/lunaconvergence-task-004.result.md"

# A pre-policy broad root that exhausted monotonic liveness may migrate only to
# mandatory child-criterion decomposition. Historical counts remain archived,
# while the new child boundary receives its own measured budget.
printf 'accepted evidence\n' > "$project/archive/lunaconvergence-task-003.accepted.md"
printf 'rejected evidence\n' > "$project/archive/lunaconvergence-task-003-revision-01.rejected.md"
cat > "$project/control/progress/lunaconvergence-task-003.replans.tsv" <<'TSV'
replanned_at	task_id	trigger	strategy_id	strategy_change	blocking_fingerprint	progress_percent	context_mode	assignment	verified_items	completed_criteria
2026-08-17T00:00:00Z	003-revision-01	TEST	legacy	legacy	-	0	fresh	-	0	0
TSV
cat > "$project/control/progress/lunaconvergence-task-003.architecture-reassessment-required.md" <<'MARKER'
# Architecture Reassessment Required

Project: lunaconvergence

Task-Root: 003

Triggered-By: 003-revision-01

Category: TOTAL_ROOT_REPLANS

Reason: legacy broad boundary exhausted
MARKER
migration_output="$("$ROOT/bin/harness-migrate-state" "$TMP/harness.env")"
grep -Fq 'liveness-roots=1' <<< "$migration_output"
grep -Fq 'pending-results=1' <<< "$migration_output"
test ! -e "$legacy_ready"
test -f "$project/archive/lunaconvergence-task-002.assignment.md"
migration_marker="$project/control/progress/lunaconvergence-task-002.needs-replan.md"
grep -Fqx 'Trigger-Outcome: LUNA_ONLY_POLICY_MIGRATION' "$migration_marker"
grep -Fqx 'status=READY' "$project/control/luna-only-migration.env"
grep -Fqx 'migrated_ready_tasks=1' "$project/control/luna-only-migration.env"
grep -Fqx 'migrated_pending_results=1' "$project/control/luna-only-migration.env"
grep -Fqx 'migrated_liveness_roots=1' "$project/control/luna-only-migration.env"
test ! -e "$project/results/lunaconvergence-task-004.result.md"
test -f "$project/archive/lunaconvergence-task-004.policy-migration-result.md"
test -f "$project/control/lunaconvergence-task-004.policy-migrated"
grep -Fqx 'Trigger-Outcome: LUNA_ONLY_POLICY_MIGRATION' \
	"$project/control/progress/lunaconvergence-task-004.needs-replan.md"
test -f "$project/control/lunaconvergence-task-002.policy-migrated"

# Crash recovery must not reinterpret an intentionally archived migration
# assignment as an interrupted worker completion and recreate the old task.
"$ROOT/bin/harness-recover" "$TMP/harness.env" >/dev/null
test ! -e "$project/tasks/lunaconvergence-task-002.ready.md"
test ! -e "$project/tasks/lunaconvergence-task-004.ready.md"
test ! -e "$project/control/progress/lunaconvergence-task-003.architecture-reassessment-required.md"
test "$(find "$project/archive/luna-only-migrations" -type f -name '*task-003*.migrated' | wc -l)" -eq 1
grep -Fqx 'Trigger-Outcome: LUNA_ONLY_POLICY_MIGRATION' \
	"$project/control/progress/lunaconvergence-task-003.needs-replan.md"
epoch="$project/control/progress/lunaconvergence-task-003.liveness-epoch.env"
grep -Fqx 'authorized_reset=1' "$epoch"
grep -Fqx 'budget_scope=luna-only-migrated-child-boundary' "$epoch"
grep -Fqx 'reviewed_attempts=2' "$epoch"

# A policy migration is an explicit mandatory-decomposition boundary. Neither
# historical blocker fingerprints nor an exhausted legacy automatic-replan
# budget may silently downgrade it to manager remediation.
grep -Fq 'resource_recovery == 0 && policy_migration == 0 && closure_repair == 0' \
	"$ROOT/bin/manager-auto-replan-root"
test "$(grep -Fc 'closure_repair == 0' \
	"$ROOT/bin/manager-auto-replan-root")" -eq 2

printf 'new child rejection\n' > "$project/archive/lunaconvergence-task-003-revision-02.rejected.md"
cat >> "$project/control/progress/lunaconvergence-task-003.replans.tsv" <<'TSV'
2026-08-17T00:01:00Z	003-revision-02	TEST	child	decompose	-	0	fresh	-	0	0
TSV
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; \
  test "$(root_liveness_epoch_delta 003 reviewed_attempts "$(root_reviewed_attempt_count 003)")" = 1; \
  test "$(root_liveness_epoch_delta 003 total_replans "$(root_total_replan_count 003)")" = 1; \
  ! root_liveness_violation_reason 003' _ "$ROOT" "$TMP/harness.env"

printf 'Luna-only convergence tests passed.\n'
