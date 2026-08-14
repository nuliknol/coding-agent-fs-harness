#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-specification-review.XXXXXX)"
trap '[[ "${KEEP_TEST_ROOT:-0}" == 1 ]] || rm -rf -- "$TEST_ROOT"' EXIT

repo="$TEST_ROOT/repo"
state="$TEST_ROOT/state"
mkdir -p "$repo/src" "$TEST_ROOT/configs" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'REQ-1: expose target_symbol and preserve zero on invalid input.\n' > "$repo/spec.md"
printf 'int target_symbol(int value) { return value < 0 ? 0 : value; }\n' > "$repo/src/a.c"
git -C "$repo" init -q
git -C "$repo" add spec.md src/a.c
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
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="100"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$env_file"
"$HARNESS_BIN/harness-init" "$env_file" >/dev/null
project_dir="$state/projects/spec-review-test"
spec_sha="$(sha256sum "$repo/spec.md" | awk '{print $1}')"
baseline="$(git -C "$repo" rev-parse HEAD)"

verdict="$TEST_ROOT/verdict.md"
facts="$TEST_ROOT/facts.tsv"
issues="$TEST_ROOT/issues.tsv"
cat > "$verdict" <<EOF
# Specification Review

Project: spec-review-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Decision: SPEC_CLARIFICATION_REQUIRED

## Review summary
REQ-1 does not define whether negative input is rejected or normalized.
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
record_output="$("$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues")"
[[ "$record_output" =~ ^spec-review/specification-review-.*\.md$ ]]
[[ -f "$repo/$record_output" ]]
grep -Fqx 'status=SPEC_CLARIFICATION_REQUIRED' "$project_dir/control/specification-review.env"

set +e
start_output="$("$HARNESS_BIN/harness-start" "$env_file" 2>&1)"
start_status=$?
set -e
(( start_status == 3 ))
grep -Fqx "Specification clarification required: $record_output" <<< "$start_output"
[[ ! -f "$project_dir/control/project-plan.tsv" ]]

status_output="$("$HARNESS_BIN/harness-status" "$env_file")"
grep -Fq "Specification review: SPEC_CLARIFICATION_REQUIRED ($record_output)" <<< "$status_output"
grep -Fq "Project status: SPEC_CLARIFICATION_REQUIRED. Review $record_output before DAG registration." <<< "$status_output"
watch_output="$(HARNESS_WATCH_COLOR=always COLUMNS=120 LINES=30 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/configs")"
grep -Eq $'^\033\[7mspec-review-test +\| *0\| clarify' <<< "$watch_output"
grep -Fq "$record_output" <<< "$watch_output"

plan="$TEST_ROOT/plan.tsv"
cat > "$plan" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
n1	-	-	Add focused target_symbol tests	Negative and nonnegative cases pass	test -f src/a.c	src/a.c	target_symbol	TEST_IMPLEMENTATION	LOW	LUNA
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
Decision: ACCEPT
EOF
printf '%s\n' $'issue_id\tclass\trequirement_ids\tsource_locations\toutcome_a\toutcome_b\tevidence_checked\tmissing_decision\tminimal_question' > "$issues"
if "$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" >/dev/null 2>&1; then
	printf 'unchanged specification was unexpectedly accepted after clarification\n' >&2
	exit 1
fi

printf 'REQ-1: target_symbol must normalize negative input to zero.\n' > "$repo/spec.md"
git -C "$repo" add spec.md
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm clarify-negative-input
spec_sha="$(sha256sum "$repo/spec.md" | awk '{print $1}')"
baseline="$(git -C "$repo" rev-parse HEAD)"
cat > "$verdict" <<EOF
# Specification Review

Project: spec-review-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Decision: ACCEPT

## Review summary
REQ-1 and the existing public behavior consistently require normalization to zero.
EOF
printf '%s\n' $'issue_id\tclass\trequirement_ids\tsource_locations\toutcome_a\toutcome_b\tevidence_checked\tmissing_decision\tminimal_question' > "$issues"
"$HARNESS_BIN/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" >/dev/null
grep -Fqx 'status=ACCEPTED' "$project_dir/control/specification-review.env"

"$HARNESS_BIN/manager-init-project-plan" "$env_file" "$plan" >/dev/null

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
status_output="$("$HARNESS_BIN/harness-status" "$env_file")"
grep -Fq 'Manager [gpt-5.6-terra]: input=150 cached=100 output=20 processed=170' <<< "$status_output"
grep -Fq 'Luna worker [gpt-5.6-luna]: input=40 cached=30 output=10 processed=50' <<< "$status_output"
grep -Fq 'Terra worker [gpt-5.6-terra]: input=20 cached=5 output=5 processed=25' <<< "$status_output"
grep -Fq 'Role ratio manager/worker: 2.27:1 (higher: manager)' <<< "$status_output"
grep -Fq 'Model ratio Luna/Terra: 0.26:1 (higher: Terra)' <<< "$status_output"

printf 'specification review and token usage tests passed\n'
