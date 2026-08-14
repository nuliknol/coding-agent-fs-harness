#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-specification-review.XXXXXX)"
trap '[[ "${KEEP_TEST_ROOT:-0}" == 1 ]] || rm -rf -- "$TEST_ROOT"' EXIT

repo="$TEST_ROOT/repo"
state="$TEST_ROOT/state"
mkdir -p "$repo/src" "$repo/.harness/domain-profiles" "$TEST_ROOT/configs" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'REQ-1: expose target_symbol and preserve zero on invalid input.\n' > "$repo/spec.md"
printf 'int target_symbol(int value) { return value < 0 ? 0 : value; }\n' > "$repo/src/a.c"
cat > "$repo/.harness/domain-profiles/test-contract.tsv" <<'EOF'
invariant_id	category	statement	source_authority	validation_hint
stable-negative-contract	CONTRACT	Negative input behavior remains stable	PROJECT_POLICY	Focused negative-input test
EOF
git -C "$repo" init -q
git -C "$repo" add spec.md src/a.c .harness/domain-profiles/test-contract.tsv
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed
printf '/spec-review/\n' >> "$repo/.git/info/exclude"

env_file="$TEST_ROOT/configs/spec-review.env"
cat > "$env_file" <<ENV
export PROJECT="spec-review-test"
export REPOSITORY="$repo"
export SPECIFICATION="$repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/false"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/false"
export MANAGER_MODEL="gpt-5.6-terra"
export WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_DOMAIN_PROFILES="test-contract"
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="100"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$env_file"
"$HARNESS_BIN/harness-init" "$env_file" >/dev/null
project_dir="$state/projects/spec-review-test"
spec_sha="$(sha256sum "$repo/spec.md" | awk '{print $1}')"
baseline="$(git -C "$repo" rev-parse HEAD)"
domain_sha="$(bash -c 'source "$1"; load_harness_env "$2"; domain_profiles_sha256' _ "$HARNESS_HOME/lib/harness-common.sh" "$env_file")"

verdict="$TEST_ROOT/verdict.md"
facts="$TEST_ROOT/facts.tsv"
issues="$TEST_ROOT/issues.tsv"
obligations="$TEST_ROOT/obligations.tsv"
relations="$TEST_ROOT/relations.tsv"
inventory="$TEST_ROOT/inventory.tsv"
domain_manifest="$TEST_ROOT/domain-manifest.tsv"
"$HARNESS_BIN/harness-build-repository-inventory" "$env_file" "$inventory" >/dev/null
printf '%s\n' \
	$'profile_id\tsource\tsha256' \
	"test-contract"$'\t'"$repo/.harness/domain-profiles/test-contract.tsv"$'\t'"$(sha256sum "$repo/.harness/domain-profiles/test-contract.tsv" | awk '{print $1}')" > "$domain_manifest"
cat > "$verdict" <<EOF
# Specification Review

Project: spec-review-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Domain-Profiles-SHA256: $domain_sha
Decision: SPEC_CLARIFICATION_REQUIRED

## Review summary
REQ-1 does not define whether negative input is rejected or normalized.
EOF
cat > "$obligations" <<'EOF'
obligation_id	authority	source_requirement	source_location	obligation_type	statement	observable_outcome	acceptance_authority
REQ-1	SPECIFIED	REQ-1	spec.md:1	CONTRACT	Define target_symbol negative-input behavior	One authoritative negative-input outcome	specification:REQ-1
PROFILE-negative-contract	DOMAIN_PROFILE	PROFILE:test-contract:stable-negative-contract	.harness/domain-profiles/test-contract.tsv:2	INVARIANT	Preserve stable negative-input behavior	Focused negative-input behavior remains stable	profile:test-contract
EOF
cat > "$relations" <<'EOF'
relation_id	relation_type	subject	object	authority	evidence
REL-req-validates	VALIDATES	REQ-1	FACT-target-test	SPECIFIED	specification:REQ-1
REL-profile-validates	VALIDATES	PROFILE-negative-contract	validation:negative-input	DOMAIN_PROFILE	profile:test-contract
REL-profile-preserves	PRESERVES	PROFILE-negative-contract	FACT-target-symbol	DOMAIN_PROFILE	profile:test-contract
REL-profile-depends	DEPENDS_ON	PROFILE-negative-contract	REQ-1	DOMAIN_PROFILE	profile:test-contract
REL-hint-cycle	DEPENDS_ON	REQ-1	PROFILE-negative-contract	PLANNING_HINT	advisory-only reverse ordering
EOF
cat > "$facts" <<'EOF'
fact_id	kind	subject	value	evidence	authority	confidence
FACT-target-symbol	SYMBOL	target_symbol	existing implementation	src/a.c:1	OBSERVED	HIGH
FACT-target-test	TEST_TARGET	target_symbol	no focused test target	specification:REQ-1	INFERRED	MEDIUM
EOF
cat > "$issues" <<'EOF'
issue_id	class	requirement_ids	source_locations	outcome_a	outcome_b	evidence_checked	missing_decision	minimal_question
SPEC-negative-input	OBSERVABLE_CONTRACT_AMBIGUITY	REQ-1	spec.md:1	Return zero for negative input	Return a typed invalid-input error	spec.md:1;src/a.c:1	Authoritative negative-input behavior	Should negative input normalize to zero or return an error?
EOF
record_output="$("$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" "$obligations" "$relations" "$inventory" "$domain_manifest")"
[[ "$record_output" =~ ^spec-review/specification-review-.*\.md$ ]]
[[ -f "$repo/$record_output" ]]
grep -Fqx 'status=SPEC_CLARIFICATION_REQUIRED' "$project_dir/control/specification-review.env"

clarification_prompt="$("$HARNESS_BIN/harness-show-clarification-request" "$env_file")"
grep -Fq '# Specification Author Action Required' <<< "$clarification_prompt"
grep -Fq "Repository: $repo" <<< "$clarification_prompt"
grep -Fq "Governing specification: $repo/spec.md" <<< "$clarification_prompt"
grep -Fq '### SPEC-negative-input — OBSERVABLE_CONTRACT_AMBIGUITY' <<< "$clarification_prompt"
grep -Fq 'Question you must answer: Should negative input normalize to zero or return an error?' \
	<<< "$clarification_prompt"
grep -Fq '## Required specification amendment' <<< "$clarification_prompt"
grep -Fq "git -C $repo add -- spec.md" <<< "$clarification_prompt"
grep -Fq "$HARNESS_BIN/harness-start --background $env_file" <<< "$clarification_prompt"
grep -Fq 'Do not wait for the detached startup to finish.' <<< "$clarification_prompt"

background_output="$("$HARNESS_BIN/harness-start" --background "$env_file")"
grep -Fq 'Harness start launched in background.' <<< "$background_output"
background_pid="$(awk -F': ' '$1 == "PID" {print $2}' <<< "$background_output")"
background_log="$(awk -F': ' '$1 == "Log" {print $2}' <<< "$background_output")"
background_status_file="$(awk -F': ' '$1 == "Status" {print $2}' <<< "$background_output")"
[[ "$background_pid" =~ ^[1-9][0-9]*$ ]]
[[ -n "$background_log" && -n "$background_status_file" ]]
for _ in $(seq 1 300); do
	[[ -f "$background_status_file" ]] || { sleep 0.01; continue; }
	background_state="$(awk -F= '$1 == "state" {print $2}' "$background_status_file")"
	[[ "$background_state" != RUNNING ]] && break
	sleep 0.01
done
grep -Fqx 'state=SPEC_CLARIFICATION_REQUIRED' "$background_status_file"
grep -Fqx 'exit_status=3' "$background_status_file"
grep -Fq "Specification clarification required: $record_output" "$background_log"
test ! -e "$project_dir/control/harness-start-background.pid"

set +e
printf 'must block review startup\n' > "$repo/untracked-before-start.txt"
dirty_start_output="$("$HARNESS_BIN/harness-start" "$env_file" 2>&1)"
dirty_start_status=$?
rm -f "$repo/untracked-before-start.txt"
set -e
(( dirty_start_status == 1 ))
grep -Fq '?? untracked-before-start.txt' <<< "$dirty_start_output"
grep -Fq 'repository has staged, unstaged, or non-ignored untracked files' <<< "$dirty_start_output"

set +e
start_output="$("$HARNESS_BIN/harness-start" "$env_file" 2>&1)"
start_status=$?
set -e
(( start_status == 3 ))
grep -Fqx "Specification clarification required: $record_output" <<< "$start_output"
[[ ! -f "$project_dir/control/project-plan.tsv" ]]

status_output="$("$HARNESS_BIN/harness-status" --full "$env_file")"
grep -Fq "Specification review: SPEC_CLARIFICATION_REQUIRED ($record_output)" <<< "$status_output"
grep -Fq "Project status: SPEC_CLARIFICATION_REQUIRED. Review $record_output before DAG registration." <<< "$status_output"
watch_output="$(HARNESS_WATCH_COLOR=always COLUMNS=120 LINES=30 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/configs")"
grep -Eq $'^\033\[7mspec-review-test +\| *0\| clarify' <<< "$watch_output"
grep -Fq "$record_output" <<< "$watch_output"

plan="$TEST_ROOT/plan.tsv"
cat > "$plan" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
n1	-	-	Add focused target_symbol tests	Negative and nonnegative cases pass	test -f src/a.c	src/a.c	target_symbol	TEST_IMPLEMENTATION	LOW	LUNA
n2	-	n1	Verify profile compatibility	Profile-focused compatibility assertion passes	test -f src/a.c	src/a.c	target_symbol	TEST_IMPLEMENTATION	LOW	LUNA
EOF
if "$HARNESS_BIN/manager-init-project-plan" "$env_file" "$plan" >/dev/null 2>&1; then
	printf 'DAG registration unexpectedly bypassed specification clarification\n' >&2
	exit 1
fi

cat > "$verdict" <<EOF
# Specification Review

Project: spec-review-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Domain-Profiles-SHA256: $domain_sha
Decision: ACCEPT
EOF
printf '%s\n' $'issue_id\tclass\trequirement_ids\tsource_locations\toutcome_a\toutcome_b\tevidence_checked\tmissing_decision\tminimal_question' > "$issues"
if "$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" "$obligations" "$relations" "$inventory" "$domain_manifest" >/dev/null 2>&1; then
	printf 'unchanged specification was unexpectedly accepted after clarification\n' >&2
	exit 1
fi

printf 'REQ-1: target_symbol must normalize negative input to zero.\n' > "$repo/spec.md"
git -C "$repo" add spec.md
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm clarify-negative-input
spec_sha="$(sha256sum "$repo/spec.md" | awk '{print $1}')"
baseline="$(git -C "$repo" rev-parse HEAD)"
"$HARNESS_BIN/harness-build-repository-inventory" "$env_file" "$inventory" >/dev/null
cat > "$verdict" <<EOF
# Specification Review

Project: spec-review-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Domain-Profiles-SHA256: $domain_sha
Decision: ACCEPT

## Review summary
REQ-1 and the existing public behavior consistently require normalization to zero.
EOF
printf '%s\n' $'issue_id\tclass\trequirement_ids\tsource_locations\toutcome_a\toutcome_b\tevidence_checked\tmissing_decision\tminimal_question' > "$issues"
"$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" "$obligations" "$relations" "$inventory" "$domain_manifest" >/dev/null
grep -Fqx 'status=ACCEPTED' "$project_dir/control/specification-review.env"
if "$HARNESS_BIN/harness-show-clarification-request" "$env_file" \
	>"$TEST_ROOT/no-clarification.out" 2>"$TEST_ROOT/no-clarification.err"; then
	printf 'clarification command succeeded for an accepted specification\n' >&2
	exit 1
fi
grep -Fq 'current specification review does not require clarification' \
	"$TEST_ROOT/no-clarification.err"

renormalization_reason="$TEST_ROOT/renormalization.md"
cat > "$renormalization_reason" <<'EOF'
# Specification Renormalization Request

The governing requirement is clear, but the generated relation set should be independently regenerated.
EOF
"$HARNESS_BIN/manager-request-specification-renormalization" "$env_file" "$renormalization_reason" >/dev/null
[[ ! -f "$project_dir/control/specification-review.env" ]]
[[ "$(find "$project_dir/control/specification-review-revisions" -type f -name '*.state.env' | wc -l)" == 1 ]]
"$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" "$obligations" "$relations" "$inventory" "$domain_manifest" >/dev/null

challenge_report="$TEST_ROOT/challenge.md"
challenge_issues="$TEST_ROOT/challenge-issues.tsv"
cat > "$challenge_report" <<'EOF'
# Specification Review Challenge

The accepted review missed a genuine compatibility choice in the governing source.
EOF
cat > "$challenge_issues" <<'EOF'
issue_id	class	requirement_ids	source_locations	outcome_a	outcome_b	evidence_checked	missing_decision	minimal_question
SPEC-compatibility	UNDEFINED_COMPATIBILITY	REQ-1	spec.md:1	Preserve zero normalization	Replace normalization with a typed error	spec.md:1;src/a.c:1	Compatibility authority	Must existing zero normalization remain compatible?
EOF
challenge_output="$("$HARNESS_BIN/manager-challenge-specification-review" "$env_file" "$challenge_report" "$challenge_issues")"
[[ "$challenge_output" =~ ^spec-review/specification-critic-challenge-.*\.md$ ]]
grep -Fqx 'status=SPEC_CLARIFICATION_REQUIRED' "$project_dir/control/specification-review.env"

printf '%s\n' \
	'REQ-1: target_symbol must normalize negative input to zero.' \
	'Scope clarification: this normalization is a compatibility requirement.' > "$repo/spec.md"
git -C "$repo" add spec.md
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm clarify-compatibility
spec_sha="$(sha256sum "$repo/spec.md" | awk '{print $1}')"
baseline="$(git -C "$repo" rev-parse HEAD)"
"$HARNESS_BIN/harness-build-repository-inventory" "$env_file" "$inventory" >/dev/null
cat > "$verdict" <<EOF
# Specification Review

Project: spec-review-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Domain-Profiles-SHA256: $domain_sha
Decision: ACCEPT

## Review summary
REQ-1 explicitly makes zero normalization a compatibility requirement.
EOF
"$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" "$obligations" "$relations" "$inventory" "$domain_manifest" >/dev/null
grep -Fqx 'status=ACCEPTED' "$project_dir/control/specification-review.env"

coverage="$TEST_ROOT/coverage.tsv"
incomplete_coverage="$TEST_ROOT/incomplete-coverage.tsv"
invalid_dependency_coverage="$TEST_ROOT/invalid-dependency-coverage.tsv"
cat > "$incomplete_coverage" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-1	n1	Focused negative and nonnegative target_symbol test
EOF
if "$HARNESS_BIN/manager-init-project-plan" "$env_file" "$plan" "$incomplete_coverage" >/dev/null 2>&1; then
	printf 'DAG registration unexpectedly accepted incomplete specification coverage\n' >&2
	exit 1
fi
[[ ! -f "$project_dir/control/project-plan.tsv" ]]
cat > "$invalid_dependency_coverage" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-1	n2	Focused negative and nonnegative target_symbol test
PROFILE-negative-contract	n1	Profile compatibility is checked before its required contract
EOF
if "$HARNESS_BIN/manager-init-project-plan" "$env_file" "$plan" "$invalid_dependency_coverage" >/dev/null 2>&1; then
	printf 'DAG registration unexpectedly accepted reversed typed dependency coverage\n' >&2
	exit 1
fi
[[ ! -f "$project_dir/control/project-plan.tsv" ]]
cat > "$coverage" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-1	n1	Focused negative and nonnegative target_symbol test
PROFILE-negative-contract	n2	The downstream focused test proves profile compatibility
EOF
"$HARNESS_BIN/manager-init-project-plan" "$env_file" "$plan" "$coverage" >/dev/null
grep -Fqx $'REQ-1\tn1\tFocused negative and nonnegative target_symbol test' "$project_dir/control/specification-coverage.tsv"

printf 'int target_symbol_helper(void) { return 0; }\n' > "$repo/src/helper.c"
git -C "$repo" add src/helper.c
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm advance-implementation
post_commit_status="$("$HARNESS_BIN/harness-status" --full "$env_file")"
grep -Fq 'Specification IR: obligations=2 relations=5 domain-profiles=test-contract' <<< "$post_commit_status"
mv "$project_dir/control/specification-coverage.tsv" "$TEST_ROOT/preserved-coverage.tsv"
invalid_status="$("$HARNESS_BIN/harness-status" --full "$env_file")"
grep -Fq 'Project status: SPECIFICATION_IR_INVALID.' <<< "$invalid_status"
invalid_watch="$(HARNESS_WATCH_COLOR=always COLUMNS=120 LINES=30 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/configs")"
grep -Eq $'^\033\[7mspec-review-test +\| *0\| paused' <<< "$invalid_watch"
if "$HARNESS_BIN/manager-plan-next-task" "$env_file" >/dev/null 2>&1; then
	printf 'manager planning unexpectedly bypassed missing registered Specification IR coverage\n' >&2
	exit 1
fi
mv "$TEST_ROOT/preserved-coverage.tsv" "$project_dir/control/specification-coverage.tsv"

cat > "$project_dir/archive/spec-review-test-task-luna.assignment.md" <<'EOF'
Task-ID: luna
Worker-Route: LUNA
EOF
cat > "$project_dir/archive/spec-review-test-task-terra.assignment.md" <<'EOF'
Task-ID: terra
Worker-Route: TERRA
EOF
cat > "$project_dir/logs/manager-plan-001.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"manager-thread"}
{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":70,"output_tokens":15}}
EOF
cat > "$project_dir/logs/manager-review-002.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"manager-thread"}
{"type":"turn.completed","usage":{"input_tokens":150,"cached_input_tokens":100,"output_tokens":20}}
EOF
cat > "$project_dir/logs/worker-task-luna-001.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"luna-thread"}
{"type":"turn.completed","usage":{"input_tokens":40,"cached_input_tokens":30,"output_tokens":10}}
EOF
cat > "$project_dir/logs/worker-task-terra-001.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"terra-thread"}
{"type":"turn.completed","usage":{"input_tokens":20,"cached_input_tokens":5,"output_tokens":5}}
EOF
token_output="$("$HARNESS_BIN/harness-agent-token-usage" "$env_file")"
[[ "$(find "$project_dir/control/agent-token-usage-cache" -maxdepth 1 -type f -name '*.usage' | wc -l)" == 4 ]]
[[ "$("$HARNESS_BIN/harness-agent-token-usage" "$env_file")" == "$token_output" ]]
grep -Fqx $'manager_input_tokens\t150' <<< "$token_output"
grep -Fqx $'manager_cached_tokens\t100' <<< "$token_output"
grep -Fqx $'manager_output_tokens\t20' <<< "$token_output"
grep -Fqx $'worker_luna_input_tokens\t40' <<< "$token_output"
grep -Fqx $'worker_terra_input_tokens\t20' <<< "$token_output"
status_output="$("$HARNESS_BIN/harness-status" --full "$env_file")"
grep -Fq 'Specification IR: obligations=2 relations=5 domain-profiles=test-contract' <<< "$status_output"
grep -Fq 'Specification coverage: mapped=2/2 verified=0/2' <<< "$status_output"
grep -Fq 'Manager [gpt-5.6-terra]: input=150 cached=100 output=20 processed=170' <<< "$status_output"
grep -Fq 'Luna worker [gpt-5.6-luna]: input=40 cached=30 output=10 processed=50' <<< "$status_output"
grep -Fq 'Terra worker [gpt-5.6-terra]: input=20 cached=5 output=5 processed=25' <<< "$status_output"
grep -Fq 'Role ratio manager/worker: 2.27:1 (higher: manager)' <<< "$status_output"
grep -Fq 'Model ratio Luna/Terra: 0.26:1 (higher: Terra)' <<< "$status_output"

concise_status="$("$HARNESS_BIN/harness-status" "$env_file")"
grep -Fq 'Project: spec-review-test' <<< "$concise_status"
grep -Fq 'Specification IR: obligations=2 relations=5 domain-profiles=test-contract' <<< "$concise_status"
grep -Fq 'Project progress:' <<< "$concise_status"
grep -Fq 'Project status:' <<< "$concise_status"
if grep -Fq 'Agent token usage' <<< "$concise_status" || grep -Fq 'PLAN ITEM' <<< "$concise_status"; then
	printf 'concise status unexpectedly included detailed reporting tables\n' >&2
	exit 1
fi

info_output="$("$HARNESS_BIN/harness-info" "$env_file")"
grep -Fq 'Obligations / relations: 2 / 5' <<< "$info_output"
grep -Fq 'DAG nodes: 2 (0 complete)' <<< "$info_output"
grep -Fq 'Routes: Luna=2 Terra=0' <<< "$info_output"

statistics_output="$("$HARNESS_BIN/harness-statistics" "$env_file")"
grep -Fq 'Nodes complete: 0/2' <<< "$statistics_output"
grep -Fq 'Manager: 170; workers: 75; Oracle: 0' <<< "$statistics_output"
grep -Fq 'Manager/worker ratio: 2.27:1' <<< "$statistics_output"

implementation_output="$("$HARNESS_BIN/harness-implementation-log" "$env_file")"
grep -Fq 'Specification ACCEPTED; obligations=2, relations=5' <<< "$implementation_output"
grep -Fq 'Decomposition DAG registered; nodes=2' <<< "$implementation_output"

printf 'specification review and token usage tests passed\n'
