#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-decomposition-startup.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\\n" "$TEST_ROOT" >&2' EXIT
else
	trap 'rm -rf -- "$TEST_ROOT"' EXIT
fi

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
REQ-ONE	SPECIFIED	REQ-ONE	spec.md:1	FUNCTIONAL	Implement target ownership with exact error handling and receipt telemetry	Focused target validation passes	SPECIFICATION
REQ-TWO	SPECIFIED	REQ-TWO	spec.md:1	FUNCTIONAL	Expose the completed target behavior	The same focused target validation passes	SPECIFICATION
EOF
cat > "$repo/spec-review/relations.tsv" <<'EOF'
relation_id	relation_type	subject	object	authority	evidence
REL-TWO-ONE	DEPENDS_ON	REQ-TWO	REQ-ONE	SPECIFIED	spec.md:1
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
obligation_count=2
relation_count=1
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
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n01	-	-	Implement target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
n02	-	n01	Expose target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
terra-contract	-	n02	Choose the target contract	Contract decision is accepted	test -f src/a.c	src/a.c	target	CONTRACT_DESIGN	HIGH	TERRA	2	2	2	0	2	3	11	360000	CONTRACT_DECISION
EOF
cat > "$TEST_ROOT/coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-ONE	n01	n01 focused source validation
REQ-TWO	n02,terra-contract	n02 exposes behavior and terra-contract fixes its contract
EOF
cat > "$TEST_ROOT/verification-dag.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n01	-	-	Verify existing target behavior	Focused source already exists	test -f src/a.c	src/a.c	target	VERIFICATION_ONLY	LOW	LUNA	1	0	0	0	1	0	3	70000	-
n02	-	n01	Expose target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
terra-contract	-	n02	Choose the target contract	Contract decision is accepted	test -f src/a.c	src/a.c	target	CONTRACT_DESIGN	HIGH	TERRA	2	2	2	0	2	3	11	360000	CONTRACT_DECISION
EOF
awk -F '\t' 'BEGIN {OFS=FS} $1=="terra-contract" {$17=0} {print}' \
	"$TEST_ROOT/dag.tsv" > "$TEST_ROOT/zero-write-terra-dag.tsv"
awk -F '\t' 'BEGIN {OFS=FS} $1=="n01" {$17=0} {print}' \
	"$TEST_ROOT/dag.tsv" > "$TEST_ROOT/zero-write-luna-coding-dag.tsv"
cat > "$TEST_ROOT/over-budget-dag.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n01	-	-	Implement target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	2	0	0	0	1	1	4	100000	-
EOF
cat > "$TEST_ROOT/over-budget-coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-ONE	n01	n01 combined behavior validation
REQ-TWO	n01	n01 combined behavior validation
EOF
cat > "$TEST_ROOT/split-dag.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n10	-	-	Implement target behavior and ownership	Focused source and ownership evidence exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	2	0	1	0	1	1	4	100000	-
n11	-	n10	Expose target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
EOF
cat > "$TEST_ROOT/split-coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-ONE	n10	n10 implements the prerequisite
REQ-TWO	n11	n11 exposes the accepted prerequisite behavior
EOF
cat > "$TEST_ROOT/replacements.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n10a	-	-	Implement target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	3	70000	-
n10b	-	n10a	Verify target ownership	Focused ownership evidence exists	test -f src/a.c	src/a.c	target	TEST_IMPLEMENTATION	LOW	LUNA	1	0	1	0	1	1	3	70000	-
EOF
cat > "$TEST_ROOT/split-mapping.tsv" <<'EOF'
old_node_id	replacement_node_ids
n10	n10a,n10b
EOF
cat > "$TEST_ROOT/bad-coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
EOF
sed 's#src/a.c#spec.md#g' "$TEST_ROOT/dag.tsv" > "$TEST_ROOT/spec-edit-dag.tsv"
cat > "$TEST_ROOT/omitted-node-dag.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n00	-	-	Implement target prerequisite	Focused prerequisite exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
n01	-	n00	Implement bounded target adaptation	Focused adaptation exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
n02	-	n01	Expose target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
EOF
cat > "$TEST_ROOT/omitted-node-coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-ONE	n00	n00 implements the prerequisite behavior
REQ-TWO	n02	n02 exposes the accepted prerequisite behavior
EOF
cat > "$TEST_ROOT/omitted-node-mapping.tsv" <<'EOF'
node_id	obligation_ids
n01	REQ-TWO
EOF
cat > "$TEST_ROOT/reorder-dag.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n01	-	-	Expose target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
n02	-	-	Implement target behavior	Focused source exists	test -f src/a.c	src/a.c	target	LOCAL_IMPLEMENTATION	LOW	LUNA	1	0	0	0	1	1	4	100000	-
EOF
cat > "$TEST_ROOT/reorder-coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-ONE	n02	n02 implements the prerequisite
REQ-TWO	n01	n01 exposes the dependent behavior
EOF

# A subjective LOW/LUNA label cannot bypass the deterministic complexity
# vector. The candidate remains repairable and exposes its exact excess.
grep -Fq 'leaf_type INTEGRATION, complexity_class HIGH, worker_route TERRA, and terra_exception IRREDUCIBLE_CROSS_BOUNDARY' \
	"$HARNESS_BIN/manager-decomposition-dag-repair"
# The bounded repair mapping is initialized directly from the measured report;
# an undefined intermediary once made every real recursive repair fail before
# Sol could be invoked.
grep -Fq 'NR>1 && $19=="OVER_BUDGET"' "$HARNESS_BIN/manager-decomposition-dag-repair"
grep -Fq '"$complexity_report"' "$HARNESS_BIN/manager-decomposition-dag-repair"
! grep -Fq '"$allowed"' "$HARNESS_BIN/manager-decomposition-dag-repair"
set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/over-budget-dag.tsv" "$TEST_ROOT/over-budget-coverage.tsv" >/dev/null 2>&1
complexity_status=$?
set -e
(( complexity_status != 0 ))
complexity_rejection_log="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Fq 'LUNA_COMPLEXITY_OVER_BUDGET node=n01' "$complexity_rejection_log"
grep -Fq 'behavioral_concerns=2>1' "$complexity_rejection_log"

# External contract/integration decisions may be executable zero-write Terra
# leaves, while routine Luna coding cannot claim that exemption.
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" \
	"$TEST_ROOT/zero-write-terra-dag.tsv" "$TEST_ROOT/coverage.tsv" >/dev/null
grep -Fqx 'status=STAGED' "$project_dir/control/decomposition-dag-candidate.env"
set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" \
	"$TEST_ROOT/zero-write-luna-coding-dag.tsv" "$TEST_ROOT/coverage.tsv" >/dev/null 2>&1
zero_write_luna_status=$?
set -e
(( zero_write_luna_status != 0 ))
zero_write_luna_rejection="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Fq 'implementation files may be zero only for zero-write verification or Terra decision/integration leaves' \
	"$zero_write_luna_rejection"

# Candidate preflight reports every malformed vector in one Sol correction.
awk -F '\t' 'BEGIN {OFS=FS} NR > 1 {$12=0; $16=0} {print}' \
	"$TEST_ROOT/dag.tsv" > "$TEST_ROOT/multi-invalid-vector-dag.tsv"
set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" \
	"$TEST_ROOT/multi-invalid-vector-dag.tsv" "$TEST_ROOT/coverage.tsv" >/dev/null 2>&1
multi_vector_status=$?
set -e
(( multi_vector_status != 0 ))
multi_vector_rejection="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Fq 'LUNA_COMPLEXITY_INVALID node=n01 dimension_12 must be positive' "$multi_vector_rejection"
grep -Fq 'LUNA_COMPLEXITY_INVALID node=n02 dimension_12 must be positive' "$multi_vector_rejection"

# Preferred-route preflight likewise reports every routine Terra escape in a
# single rejection instead of revealing one coding node per paid repair turn.
awk -F '\t' 'BEGIN {OFS=FS} NR > 1 {$10="HIGH"; $11="TERRA"; $20="IRREDUCIBLE_CROSS_BOUNDARY"} {print}' \
	"$TEST_ROOT/dag.tsv" > "$TEST_ROOT/multi-terra-coding-dag.tsv"
set +e
bash -c 'source "$1"; load_harness_env "$2"; initialize_project_plan_v2 "$3" "$4"' _ \
	"$HARNESS_HOME/lib/harness-common.sh" "$env_file" \
	"$TEST_ROOT/multi-terra-coding-dag.tsv" "$TEST_ROOT/coverage.tsv" \
	> "$TEST_ROOT/multi-route-rejection.log" 2>&1
multi_route_status=$?
set -e
(( multi_route_status != 0 ))
multi_route_rejection="$TEST_ROOT/multi-route-rejection.log"
grep -Fq 'Luna-preferred DAG routes coding node n01 to Terra' "$multi_route_rejection"
grep -Fq 'Luna-preferred DAG routes coding node n02 to Terra' "$multi_route_rejection"

set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/spec-edit-dag.tsv" "$TEST_ROOT/coverage.tsv" >/dev/null 2>&1
spec_edit_status=$?
set -e
(( spec_edit_status != 0 ))
spec_edit_rejection="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Fq 'decomposition DAG must treat the accepted governing specification as immutable authority' "$spec_edit_rejection"

# Recursive complexity repair is submitted as a bounded replacement patch.
# The machine merges it into the full DAG, rewrites dependent edges and
# obligation coverage, then runs the ordinary global validators.
set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/split-dag.tsv" "$TEST_ROOT/split-coverage.tsv" >/dev/null 2>&1
split_status=$?
set -e
(( split_status != 0 ))
"$HARNESS_BIN/manager-stage-decomposition-node-split" "$env_file" "$TEST_ROOT/replacements.tsv" "$TEST_ROOT/split-mapping.tsv" >/dev/null
split_candidate_dag="$(awk -F= '$1=="dag" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
split_candidate_coverage="$(awk -F= '$1=="coverage" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Fq $'n11\t-\tn10b\t' "$split_candidate_dag"
grep -Fq $'REQ-ONE\tn10a,n10b\t' "$split_candidate_coverage"
grep -Fqx 'status=STAGED' "$project_dir/control/decomposition-dag-candidate.env"

# Sol may split a covered obligation into an executable chain but omit a new
# child ID from node_ids.  That is a mechanical serialization defect: bind the
# child to the nearest covered acceptance boundary without another model turn.
set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/omitted-node-dag.tsv" "$TEST_ROOT/omitted-node-coverage.tsv" >/dev/null 2>&1
omitted_status=$?
set -e
(( omitted_status != 0 ))
omitted_rejection_log="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Fq 'DAG node is not justified by a normalized specification obligation: n01' "$omitted_rejection_log"
"$HARNESS_BIN/manager-stage-decomposition-coverage-patch" "$env_file" "$TEST_ROOT/omitted-node-mapping.tsv" >/dev/null
patched_coverage="$(awk -F= '$1=="coverage" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Eq $'^REQ-TWO\tn02,n01\t' "$patched_coverage"
grep -Fqx 'status=STAGED' "$project_dir/control/decomposition-dag-candidate.env"

# The no-agent repair reaches the same valid bounded mapping when topology and
# existing acceptance boundaries make it unambiguous.
set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/omitted-node-dag.tsv" "$TEST_ROOT/omitted-node-coverage.tsv" >/dev/null 2>&1
omitted_status=$?
set -e
(( omitted_status != 0 ))
"$HARNESS_BIN/manager-repair-decomposition-coverage" "$env_file" >/dev/null
repaired_coverage="$(awk -F= '$1=="coverage" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -Eq $'^REQ-TWO\tn02,n01\t' "$repaired_coverage"
grep -Fqx 'status=STAGED' "$project_dir/control/decomposition-dag-candidate.env"

set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/reorder-dag.tsv" "$TEST_ROOT/reorder-coverage.tsv" >/dev/null 2>&1
reorder_status=$?
set -e
(( reorder_status != 0 ))
"$HARNESS_BIN/manager-repair-decomposition-relations" "$env_file" >/dev/null
reordered_dag="$(awk -F= '$1=="dag" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
[[ "$(awk -F '\t' 'NR==2 {print $1}' "$reordered_dag")" == n02 ]]
[[ "$(awk -F '\t' 'NR==3 {print $1 " " $3}' "$reordered_dag")" == 'n01 n02' ]]

set +e
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" "$TEST_ROOT/dag.tsv" "$TEST_ROOT/bad-coverage.tsv" >/dev/null 2>&1
bad_dag_status=$?
set -e
(( bad_dag_status != 0 ))
grep -Fqx 'status=REJECTED' "$project_dir/control/decomposition-dag-candidate.env"
dag_rejection_log="$(awk -F= '$1=="rejection_log" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
test -s "$dag_rejection_log"

# Existing acceptance evidence is a first-class zero-write Luna leaf rather
# than a fake test implementation with source mutation authority.
"$HARNESS_BIN/manager-stage-decomposition-dag" "$env_file" \
	"$TEST_ROOT/verification-dag.tsv" "$TEST_ROOT/coverage.tsv" >/dev/null
verification_candidate="$(awk -F= '$1=="directory" {print $2}' "$project_dir/control/decomposition-dag-candidate.env")"
grep -q $'^n01\t.*\tVERIFICATION_ONLY\tLOW\tLUNA\t.*\t0\t' "$verification_candidate/dag.tsv"

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
grep -Eq $'^startup-split +\| *0\| \033\[31mpaused\033\[0m +\|' <<< "$watch_output"

"$HARNESS_BIN/manager-submit-decomposition" --recover "$env_file" >/dev/null
grep -Fqx 'status=INSTALLED' "$project_dir/control/decomposition-candidate.env"
test -f "$project_dir/control/project-decomposition-v2.tsv"
test -f "$project_dir/control/decomposition-complexity.tsv"
grep -Fq $'n01\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"
complexity_output="$($HARNESS_BIN/harness-complexity "$env_file")"
grep -Fq 'n01' <<< "$complexity_output"
grep -Fq 'READY' <<< "$complexity_output"
# A broad parent obligation may span ownership, error, and telemetry domains.
# Its focused child does not inherit those words for risk-domain scoring; full
# obligation coverage remains mandatory through the separate coverage table.
grep -Fq $'n01\tLUNA\tLOCAL_IMPLEMENTATION\t' "$project_dir/control/decomposition-complexity.tsv"
[[ "$(awk -F '\t' '$1=="n01" {print $18}' "$project_dir/control/decomposition-complexity.tsv")" == 0 ]]
# Sol may underestimate tool actions, but a source-changing node is always
# normalized to the deterministic inspect/edit/validate/commit/result floor.
[[ "$(awk -F '\t' '$1=="n01" {print $15}' "$project_dir/control/decomposition-complexity.tsv")" == 6 ]]

# Observed execution and manager outcome feed model- and planner-specific
# calibration without changing the immutable plan.
cat > "$TEST_ROOT/worker.classification" <<'EOF'
classification=success
invocation_processed_delta=80000
estimated_processed_tokens=80000
item_started_count=4
changed_file_count=1
changed_line_count=12
invocation_duration_seconds=30
EOF
cat > "$TEST_ROOT/worker.jsonl" <<'EOF'
{"type":"item.completed","item":{"type":"command_execution","command":"sed -n '1,20p' src/a.c","aggregated_output":"bounded source"}}
EOF
bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	ensure_project
	record_worker_complexity_observation leaf-task n01 worker "$LUNA_WORKER_MODEL" "$3" "$4"
	record_worker_complexity_outcome leaf-task ACCEPTED
' _ "$HARNESS_HOME" "$env_file" "$TEST_ROOT/worker.classification" "$TEST_ROOT/worker.jsonl"
complexity_output="$($HARNESS_BIN/harness-complexity "$env_file")"
grep -Fq $'gpt-5.6-luna\tLUNA\t1\t100.00' <<< "$complexity_output"
grep -Fq $'gpt-5.6-sol\t1\t0.00\t100.00\t100.00\t80000' <<< "$complexity_output"

# A truncated or resource-fused episode remains reportable but must not poison
# the accepted-success calibration population used to admit future leaves.
cat > "$TEST_ROOT/anomalous-worker.classification" <<'EOF'
classification=agent_estimated_token_budget_exceeded
invocation_processed_delta=500000
estimated_processed_tokens=500000
item_started_count=20
changed_file_count=0
changed_line_count=0
invocation_duration_seconds=300
EOF
bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	ensure_project
	record_worker_complexity_observation anomaly-task n01 worker "$LUNA_WORKER_MODEL" "$3" "$4"
	record_worker_complexity_outcome anomaly-task ACCEPTED
' _ "$HARNESS_HOME" "$env_file" "$TEST_ROOT/anomalous-worker.classification" "$TEST_ROOT/worker.jsonl"
calibrated_rate="$(HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES=2 bash -c '
	source "$1/lib/harness-common.sh"
	load_harness_env "$2"
	complexity_calibrated_tokens_per_score "$LUNA_WORKER_MODEL"
' _ "$HARNESS_HOME" "$env_file")"
[[ "$calibrated_rate" == 10000 ]]

# Recovery revisions inherit the same machine-owned measured vector as their
# active plan node. Even an ultimately invalid draft is normalized before
# semantic validation, so an agent never has to guess these fields.
sed -i $'s/^n01\tPENDING\t-/n01\tACTIVE\tleaf-root/' "$project_dir/control/project-plan-state.tsv"
mkdir -p "$project_dir/control/progress"
cat > "$project_dir/control/progress/startup-split-task-leaf-root.needs-replan.md" <<'EOF'
# Root Task Needs Replanning

Task-Root: leaf-root
Triggered-By: leaf-root
Trigger-Outcome: REJECT
EOF
cat > "$TEST_ROOT/revision-draft.md" <<'EOF'
# Revision draft

Task-ID: leaf-root-revision-01
Complexity-Class: HIGH
Worker-Route: TERRA
Leaf-Type: LOCAL_IMPLEMENTATION
Validation-Class: FOCUSED
Expected-Max-Implementation-Files: 1
Expected-Max-Worker-Turns: 1
Required-Symbols: target
Obligations: REQ-ONE
Architecture-Decisions: NONE
EOF
set +e
"$HARNESS_BIN/manager-publish-task" "$env_file" leaf-root-revision-01 \
	"$TEST_ROOT/revision-draft.md" --auto-replan >/dev/null 2>&1
revision_status=$?
set -e
(( revision_status != 0 ))
for field in Complexity-Score Behavioral-Concerns Failure-Paths Ownership-Transitions \
	Concurrency-Boundaries Validation-Surfaces Expected-Max-Implementation-Files \
	Expected-Max-Agent-Actions Predicted-P95-Tokens Effective-P95-Tokens Terra-Exception \
	Complexity-Class Worker-Route; do
	[[ "$(grep -c "^$field:" "$TEST_ROOT/revision-draft.md")" == 1 ]]
done
grep -Fqx 'Task-ID: leaf-root-revision-01' "$TEST_ROOT/revision-draft.md"
grep -Fqx 'Task-Root: leaf-root' "$TEST_ROOT/revision-draft.md"
grep -Fqx 'Worker-Context: FRESH' "$TEST_ROOT/revision-draft.md"
grep -Fqx 'Supersedes-Task: leaf-root' "$TEST_ROOT/revision-draft.md"
[[ "$(grep -c '^Replan-Strategy-ID:' "$TEST_ROOT/revision-draft.md")" == 1 ]]
grep -Fqx 'Complexity-Class: LOW' "$TEST_ROOT/revision-draft.md"
grep -Fqx 'Worker-Route: LUNA' "$TEST_ROOT/revision-draft.md"
grep -Fqx 'Expected-Max-Agent-Actions: 6' "$TEST_ROOT/revision-draft.md"
# The residual child computes to 90K, but recovery may not lower an already
# calibrated Luna node's immutable 140K P95 baseline.
grep -Fqx 'Effective-P95-Tokens: 140000' "$TEST_ROOT/revision-draft.md"

# Once Luna strategies are exhausted and structural depth cannot grow, recovery
# may promote the bounded remainder to an irreducible Terra integration leaf.
# Normalization must not restore the original Luna route and manufacture the
# impossible INTEGRATION/LUNA combination.
for failed_revision in 90 91 92; do
	cat > "$project_dir/archive/startup-split-task-leaf-root-revision-$failed_revision.assignment.md" <<'EOF'
Task-ID: leaf-root-revision-failed
Task-Root: leaf-root
Worker-Route: LUNA
EOF
	cat > "$project_dir/archive/startup-split-task-leaf-root-revision-$failed_revision.result.md" <<'EOF'
Task-ID: leaf-root-revision-failed
Goal-Outcome: NEEDS_DECOMPOSITION
EOF
done
cat > "$TEST_ROOT/integration-draft.md" <<'EOF'
Task-ID: leaf-root-revision-02
Leaf-Type: INTEGRATION
Complexity-Class: HIGH
Worker-Route: TERRA
Validation-Class: INCREMENTAL
Expected-Max-Implementation-Files: 1
Expected-Max-Worker-Turns: 2
Required-Symbols: target
Obligations: REQ-ONE
Architecture-Decisions: NONE
Terra-Exception: IRREDUCIBLE_CROSS_BOUNDARY
EOF
set +e
"$HARNESS_BIN/manager-publish-task" "$env_file" leaf-root-revision-02 \
	"$TEST_ROOT/integration-draft.md" --auto-replan >"$TEST_ROOT/integration.out" 2>"$TEST_ROOT/integration.err"
integration_status=$?
set -e
(( integration_status != 0 ))
grep -Fqx 'Leaf-Type: INTEGRATION' "$TEST_ROOT/integration-draft.md"
grep -Fqx 'Worker-Route: TERRA' "$TEST_ROOT/integration-draft.md"
grep -Fqx 'Terra-Exception: IRREDUCIBLE_CROSS_BOUNDARY' "$TEST_ROOT/integration-draft.md"
! grep -Fq 'requires Terra' "$TEST_ROOT/integration.err"

cat > "$TEST_ROOT/remediation-draft.md" <<'EOF'
# Manager remediation draft

Task-ID: leaf-root-revision-01
Complexity-Class: LOW
Worker-Route: LUNA
EOF
set +e
"$HARNESS_BIN/manager-publish-task" "$env_file" leaf-root-revision-01 \
	"$TEST_ROOT/remediation-draft.md" --manager-remediation >/dev/null 2>&1
remediation_status=$?
set -e
(( remediation_status != 0 ))
grep -Fqx 'Complexity-Class: LOW' "$TEST_ROOT/remediation-draft.md"
grep -Fqx 'Worker-Route: TERRA' "$TEST_ROOT/remediation-draft.md"
grep -Fqx 'Terra-Exception: -' "$TEST_ROOT/remediation-draft.md"

# A verified Terra decision may leave only bounded, zero-write validation
# evidence. Recovery must preserve immutable architecture authority while
# replacing the completed HIGH/TERRA execution vector with a deterministic
# residual LOW/LUNA vector. This is the exact transition that previously left
# a live supervisor idle behind a permanently rejected continuation.
sed -i \
	-e $'s/^n01\tACTIVE\tleaf-root/n01\tCOMPLETE\tleaf-root/' \
	-e $'s/^n02\tPENDING\t-/n02\tCOMPLETE\tn02/' \
	-e $'s/^terra-contract\tPENDING\t-/terra-contract\tACTIVE\tterra-contract/' \
	"$project_dir/control/project-plan-state.tsv"
cat > "$project_dir/control/progress/startup-split-task-terra-contract.root-assignment.md" <<'EOF'
# Terra contract root

Task-ID: terra-contract
Task-Root: terra-contract
Root-Criterion: terra-contract.acceptance
Allowed-Scope: src/a.c
Architecture-Decisions: TERRA-CONTRACT-001
Expected-Max-Implementation-Files: 3
Expected-Max-Worker-Turns: 11
EOF
cat > "$project_dir/control/progress/startup-split-task-terra-contract.criteria.tsv" <<'EOF'
item_id	state	verified_by	evidence_sha256	updated_at
terra-contract.decision	VERIFIED	terra-contract	sha256:test	2026-08-15T00:00:00Z
EOF
cat > "$project_dir/control/progress/startup-split-task-terra-contract.needs-replan.md" <<'EOF'
# Root Task Needs Replanning

Task-Root: terra-contract
Triggered-By: terra-contract
Trigger-Outcome: CHECKPOINT
Blocking-Fingerprint: -
EOF
cat > "$project_dir/control/startup-split-task-terra-contract.manager-replan-failed.md" <<'EOF'
# Automatic Manager Replan Invocation Failed

Project: startup-split
Task-Root: terra-contract
Exit-Status: 70
EOF
recovery_status="$($HARNESS_BIN/harness-status --machine "$env_file")"
grep -Fq 'Project status: RECOVERY_STALLED.' <<< "$recovery_status"
recovery_watch="$(HARNESS_WATCH_COLOR=always COLUMNS=120 LINES=30 \
	"$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/configs")"
grep -Eq $'^startup-split +\| *0\| \033\[31mpaused\033\[0m +\|' <<< "$recovery_watch"
grep -Fq 'RECOVERY_STALLED:' <<< "$recovery_watch"
rm -f "$project_dir/control/startup-split-task-terra-contract.manager-replan-failed.md"

cat > "$TEST_ROOT/residual-evidence.md" <<'EOF'
# Residual evidence leaf

Task-ID: terra-contract-revision-01
Task-Root: terra-contract
Target-Criterion: terra-contract.acceptance
Worker-Context: FRESH
Replan-Strategy-ID: residual-evidence-v1
Strategy-Change: NEW_EVIDENCE
Supersedes-Task: terra-contract
Execution-Mode: LEAF_GOAL
Goal-ID: terra-contract.residual-evidence.v1
Goal-Success-Evidence: The existing target contract has retained focused evidence.
Focused-Validation: test -f src/a.c
Allowed-Scope: src/a.c
Baseline-Boundary: Preserve the verified Terra decision while changing only src/a.c.
Hard-Block-Conditions: Stop if evidence requires changing the accepted contract.
Leaf-Type: LOCAL_IMPLEMENTATION
Complexity-Class: HIGH
Worker-Route: TERRA
Depends-On: n02
Deliverable: Retained focused validation evidence.
Required-Symbols: target,target_contract,target_validate,target_encode,target_decode
Context-Paths: src/a.c
Architecture-Decisions: -
Validation-Class: FOCUSED
Expected-Max-Implementation-Files: 1
Expected-Max-Worker-Turns: 2

## Objective

Apply one bounded source correction after the Terra decision has already been verified.

## Acceptance criteria

- The focused target evidence is retained.

## Validation commands

```sh
test -f src/a.c
```
EOF
"$HARNESS_BIN/manager-publish-task" "$env_file" terra-contract-revision-01 \
	"$TEST_ROOT/residual-evidence.md" --auto-replan >/dev/null
residual_ready="$project_dir/tasks/startup-split-task-terra-contract-revision-01.ready.md"
test -f "$residual_ready"
grep -Fqx 'Complexity-Class: LOW' "$residual_ready"
grep -Fqx 'Worker-Route: LUNA' "$residual_ready"
grep -Fqx 'Expected-Max-Implementation-Files: 1' "$residual_ready"
grep -Fqx 'Terra-Exception: -' "$residual_ready"
grep -Fqx 'Architecture-Decisions: NONE' "$residual_ready"
awk -F': ' -v maximum=24 '$1=="Complexity-Score" {found=1; exit !($2<=maximum)} END{exit !found}' "$residual_ready"
grep -Fq 'RECOVERY_CHILD_RECLASSIFIED root=terra-contract task=terra-contract-revision-01 leaf_type=LOCAL_IMPLEMENTATION' \
	"$project_dir/logs/events.log"

printf 'split decomposition startup transaction tests passed\n'
