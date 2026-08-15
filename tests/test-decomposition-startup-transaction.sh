#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-decomposition-startup.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

repo="$TEST_ROOT/repo"
state="$TEST_ROOT/state"
mkdir -p "$repo/src" "$repo/spec-review" "$TEST_ROOT/configs" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'REQ-ONE: implement one bounded behavior.\n' > "$repo/spec.md"
printf 'int target(void) { return 0; }\n' > "$repo/src/a.c"
git -C "$repo" init -q
git -C "$repo" add spec.md src/a.c
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed

env_file="$TEST_ROOT/configs/startup.env"
cat > "$env_file" <<ENV
export PROJECT="startup-split"
export REPOSITORY="$repo"
export SPECIFICATION="$repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$state"
export HARNESS_BOOT_RECOVERY="0"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/false"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/false"
export DECOMPOSITION_MODEL="gpt-5.6-sol"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="1"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="100"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$env_file"
"$HARNESS_BIN/harness-init" "$env_file" >/dev/null
project_dir="$state/projects/startup-split"

# Concurrent read-only reporting must never be mistaken for an owning startup
# or agent process, while a mutating harness command remains detectable.
bash -c 'sleep 30; :' "$HARNESS_BIN/harness-status" "$env_file" &
report_pid=$!
sleep 0.1
report_lines="$(bash -c 'source "$1"; load_harness_env "$2"; env_process_lines' _ "$HARNESS_HOME/lib/harness-common.sh" "$env_file")"
[[ -z "$report_lines" ]]
kill "$report_pid" 2>/dev/null || true
wait "$report_pid" 2>/dev/null || true
bash -c 'sleep 30; :' "$HARNESS_BIN/harness-start" "$env_file" &
owner_pid=$!
sleep 0.1
owner_lines="$(bash -c 'source "$1"; load_harness_env "$2"; env_process_lines' _ "$HARNESS_HOME/lib/harness-common.sh" "$env_file")"
grep -Fq "$owner_pid" <<< "$owner_lines"
kill "$owner_pid" 2>/dev/null || true
wait "$owner_pid" 2>/dev/null || true

spec_sha="$(sha256sum "$repo/spec.md" | awk '{print $1}')"
baseline="$(git -C "$repo" rev-parse HEAD)"
domain_sha="$(bash -c 'source "$1"; load_harness_env "$2"; domain_profiles_sha256' _ "$HARNESS_HOME/lib/harness-common.sh" "$env_file")"

cat > "$repo/spec-review/accepted.md" <<EOF
# Specification Review

Project: startup-split
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Decision: ACCEPT
EOF
cat > "$repo/spec-review/obligations.tsv" <<'EOF'
obligation_id	authority	source_requirement	source_location	obligation_type	statement	observable_outcome	acceptance_authority
REQ-ONE	SPECIFIED	REQ-ONE	spec.md:1	FUNCTIONAL	Implement target behavior	Focused target validation passes	SPECIFICATION
EOF
cat > "$repo/spec-review/relations.tsv" <<'EOF'
relation_id	relation_type	subject	object	authority	evidence
EOF
cat > "$repo/spec-review/facts.tsv" <<'EOF'
fact_id	kind	subject	value	evidence	authority	confidence
FACT-ONE	PATH	target source	src/a.c	src/a.c:1	OBSERVED	HIGH
EOF
printf 'kind\tpath\tdetail\tevidence\n' > "$repo/spec-review/inventory.tsv"
printf 'profile_id\tsource\tsha256\n' > "$repo/spec-review/domain.tsv"
cat > "$project_dir/control/specification-review.env" <<EOF
status=ACCEPTED
specification_sha256=$spec_sha
repository_baseline=$baseline
domain_profiles_sha256=$domain_sha
report=spec-review/accepted.md
facts=spec-review/facts.tsv
issues=spec-review/no-issues.tsv
obligations=spec-review/obligations.tsv
relations=spec-review/relations.tsv
inventory=spec-review/inventory.tsv
domain_manifest=spec-review/domain.tsv
issue_count=0
obligation_count=1
relation_count=0
reviewed_at=2026-08-14T00:00:00Z
EOF

fit_report="$TEST_ROOT/fit.md"
cat > "$fit_report" <<EOF
# Architecture Fit Review

Project: startup-split
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Domain-Profiles-SHA256: $domain_sha
Decision: ACCEPT

Evidence: the bounded source has one owner, no cross-component transaction, and a focused validation seam.
EOF
fit_relative="$($HARNESS_BIN/manager-record-architecture-fit "$env_file" "$fit_report")"
[[ "$fit_relative" == architecture-review/architecture-fit-* ]]
grep -Fqx 'status=ACCEPTED' "$project_dir/control/architecture-fit-review.env"

cat > "$TEST_ROOT/dag.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
n01	-	-	Implement target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA
EOF
cat > "$TEST_ROOT/coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-ONE	n01	n01 focused source validation
EOF
cat > "$TEST_ROOT/bad-coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
EOF

set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/dag.tsv" "$TEST_ROOT/bad-coverage.tsv" >/dev/null 2>&1
bad_dag_status=$?
set -e
(( bad_dag_status != 0 ))
grep -Fqx 'status=REJECTED' "$project_dir/control/decomposition-dag-candidate.env"
dag_rejection_log="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
test -s "$dag_rejection_log"

"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/dag.tsv" "$TEST_ROOT/coverage.tsv" >/dev/null
grep -Fqx 'status=STAGED' "$project_dir/control/decomposition-dag-candidate.env"
staged_dag="$(awk -F= '$1=="dag" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
cmp -s "$TEST_ROOT/dag.tsv" "$staged_dag"

# Deterministic rejection must retain exact diagnostics so startup can repair
# the staged artifact without another global decomposition pass.
set +e
"$HARNESS_BIN/manager-submit-decomposition" "$env_file" "$TEST_ROOT/dag.tsv" "$TEST_ROOT/bad-coverage.tsv" - >/dev/null 2>&1
bad_status=$?
set -e
(( bad_status != 0 ))
grep -Fqx 'status=REJECTED' "$project_dir/control/decomposition-candidate.env"
rejection_log="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-candidate.env" | tail -1)"
test -s "$rejection_log"
grep -Eq 'coverage|obligation|mapped' "$rejection_log"

# A killed submission may leave a complete staged candidate before plan
# installation. Startup must report the failure, then recover it without a new
# model invocation.
candidate="$project_dir/control/decomposition-candidates/test-candidate"
mkdir -p "$candidate"
install -m 600 "$TEST_ROOT/dag.tsv" "$candidate/dag.tsv"
install -m 600 "$TEST_ROOT/coverage.tsv" "$candidate/coverage.tsv"
cat > "$project_dir/control/decomposition-candidate.env" <<EOF
status=STAGED
specification_sha256=$spec_sha
repository_baseline=$baseline
domain_profiles_sha256=$domain_sha
directory=$candidate
architecture_directory=-
architecture_registered_by_candidate=0
staged_at=2026-08-14T00:00:00Z
EOF
cat > "$project_dir/control/harness-start-background.status" <<EOF
state=FAILED
pid=999999
started_at=2026-08-14T00:00:00Z
finished_at=2026-08-14T00:01:00Z
exit_status=75
log=$project_dir/logs/harness-start-test.log
EOF
status_output="$($HARNESS_BIN/harness-status --machine "$env_file")"
grep -Fq 'Startup transaction: FAILED exit=75' <<< "$status_output"
grep -Fq 'Project status: STARTUP_FAILED.' <<< "$status_output"
watch_output="$(HARNESS_WATCH_COLOR=always COLUMNS=120 LINES=30 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/configs")"
grep -Eq $'^\033\[7mstartup-split +\| *0\| paused' <<< "$watch_output"

"$HARNESS_BIN/manager-submit-decomposition" --recover "$env_file" >/dev/null
grep -Fqx 'status=INSTALLED' "$project_dir/control/decomposition-candidate.env"
test -f "$project_dir/control/project-decomposition-v2.tsv"
grep -Fq $'n01\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"

printf 'split decomposition startup transaction tests passed\n'
