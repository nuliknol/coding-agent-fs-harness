#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-specification-satisfiability.XXXXXX)"
trap '[[ "${KEEP_TEST_ROOT:-0}" == 1 ]] || rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/configs" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
mock_codex="$TEST_ROOT/mock-specification-reviewer"
cat > "$mock_codex" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
prompt="$(cat)"
value()
{
	local key="$1"
	printf '%s\n' "$prompt" | awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}'
}
last_message=""
next=0
for argument in "$@"; do
	if (( next )); then last_message="$argument"; next=0; continue; fi
	[[ "$argument" != --output-last-message ]] || next=1
done
env_file="$(value ENV_FILE)"
harness_bin="$(value HARNESS_BIN)"
project="$(value PROJECT)"
project_tmp="$(value PROJECT_TMP_DIR)"
spec_sha="$(value SPECIFICATION_SHA256)"
baseline="$(value REPOSITORY_BASELINE)"
domain_sha="$(value DOMAIN_PROFILES_SHA256)"
inventory="$(value REPOSITORY_INVENTORY)"
domain_manifest="$(value DOMAIN_PROFILE_MANIFEST)"
verdict="$project_tmp/verdict.md"
facts="$project_tmp/facts.tsv"
issues="$project_tmp/issues.tsv"
obligations="$project_tmp/obligations.tsv"
relations="$project_tmp/relations.tsv"
cat > "$verdict" <<EOF
# Specification Review

Project: $project
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Domain-Profiles-SHA256: $domain_sha
Decision: SPEC_CLARIFICATION_REQUIRED

## Review summary
The adversarial satisfiability witness failed before decomposition.
EOF
printf '%s\n' \
	$'fact_id\tkind\tsubject\tvalue\tevidence\tauthority\tconfidence' \
	$'FACT-baseline\tBASELINE\trepository\tcurrent committed tree\tgit:HEAD\tOBSERVED\tHIGH' > "$facts"
printf '%s\n' \
	$'issue_id\tclass\trequirement_ids\tsource_locations\toutcome_a\toutcome_b\tevidence_checked\tmissing_decision\tminimal_question' > "$issues"
case "$project" in
	contradictory-output)
		printf '%s\n' $'SPEC-sole-output\tCONTRADICTORY_REQUIREMENTS\tREQ-SUM,REQ-PRODUCT\tspec.md:3,spec.md:4\tThe sole output is the arithmetic sum\tThe same sole output is the arithmetic product\tspec.md:3-5 and repository baseline\tOne authoritative output contract or separate named outputs\tShould the sole output be the sum, the product, or two explicitly named outputs?' >> "$issues"
		;;
	unreachable-acceptance)
		printf '%s\n' $'SPEC-negative-witness\tMISSING_ACCEPTANCE_AUTHORITY\tREQ-NEGATIVE,TEST-POSITIVE-ONLY\tspec.md:3,spec.md:4\tAcceptance proves immediate exit for a negative input\tMandatory acceptance data contain only positive inputs and forbid adding a negative case\tspec.md:3-5 and repository baseline\tA reachable negative-input acceptance witness or removal of the proof obligation\tMay acceptance include a negative input that exercises the required immediate-exit behavior?' >> "$issues"
		;;
	*) exit 91 ;;
esac
printf '%s\n' $'obligation_id\tauthority\tsource_requirement\tsource_location\tobligation_type\tstatement\tobservable_outcome\tacceptance_authority' > "$obligations"
printf '%s\n' $'relation_id\trelation_type\tsubject\tobject\tauthority\tevidence' > "$relations"
"$harness_bin/manager-record-specification-review" "$env_file" "$verdict" "$facts" "$issues" "$obligations" "$relations" "$inventory" "$domain_manifest" >/dev/null
[[ -z "$last_message" ]] || printf 'Specification clarification recorded.\n' > "$last_message"
printf '%s\n' \
	'{"type":"thread.started","thread_id":"satisfiability-review-thread"}' \
	'{"type":"item.completed","item":{"type":"agent_message","text":"clarification recorded"}}' \
	'{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":20}}'
MOCK
chmod 755 "$mock_codex"

run_case()
{
	local project="$1" expected_class="$2" spec_text="$3"
	local repo="$TEST_ROOT/$project-repo" state="$TEST_ROOT/$project-state"
	local env_file="$TEST_ROOT/configs/$project.env" project_dir output status report issues
	mkdir -p "$repo"
	printf '%s\n' "$spec_text" > "$repo/spec.md"
	git -C "$repo" init -q
	git -C "$repo" add spec.md
	git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed
	cat > "$env_file" <<ENV
export PROJECT="$project"
export REPOSITORY="$repo"
export SPECIFICATION="$repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="$mock_codex"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="$mock_codex"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="1"
export HARNESS_ARCHITECTURE_GUARDS="0"
export MAX_ORACLE_RUNS="0"
ENV
	chmod 600 "$env_file"
	"$HARNESS_BIN/harness-init" "$env_file" >/dev/null
	set +e
	output="$("$HARNESS_BIN/harness-start" "$env_file" 2>&1)"
	status=$?
	set -e
	(( status == 3 ))
	grep -Fq 'Specification clarification required: spec-review/specification-review-' <<< "$output"
	project_dir="$state/projects/$project"
	grep -Fqx 'status=SPEC_CLARIFICATION_REQUIRED' "$project_dir/control/specification-review.env"
	report="$(awk -F= '$1 == "report" {sub(/^[^=]*=/, ""); print}' "$project_dir/control/specification-review.env")"
	issues="$(awk -F= '$1 == "issues" {sub(/^[^=]*=/, ""); print}' "$project_dir/control/specification-review.env")"
	[[ -f "$repo/$report" ]]
	[[ -f "$repo/$issues" ]]
	grep -Fq "$expected_class" "$repo/$issues"
	[[ ! -e "$project_dir/control/project-plan.tsv" ]]
	[[ "$(find "$project_dir/tasks" -type f 2>/dev/null | wc -l)" == 0 ]]
	[[ "$(find "$project_dir/logs" -type f -name 'worker-*.jsonl' 2>/dev/null | wc -l)" == 0 ]]
	[[ "$(find "$project_dir/logs" -type f -name 'manager-specification-review-*.jsonl' | wc -l)" == 1 ]]
	"$HARNESS_BIN/harness-status" "$env_file" | grep -Fq 'Project status: SPEC_CLARIFICATION_REQUIRED.'
}

run_case contradictory-output CONTRADICTORY_REQUIREMENTS '# Contradictory output contract

REQ-SUM: For two input numbers, the program MUST emit exactly one value and that value MUST be their arithmetic sum.
REQ-PRODUCT: For the same two inputs and execution, that same sole output MUST be their arithmetic product.
No second output, precedence rule, or mode selector is permitted.'

run_case unreachable-acceptance MISSING_ACCEPTANCE_AUTHORITY '# Unreachable acceptance contract

REQ-NEGATIVE: The program MUST exit immediately whenever either input is negative.
TEST-POSITIVE-ONLY: Acceptance MUST use only the positive pairs (2,3) and (4,5); adding a negative test input is forbidden.
The positive-only acceptance run MUST prove REQ-NEGATIVE.'

printf 'specification satisfiability tests passed\n'
