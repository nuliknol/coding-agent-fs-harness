#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
CONTAINMENT_ENV_FILE=""
cleanup_test()
{
	if [[ -n "$CONTAINMENT_ENV_FILE" && -f "$CONTAINMENT_ENV_FILE" ]]; then
		"$ROOT/bin/harness-stop" "$CONTAINMENT_ENV_FILE" \
			>/dev/null 2>&1 || true
	fi
	rm -rf "$TEST_DIR"
}
trap cleanup_test EXIT

repo="$TEST_DIR/repository"
state_root="$TEST_DIR/state"
fake_state="$TEST_DIR/fake-state"
mkdir -p "$repo" "$fake_state" "$TEST_DIR/codex-home"

git -C "$repo" init -q
git -C "$repo" config user.name 'Harness Test'
git -C "$repo" config user.email 'harness-test@example.invalid'
printf 'historical baseline\n' > "$repo/historical.txt"
git -C "$repo" add historical.txt
git -C "$repo" commit -q -m 'historical specification inspection baseline'
historical_commit="$(git -C "$repo" rev-parse HEAD)"
printf 'pre-existing integrated work\n' > "$repo/pre-existing.txt"
git -C "$repo" add pre-existing.txt
git -C "$repo" commit -q -m 'integrated work present at harness launch'
launch_commit="$(git -C "$repo" rev-parse HEAD)"

{
	printf '# Feature\n\n'
	printf 'Create feature.txt containing exactly `complete`.\n\n'
	printf 'Repository baseline inspected: `%s`.\n' "$historical_commit"
} > "$TEST_DIR/specification.md"

cat > "$TEST_DIR/development-policy.txt" <<'EOF'
Development mode: prototype / feature-first.
Implement the requested feature with the smallest reasonable code change.
Use one happy-path smoke test. Do not build production infrastructure.
EOF

cat > "$TEST_DIR/fake-codex" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >> "$FAKE_CODEX_STATE/codex-argv.log"
output=""
model=""
resume_thread=""
while (( $# > 0 )); do
	case "$1" in
		--output-last-message)
			output="$2"
			shift 2
			;;
		--model)
			model="$2"
			shift 2
			;;
		--sandbox|--cd|--add-dir|-c|--config)
			shift 2
			;;
		resume)
			resume_thread="$2"
			shift 2
			;;
		-)
			shift
			break
			;;
		*)
			shift
			;;
	esac
done
prompt="$(cat)"
counter_file="$FAKE_CODEX_STATE/manager-counter"
touch "$FAKE_CODEX_STATE/invocations.log"

if [[ "$model" == gpt-5.6-terra ]]; then
	counter=0
	[[ ! -f "$counter_file" ]] || counter="$(cat "$counter_file")"
	counter=$((counter + 1))
	printf '%s\n' "$counter" > "$counter_file"
	thread="manager-$counter"
	if [[ "$prompt" == *"# Reviewer protocol repair"* ]]; then
		touch "$FAKE_CODEX_STATE/protocol-repair-ran"
		if [[ "$prompt" == *'Role: `manager_convergence`'* ]]; then
			touch "$FAKE_CODEX_STATE/actionable-audit-ran"
			message=$'DECISION: ACTIONABLE\n\nADD-001\nFinding-Key: convergence-first-gap\nSpecification: first convergence requirement.\nEvidence: first convergence evidence.\nRequired correction: first convergence correction.\nVerification: first convergence verification.\n\nADD-002\nFinding-Key: convergence-second-gap\nSpecification: second convergence requirement.\nEvidence: second convergence evidence.\nRequired correction: second convergence correction.\nVerification: second convergence verification.'
		elif [[ "${FAKE_PROTOCOL_REPAIR_STAYS_INVALID:-0}" == 1 ]]; then
			message=$'DECISION: ACCEPT\nThe formatting repair improperly changed the substantive decision.'
		else
			message=$'DECISION: REVISE\n\nADD-001\nFinding-Key: first-distinct-gap\nSpecification: first requirement.\nEvidence: first evidence.\nRequired correction: first correction.\nVerification: first verification.\n\nADD-002\nFinding-Key: second-distinct-gap\nSpecification: second requirement.\nEvidence: second evidence.\nRequired correction: second correction.\nVerification: second verification.'
		fi
	elif [[ "$prompt" == *"fresh Terra convergence auditor"* ]]; then
		if [[ "${FAKE_INVALID_CONVERGENCE:-0}" == 1 &&
			! -f "$FAKE_CODEX_STATE/invalid-convergence-emitted" ]]; then
			touch "$FAKE_CODEX_STATE/invalid-convergence-emitted"
			touch "$FAKE_CODEX_STATE/actionable-audit-ran"
			message=$'DECISION: ACTIONABLE\n\nADD-001\nFinding-Key: duplicate-convergence-key\nSpecification: first convergence requirement.\nEvidence: first convergence evidence.\nRequired correction: first convergence correction.\nVerification: first convergence verification.\n\nADD-002\nFinding-Key: duplicate-convergence-key\nSpecification: second convergence requirement.\nEvidence: second convergence evidence.\nRequired correction: second convergence correction.\nVerification: second convergence verification.'
		elif [[ "${FAKE_CONVERGENCE_ACTIONABLE:-0}" == 1 ]]; then
			touch "$FAKE_CODEX_STATE/actionable-audit-ran"
			message=$'DECISION: ACTIONABLE\n\n1. **ADD-001**\n- **Finding-Key:** **direct-repository-correction**\nSpecification: feature.txt must contain exactly complete.\nEvidence: repository-local work can satisfy the requirement.\nRequired correction: write the required complete value directly.\nVerification: test the resulting feature content.'
		else
			message=$'DECISION: NEEDS_OPERATOR\n\nThe repeated requirement depends on an unavailable external operator decision.\nSpecification: the configured external decision is mandatory.\nEvidence: no repository-local change can supply it.\nOperator input: choose the external value.'
		fi
	elif [[ "$prompt" == *"Terra goal author"* ]]; then
		message=$'# Persistent Worker Goal\nImplement the complete immutable specification, verify it, and continue until it works.\nGOAL_READY'
	elif [[ "${FAKE_INVALID_MANAGER_REVIEW:-0}" == 1 &&
		! -f "$FAKE_CODEX_STATE/invalid-manager-review-emitted" ]]; then
		touch "$FAKE_CODEX_STATE/invalid-manager-review-emitted"
		message=$'DECISION: REVISE\n\nADD-001\nFinding-Key: duplicate-key\nSpecification: first requirement.\nEvidence: first evidence.\nRequired correction: first correction.\nVerification: first verification.\n\nADD-002\nFinding-Key: duplicate-key\nSpecification: second requirement.\nEvidence: second evidence.\nRequired correction: second correction.\nVerification: second verification.'
	elif [[ -f "$FAKE_CODEX_STATE/actionable-audit-ran" &&
		"${FAKE_CONVERGENCE_STAYS_ACTIONABLE:-0}" != 1 ]]; then
		message=$'DECISION: ACCEPT\nThe actionable convergence correction is complete.'
	elif [[ "${FAKE_REPEAT_FINDINGS:-0}" == 1 ]]; then
		message=$'DECISION: REVISE\n\n`ADD-001` — external decision remains unavailable.\n- `Finding-Key:` `external-decision-unavailable`\n- `Specification:` feature.txt must contain exactly complete.\n- `Evidence:` the configured external decision is still unavailable.\n- `Required correction:` use the external decision to complete the feature.\n- `Verification:` verify the configured external decision.'
	elif [[ -f "$FAKE_REPOSITORY/feature.txt" ]] &&
		[[ "$(cat "$FAKE_REPOSITORY/feature.txt")" == complete ]]; then
		message=$'DECISION: ACCEPT\nAll specified behavior is implemented.'
	else
		message=$'DECISION: REVISE\n\nADD-001\nFinding-Key: `feature-content-incomplete`\nSpecification: feature.txt must contain exactly complete.\nEvidence: the repository contains only a partial value.\nRequired correction: replace it with the complete value.\nVerification: test \"$(cat feature.txt)\" = complete.'
	fi
	input=100
	cached=80
	output_tokens=20
elif [[ "$model" == gpt-5.6-sol ]]; then
	oracle_counter_file="$FAKE_CODEX_STATE/oracle-counter"
	oracle_counter=0
	[[ ! -f "$oracle_counter_file" ]] ||
		oracle_counter="$(cat "$oracle_counter_file")"
	oracle_counter=$((oracle_counter + 1))
	printf '%s\n' "$oracle_counter" > "$oracle_counter_file"
	thread="oracle-$oracle_counter"
	oracle_run="$(sed -n 's/^Oracle run: `\([0-9][0-9]*\)`.*/\1/p' <<< "$prompt" | tail -n 1)"
	manager_cycle="$(sed -n 's/^Manager cycle: `\([0-9][0-9]*\)`.*/\1/p' <<< "$prompt" | tail -n 1)"
	if [[ "$prompt" == *"# Reviewer protocol repair"* ]]; then
		touch "$FAKE_CODEX_STATE/oracle-protocol-repair-ran"
		printf -v message 'DECISION: PASS\nOracle-Run: %s\nManager-Cycle: %s\n\nREQUIREMENT: SPECIFICATION-WHOLE\nEvidence: feature.txt contains exactly complete and the repository matches the immutable specification.\nVerification: test "$(cat feature.txt)" = complete passed.\nORACLE_AUDIT_COMPLETE' "$oracle_run" "$manager_cycle"
	elif [[ "${FAKE_INVALID_ORACLE_PASS:-0}" == 1 &&
		! -f "$FAKE_CODEX_STATE/invalid-oracle-pass-emitted" ]]; then
		touch "$FAKE_CODEX_STATE/invalid-oracle-pass-emitted"
		printf -v message 'DECISION: PASS\nOracle-Run: %s\nManager-Cycle: %s\n\nREQUIREMENT: SPECIFICATION-WHOLE\nEvidence: feature.txt appears complete.\nORACLE_AUDIT_COMPLETE' "$oracle_run" "$manager_cycle"
	elif (( oracle_counter <= ${FAKE_ORACLE_REVISIONS:-0} )); then
		printf -v message 'DECISION: REVISE\nAddendum-Source: ORACLE\nOracle-Run: %s\nManager-Cycle: %s\n\nADD-001: independent final gap\nFinding-Key: oracle-independent-gap\nSpecification: feature.txt must satisfy the complete immutable specification.\nEvidence: the independent audit found a repository-local completion gap.\nRequired correction: close the complete gap and rerun verification.\nVerification: run the focused feature smoke test.\nORACLE_AUDIT_COMPLETE' "$oracle_run" "$manager_cycle"
	else
		printf -v message 'DECISION: PASS\nOracle-Run: %s\nManager-Cycle: %s\n\nREQUIREMENT: SPECIFICATION-WHOLE\nEvidence: feature.txt contains exactly complete and the repository matches the immutable specification.\nVerification: test "$(cat feature.txt)" = complete passed.\nORACLE_AUDIT_COMPLETE' "$oracle_run" "$manager_cycle"
	fi
	input=500
	cached=300
	output_tokens=50
else
	thread="${resume_thread:-worker-thread}"
	if [[ "${FAKE_WORKER_NO_CHANGES:-0}" == 1 ]]; then
		printf 'worker unchanged %s\n' "${resume_thread:-fresh}" >> \
			"$FAKE_CODEX_STATE/invocations.log"
		message='No repository change was made in this worker turn.'
		input=500
		cached=400
		output_tokens=50
	elif [[ -n "$resume_thread" ]]; then
		printf 'complete\n' > "$FAKE_REPOSITORY/feature.txt"
		printf 'worker resume %s\n' "$resume_thread" >> "$FAKE_CODEX_STATE/invocations.log"
		message='Resolved the complete addendum and verified the specification.'
		input=2500
		cached=2000
		output_tokens=250
	else
		printf 'partial\n' > "$FAKE_REPOSITORY/feature.txt"
		printf 'worker fresh\n' >> "$FAKE_CODEX_STATE/invocations.log"
		if [[ -n "${FAKE_RELOAD_ENV_FILE:-}" &&
			! -f "$FAKE_CODEX_STATE/environment-reload-applied" ]]; then
			if [[ -n "${FAKE_RELOAD_HARD_PROJECT:-}" ]]; then
				printf 'export PROJECT="%s"\n' \
					"$FAKE_RELOAD_HARD_PROJECT" >> "$FAKE_RELOAD_ENV_FILE"
			else
				printf 'export MANAGER_REASONING_EFFORT="xhigh"\n' >> \
					"$FAKE_RELOAD_ENV_FILE"
			fi
			touch "$FAKE_CODEX_STATE/environment-reload-applied"
		fi
		message='Implemented the first complete pass and reached review readiness.'
		input=1000
		cached=800
		output_tokens=100
	fi
fi

printf '%s\n' "$message" > "$output"
jq -cn --arg thread "$thread" '{type:"thread.started",thread_id:$thread}'
jq -cn --arg text "$message" \
	'{type:"item.completed",item:{type:"agent_message",text:$text}}'
jq -cn --argjson input "$input" --argjson cached "$cached" \
	--argjson output "$output_tokens" \
	'{type:"turn.completed",usage:{input_tokens:$input,cached_input_tokens:$cached,cache_write_input_tokens:0,output_tokens:$output}}'
EOF
chmod +x "$TEST_DIR/fake-codex"

mkdir -p "$TEST_DIR/fake-bin"
cat > "$TEST_DIR/fake-bin/strace" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

output=""
while (( $# > 0 )); do
	case "$1" in
		-ff|-ttt|-T|-yy)
			shift
			;;
		-s|-e|-o)
			[[ "$1" != -o ]] || output="$2"
			shift 2
			;;
		*)
			break
			;;
	esac
done
printf '%s\n' "$*" >> "$FAKE_CODEX_STATE/strace-invocations.log"
[[ -z "$output" ]] || printf 'fake trace\n' > "$output.fake"
exec "$@"
EOF
chmod +x "$TEST_DIR/fake-bin/strace"

cat > "$TEST_DIR/slow-codex" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

output=""
while (( $# > 0 )); do
	case "$1" in
		--output-last-message)
			output="$2"
			shift 2
			;;
		--model|--sandbox|--cd|--add-dir|-c|--config)
			shift 2
			;;
		resume)
			shift 2
			;;
		-)
			shift
			break
			;;
		*)
			shift
			;;
	esac
done
cat >/dev/null
jq -cn '{type:"thread.started",thread_id:"slow-thread"}'
sleep 4
printf 'slow turn completed\n' > "$output"
jq -cn '{type:"turn.completed",usage:{input_tokens:1,cached_input_tokens:0,cache_write_input_tokens:0,output_tokens:1}}'
EOF
chmod +x "$TEST_DIR/slow-codex"

cat > "$TEST_DIR/detached-codex" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

while (( $# > 0 )); do
	case "$1" in
		--output-last-message|--model|--sandbox|--cd|--add-dir|-c|--config)
			shift 2
			;;
		resume)
			shift 2
			;;
		-)
			shift
			break
			;;
		*)
			shift
			;;
	esac
done
cat >/dev/null
setsid sleep 300 >/dev/null 2>&1 &
printf '%s\n' "$!" > "$DETACHED_PID_FILE"
jq -cn '{type:"thread.started",thread_id:"detached-thread"}'
sleep 300
EOF
chmod +x "$TEST_DIR/detached-codex"

cat > "$TEST_DIR/protected-state-codex" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
output=""
while (( $# > 0 )); do
	case "$1" in
		--output-last-message) output="$2"; shift 2 ;;
		--model|--sandbox|--cd|--add-dir|-c|--config) shift 2 ;;
		resume) shift 2 ;;
		-) shift; break ;;
		*) shift ;;
	esac
done
cat >/dev/null
rm -f -- "$PROTECTED_TEST_SOURCE"
printf 'corrupted immutable input\n' > \
	"$PROTECTED_TEST_STATE/inputs/specification.txt"
printf 'corrupted worker goal\n' > \
	"$PROTECTED_TEST_STATE/control/worker-goal.md"
printf 'staged worker edit\n' > "$FAKE_REPOSITORY/pre-existing.txt"
git -C "$FAKE_REPOSITORY" add pre-existing.txt
printf 'attempted protected mutation\n' > "$output"
jq -cn '{type:"thread.started",thread_id:"protected-state-thread"}'
jq -cn '{type:"turn.completed",usage:{input_tokens:1,cached_input_tokens:0,cache_write_input_tokens:0,output_tokens:1}}'
EOF
chmod +x "$TEST_DIR/protected-state-codex"

cat > "$TEST_DIR/head-moving-codex" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
output=""
while (( $# > 0 )); do
	case "$1" in
		--output-last-message) output="$2"; shift 2 ;;
		--model|--sandbox|--cd|--add-dir|-c|--config) shift 2 ;;
		resume) shift 2 ;;
		-) shift; break ;;
		*) shift ;;
	esac
done
cat >/dev/null
printf 'unauthorized commit\n' > "$FAKE_REPOSITORY/committed-by-agent.txt"
git -C "$FAKE_REPOSITORY" add committed-by-agent.txt
git -C "$FAKE_REPOSITORY" commit -q -m 'unauthorized worker commit'
printf 'attempted HEAD movement\n' > "$output"
jq -cn '{type:"thread.started",thread_id:"head-moving-thread"}'
jq -cn '{type:"turn.completed",usage:{input_tokens:1,cached_input_tokens:0,cache_write_input_tokens:0,output_tokens:1}}'
EOF
chmod +x "$TEST_DIR/head-moving-codex"

cat > "$TEST_DIR/project.env" <<EOF
export PROJECT="light-smoke"
export REPOSITORY="$repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$state_root"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MANAGER_MODEL="gpt-5.6-terra"
export MANAGER_REASONING_EFFORT="high"
export WORKER_MODEL="gpt-5.6-luna"
export WORKER_REASONING_EFFORT="high"
export MAX_ORACLE_RUNS="0"
export HARNESS_MANAGER_REVIEW_CHECKLIST="c-strict"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export FAKE_CODEX_STATE="$fake_state"
export FAKE_REPOSITORY="$repo"
export FAKE_RELOAD_ENV_FILE="$TEST_DIR/project.env"
EOF
chmod 600 "$TEST_DIR/project.env"

grep -v -e '^export HARNESS_MANAGER_REVIEW_CHECKLIST=' \
	-e '^export MAX_ORACLE_RUNS=' \
	"$TEST_DIR/project.env" > "$TEST_DIR/default-project.env"
chmod 600 "$TEST_DIR/default-project.env"
default_check="$("$ROOT/bin/harness-check-env" "$TEST_DIR/default-project.env")"
grep -q 'Manager first-review checklist: none' <<< "$default_check"
grep -q 'Manager review limit: 50' <<< "$default_check"
grep -q 'Protocol repair attempts: 2' <<< "$default_check"
grep -q 'Repeated-finding convergence audit: after 3 consecutive reviews' \
	<<< "$default_check"
grep -q 'No-source-progress pause: after 5 unchanged worker deliveries' \
	<<< "$default_check"
grep -q 'Repeated-convergence pause: after 3 audits retain a finding' \
	<<< "$default_check"
grep -q 'Oracle: gpt-5.6-sol (high), sandbox=workspace-write, maximum runs=3' \
	<<< "$default_check"
grep -q 'Codex diagnostic profile: disabled' <<< "$default_check"
grep -q 'Codex goal tools: disabled by harness' <<< "$default_check"

cp "$TEST_DIR/project.env" "$TEST_DIR/diagnostic-profile.env"
printf 'export HARNESS_CODEX_DIAGNOSTIC_PROFILE="1"\n' >> \
	"$TEST_DIR/diagnostic-profile.env"
chmod 600 "$TEST_DIR/diagnostic-profile.env"
diagnostic_check="$("$ROOT/bin/harness-check-env" \
	"$TEST_DIR/diagnostic-profile.env")"
grep -q 'Codex diagnostic profile: enabled' <<< "$diagnostic_check"
grep -q 'Codex Rust diagnostics: codex_core=debug' <<< "$diagnostic_check"
grep -q 'Codex strace: disabled' <<< "$diagnostic_check"
grep -q 'Codex stall snapshots: after 1800 seconds without output, repeated every 900 seconds' \
	<<< "$diagnostic_check"

sed 's/HARNESS_MANAGER_REVIEW_CHECKLIST="c-strict"/HARNESS_MANAGER_REVIEW_CHECKLIST="unsupported"/' \
	"$TEST_DIR/project.env" > "$TEST_DIR/invalid-project.env"
chmod 600 "$TEST_DIR/invalid-project.env"
if "$ROOT/bin/harness-check-env" "$TEST_DIR/invalid-project.env" \
	>"$TEST_DIR/invalid-check.out" 2>"$TEST_DIR/invalid-check.err"; then
	printf 'unsupported manager review checklist was accepted\n' >&2
	exit 1
fi
grep -q 'invalid HARNESS_MANAGER_REVIEW_CHECKLIST: unsupported' \
	"$TEST_DIR/invalid-check.err"

cp "$TEST_DIR/project.env" "$TEST_DIR/invalid-diagnostics.env"
printf 'export HARNESS_CODEX_STRACE="2"\n' >> "$TEST_DIR/invalid-diagnostics.env"
chmod 600 "$TEST_DIR/invalid-diagnostics.env"
if "$ROOT/bin/harness-check-env" "$TEST_DIR/invalid-diagnostics.env" \
	>"$TEST_DIR/invalid-diagnostics.out" 2>"$TEST_DIR/invalid-diagnostics.err"; then
	printf 'invalid Codex strace setting was accepted\n' >&2
	exit 1
fi
grep -q 'HARNESS_CODEX_STRACE must be 0 or 1' \
	"$TEST_DIR/invalid-diagnostics.err"

cat > "$TEST_DIR/oracle-pass-specification.md" <<'EOF'
# Structured Oracle PASS fixture

- Requirement ID: `REQ-ONE`
- Requirement ID: `REQ-TWO`
EOF
cat > "$TEST_DIR/oracle-pass-valid.md" <<'EOF'
DECISION: PASS
Oracle-Run: 1
Manager-Cycle: 2

REQUIREMENT: REQ-ONE
Evidence: src/one.c implements the first requirement.
Verification: the focused first-requirement check passed.

REQUIREMENT: REQ-TWO
Evidence: src/two.c implements the second requirement.
Verification: the focused second-requirement check passed.
ORACLE_AUDIT_COMPLETE
EOF
bash -c 'source "$1"; validate_oracle_pass "$2" "$3"' _ \
	"$ROOT/lib/harness-common.sh" \
	"$TEST_DIR/oracle-pass-specification.md" \
	"$TEST_DIR/oracle-pass-valid.md"

sed '/^Verification: the focused second-requirement check passed\.$/d' \
	"$TEST_DIR/oracle-pass-valid.md" > \
	"$TEST_DIR/oracle-pass-missing-verification.md"
if bash -c 'source "$1"; validate_oracle_pass "$2" "$3"' _ \
	"$ROOT/lib/harness-common.sh" \
	"$TEST_DIR/oracle-pass-specification.md" \
	"$TEST_DIR/oracle-pass-missing-verification.md" \
	>"$TEST_DIR/oracle-pass-invalid.out" \
	2>"$TEST_DIR/oracle-pass-invalid.err"; then
	printf 'Oracle PASS without per-requirement verification was accepted\n' >&2
	exit 1
fi
grep -q 'REQ-TWO has empty Verification' \
	"$TEST_DIR/oracle-pass-invalid.err"

sed '/^REQUIREMENT: REQ-TWO$/,/^Verification: the focused second-requirement check passed\.$/d' \
	"$TEST_DIR/oracle-pass-valid.md" > \
	"$TEST_DIR/oracle-pass-missing-requirement.md"
if bash -c 'source "$1"; validate_oracle_pass "$2" "$3"' _ \
	"$ROOT/lib/harness-common.sh" \
	"$TEST_DIR/oracle-pass-specification.md" \
	"$TEST_DIR/oracle-pass-missing-requirement.md" \
	>"$TEST_DIR/oracle-pass-invalid.out" \
	2>"$TEST_DIR/oracle-pass-invalid.err"; then
	printf 'Oracle PASS with missing requirement coverage was accepted\n' >&2
	exit 1
fi
grep -q 'missing requirement evidence for REQ-TWO' \
	"$TEST_DIR/oracle-pass-invalid.err"

sed 's/PROJECT="light-smoke"/PROJECT="dirty-init"/' \
	"$TEST_DIR/project.env" > "$TEST_DIR/dirty-project.env"
chmod 600 "$TEST_DIR/dirty-project.env"
printf 'operator-owned untracked file\n' > "$repo/untracked-at-init.txt"
if "$ROOT/bin/harness-init" "$TEST_DIR/dirty-project.env" \
	>"$TEST_DIR/dirty-init.out" 2>"$TEST_DIR/dirty-init.err"; then
	printf 'dirty repository was initialized without --force\n' >&2
	exit 1
fi
grep -q 'repository has uncommitted or untracked files' \
	"$TEST_DIR/dirty-init.err"
"$ROOT/bin/harness-init" --force "$TEST_DIR/dirty-project.env" >/dev/null
grep -qx "repository_launch_commit=$launch_commit" \
	"$state_root/projects/dirty-init/project.conf"
rm -f "$repo/untracked-at-init.txt"

"$ROOT/bin/harness-check-env" "$TEST_DIR/project.env" >/dev/null
"$ROOT/bin/harness-init" "$TEST_DIR/project.env" >/dev/null
grep -qx "repository_launch_commit=$launch_commit" \
	"$state_root/projects/light-smoke/project.conf"
"$ROOT/bin/harness-start" "$TEST_DIR/project.env" >/dev/null

project="$state_root/projects/light-smoke"
for _ in {1..30}; do
	[[ -f "$project/control/state.env" ]] &&
		grep -qx 'status=COMPLETE' "$project/control/state.env" &&
		break
	sleep 1
done
for _ in 1 2 3 4 5; do
	[[ ! -f "$project/control/supervisor.pid" ]] && break
	sleep 1
done
grep -qx 'status=COMPLETE' "$project/control/state.env"
test ! -f "$project/control/supervisor.pid"
grep -qx 'phase=ACCEPTED' "$project/control/state.env"
grep -qx 'cycle=2' "$project/control/state.env"
grep -qx 'worker-thread' "$project/control/worker.thread"
grep -qx 'complete' "$repo/feature.txt"
test -f "$project/addenda/addendum-001.md"
test -f "$project/reviews/review-001.md"
test -f "$project/reviews/review-002.md"
test -f "$project/control/final-acceptance.md"
grep -q '^DECISION: REVISE$' "$project/addenda/addendum-001.md"
grep -q '^Finding-Key: `feature-content-incomplete`$' \
	"$project/addenda/addendum-001.md"
grep -q '^DECISION: ACCEPT$' "$project/control/final-acceptance.md"
grep -q '^worker fresh$' "$fake_state/invocations.log"
grep -q '^worker resume worker-thread$' "$fake_state/invocations.log"
grep -Fq -- '--disable goals' "$fake_state/codex-argv.log"
grep -q '^manager_review_checklist=c-strict$' "$project/project.conf"
grep -q '^max_no_source_progress_reviews=5$' "$project/project.conf"
grep -q '^max_repeated_convergence_audits=3$' "$project/project.conf"
grep -q '^# Operator-selected first-review checklist$' \
	"$project/prompts/manager-review-001.md"
grep -q '^## Strict C verification profile$' \
	"$project/prompts/manager-review-001.md"
if grep -q '^## Strict C verification profile$' \
	"$project/prompts/manager-review-002.md"; then
	printf 'strict C checklist repeated after the first review\n' >&2
	exit 1
fi
grep -q 'MANAGER_REVIEW_CHECKLIST_ATTACHED cycle=1 profile=c-strict' \
	"$project/logs/events.log"
for prompt in "$project/prompts/manager-goal.md" \
	"$project/prompts/worker-001.md" \
	"$project/prompts/manager-review-001.md" \
	"$project/prompts/worker-002.md"; do
	grep -Fq "Canonical repository baseline for this turn: \`$launch_commit\`" \
		"$prompt"
	grep -Fq 'Commit hashes mentioned inside the specification are historical inspection provenance' \
		"$prompt"
done
grep -q '^# Complete immutable specification$' \
	"$project/prompts/worker-001.md"
grep -Fq 'Create feature.txt containing exactly `complete`.' \
	"$project/prompts/worker-001.md"
grep -Fq 'repository owner grants the worker full authority' \
	"$project/prompts/worker-001.md"
for prompt in "$project/prompts/worker-001.md" \
	"$project/prompts/worker-002.md"; do
	grep -Fq '`create_goal`, `get_goal`, `update_goal`' \
		"$prompt"
	grep -Fq 'Terra can judge it.' "$prompt"
	grep -Fq 'fresh unique temporary' "$prompt"
	grep -Fq 'exceptions apply' "$prompt"
done
grep -Fq 'never create a finding whose only' \
	"$project/prompts/manager-review-001.md"
grep -Fq 'never parking an internal goal as blocked' \
	"$project/prompts/manager-goal.md"
test -f "$repo/pre-existing.txt"

status_output="$("$ROOT/bin/harness-status" "$TEST_DIR/project.env")"
grep -q 'Manager first-review checklist: c-strict' <<< "$status_output"
grep -q 'Codex goal tools: disabled by harness' <<< "$status_output"
grep -q 'Environment reload: before every manager review and Oracle audit (soft parameters only)' \
	<<< "$status_output"
grep -q "Repository launch commit: $launch_commit" <<< "$status_output"
grep -q "Canonical repository baseline: $launch_commit" <<< "$status_output"
grep -q 'Worker tokens: input=2500 cached=2000 output=250' <<< "$status_output"
grep -q 'Manager tokens: input=300 cached=240 output=60' <<< "$status_output"
grep -q 'ENV_RELOADED role=manager_review cycle=1 .*manager_effort=xhigh' \
	"$project/logs/events.log"
grep -q 'ENV_RELOADED role=manager_review cycle=2 .*manager_effort=xhigh' \
	"$project/logs/events.log"
if find "$project" -iname '*oracle*' -print -quit | grep -q .; then
	printf 'unexpected Oracle state exists\n' >&2
	exit 1
fi

repair_repo="$TEST_DIR/protocol-repair-repository"
repair_state="$TEST_DIR/protocol-repair-state"
repair_fake_state="$TEST_DIR/protocol-repair-fake-state"
repair_env="$TEST_DIR/protocol-repair-project.env"
mkdir -p "$repair_repo" "$repair_fake_state"
git -C "$repair_repo" init -q
git -C "$repair_repo" config user.name 'Harness Test'
git -C "$repair_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$repair_repo/baseline.txt"
git -C "$repair_repo" add baseline.txt
git -C "$repair_repo" commit -q -m baseline
cat > "$repair_env" <<EOF
export PROJECT="protocol-repair"
export REPOSITORY="$repair_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$repair_state"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MAX_ORACLE_RUNS="0"
export HARNESS_MAX_PROTOCOL_REPAIR_ATTEMPTS="2"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export FAKE_CODEX_STATE="$repair_fake_state"
export FAKE_REPOSITORY="$repair_repo"
export FAKE_INVALID_MANAGER_REVIEW="1"
EOF
chmod 600 "$repair_env"
"$ROOT/bin/harness-init" "$repair_env" >/dev/null
"$ROOT/bin/harness-start" "$repair_env" >/dev/null
repair_project="$repair_state/projects/protocol-repair"
for _ in {1..30}; do
	grep -qx 'status=COMPLETE' "$repair_project/control/state.env" 2>/dev/null &&
		break
	sleep 1
done
grep -qx 'status=COMPLETE' "$repair_project/control/state.env"
grep -qx 'phase=ACCEPTED' "$repair_project/control/state.env"
test -f "$repair_project/reviews/rejected/manager-review-001-invalid-000.md"
grep -q 'duplicate Finding-Key' \
	"$repair_project/prompts/manager-review-001-protocol-repair-001.md"
grep -qx 'Finding-Key: first-distinct-gap' \
	"$repair_project/reviews/review-001.md"
grep -qx 'Finding-Key: second-distinct-gap' \
	"$repair_project/reviews/review-001.md"
grep -q 'PROTOCOL_VALIDATION_FAILED role=manager_review cycle=1 .*attempt=0' \
	"$repair_project/logs/events.log"
grep -q 'PROTOCOL_REPAIR_COMPLETED role=manager_review cycle=1 .*attempts=1' \
	"$repair_project/logs/events.log"
grep -F -- '--model gpt-5.6-terra --sandbox read-only' \
	"$repair_fake_state/codex-argv.log" >/dev/null
test ! -e "$repair_project/control/operator-required.md"

repair_fail_repo="$TEST_DIR/protocol-repair-fail-repository"
repair_fail_state="$TEST_DIR/protocol-repair-fail-state"
repair_fail_fake_state="$TEST_DIR/protocol-repair-fail-fake-state"
repair_fail_env="$TEST_DIR/protocol-repair-fail-project.env"
mkdir -p "$repair_fail_repo" "$repair_fail_fake_state"
git -C "$repair_fail_repo" init -q
git -C "$repair_fail_repo" config user.name 'Harness Test'
git -C "$repair_fail_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$repair_fail_repo/baseline.txt"
git -C "$repair_fail_repo" add baseline.txt
git -C "$repair_fail_repo" commit -q -m baseline
sed -e 's/PROJECT="protocol-repair"/PROJECT="protocol-repair-fail"/' \
	-e "s|REPOSITORY=\"$repair_repo\"|REPOSITORY=\"$repair_fail_repo\"|" \
	-e "s|HARNESS_ROOT=\"$repair_state\"|HARNESS_ROOT=\"$repair_fail_state\"|" \
	-e "s|FAKE_CODEX_STATE=\"$repair_fake_state\"|FAKE_CODEX_STATE=\"$repair_fail_fake_state\"|" \
	-e "s|FAKE_REPOSITORY=\"$repair_repo\"|FAKE_REPOSITORY=\"$repair_fail_repo\"|" \
	"$repair_env" > "$repair_fail_env"
printf 'export FAKE_PROTOCOL_REPAIR_STAYS_INVALID="1"\n' >> "$repair_fail_env"
chmod 600 "$repair_fail_env"
"$ROOT/bin/harness-init" "$repair_fail_env" >/dev/null
"$ROOT/bin/harness-start" "$repair_fail_env" >/dev/null
repair_fail_project="$repair_fail_state/projects/protocol-repair-fail"
for _ in {1..30}; do
	grep -qx 'status=PAUSED' "$repair_fail_project/control/state.env" 2>/dev/null &&
		break
	sleep 1
done
grep -qx 'status=PAUSED' "$repair_fail_project/control/state.env"
grep -qx 'phase=NEEDS_OPERATOR' "$repair_fail_project/control/state.env"
grep -qx 'cycle=1' "$repair_fail_project/control/state.env"
test ! -e "$repair_fail_project/control/last-error.txt"
test ! -e "$repair_fail_project/reviews/review-001.md"
test ! -e "$repair_fail_project/addenda/addendum-001.md"
for attempt in 000 001 002; do
	test -f "$repair_fail_project/reviews/rejected/manager-review-001-invalid-$attempt.md"
done
grep -q 'after 2 repair attempts' \
	"$repair_fail_project/control/operator-required.md"
grep -q 'changed decision from REVISE to ACCEPT' \
	"$repair_fail_project/control/operator-required.md"
grep -q 'PROTOCOL_REPAIR_EXHAUSTED role=manager_review cycle=1 .*attempts=2' \
	"$repair_fail_project/logs/events.log"

hard_reload_repo="$TEST_DIR/hard-reload-repository"
hard_reload_state="$TEST_DIR/hard-reload-state"
hard_reload_fake_state="$TEST_DIR/hard-reload-fake-state"
hard_reload_env="$TEST_DIR/hard-reload-project.env"
mkdir -p "$hard_reload_repo" "$hard_reload_fake_state"
git -C "$hard_reload_repo" init -q
git -C "$hard_reload_repo" config user.name 'Harness Test'
git -C "$hard_reload_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$hard_reload_repo/baseline.txt"
git -C "$hard_reload_repo" add baseline.txt
git -C "$hard_reload_repo" commit -q -m baseline
cat > "$hard_reload_env" <<EOF
export PROJECT="hard-reload-test"
export REPOSITORY="$hard_reload_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$hard_reload_state"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MAX_ORACLE_RUNS="0"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export FAKE_CODEX_STATE="$hard_reload_fake_state"
export FAKE_REPOSITORY="$hard_reload_repo"
export FAKE_RELOAD_ENV_FILE="$hard_reload_env"
export FAKE_RELOAD_HARD_PROJECT="redirected-project"
EOF
chmod 600 "$hard_reload_env"
"$ROOT/bin/harness-init" "$hard_reload_env" >/dev/null
"$ROOT/bin/harness-start" "$hard_reload_env" >/dev/null
hard_reload_project="$hard_reload_state/projects/hard-reload-test"
for _ in {1..30}; do
	grep -qx 'status=FAILED' \
		"$hard_reload_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=FAILED' "$hard_reload_project/control/state.env"
grep -qx 'phase=TERMINAL_FAILURE' "$hard_reload_project/control/state.env"
grep -q 'attempted to change hard parameters.*PROJECT' \
	"$hard_reload_project/control/last-error.txt"
grep -q 'ENV_RELOAD_REJECTED role=manager_review cycle=1 reason=hard_parameters fields=PROJECT' \
	"$hard_reload_project/logs/events.log"
test ! -e "$hard_reload_state/projects/redirected-project/control/state.env"

repeat_repo="$TEST_DIR/repeat-repository"
repeat_state="$TEST_DIR/repeat-state"
repeat_fake_state="$TEST_DIR/repeat-fake-state"
mkdir -p "$repeat_repo" "$repeat_fake_state"
git -C "$repeat_repo" init -q
git -C "$repeat_repo" config user.name 'Harness Test'
git -C "$repeat_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$repeat_repo/baseline.txt"
git -C "$repeat_repo" add baseline.txt
git -C "$repeat_repo" commit -q -m baseline
cat > "$TEST_DIR/repeat-project.env" <<EOF
export PROJECT="repeat-circuit"
export REPOSITORY="$repeat_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$repeat_state"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MAX_ORACLE_RUNS="0"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export HARNESS_MAX_MANAGER_REVIEWS="50"
export HARNESS_MAX_REPEATED_FINDING_REVIEWS="3"
export FAKE_CODEX_STATE="$repeat_fake_state"
export FAKE_REPOSITORY="$repeat_repo"
export FAKE_REPEAT_FINDINGS="1"
EOF
chmod 600 "$TEST_DIR/repeat-project.env"
"$ROOT/bin/harness-init" "$TEST_DIR/repeat-project.env" >/dev/null
"$ROOT/bin/harness-start" "$TEST_DIR/repeat-project.env" >/dev/null
repeat_project="$repeat_state/projects/repeat-circuit"
for _ in {1..30}; do
	grep -qx 'status=PAUSED' "$repeat_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=PAUSED' "$repeat_project/control/state.env"
grep -qx 'phase=NEEDS_OPERATOR' "$repeat_project/control/state.env"
grep -qx 'cycle=3' "$repeat_project/control/state.env"
test -f "$repeat_project/reviews/convergence-audit-003.md"
test -f "$repeat_project/control/operator-required.md"
grep -qx 'DECISION: NEEDS_OPERATOR' \
	"$repeat_project/control/operator-required.md"
grep -q 'CONVERGENCE_TRIGGERED cycle=3 threshold=3 keys=external-decision-unavailable' \
	"$repeat_project/logs/events.log"
grep -q 'CONVERGENCE_AUDIT_FINISHED cycle=3 decision=NEEDS_OPERATOR' \
	"$repeat_project/logs/events.log"
test ! -f "$repeat_project/outputs/worker-004.md"

action_repo="$TEST_DIR/action-repository"
action_state="$TEST_DIR/action-state"
action_fake_state="$TEST_DIR/action-fake-state"
mkdir -p "$action_repo" "$action_fake_state"
git -C "$action_repo" init -q
git -C "$action_repo" config user.name 'Harness Test'
git -C "$action_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$action_repo/baseline.txt"
git -C "$action_repo" add baseline.txt
git -C "$action_repo" commit -q -m baseline
sed -e 's/PROJECT="repeat-circuit"/PROJECT="actionable-circuit"/' \
	-e "s|REPOSITORY=\"$repeat_repo\"|REPOSITORY=\"$action_repo\"|" \
	-e "s|HARNESS_ROOT=\"$repeat_state\"|HARNESS_ROOT=\"$action_state\"|" \
	-e "s|FAKE_CODEX_STATE=\"$repeat_fake_state\"|FAKE_CODEX_STATE=\"$action_fake_state\"|" \
	-e "s|FAKE_REPOSITORY=\"$repeat_repo\"|FAKE_REPOSITORY=\"$action_repo\"|" \
	"$TEST_DIR/repeat-project.env" > "$TEST_DIR/action-project.env"
printf 'export FAKE_CONVERGENCE_ACTIONABLE="1"\n' >> \
	"$TEST_DIR/action-project.env"
printf 'export FAKE_INVALID_CONVERGENCE="1"\n' >> \
	"$TEST_DIR/action-project.env"
chmod 600 "$TEST_DIR/action-project.env"
"$ROOT/bin/harness-init" "$TEST_DIR/action-project.env" >/dev/null
"$ROOT/bin/harness-start" "$TEST_DIR/action-project.env" >/dev/null
action_project="$action_state/projects/actionable-circuit"
for _ in {1..30}; do
	grep -qx 'status=COMPLETE' "$action_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=COMPLETE' "$action_project/control/state.env"
grep -qx 'phase=ACCEPTED' "$action_project/control/state.env"
grep -qx 'cycle=4' "$action_project/control/state.env"
grep -qx 'DECISION: ACTIONABLE' \
	"$action_project/reviews/convergence-audit-003.md"
grep -qx 'Finding-Key: convergence-first-gap' \
	"$action_project/reviews/convergence-audit-003.md"
test -f \
	"$action_project/reviews/rejected/manager-convergence-003-invalid-000.md"
grep -qx 'DECISION: ACTIONABLE' \
	"$action_project/addenda/addendum-003.md"
grep -q 'CONVERGENCE_ADDENDUM_PUBLISHED cycle=3' \
	"$action_project/logs/events.log"
grep -q 'PROTOCOL_REPAIR_COMPLETED role=manager_convergence cycle=3 .*attempts=1' \
	"$action_project/logs/events.log"
grep -q '^worker resume worker-thread$' "$action_fake_state/invocations.log"

no_progress_repo="$TEST_DIR/no-progress-repository"
no_progress_state="$TEST_DIR/no-progress-state"
no_progress_fake_state="$TEST_DIR/no-progress-fake-state"
mkdir -p "$no_progress_repo" "$no_progress_fake_state"
git -C "$no_progress_repo" init -q
git -C "$no_progress_repo" config user.name 'Harness Test'
git -C "$no_progress_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$no_progress_repo/baseline.txt"
git -C "$no_progress_repo" add baseline.txt
git -C "$no_progress_repo" commit -q -m baseline
cat > "$TEST_DIR/no-progress-project.env" <<EOF
export PROJECT="no-progress-circuit"
export REPOSITORY="$no_progress_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$no_progress_state"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MAX_ORACLE_RUNS="0"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export HARNESS_MAX_REPEATED_FINDING_REVIEWS="0"
export HARNESS_MAX_NO_SOURCE_PROGRESS_REVIEWS="2"
export HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS="3"
export FAKE_CODEX_STATE="$no_progress_fake_state"
export FAKE_REPOSITORY="$no_progress_repo"
export FAKE_REPEAT_FINDINGS="1"
export FAKE_WORKER_NO_CHANGES="1"
EOF
chmod 600 "$TEST_DIR/no-progress-project.env"
"$ROOT/bin/harness-init" "$TEST_DIR/no-progress-project.env" >/dev/null
"$ROOT/bin/harness-start" "$TEST_DIR/no-progress-project.env" >/dev/null
no_progress_project="$no_progress_state/projects/no-progress-circuit"
for _ in {1..30}; do
	grep -qx 'phase=NO_SOURCE_PROGRESS' \
		"$no_progress_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=PAUSED' "$no_progress_project/control/state.env"
grep -qx 'phase=NO_SOURCE_PROGRESS' "$no_progress_project/control/state.env"
grep -qx 'cycle=2' "$no_progress_project/control/state.env"
grep -qx '2' "$no_progress_project/control/no-source-progress-count"
grep -q '^changed=0$' "$no_progress_project/control/worker-progress-002.env"
grep -q '^# No source progress limit reached$' \
	"$no_progress_project/control/operator-required.md"
grep -q 'NO_SOURCE_PROGRESS_LIMIT_REACHED cycle=2 count=2 max=2' \
	"$no_progress_project/logs/events.log"
test ! -f "$no_progress_project/reviews/review-002.md"
paused_start_output="$("$ROOT/bin/harness-start" \
	"$TEST_DIR/no-progress-project.env")"
grep -q 'Project remains paused after 2 unchanged worker deliveries' \
	<<< "$paused_start_output"
printf 'operator integration\n' > "$no_progress_repo/operator-integration.txt"
printf 'export FAKE_WORKER_NO_CHANGES="0"\n' >> \
	"$TEST_DIR/no-progress-project.env"
printf 'export FAKE_REPEAT_FINDINGS="0"\n' >> \
	"$TEST_DIR/no-progress-project.env"
"$ROOT/bin/harness-start" "$TEST_DIR/no-progress-project.env" >/dev/null
for _ in {1..30}; do
	grep -qx 'status=COMPLETE' \
		"$no_progress_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=COMPLETE' "$no_progress_project/control/state.env"
test -f "$no_progress_project/reviews/operator-pause-no-source-progress-2-2.md"
test ! -f "$no_progress_project/control/operator-required.md"
grep -q 'NO_SOURCE_PROGRESS_RESUMED cycle=2 .*repository_changed=1' \
	"$no_progress_project/logs/events.log"

convergence_cap_repo="$TEST_DIR/convergence-cap-repository"
convergence_cap_state="$TEST_DIR/convergence-cap-state"
convergence_cap_fake_state="$TEST_DIR/convergence-cap-fake-state"
mkdir -p "$convergence_cap_repo" "$convergence_cap_fake_state"
git -C "$convergence_cap_repo" init -q
git -C "$convergence_cap_repo" config user.name 'Harness Test'
git -C "$convergence_cap_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$convergence_cap_repo/baseline.txt"
git -C "$convergence_cap_repo" add baseline.txt
git -C "$convergence_cap_repo" commit -q -m baseline
cat > "$TEST_DIR/convergence-cap-project.env" <<EOF
export PROJECT="convergence-cap-circuit"
export REPOSITORY="$convergence_cap_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$convergence_cap_state"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MAX_ORACLE_RUNS="0"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export HARNESS_MAX_MANAGER_REVIEWS="50"
export HARNESS_MAX_REPEATED_FINDING_REVIEWS="2"
export HARNESS_MAX_NO_SOURCE_PROGRESS_REVIEWS="0"
export HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS="3"
export FAKE_CODEX_STATE="$convergence_cap_fake_state"
export FAKE_REPOSITORY="$convergence_cap_repo"
export FAKE_REPEAT_FINDINGS="1"
export FAKE_CONVERGENCE_ACTIONABLE="1"
export FAKE_CONVERGENCE_STAYS_ACTIONABLE="1"
EOF
chmod 600 "$TEST_DIR/convergence-cap-project.env"
"$ROOT/bin/harness-init" "$TEST_DIR/convergence-cap-project.env" >/dev/null
"$ROOT/bin/harness-start" "$TEST_DIR/convergence-cap-project.env" >/dev/null
convergence_cap_project="$convergence_cap_state/projects/convergence-cap-circuit"
for _ in {1..45}; do
	grep -qx 'phase=CONVERGENCE_LIMIT_REACHED' \
		"$convergence_cap_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=PAUSED' "$convergence_cap_project/control/state.env"
grep -qx 'phase=CONVERGENCE_LIMIT_REACHED' \
	"$convergence_cap_project/control/state.env"
grep -qx 'cycle=6' "$convergence_cap_project/control/state.env"
test -f "$convergence_cap_project/reviews/convergence-audit-002.md"
test -f "$convergence_cap_project/reviews/convergence-audit-004.md"
test -f "$convergence_cap_project/reviews/convergence-audit-006.md"
grep -q 'direct-repository-correction' \
	"$convergence_cap_project/control/operator-required.md"
grep -q 'CONVERGENCE_LIMIT_REACHED cycle=6 max=3' \
	"$convergence_cap_project/logs/events.log"
if grep -q 'CONVERGENCE_ADDENDUM_PUBLISHED cycle=6' \
	"$convergence_cap_project/logs/events.log"; then
	printf 'third repeated convergence audit incorrectly resumed Luna\n' >&2
	exit 1
fi
printf 'export HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS="4"\n' >> \
	"$TEST_DIR/convergence-cap-project.env"
printf 'export FAKE_CONVERGENCE_STAYS_ACTIONABLE="0"\n' >> \
	"$TEST_DIR/convergence-cap-project.env"
"$ROOT/bin/harness-start" "$TEST_DIR/convergence-cap-project.env" >/dev/null
for _ in {1..30}; do
	grep -qx 'status=COMPLETE' \
		"$convergence_cap_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=COMPLETE' "$convergence_cap_project/control/state.env"
test -f "$convergence_cap_project/reviews/operator-pause-convergence-6-3.md"
test ! -f "$convergence_cap_project/control/operator-required.md"
grep -q 'CONVERGENCE_LIMIT_RESUMED cycle=6 previous_count=3 new_limit=4' \
	"$convergence_cap_project/logs/events.log"

cap_repo="$TEST_DIR/cap-repository"
cap_state="$TEST_DIR/cap-state"
cap_fake_state="$TEST_DIR/cap-fake-state"
mkdir -p "$cap_repo" "$cap_fake_state"
git -C "$cap_repo" init -q
git -C "$cap_repo" config user.name 'Harness Test'
git -C "$cap_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$cap_repo/baseline.txt"
git -C "$cap_repo" add baseline.txt
git -C "$cap_repo" commit -q -m baseline
sed -e 's/PROJECT="repeat-circuit"/PROJECT="emergency-cap"/' \
	-e "s|REPOSITORY=\"$repeat_repo\"|REPOSITORY=\"$cap_repo\"|" \
	-e "s|HARNESS_ROOT=\"$repeat_state\"|HARNESS_ROOT=\"$cap_state\"|" \
	-e 's/HARNESS_MAX_MANAGER_REVIEWS="50"/HARNESS_MAX_MANAGER_REVIEWS="2"/' \
	-e 's/HARNESS_MAX_REPEATED_FINDING_REVIEWS="3"/HARNESS_MAX_REPEATED_FINDING_REVIEWS="0"/' \
	-e "s|FAKE_CODEX_STATE=\"$repeat_fake_state\"|FAKE_CODEX_STATE=\"$cap_fake_state\"|" \
	-e "s|FAKE_REPOSITORY=\"$repeat_repo\"|FAKE_REPOSITORY=\"$cap_repo\"|" \
	"$TEST_DIR/repeat-project.env" > "$TEST_DIR/cap-project.env"
chmod 600 "$TEST_DIR/cap-project.env"
"$ROOT/bin/harness-init" "$TEST_DIR/cap-project.env" >/dev/null
"$ROOT/bin/harness-start" "$TEST_DIR/cap-project.env" >/dev/null
cap_project="$cap_state/projects/emergency-cap"
for _ in {1..30}; do
	grep -qx 'status=PAUSED' "$cap_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'phase=REVIEW_LIMIT_REACHED' "$cap_project/control/state.env"
grep -qx 'cycle=2' "$cap_project/control/state.env"
test ! -f "$cap_project/reviews/convergence-audit-002.md"
grep -q 'REVIEW_LIMIT_REACHED cycle=2 max=2' "$cap_project/logs/events.log"

oracle_repo="$TEST_DIR/oracle-repository"
oracle_state="$TEST_DIR/oracle-state"
oracle_fake_state="$TEST_DIR/oracle-fake-state"
oracle_env="$TEST_DIR/oracle-project.env"
mkdir -p "$oracle_repo" "$oracle_fake_state"
git -C "$oracle_repo" init -q
git -C "$oracle_repo" config user.name 'Harness Test'
git -C "$oracle_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$oracle_repo/baseline.txt"
git -C "$oracle_repo" add baseline.txt
git -C "$oracle_repo" commit -q -m baseline
cat > "$oracle_env" <<EOF
export PROJECT="oracle-gate"
export REPOSITORY="$oracle_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$oracle_state"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export ORACLE_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export ORACLE_CODEX_HOME="$TEST_DIR/codex-home"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export HARNESS_MAX_REPEATED_FINDING_REVIEWS="0"
export MAX_ORACLE_RUNS="1"
export FAKE_CODEX_STATE="$oracle_fake_state"
export FAKE_REPOSITORY="$oracle_repo"
export FAKE_ORACLE_REVISIONS="1"
EOF
chmod 600 "$oracle_env"
"$ROOT/bin/harness-init" "$oracle_env" >/dev/null
"$ROOT/bin/harness-start" "$oracle_env" >/dev/null
oracle_project="$oracle_state/projects/oracle-gate"
for _ in {1..30}; do
	grep -qx 'phase=ORACLE_LIMIT_REACHED' \
		"$oracle_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=PAUSED' "$oracle_project/control/state.env"
grep -qx 'phase=ORACLE_LIMIT_REACHED' "$oracle_project/control/state.env"
grep -qx 'cycle=3' "$oracle_project/control/state.env"
test ! -e "$oracle_project/control/final-acceptance.md"
test -f "$oracle_project/control/provisional-acceptance.md"
test -f "$oracle_project/reviews/oracle-audit-001.md"
grep -qx 'Addendum-Source: ORACLE' \
	"$oracle_project/addenda/addendum-002.md"
grep -qx 'Oracle-Run: 1' "$oracle_project/addenda/addendum-002.md"
grep -qx 'Manager-Cycle: 2' "$oracle_project/addenda/addendum-002.md"
grep -q '^# Complete immutable specification$' \
	"$oracle_project/prompts/oracle-audit-001.md"
grep -Fq 'Create feature.txt containing exactly `complete`.' \
	"$oracle_project/prompts/oracle-audit-001.md"
grep -Fq 'Run the focused builds, smoke tests, integration tests' \
	"$oracle_project/prompts/oracle-audit-001.md"
grep -Fq '# Expected Oracle PASS requirement IDs' \
	"$oracle_project/prompts/oracle-audit-001.md"
grep -Fq -- '- `SPECIFICATION-WHOLE`' \
	"$oracle_project/prompts/oracle-audit-001.md"
grep -Fq -- '--model gpt-5.6-sol' "$oracle_fake_state/codex-argv.log"
grep -Fq -- 'model_reasoning_effort="high"' \
	"$oracle_fake_state/codex-argv.log"
grep -q 'ORACLE_ADDENDUM_PUBLISHED cycle=2 run=1' \
	"$oracle_project/logs/events.log"
grep -q 'ORACLE_LIMIT_REACHED cycle=3 completed_runs=1 max_runs=1' \
	"$oracle_project/logs/events.log"

sed -i 's/MAX_ORACLE_RUNS="1"/MAX_ORACLE_RUNS="2"/' "$oracle_env"
"$ROOT/bin/harness-start" "$oracle_env" >/dev/null
for _ in {1..30}; do
	grep -qx 'status=COMPLETE' "$oracle_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=COMPLETE' "$oracle_project/control/state.env"
grep -qx 'phase=ORACLE_ACCEPTED' "$oracle_project/control/state.env"
grep -qx 'cycle=3' "$oracle_project/control/state.env"
test -f "$oracle_project/reviews/oracle-audit-002.md"
grep -qx 'DECISION: PASS' "$oracle_project/control/final-acceptance.md"
grep -qx 'Oracle-Run: 2' "$oracle_project/control/final-acceptance.md"
grep -qx 'Manager-Cycle: 3' "$oracle_project/control/final-acceptance.md"
grep -qx 'REQUIREMENT: SPECIFICATION-WHOLE' \
	"$oracle_project/control/final-acceptance.md"
test ! -e "$oracle_project/control/provisional-acceptance.md"
grep -q 'ORACLE_LIMIT_RESUMED cycle=3 completed_runs=1 new_limit=2' \
	"$oracle_project/logs/events.log"
grep -q 'PROJECT_COMPLETED cycle=3 oracle_run=2 .*source=oracle' \
	"$oracle_project/logs/events.log"
oracle_status="$({ "$ROOT/bin/harness-status" "$oracle_env"; })"
grep -q 'Oracle: gpt-5.6-sol (high)' <<< "$oracle_status"
grep -q 'Oracle audits: 2 of 2' <<< "$oracle_status"
grep -q 'Oracle tokens: input=1000 cached=600 output=100' <<< "$oracle_status"

oracle_repair_repo="$TEST_DIR/oracle-repair-repository"
oracle_repair_state="$TEST_DIR/oracle-repair-state"
oracle_repair_fake_state="$TEST_DIR/oracle-repair-fake-state"
oracle_repair_env="$TEST_DIR/oracle-repair-project.env"
mkdir -p "$oracle_repair_repo" "$oracle_repair_fake_state"
git -C "$oracle_repair_repo" init -q
git -C "$oracle_repair_repo" config user.name 'Harness Test'
git -C "$oracle_repair_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$oracle_repair_repo/baseline.txt"
git -C "$oracle_repair_repo" add baseline.txt
git -C "$oracle_repair_repo" commit -q -m baseline
cat > "$oracle_repair_env" <<EOF
export PROJECT="oracle-protocol-repair"
export REPOSITORY="$oracle_repair_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$oracle_repair_state"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export ORACLE_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export ORACLE_CODEX_HOME="$TEST_DIR/codex-home"
export MAX_ORACLE_RUNS="3"
export HARNESS_MAX_PROTOCOL_REPAIR_ATTEMPTS="2"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export FAKE_CODEX_STATE="$oracle_repair_fake_state"
export FAKE_REPOSITORY="$oracle_repair_repo"
export FAKE_INVALID_ORACLE_PASS="1"
EOF
chmod 600 "$oracle_repair_env"
"$ROOT/bin/harness-init" "$oracle_repair_env" >/dev/null
"$ROOT/bin/harness-start" "$oracle_repair_env" >/dev/null
oracle_repair_project="$oracle_repair_state/projects/oracle-protocol-repair"
for _ in {1..30}; do
	grep -qx 'status=COMPLETE' \
		"$oracle_repair_project/control/state.env" 2>/dev/null && break
	sleep 1
done
grep -qx 'status=COMPLETE' "$oracle_repair_project/control/state.env"
grep -qx 'phase=ORACLE_ACCEPTED' "$oracle_repair_project/control/state.env"
test -f "$oracle_repair_project/reviews/rejected/oracle-audit-001-invalid-000.md"
grep -q 'SPECIFICATION-WHOLE has empty Verification' \
	"$oracle_repair_project/prompts/oracle-audit-001-protocol-repair-001.md"
grep -qx 'REQUIREMENT: SPECIFICATION-WHOLE' \
	"$oracle_repair_project/control/final-acceptance.md"
grep -qx 'Verification: test "$(cat feature.txt)" = complete passed.' \
	"$oracle_repair_project/control/final-acceptance.md"
grep -q 'PROTOCOL_REPAIR_COMPLETED role=oracle_audit .*attempts=1' \
	"$oracle_repair_project/logs/events.log"
grep -F -- '--model gpt-5.6-sol --sandbox read-only' \
	"$oracle_repair_fake_state/codex-argv.log" >/dev/null

cp "$TEST_DIR/project.env" "$TEST_DIR/trace-project.env"
{
	printf 'export PATH="%s:$PATH"\n' "$TEST_DIR/fake-bin"
	printf 'export HARNESS_CODEX_RUST_LOG="codex_core=debug"\n'
	printf 'export HARNESS_CODEX_STRACE="1"\n'
} >> "$TEST_DIR/trace-project.env"
chmod 600 "$TEST_DIR/trace-project.env"
"$ROOT/bin/codex-exec-jsonl" "$TEST_DIR/trace-project.env" manager_goal \
	"$project/prompts/manager-goal.md" \
	"$project/logs/trace-test.jsonl" \
	"$project/logs/trace-test.stderr.log" \
	"$project/outputs/trace-test.md"
grep -q '^env CODEX_HOME=.* RUST_LOG=codex_core=debug .*fake-codex exec ' \
	"$fake_state/strace-invocations.log"
grep -qx 'fake trace' "$project/logs/trace-test.diagnostics/strace.fake"
grep -q '^strace_prefix=.*/trace-test.diagnostics/strace$' \
	"$project/logs/trace-test.classification"

cp "$TEST_DIR/project.env" "$TEST_DIR/stall-project.env"
{
	printf 'export MANAGER_CODEX_BIN="%s"\n' "$TEST_DIR/slow-codex"
	printf 'export HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS="1"\n'
	printf 'export HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS="1"\n'
} >> "$TEST_DIR/stall-project.env"
chmod 600 "$TEST_DIR/stall-project.env"
"$ROOT/bin/codex-exec-jsonl" "$TEST_DIR/stall-project.env" manager_goal \
	"$project/prompts/manager-goal.md" \
	"$project/logs/stall-test.jsonl" \
	"$project/logs/stall-test.stderr.log" \
	"$project/outputs/stall-test.md" &
slow_executor=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[[ -s "$project/logs/stall-test.jsonl" ]] && break
	sleep 0.1
done
diagnose_output="$("$ROOT/bin/harness-diagnose" \
	"$TEST_DIR/stall-project.env" test-manual)"
stall_status="$("$ROOT/bin/harness-status" "$TEST_DIR/stall-project.env")"
grep -q '^Codex warning: ' <<< "$stall_status"
grep -q '^Warning evidence: ' <<< "$stall_status"
wait "$slow_executor"
grep -q '^Captured Codex diagnostics: ' <<< "$diagnose_output"
manual_snapshot="$(find "$project/logs/stall-test.diagnostics" \
	-mindepth 1 -maxdepth 1 -type d -name '*-test-manual' -print -quit)"
[[ -n "$manual_snapshot" ]]
grep -qx 'reason=test-manual' "$manual_snapshot/metadata.env"
mapfile -t stall_snapshots < <(find "$project/logs/stall-test.diagnostics" \
	-mindepth 1 -maxdepth 1 -type d -name '*-stall' -print | sort)
(( ${#stall_snapshots[@]} >= 2 ))
snapshot="${stall_snapshots[0]}"
[[ -n "$snapshot" ]]
grep -qx 'reason=stall' "$snapshot/metadata.env"
grep -q 'slow-codex' "$snapshot/process-tree.txt"
grep -q '^classification=' "$snapshot/warning.env"
no_progress_warning=0
for snapshot_candidate in "${stall_snapshots[@]}"; do
	if grep -qx 'classification=no_observable_progress' \
		"$snapshot_candidate/warning.env"; then
		no_progress_warning=1
	fi
done
(( no_progress_warning == 1 ))
grep -q 'CODEX_DIAGNOSTICS_CAPTURED role=manager_goal reason=stall' \
	"$project/logs/events.log"
grep -q 'CODEX_WARNING role=manager_goal classification=' \
	"$project/logs/events.log"

cp "$TEST_DIR/project.env" "$TEST_DIR/protected-state-project.env"
{
	printf 'export MANAGER_CODEX_BIN="%s"\n' "$TEST_DIR/protected-state-codex"
	printf 'export PROTECTED_TEST_SOURCE="%s"\n' "$TEST_DIR/specification.md"
	printf 'export PROTECTED_TEST_STATE="%s"\n' "$project"
} >> "$TEST_DIR/protected-state-project.env"
chmod 600 "$TEST_DIR/protected-state-project.env"
worker_goal_sha="$(sha256sum "$project/control/worker-goal.md" | awk '{print $1}')"
if "$ROOT/bin/codex-exec-jsonl" "$TEST_DIR/protected-state-project.env" \
	manager_goal "$project/prompts/manager-goal.md" \
	"$project/logs/protected-state-test.jsonl" \
	"$project/logs/protected-state-test.stderr.log" \
	"$project/outputs/protected-state-test.md"; then
	printf 'protected content mutation was accepted\n' >&2
	exit 1
fi
grep -qx 'classification=protected_content_modified' \
	"$project/logs/protected-state-test.classification"
cmp -s "$TEST_DIR/specification.md" "$project/inputs/specification.txt"
test "$(sha256sum "$project/control/worker-goal.md" | awk '{print $1}')" = \
	"$worker_goal_sha"
git -C "$repo" diff --cached --quiet
grep -q 'PROTECTED_CONTENT_RESTORED role=manager_goal state=1 source=1' \
	"$project/logs/events.log"
grep -q 'GIT_INDEX_RESTORED role=manager_goal' "$project/logs/events.log"
git -C "$repo" restore --worktree -- pre-existing.txt

containment_repo="$TEST_DIR/containment-repository"
containment_state="$TEST_DIR/containment-state"
containment_pid_file="$TEST_DIR/detached.pid"
mkdir -p "$containment_repo"
git -C "$containment_repo" init -q
git -C "$containment_repo" config user.name 'Harness Test'
git -C "$containment_repo" config user.email 'harness-test@example.invalid'
printf 'baseline\n' > "$containment_repo/baseline.txt"
git -C "$containment_repo" add baseline.txt
git -C "$containment_repo" commit -q -m baseline
CONTAINMENT_ENV_FILE="$TEST_DIR/containment-project.env"
cat > "$CONTAINMENT_ENV_FILE" <<EOF
export PROJECT="containment-test"
export REPOSITORY="$containment_repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$containment_state"
export MANAGER_CODEX_BIN="$TEST_DIR/detached-codex"
export WORKER_CODEX_BIN="$TEST_DIR/detached-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MAX_ORACLE_RUNS="0"
export HARNESS_CODEX_KILL_GRACE_SECONDS="2"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export DETACHED_PID_FILE="$containment_pid_file"
EOF
chmod 600 "$CONTAINMENT_ENV_FILE"
"$ROOT/bin/harness-init" "$CONTAINMENT_ENV_FILE" >/dev/null
"$ROOT/bin/harness-start" "$CONTAINMENT_ENV_FILE" >/dev/null
containment_project="$containment_state/projects/containment-test"
for _ in {1..50}; do
	[[ -s "$containment_pid_file" ]] && break
	sleep 0.1
done
test -s "$containment_pid_file"
detached_pid="$(cat "$containment_pid_file")"
kill -0 "$detached_pid"
test -s "$containment_project/control/process-token"
if command -v systemctl >/dev/null 2>&1 &&
	command -v systemd-run >/dev/null 2>&1 &&
	systemctl --user show-environment >/dev/null 2>&1; then
	test -s "$containment_project/control/supervisor.unit"
fi
containment_status="$("$ROOT/bin/harness-status" "$CONTAINMENT_ENV_FILE")"
grep -q '^Process containment: ' <<< "$containment_status"
if flock -n "$containment_project/control/supervisor.lock" true; then
	printf 'active supervisor lock was unexpectedly acquirable\n' >&2
	exit 1
fi
"$ROOT/bin/harness-stop" "$CONTAINMENT_ENV_FILE" >/dev/null
if kill -0 "$detached_pid" 2>/dev/null; then
	printf 'detached Codex child survived harness-stop\n' >&2
	exit 1
fi
test ! -e "$containment_project/control/supervisor.pid"
test ! -e "$containment_project/control/process-token"
test ! -e "$containment_project/control/supervisor.unit"
flock -n "$containment_project/control/supervisor.lock" true

rm -f "$containment_pid_file"
"$ROOT/bin/harness-start" "$CONTAINMENT_ENV_FILE" >/dev/null
for _ in {1..50}; do
	[[ -s "$containment_pid_file" ]] && break
	sleep 0.1
done
test -s "$containment_pid_file"
restarted_detached_pid="$(cat "$containment_pid_file")"
kill -0 "$restarted_detached_pid"
test "$restarted_detached_pid" != "$detached_pid"
"$ROOT/bin/harness-stop" "$CONTAINMENT_ENV_FILE" >/dev/null
if kill -0 "$restarted_detached_pid" 2>/dev/null; then
	printf 'restarted detached child survived harness-stop\n' >&2
	exit 1
fi
CONTAINMENT_ENV_FILE=""

cp "$TEST_DIR/project.env" "$TEST_DIR/head-moving-project.env"
printf 'export MANAGER_CODEX_BIN="%s"\n' "$TEST_DIR/head-moving-codex" >> \
	"$TEST_DIR/head-moving-project.env"
chmod 600 "$TEST_DIR/head-moving-project.env"
head_before="$(git -C "$repo" rev-parse HEAD)"
if "$ROOT/bin/codex-exec-jsonl" "$TEST_DIR/head-moving-project.env" \
	manager_goal "$project/prompts/manager-goal.md" \
	"$project/logs/head-moving-test.jsonl" \
	"$project/logs/head-moving-test.stderr.log" \
	"$project/outputs/head-moving-test.md"; then
	printf 'Codex-created commit was accepted\n' >&2
	exit 1
fi
grep -qx 'classification=repository_head_changed' \
	"$project/logs/head-moving-test.classification"
test "$(git -C "$repo" rev-parse HEAD)" != "$head_before"

printf 'PASS light harness persistent-worker smoke\n'
