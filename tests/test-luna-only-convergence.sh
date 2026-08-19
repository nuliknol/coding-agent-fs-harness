#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/luna-only-convergence-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# A published continuation may cross worker admission and enter its next typed
# repair before the manager wrapper observes the ready file. Keep that durable
# successor transition in the committed-publication predicate.
grep -Fq 'successor_trigger="$(metadata_value "$successor_marker" Triggered-By)"' \
	"$ROOT/bin/manager-auto-replan-root"
grep -Fq '[[ "$successor_trigger" == "$expected_task_id" ]]' \
	"$ROOT/bin/manager-auto-replan-root"
grep -Fq 'if prepare_typed_context_expansion "$last_message"; then' \
	"$ROOT/bin/worker-invoke-task"
grep -Fq 'PATCH_ONLY_FORMAT_REPAIR_READY' "$ROOT/bin/worker-invoke-task"
grep -Fq 'attempt < patch_only_attempt_limit' "$ROOT/bin/worker-invoke-task"
grep -Fq 'attempt >= patch_only_attempt_limit' "$ROOT/bin/worker-invoke-task"
grep -Fq 'PATCH_ONLY_ZERO_FILE_VERIFICATION_PASSED' "$ROOT/bin/worker-invoke-task"
grep -Fq 'PATCH_ONLY_ZERO_FILE_VERIFICATION_FAILED' "$ROOT/bin/worker-invoke-task"
grep -Fq 'git -C "$REPOSITORY" apply -R --whitespace=nowarn --unidiff-zero' \
	"$ROOT/bin/worker-invoke-task"
grep -Fq 'PATCH_ROLLBACK_FAILURE' "$ROOT/bin/worker-invoke-task"
grep -Fq 'WORKER_TRANSACTION_ORPHANED' "$ROOT/bin/worker-supervisor"
grep -Fq 'DECOMPOSITION_COVERAGE_REPAIR_CAPSULE' \
	"$ROOT/bin/manager-decomposition-coverage-repair"
grep -Fq 'Read COVERAGE_REPAIR_CAPSULE exactly once in one bounded command.' \
	"$ROOT/bin/manager-decomposition-coverage-repair"
grep -Fq 'WORKER_PATCH_FORMAT_REPAIR_RESUMING' "$ROOT/bin/worker-invoke-task"
grep -Fq '"$(metadata_value "$trigger_assignment" Manager-Remediation)" == 1' \
	"$ROOT/bin/manager-auto-replan-root"
grep -Fq 'typed Context Closure repair must retain the triggering manager-remediation prerequisite authority' \
	"$ROOT/bin/manager-auto-replan-root"
grep -Fq 'normalize_recovery_context_paths' "$ROOT/bin/manager-publish-task"
grep -Fq 'LUNA_CONTEXT_PATHS_NORMALIZED' "$ROOT/bin/manager-publish-task"
grep -Fq 'QUALIFIED_CONTEXT_SYMBOL_NORMALIZED' "$ROOT/bin/manager-publish-task"
grep -Fq 'CONTEXT_INCOMPLETE_REQUIRED_SYMBOL_EXPANDED' "$ROOT/bin/manager-publish-task"
grep -Fq 'CONTEXT_MUTATION_REGION_EXPANDED' "$ROOT/bin/manager-publish-task"
grep -Fq 'ACP_MUTATION_REGION_CONTEXT_INCOMPLETE' "$ROOT/bin/worker-invoke-task"
grep -Fq 'harness-compile-task-mutation-capabilities' "$ROOT/bin/harness-apply-worker-patch"
grep -Fq 'harness-compile-task-mutation-capabilities' "$ROOT/bin/harness-commit-source"
grep -Fq 'CONTEXT_CLOSURE_EXEMPT' "$ROOT/bin/worker-invoke-task"
(
	source "$ROOT/lib/harness-worker-policy.sh"
	luna_bounded_execution=1
	HARNESS_CONTEXT_CLOSURE_MODE=patch_only
	context_closure_status=NEEDS_FURTHER_DECOMPOSITION
	zero_write_verification=1
	! harness_worker_context_admission_requires_repair
	zero_write_verification=0
	harness_worker_context_admission_requires_repair
)
grep -Fq 'DETERMINISTIC_CLOSURE_CUT=' "$ROOT/bin/manager-auto-replan-root"
grep -Fq 'root_child_count + trigger_closure_repair_child_count > HARNESS_MAX_ROOT_CHILD_CRITERIA' \
	"$ROOT/bin/manager-auto-replan-root"
grep -Fq 'child_count + repair_child_count <= HARNESS_MAX_ROOT_CHILD_CRITERIA' \
	"$ROOT/bin/manager-publish-task"
grep -Fq 'DETERMINISTIC_CLOSURE_CUT_VALIDATED' "$ROOT/bin/manager-publish-task"
grep -Fq "Context-Closure-Cut: \$closure_cut_id" "$ROOT/bin/manager-auto-replan-root"
if grep -Fq '[[ "$trigger_closure_repair_action" == GRAFT_GRAPH_CUTS ]]; } && [[ "$recovery_mode" != MANAGER_REMEDIATION ]]' \
	"$ROOT/bin/manager-auto-replan-root"; then
	printf 'manager remediation still disables deterministic closure grafting\n' >&2
	exit 1
fi

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
loaded_decomposition_model="$(bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; printf "%s" "$DECOMPOSITION_MODEL"' \
	_ "$ROOT" "$TMP/harness.env")"
[[ "$loaded_decomposition_model" == gpt-5.6-sol ]]
grep -Fq 'required_policy_model="$DECOMPOSITION_MODEL"' "$ROOT/bin/codex-exec-jsonl"

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

# Manager remediation is authority, not a stronger model route. A task already
# validated against the bounded Luna leaf contract must survive restart-time
# migration and execute with the effective Luna-only model.
bounded_remediation_ready="$project/tasks/lunaconvergence-task-005.ready.md"
cat > "$bounded_remediation_ready" <<'TASK'
# Bounded Luna-only manager remediation

Task-ID: 005
Worker-Route: LUNA
Manager-Remediation: 1
Leaf-Type: LOCAL_IMPLEMENTATION
Complexity-Class: LOW
Terra-Exception: -
Validation-Class: FOCUSED
Allowed-Scope: target.c
Context-Paths: target.c
Required-Symbols: target
Expected-Max-Implementation-Files: 1
Expected-Max-Worker-Turns: 1
Expected-Max-Agent-Actions: 4
Effective-P95-Tokens: 100000
Complexity-Score: 8
TASK
chmod 600 "$bounded_remediation_ready"

# Upgrade recovery reverses the exact bad state emitted by the old migration:
# a publisher-validated Luna remediation archived solely for its authority tag.
reversible_assignment="$project/archive/lunaconvergence-task-006.assignment.md"
cp "$bounded_remediation_ready" "$reversible_assignment"
sed -i 's/Task-ID: 005/Task-ID: 006/' "$reversible_assignment"
touch "$project/control/lunaconvergence-task-006.policy-migrated" \
	"$project/control/lunaconvergence-task-006.recovery-retired"
cat > "$project/control/progress/lunaconvergence-task-006.needs-replan.md" <<'MARKER'
# Root Task Needs Replanning

Project: lunaconvergence

Task-Root: 006

Triggered-By: 006

Trigger-Outcome: LUNA_ONLY_POLICY_MIGRATION
MARKER
chmod 600 "$reversible_assignment" \
	"$project/control/lunaconvergence-task-006.policy-migrated" \
	"$project/control/lunaconvergence-task-006.recovery-retired" \
	"$project/control/progress/lunaconvergence-task-006.needs-replan.md"

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

# A pre-policy broad root that exhausted a monotonic liveness fuse remains an
# investigation incident. Policy migration cannot manufacture a fresh budget;
# only the explicit operator resolution command may resume it.
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
grep -Fq 'liveness-roots=0' <<< "$migration_output"
grep -Fq 'retained-liveness-incidents=1' <<< "$migration_output"
grep -Fq 'pending-results=1' <<< "$migration_output"
test ! -e "$legacy_ready"
test -f "$project/archive/lunaconvergence-task-002.assignment.md"
migration_marker="$project/control/progress/lunaconvergence-task-002.needs-replan.md"
grep -Fqx 'Trigger-Outcome: LUNA_ONLY_POLICY_MIGRATION' "$migration_marker"
grep -Fqx 'status=READY' "$project/control/luna-only-migration.env"
grep -Fqx 'migrated_ready_tasks=1' "$project/control/luna-only-migration.env"
test -f "$bounded_remediation_ready"
test ! -e "$project/archive/lunaconvergence-task-005.assignment.md"
test -f "$project/tasks/lunaconvergence-task-006.ready.md"
test ! -e "$reversible_assignment"
test ! -e "$project/control/lunaconvergence-task-006.policy-migrated"
test ! -e "$project/control/lunaconvergence-task-006.recovery-retired"
test ! -e "$project/control/progress/lunaconvergence-task-006.needs-replan.md"
grep -Fqx 'restored_safe_remediations=1' "$project/control/luna-only-migration.env"
grep -Fqx 'migrated_pending_results=1' "$project/control/luna-only-migration.env"
grep -Fqx 'migrated_liveness_roots=0' "$project/control/luna-only-migration.env"
grep -Fqx 'retained_liveness_incidents=1' "$project/control/luna-only-migration.env"
test ! -e "$project/results/lunaconvergence-task-004.result.md"
test -f "$project/archive/lunaconvergence-task-004.policy-migration-result.md"
test -f "$project/control/lunaconvergence-task-004.policy-migrated"
test -f "$project/control/lunaconvergence-task-004.recovery-retired"
grep -Fqx 'Trigger-Outcome: LUNA_ONLY_POLICY_MIGRATION' \
	"$project/control/progress/lunaconvergence-task-004.needs-replan.md"
test -f "$project/control/lunaconvergence-task-002.policy-migrated"
test -f "$project/control/lunaconvergence-task-002.recovery-retired"

# Keep the following recovery fixture focused on the deliberately migrated
# tasks rather than the preserved executable boundary above.
rm -f "$bounded_remediation_ready" "$project/tasks/lunaconvergence-task-006.ready.md"

# Crash recovery must not reinterpret an intentionally archived migration
# or Context Closure repair assignment as an interrupted worker completion and
# recreate the old task. Also cover an archive produced by the older deployment
# before terminal transaction markers existed.
rm -f "$project/control/lunaconvergence-task-002.policy-migrated" \
	"$project/control/lunaconvergence-task-002.recovery-retired"
recovery_output="$("$ROOT/bin/harness-recover" "$TMP/harness.env" --reset-orphaned)"
grep -Fq 'TYPED_INTERNAL_ASSIGNMENT_RETIRED task=002' <<< "$recovery_output"
grep -Fq 'TYPED_INTERNAL_ASSIGNMENT_RETIRED task=001' <<< "$recovery_output"
test -f "$project/control/lunaconvergence-task-001.recovery-retired"
test -f "$project/control/lunaconvergence-task-002.recovery-retired"
test ! -e "$project/tasks/lunaconvergence-task-001.ready.md"

# Reset-mode recovery removes stale transaction scratch files from the hot
# control directory while retaining them in the crash-recovery archive.
stale_tmp="$project/control/project-plan.tsv.tmp.12345"
printf 'stale transaction scratch\n' > "$stale_tmp"
touch -d '2 hours ago' "$stale_tmp"
recovery_output="$("$ROOT/bin/harness-recover" "$TMP/harness.env" --reset-orphaned)"
grep -Fq 'STALE_TEMP_ARCHIVED' <<< "$recovery_output"
test ! -e "$stale_tmp"
test -f "$project/archive/crash-recovery/stale-temp/control.project-plan.tsv.tmp.12345"
test ! -e "$project/tasks/lunaconvergence-task-002.ready.md"
test ! -e "$project/tasks/lunaconvergence-task-004.ready.md"

# Reconcile both possible halves of an interrupted internal transition: a
# newer published child wins over an older marker, while a typed marker wins
# over an equal/older resurrected ready assignment.
cat > "$project/tasks/lunaconvergence-task-002-revision-01.ready.md" <<'TASK'
# Newer child

Task-ID: 002-revision-01
Worker-Route: LUNA
Allowed-Scope: target.c
Context-Paths: target.c
Required-Symbols: target
TASK
cp "$project/archive/lunaconvergence-task-001.assignment.md" \
	"$project/tasks/lunaconvergence-task-001.ready.md"
recovery_output="$("$ROOT/bin/harness-recover" "$TMP/harness.env" --reset-orphaned)"
grep -Fq 'STALE_REPLAN_MARKER_ARCHIVED root=002 ready=002-revision-01 trigger=002' \
	<<< "$recovery_output"
grep -Fq 'RESURRECTED_TYPED_READY_ARCHIVED task=001 trigger=001' \
	<<< "$recovery_output"
test -f "$project/tasks/lunaconvergence-task-002-revision-01.ready.md"
test ! -e "$project/control/progress/lunaconvergence-task-002.needs-replan.md"
test ! -e "$project/tasks/lunaconvergence-task-001.ready.md"
test -f "$project/control/progress/lunaconvergence-task-003.architecture-reassessment-required.md"
test ! -e "$project/control/progress/lunaconvergence-task-003.needs-replan.md"
test ! -e "$project/control/progress/lunaconvergence-task-003.liveness-epoch.env"
grep -Fq 'LUNA_ONLY_LIVENESS_BOUNDARY_RETAINED root=003 category=TOTAL_ROOT_REPLANS' \
	"$project/logs/events.log"

# Typed ready/result policy migrations remain mandatory-decomposition
# boundaries; they are separate from already-tripped investigation fuses.
grep -Fq 'resource_recovery == 0 && policy_migration == 0 && closure_repair == 0' \
	"$ROOT/bin/manager-auto-replan-root"
test "$(grep -Fc 'closure_repair == 0' \
	"$ROOT/bin/manager-auto-replan-root")" -eq 2

# Publication observes those typed repair boundaries without granting them
# authority to reset an architecture-reassessment incident.
grep -Fq 'LUNA_ONLY_POLICY_MIGRATION|CONTEXT_CLOSURE_REPAIR' \
	"$ROOT/bin/manager-publish-task"
test "$(grep -Fc 'typed_boundary_repair == 0' \
	"$ROOT/bin/manager-publish-task")" -eq 2

printf 'new child rejection\n' > "$project/archive/lunaconvergence-task-003-revision-02.rejected.md"
cat >> "$project/control/progress/lunaconvergence-task-003.replans.tsv" <<'TSV'
2026-08-17T00:01:00Z	003-revision-02	TEST	child	decompose	-	0	fresh	-	0	0
TSV
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; \
  test ! -e "$(task_root_liveness_epoch_file 003)"; \
  test "$(root_reviewed_attempt_count 003)" = 3; \
  test "$(root_total_replan_count 003)" = 2' _ "$ROOT" "$TMP/harness.env"

printf 'Luna-only convergence tests passed.\n'
