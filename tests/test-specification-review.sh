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
cat > "$repo/spec.md" <<'EOF'
REQ-1: expose target_symbol and preserve zero on invalid input.

Registry:
```
items:
  - REQ-1
```
EOF
printf 'int target_symbol(int value) { return value < 0 ? 0 : value; }\n' > "$repo/src/a.c"
cat > "$repo/.harness/domain-profiles/test-contract.tsv" <<'EOF'
invariant_id	category	statement	source_authority	validation_hint
stable-negative-contract	CONTRACT	Negative input behavior remains stable	PROJECT_POLICY	Focused negative-input test
EOF
git -C "$repo" init -q
git -C "$repo" add spec.md src/a.c .harness/domain-profiles/test-contract.tsv
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed

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

# A model-generated omission claim cannot override the complete cited fenced
# registry. This reproduces the EOF-slicing bug where the last list item was
# dropped only because an ad-hoc regex required a trailing newline.
false_issues="$TEST_ROOT/false-issues.tsv"
cat > "$false_issues" <<'EOF'
issue_id	class	requirement_ids	source_locations	outcome_a	outcome_b	evidence_checked	missing_decision	minimal_question
SPEC-false-omission	UNDEFINED_COMPLETION_BOUNDARY	REQ-1	spec.md:3	REQ-1 is required	REQ-1 is not required	The fenced registry omits REQ-1.	Whether REQ-1 is omitted	Should REQ-1 be present?
EOF
if "$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$false_issues" "$obligations" "$relations" "$inventory" "$domain_manifest" \
	>"$TEST_ROOT/false-omission.out" 2>"$TEST_ROOT/false-omission.err"; then
	printf 'source-contradicted omission clarification was unexpectedly accepted\n' >&2
	exit 1
fi
grep -Fq 'allegedly omitted REQ-1 is present in the complete fenced registry' \
	"$TEST_ROOT/false-omission.err"

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

# Harness-owned untracked review responses are valid restart input. The same
# path becomes dirty source state if an operator stages it.
[[ -n "$(git -C "$repo" status --short --untracked-files=all -- spec-review)" ]]
git -C "$repo" add -f -- "$record_output"
set +e
staged_review_output="$("$HARNESS_BIN/harness-start" "$env_file" 2>&1)"
staged_review_status=$?
set -e
(( staged_review_status == 1 ))
grep -Eq '^A[[:space:]]+spec-review/' <<< "$staged_review_output"
git -C "$repo" restore --staged -- "$record_output"

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

cat > "$repo/spec.md" <<'EOF'
REQ-1: target_symbol must normalize negative input to zero.

Registry:
```
items:
  - REQ-1
```
EOF
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

second_renormalization_reason="$TEST_ROOT/second-renormalization.md"
cat > "$second_renormalization_reason" <<'EOF'
# Specification Renormalization Request

The unchanged authority allegedly requires another compiler correction.
EOF
if "$HARNESS_BIN/manager-request-specification-renormalization" "$env_file" "$second_renormalization_reason" \
	>"$TEST_ROOT/second-renormalization.out" 2>"$TEST_ROOT/second-renormalization.err"; then
	printf 'repeated specification renormalization unexpectedly bypassed its durable limit\n' >&2
	exit 1
fi
grep -Fq 'specification normalization did not converge' "$TEST_ROOT/second-renormalization.err"
stall_file="$project_dir/control/specification-renormalization-stalled.env"
grep -Fqx 'request_count=2' "$stall_file"
grep -Fqx 'status=ACCEPTED' "$project_dir/control/specification-review.env"
if "$HARNESS_BIN/harness-start" "$env_file" >"$TEST_ROOT/stalled-start.out" 2>"$TEST_ROOT/stalled-start.err"; then
	printf 'harness-start unexpectedly launched agents after durable normalization stall\n' >&2
	exit 1
fi
grep -Fq 'specification normalization is durably stalled for unchanged inputs' "$TEST_ROOT/stalled-start.err"

# The independent decomposition critic must not bypass deterministic source
# validation that protects initial specification review. In particular, the
# final item of a fenced registry remains visible without regex/newline tricks.
false_challenge_report="$TEST_ROOT/false-challenge.md"
false_challenge_issues="$TEST_ROOT/false-challenge-issues.tsv"
cat > "$false_challenge_report" <<'EOF'
# Specification Review Challenge

The accepted review allegedly missed the final registry item.
EOF
cat > "$false_challenge_issues" <<'EOF'
issue_id	class	requirement_ids	source_locations	outcome_a	outcome_b	evidence_checked	missing_decision	minimal_question
SPEC-false-challenge	UNDEFINED_COMPLETION_BOUNDARY	REQ-1	spec.md:3	REQ-1 is required	REQ-1 is not required	The fenced registry omits REQ-1.	Whether REQ-1 is omitted	Should REQ-1 be present?
EOF
if "$HARNESS_BIN/manager-challenge-specification-review" "$env_file" "$false_challenge_report" "$false_challenge_issues" \
	>"$TEST_ROOT/false-challenge.out" 2>"$TEST_ROOT/false-challenge.err"; then
	printf 'source-contradicted decomposition challenge was unexpectedly accepted\n' >&2
	exit 1
fi
grep -Fq 'allegedly omitted REQ-1 is present in the complete fenced registry' \
	"$TEST_ROOT/false-challenge.err"
grep -Fqx 'status=ACCEPTED' "$project_dir/control/specification-review.env"

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

# A normal implementation commit advances HEAD after DAG registration without
# invalidating the accepted review whose baseline remains an ancestor.
printf 'int post_review_commit(void) { return 1; }\n' > "$repo/src/post-review.c"
git -C "$repo" add src/post-review.c
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm post-review-implementation
status_output="$("$HARNESS_BIN/harness-status" --full "$env_file")"
grep -Fq 'Specification review: ACCEPTED (' <<< "$status_output"
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
grep -Fq '  Review: ACCEPTED' <<< "$info_output"
grep -Fq 'Obligations / relations: 2 / 5' <<< "$info_output"
grep -Fq 'DAG nodes: 2 (0 complete)' <<< "$info_output"
grep -Fq 'Routes: Luna=2 Terra=0' <<< "$info_output"

statistics_output="$("$HARNESS_BIN/harness-statistics" "$env_file")"
grep -Fq 'Nodes complete: 0/2' <<< "$statistics_output"
grep -Fq 'Manager: 170; workers: 75; Oracle: 0' <<< "$statistics_output"
grep -Fq 'Manager/worker ratio: 2.27:1' <<< "$statistics_output"

cost_output="$("$HARNESS_BIN/harness-costs" "$env_file")"
grep -Fq 'Harness costs: spec-review-test' <<< "$cost_output"
grep -Eq 'scaffolding[[:space:]]+task-planning[[:space:]]+gpt-5.6-terra[[:space:]]+1[[:space:]]+100[[:space:]]+70[[:space:]]+30[[:space:]]+15[[:space:]]+\$0.0003' <<< "$cost_output"
grep -Eq 'scaffolding[[:space:]]+implementation-review[[:space:]]+gpt-5.6-terra[[:space:]]+1[[:space:]]+50[[:space:]]+30[[:space:]]+20[[:space:]]+5[[:space:]]+\$0.0001' <<< "$cost_output"
grep -Eq 'implementation[[:space:]]+worker-implementation[[:space:]]+gpt-5.6-luna[[:space:]]+1[[:space:]]+40[[:space:]]+30[[:space:]]+10[[:space:]]+10[[:space:]]+\$0.0000' <<< "$cost_output"
grep -Eq 'implementation[[:space:]]+worker-implementation[[:space:]]+gpt-5.6-terra[[:space:]]+1[[:space:]]+20[[:space:]]+5[[:space:]]+15[[:space:]]+5[[:space:]]+\$0.0001' <<< "$cost_output"
grep -Fq 'Scaffolding/implementation cost ratio: 3.41:1' <<< "$cost_output"
grep -Fq 'gpt-5.6-luna' <<< "$cost_output"
grep -Fq 'gpt-5.4-nano' <<< "$cost_output"
grep -Fq 'Cache-write tokens are not exposed' <<< "$cost_output"

cost_tsv="$("$HARNESS_BIN/harness-costs" --tsv "$env_file")"
grep -Fqx $'scope\tphase\trole\tmodel\tinvocations\tinput_tokens\tcached_input_tokens\tuncached_input_tokens\toutput_tokens\testimated_cost_usd\tpricing_status' <<< "$cost_tsv"
grep -Fqx $'scaffolding\ttask-planning\tmanager\tgpt-5.6-terra\t1\t100\t70\t30\t15\t0.00025400\tpriced' <<< "$cost_tsv"
grep -Fqx $'scaffolding\timplementation-review\tmanager\tgpt-5.6-terra\t1\t50\t30\t20\t5\t0.00010600\tpriced' <<< "$cost_tsv"

implementation_output="$("$HARNESS_BIN/harness-implementation-log" "$env_file")"
grep -Fq 'Specification ACCEPTED; obligations=2, relations=5' <<< "$implementation_output"
grep -Fq 'Decomposition DAG registered; nodes=2' <<< "$implementation_output"

# A post-turn token guard must roll back a candidate specification state even
# when the agent wrote it immediately before returning usage.
rollback_repo="$TEST_ROOT/rollback-repo"
rollback_state="$TEST_ROOT/rollback-state"
mkdir -p "$rollback_repo" "$TEST_ROOT/rollback-home"
printf 'REQ-R: deterministic rollback contract.\n' > "$rollback_repo/spec.md"
git -C "$rollback_repo" init -q
git -C "$rollback_repo" add spec.md
git -C "$rollback_repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed
rollback_env="$TEST_ROOT/configs/rollback.env"
rollback_mock="$TEST_ROOT/rollback-codex"
cat > "$rollback_env" <<ENV
export PROJECT="rollback-review"
export REPOSITORY="$rollback_repo"
export SPECIFICATION="$rollback_repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$rollback_state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/rollback-home"
export MANAGER_CODEX_BIN="$rollback_mock"
export WORKER_CODEX_HOME="$TEST_ROOT/rollback-home"
export WORKER_CODEX_BIN="/bin/false"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION="1000"
export HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION="100"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$rollback_env"
"$HARNESS_BIN/harness-init" "$rollback_env" >/dev/null
rollback_project="$rollback_state/projects/rollback-review"
rollback_spec_sha="$(sha256sum "$rollback_repo/spec.md" | awk '{print $1}')"
rollback_baseline="$(git -C "$rollback_repo" rev-parse HEAD)"
rollback_domain_sha="$(bash -c 'source "$1"; load_harness_env "$2"; domain_profiles_sha256' _ "$HARNESS_HOME/lib/harness-common.sh" "$rollback_env")"
cat > "$rollback_mock" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
last=""
next=0
for argument in "\$@"; do
	if (( next )); then last="\$argument"; next=0; continue; fi
	[[ "\$argument" != --output-last-message ]] || next=1
done
cat > "$rollback_project/control/specification-review.env" <<STATE
status=ACCEPTED
specification_sha256=$rollback_spec_sha
repository_baseline=$rollback_baseline
domain_profiles_sha256=$rollback_domain_sha
report=spec-review/untrusted.md
STATE
printf 'candidate\n' > "\$last"
printf '%s\n' '{"type":"thread.started","thread_id":"rollback-thread"}' '{"type":"turn.completed","usage":{"input_tokens":90,"cached_input_tokens":0,"output_tokens":20}}'
EOF
chmod +x "$rollback_mock"
if "$HARNESS_BIN/manager-review-specification" "$rollback_env" \
	>"$TEST_ROOT/rollback-review.out" 2>"$TEST_ROOT/rollback-review.err"; then
	printf 'resource-exceeded specification review unexpectedly succeeded\n' >&2
	exit 1
fi
test ! -f "$rollback_project/control/specification-review.env"
grep -Fq 'SPECIFICATION_REVIEW_CANDIDATE_ROLLED_BACK status=75 classification=agent_token_budget_exceeded' \
	"$rollback_project/logs/events.log"

# A source-declared cycle must become a deterministic clarification before any
# manager model is invoked. The provisional clarification IR may be empty.
cycle_repo="$TEST_ROOT/cycle-repo"
cycle_state="$TEST_ROOT/cycle-state"
mkdir -p "$cycle_repo" "$TEST_ROOT/cycle-manager-home" "$TEST_ROOT/cycle-worker-home"
cat > "$cycle_repo/spec.md" <<'EOF'
# Cyclic specification

### REQ-A — First requirement

| Field | Value |
|---|---|
| Requirement ID | REQ-A |
| Dependencies | REQ-B |

### REQ-B — Second requirement

| Field | Value |
|---|---|
| Requirement ID | REQ-B |
| Dependencies | REQ-A |
EOF
git -C "$cycle_repo" init -q
git -C "$cycle_repo" add spec.md
git -C "$cycle_repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed
cycle_env="$TEST_ROOT/configs/spec-cycle.env"
cat > "$cycle_env" <<ENV
export PROJECT="spec-cycle-test"
export REPOSITORY="$cycle_repo"
export SPECIFICATION="$cycle_repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$cycle_state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/cycle-manager-home"
export MANAGER_CODEX_BIN="/bin/false"
export WORKER_CODEX_HOME="$TEST_ROOT/cycle-worker-home"
export WORKER_CODEX_BIN="/bin/false"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="1"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_ARCHITECTURE_GUARDS="0"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$cycle_env"
"$HARNESS_BIN/harness-init" "$cycle_env" >/dev/null
set +e
cycle_start_output="$("$HARNESS_BIN/harness-start" "$cycle_env" 2>&1)"
cycle_start_status=$?
set -e
(( cycle_start_status == 3 ))
grep -Fq 'Specification clarification required: spec-review/specification-review-' <<< "$cycle_start_output"
cycle_project_dir="$cycle_state/projects/spec-cycle-test"
grep -Fqx 'status=SPEC_CLARIFICATION_REQUIRED' "$cycle_project_dir/control/specification-review.env"
grep -Fqx 'obligation_count=0' "$cycle_project_dir/control/specification-review.env"
grep -Fqx 'relation_count=0' "$cycle_project_dir/control/specification-review.env"
[[ "$(find "$cycle_project_dir/logs" -maxdepth 1 -type f -name 'manager-specification-review-*' | wc -l)" == 0 ]]
cycle_request="$("$HARNESS_BIN/harness-show-clarification-request" "$cycle_env")"
grep -Fq '### SPEC-DEPENDENCY-CYCLE — CONTRADICTORY_REQUIREMENTS' <<< "$cycle_request"
grep -Fq 'Which dependency direction is authoritative' <<< "$cycle_request"

printf 'specification review and token usage tests passed\n'
