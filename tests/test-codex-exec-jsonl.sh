#!/usr/bin/env bash
# Focused tests for the non-interactive Codex JSONL runner.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/codex-jsonl-test.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\n" "$TMP" >&2' EXIT
else
	trap 'rm -rf "$TMP"' EXIT
fi
mkdir -p "$TMP/repo" "$TMP/home"
printf 'base\n' > "$TMP/repo/tracked.txt"
printf 'test specification\n' > "$TMP/repo/spec.md"
git -C "$TMP/repo" init -q
git -C "$TMP/repo" add tracked.txt
git -C "$TMP/repo" -c user.email=test@example.invalid -c user.name=test commit -qm initial

cat > "$TMP/mock-codex" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
last=""; next=0
for a in "$@"; do
 if (( next )); then last="$a"; next=0; continue; fi
 [[ "$a" == --output-last-message ]] && next=1
done
case "${MOCK_MODE:?}" in
 success) printf 'done\n' > "$last"; printf '{"type":"turn.completed"}\n' ;;
	arg_capture) printf '%s\n' "$*" > "$last"; printf '{"type":"turn.completed"}\n' ;;
	env_capture) printf '%s\n%s\n' "${REVIEW_CONTEXT_CAPSULE_FILE:-missing}" "${RESULT_FILE:-missing}" > "$last"; printf '{"type":"turn.completed"}\n' ;;
 failed) printf '{"type":"turn.failed","error":{"message":"simulated"}}\n'; exit 1 ;;
 error) printf '{"type":"error","message":"simulated"}\n'; exit 1 ;;
 invalid) printf 'not json\n' ;;
 empty) : ;;
 nonzero) exit 7 ;;
 stderr_progress) printf 'progress\n' >&2; printf 'done\n' > "$last"; printf '{"type":"turn.completed"}\n' ;;
 benign_blocked_text) printf 'done\n' > "$last"; printf '{"type":"item.completed","item":{"type":"agent_message","text":"The blocked queue is now fixed."}}\n{"type":"turn.completed"}\n' ;;
 refusal) printf '{"type":"error","message":"Request refused by an additional safety check"}\n'; exit 1 ;;
 cyber_flag) printf '{"type":"turn.failed","error":{"message":"This content was flagged for possible cybersecurity risk. To get authorized for security work, join the Trusted Access for Cyber program."}}\n'; exit 1 ;;
 idle) sleep 5 ;;
 wall) while true; do printf 'progress\n' >&2; sleep 1; done ;;
 partial) printf 'partial\n' >> "$REPOSITORY/tracked.txt"; exit 7 ;;
	partial_already_dirty) printf 'another partial edit\n' >> "$REPOSITORY/tracked.txt"; exit 7 ;;
 capacity_code) printf '{"type":"turn.failed","error":{"code":"model_capacity","message":"busy"}}\n'; exit 1 ;;
 capacity_text) printf '{"type":"error","message":"Selected model is at capacity. Please try a different model."}\n'; exit 1 ;;
 quota_code) printf '{"type":"turn.failed","error":{"code":"usage_limit_reached","message":"limit"}}\n'; exit 1 ;;
 quota_text) printf "You've hit your usage limit; limit resets in 2 hours.\n" >&2; exit 1 ;;
 rate_status) printf '{"type":"turn.failed","error":{"status":429,"message":"slow down"}}\n'; exit 1 ;;
 network_stderr) printf 'stream disconnected: connection reset by peer\n' >&2; exit 1 ;;
 auth_code) printf '{"type":"turn.failed","error":{"code":"invalid_api_key","message":"bad credentials"}}\n'; exit 1 ;;
 success_warning) printf 'network error recovered\n' >&2; printf 'done\n' > "$last"; printf '{"type":"turn.completed"}\n' ;;
	item_loop) for i in $(seq 1 20); do printf '{"type":"item.started","item":{"id":"%s"}}\n' "$i"; done; sleep 5 ;;
	command_output_heavy) printf '{"type":"item.completed","item":{"id":"cmd-1","type":"command_execution","aggregated_output":"%040d","exit_code":0,"status":"completed"}}\n' 0; sleep 5 ;;
	command_output_completed) printf 'done\n' > "$last"; printf '{"type":"item.completed","item":{"id":"cmd-1","type":"command_execution","aggregated_output":"%040d","exit_code":0,"status":"completed"}}\n{"type":"turn.completed"}\n' 0 ;;
	repeated_read_once) printf 'done\n' > "$last"; printf '{"type":"item.started","item":{"id":"cmd-1","type":"command_execution","command":"/bin/bash -lc '\''rg -n target_symbol src/a.c | head -c 4096'\''"}}\n{"type":"turn.completed"}\n' ;;
	repeated_read) printf '{"type":"item.started","item":{"id":"cmd-1","type":"command_execution","command":"/bin/bash -lc '\''rg -n target_symbol src/a.c | head -c 4096'\''"}}\n{"type":"item.started","item":{"id":"cmd-2","type":"command_execution","command":"/bin/bash -lc '\''rg -n target_symbol src/a.c | head -c 4096'\''"}}\n'; sleep 5 ;;
	token_heavy) printf 'done\n' > "$last"; printf '{"type":"thread.started","thread_id":"budget-thread"}\n{"type":"turn.completed","usage":{"input_tokens":90,"output_tokens":20}}\n' ;;
	stop_sentinel) while true; do sleep 1; done ;;
esac
MOCK
chmod +x "$TMP/mock-codex"
cat > "$TMP/env" <<ENV
export PROJECT="jsonltest"
export REPOSITORY="$TMP/repo"
export SPECIFICATION="$TMP/repo/spec.md"
export HARNESS_HOME="$ROOT"
export HARNESS_BIN="$ROOT/bin"
export HARNESS_ROOT="$TMP/state"
export MANAGER_CODEX_HOME="$TMP/home"
export MANAGER_CODEX_BIN="$TMP/mock-codex"
export WORKER_CODEX_HOME="$TMP/home"
export WORKER_CODEX_BIN="$TMP/mock-codex"
export HARNESS_CODEX_WALL_TIMEOUT_SECONDS="2"
export HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="1"
export HARNESS_CODEX_KILL_GRACE_SECONDS="1"
export HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND="0"
ENV
chmod 600 "$TMP/env"
prompt="$TMP/prompt"; printf 'test\n' > "$prompt"

"$ROOT/bin/harness-check-env" "$TMP/env" > "$TMP/defaults.out"
grep -q '^Transient provider retry seconds: 60 (retries unlimited)$' "$TMP/defaults.out"
grep -q '^Quota retry seconds: 300 (retries unlimited)$' "$TMP/defaults.out"
grep -q '^Minimum interval between agent launches: 60 seconds (project-wide)$' "$TMP/defaults.out"
grep -q '^Supervisor startup readiness timeout: 120 seconds$' "$TMP/defaults.out"
grep -q '^Runtime PATH prefix: (none)$' "$TMP/defaults.out"
grep -q '^Patch-only validation rounds: 3$' "$TMP/defaults.out"
grep -Fqx 'Per-agent circuit breaker: 80 item starts, 500000 live-estimated tokens, 500000 authoritative processed tokens' \
	"$TMP/defaults.out"
grep -Fqx 'Per-worker-task processed-token anomaly limit: 500000' "$TMP/defaults.out"
# The remaining cases exercise classification and policy, not the production
# launch cadence. A dedicated case below restores a nonzero throttle.
printf 'export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"\n' >> "$TMP/env"

# Luna-only policy confines execution/local convergence roles to Luna while
# retaining the configured Sol global decomposition critic. Stale direct
# callers are rejected before a provider process is launched.
cp "$TMP/env" "$TMP/env-luna-only"
{
	printf 'export HARNESS_MODEL_POLICY="luna_only"\n'
	printf 'export HARNESS_ESCALATION_POLICY="decompose"\n'
	printf 'export LUNA_WORKER_MODEL="gpt-5.6-luna"\n'
	printf 'export LUNA_WORKER_REASONING_EFFORT="high"\n'
	printf 'export ORACLE_MODEL="gpt-5.6-sol"\n'
} >> "$TMP/env-luna-only"
chmod 600 "$TMP/env-luna-only"
"$ROOT/bin/harness-check-env" "$TMP/env-luna-only" > "$TMP/luna-only-check.out"
grep -q '^Model policy: luna_only$' "$TMP/luna-only-check.out"
grep -q '^Escalation policy: decompose$' "$TMP/luna-only-check.out"
grep -q '^Manager model: gpt-5.6-luna (high)$' "$TMP/luna-only-check.out"
grep -q '^Decomposition model: gpt-5.6-sol (high)$' "$TMP/luna-only-check.out"
grep -q '^Terra leaf route: disabled by Luna-only policy$' "$TMP/luna-only-check.out"
MOCK_MODE=arg_capture "$ROOT/bin/codex-exec-jsonl" "$TMP/env-luna-only" manager_review \
	gpt-5.6-luna "$prompt" "$TMP/luna-manager.jsonl" "$TMP/luna-manager.stderr" "$TMP/luna-manager.last"
grep -Fq -- '--model gpt-5.6-luna' "$TMP/luna-manager.last"
MOCK_MODE=arg_capture "$ROOT/bin/codex-exec-jsonl" "$TMP/env-luna-only" decomposition \
	gpt-5.6-sol "$prompt" "$TMP/sol-decomposition.jsonl" "$TMP/sol-decomposition.stderr" \
	"$TMP/sol-decomposition.last"
grep -Fq -- '--model gpt-5.6-sol' "$TMP/sol-decomposition.last"
set +e
MOCK_MODE=success "$ROOT/bin/codex-exec-jsonl" "$TMP/env-luna-only" decomposition \
	gpt-5.6-luna "$prompt" "$TMP/luna-reject-model.jsonl" "$TMP/luna-reject-model.stderr" \
	"$TMP/luna-reject-model.last" > "$TMP/luna-reject-model.out" 2>&1
luna_reject_model_status=$?
MOCK_MODE=success "$ROOT/bin/codex-exec-jsonl" "$TMP/env-luna-only" worker_terra \
	gpt-5.6-luna "$prompt" "$TMP/luna-reject-role.jsonl" "$TMP/luna-reject-role.stderr" \
	"$TMP/luna-reject-role.last" > "$TMP/luna-reject-role.out" 2>&1
luna_reject_role_status=$?
set -e
(( luna_reject_model_status != 0 ))
(( luna_reject_role_status != 0 ))
grep -Fq 'model policy rejected model gpt-5.6-luna for decomposition; expected gpt-5.6-sol' \
	"$TMP/luna-reject-model.out"
grep -Fq 'Luna-only policy rejected the worker_terra execution role' "$TMP/luna-reject-role.out"
rm -f "$TMP/state/projects/jsonltest/control/project-integrity-anomaly.md"

cp "$TMP/env-luna-only" "$TMP/env-luna-invalid-escalation"
printf 'export HARNESS_ESCALATION_POLICY="legacy"\n' >> "$TMP/env-luna-invalid-escalation"
chmod 600 "$TMP/env-luna-invalid-escalation"
set +e
"$ROOT/bin/harness-check-env" "$TMP/env-luna-invalid-escalation" > "$TMP/luna-invalid-escalation.out" 2>&1
luna_invalid_escalation_status=$?
set -e
(( luna_invalid_escalation_status != 0 ))
grep -Fq 'HARNESS_MODEL_POLICY=luna_only requires HARNESS_ESCALATION_POLICY=decompose' \
	"$TMP/luna-invalid-escalation.out"

# An executable Codex wrapper is not actually runnable when its env shebang
# runtime is absent. Service-like PATHs must fail at startup, while an explicit
# runtime prefix must make both validation and execution deterministic.
mkdir -p "$TMP/runtime"
cat > "$TMP/runtime/harness-test-runtime" <<'RUNTIME'
#!/usr/bin/env bash
exec /usr/bin/bash "$@"
RUNTIME
chmod +x "$TMP/runtime/harness-test-runtime"
cat > "$TMP/runtime-codex" <<RUNTIME_CODEX
#!/usr/bin/env harness-test-runtime
exec "$TMP/mock-codex" "\$@"
RUNTIME_CODEX
chmod +x "$TMP/runtime-codex"
cp "$TMP/env" "$TMP/env-runtime-missing"
{
	printf 'export MANAGER_CODEX_BIN="%s"\n' "$TMP/runtime-codex"
	printf 'export WORKER_CODEX_BIN="%s"\n' "$TMP/runtime-codex"
} >> "$TMP/env-runtime-missing"
chmod 600 "$TMP/env-runtime-missing"
set +e
PATH=/usr/bin:/bin "$ROOT/bin/harness-check-env" "$TMP/env-runtime-missing" > "$TMP/runtime-missing.out" 2>&1
runtime_missing_status=$?
set -e
(( runtime_missing_status != 0 ))
grep -q "runtime 'harness-test-runtime' is not available in PATH" "$TMP/runtime-missing.out"

cp "$TMP/env-runtime-missing" "$TMP/env-runtime-ok"
printf 'export HARNESS_RUNTIME_PATH_PREFIX="%s"\n' "$TMP/runtime" >> "$TMP/env-runtime-ok"
chmod 600 "$TMP/env-runtime-ok"
PATH=/usr/bin:/bin "$ROOT/bin/harness-check-env" "$TMP/env-runtime-ok" > "$TMP/runtime-ok.out"
grep -q "^Runtime PATH prefix: $TMP/runtime$" "$TMP/runtime-ok.out"
MOCK_MODE=success PATH=/usr/bin:/bin \
	"$ROOT/bin/codex-exec-jsonl" "$TMP/env-runtime-ok" worker gpt-5.5 "$prompt" \
	"$TMP/runtime-ok.jsonl" "$TMP/runtime-ok.stderr" "$TMP/runtime-ok.last"
grep -q '^classification=success$' "$TMP/runtime-ok.classification"

# Keep classification cases fast; the rate limiter has a focused cross-role
# assertion below.
printf 'export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"\n' >> "$TMP/env"

run_case() {
 local mode="$1" want="$2" status=0 base
 base="$TMP/$mode"
 set +e
 MOCK_MODE="$mode" "$ROOT/bin/codex-exec-jsonl" "$TMP/env" worker gpt-5.5 "$prompt" "$base.jsonl" "$base.stderr" "$base.last"
 status=$?
 set -e
 [[ "$(awk -F= '$1 == "classification" {print $2}' "$base.classification")" == "$want" ]]
}
run_case success success
# Patch-only workers run in a non-repository scratch directory and therefore
# must explicitly waive Codex's Git worktree startup check.
printf 'CONTEXT_CLOSURE_MODE=patch_only\nPATCH_ONLY_EXECUTION=1\nTASK_ID=001\n' > "$TMP/patch-only-prompt"
MOCK_MODE=arg_capture "$ROOT/bin/codex-exec-jsonl" "$TMP/env" worker_luna gpt-5.5 \
	"$TMP/patch-only-prompt" "$TMP/patch-only.jsonl" "$TMP/patch-only.stderr" "$TMP/patch-only.last"
grep -q -- '--skip-git-repo-check' "$TMP/patch-only.last"
# Project patch-only policy can retain normal bounded repository access for a
# zero-write verification leaf; only the launcher's effective decision isolates
# the process in the tool-less scratch directory.
printf 'CONTEXT_CLOSURE_MODE=patch_only\nPATCH_ONLY_EXECUTION=0\nTASK_ID=002\n' > "$TMP/verification-prompt"
MOCK_MODE=arg_capture "$ROOT/bin/codex-exec-jsonl" "$TMP/env" worker_luna gpt-5.5 \
	"$TMP/verification-prompt" "$TMP/verification.jsonl" "$TMP/verification.stderr" "$TMP/verification.last"
! grep -q -- '--skip-git-repo-check' "$TMP/verification.last"
# Durable capsule paths named by a manager prompt are also exported into its
# shell, preventing repeated harness-state path discovery.
printf 'REVIEW_CONTEXT_CAPSULE_FILE=%s\nRESULT_FILE=%s\n' "$TMP/review-capsule.md" "$TMP/result.md" > "$TMP/env-capture-prompt"
MOCK_MODE=env_capture "$ROOT/bin/codex-exec-jsonl" "$TMP/env" manager_review gpt-5.5 \
	"$TMP/env-capture-prompt" "$TMP/env-capture.jsonl" "$TMP/env-capture.stderr" "$TMP/env-capture.last"
grep -Fqx "$TMP/review-capsule.md" "$TMP/env-capture.last"
grep -Fqx "$TMP/result.md" "$TMP/env-capture.last"
run_case failed turn_failed
run_case error error_event
run_case invalid json_event_parse_failure
run_case empty empty_final_output
run_case nonzero process_nonzero_exit
run_case stderr_progress success
grep -q progress "$TMP/stderr_progress.stderr"
run_case benign_blocked_text success
run_case refusal model_refusal_or_blocked_content
run_case cyber_flag model_refusal_or_blocked_content
run_case idle idle_timeout
run_case wall wall_clock_timeout
run_case partial partial_edit_failure
# Editing a path that was already dirty before invocation must still count as
# this invocation's source movement. A porcelain path-set hash cannot observe
# this transition; the content-aware workspace fingerprint can.
printf 'preexisting dirty state\n' >> "$TMP/repo/tracked.txt"
run_case partial_already_dirty partial_edit_failure
grep -q '^partial_edits=1$' "$TMP/partial_already_dirty.classification"
before_fingerprint="$(awk -F= '$1=="workspace_fingerprint_before" {print $2}' "$TMP/partial_already_dirty.classification")"
after_fingerprint="$(awk -F= '$1=="workspace_fingerprint_after" {print $2}' "$TMP/partial_already_dirty.classification")"
[[ "$before_fingerprint" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$after_fingerprint" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$before_fingerprint" != "$after_fingerprint" ]]
run_case capacity_code provider_transient_error
grep -q '^provider_code=model_capacity$' "$TMP/capacity_code.classification"
run_case capacity_text provider_transient_error
run_case quota_code provider_quota_exhausted
run_case quota_text provider_quota_exhausted
run_case rate_status provider_transient_error
grep -q '^http_status=429$' "$TMP/rate_status.classification"
run_case network_stderr provider_transient_error
run_case auth_code terminal_authentication_error
run_case success_warning success

# A single still-running agent is stopped before it can hide an unbounded
# internal loop behind one supervisor invocation. The root is durably paused
# and the machine-readable classification records the tripped guard.
resource_prompt="$TMP/resource-prompt"
printf 'TASK_ID=resource-root\nTASK_ROOT=resource-root\n' > "$resource_prompt"
cp "$TMP/env" "$TMP/env-resource"
printf 'export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="3"\n' >> "$TMP/env-resource"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-resource" worker gpt-5.5 \
	"$resource_prompt" "$TMP/item-loop.jsonl" "$TMP/item-loop.stderr" "$TMP/item-loop.last"
item_status=$?
set -e
(( item_status != 0 ))
grep -q '^classification=agent_item_budget_exceeded$' "$TMP/item-loop.classification"
grep -q '^resource_guard=ITEM_LIMIT$' "$TMP/item-loop.classification"
grep -q 'agent invocation resource circuit breaker: live item-start budget reached' \
	"$TMP/state/projects/jsonltest/control/progress/jsonltest-task-resource-root.needs-human.md"

# A measured leaf tightens the global action ceiling to its own Sol-authored
# upper bound. Predicted semantic actions receive bounded JSONL protocol
# headroom and stop only after that measured allowance is exceeded.
cp "$TMP/env" "$TMP/env-measured-leaf"
printf 'export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="100"\n' >> "$TMP/env-measured-leaf"
measured_prompt="$TMP/measured-leaf-prompt"
printf 'TASK_ID=measured-root\nTASK_ROOT=measured-root\nEXPECTED_MAX_AGENT_ACTIONS=2\nEFFECTIVE_P95_TOKENS=100000\n' > "$measured_prompt"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-measured-leaf" worker gpt-5.5 \
	"$measured_prompt" "$TMP/measured-item-loop.jsonl" "$TMP/measured-item-loop.stderr" "$TMP/measured-item-loop.last"
measured_item_status=$?
set -e
(( measured_item_status != 0 ))
grep -q '^classification=agent_item_budget_exceeded$' "$TMP/measured-item-loop.classification"
grep -q '^item_limit=9$' "$TMP/measured-item-loop.classification"
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-measured-root.needs-human.md" \
	"$TMP/state/projects/jsonltest/control/progress/jsonltest-task-measured-root.token-usage-anomaly.md"

# Manager-remediation is a Terra-routed implementation leaf, so it inherits
# the same measured action ceiling and leaf-goal handoff semantics as a worker.
manager_remediation_prompt="$TMP/manager-remediation-measured-prompt"
printf 'TASK_ID=manager-remediation-root\nTASK_ROOT=manager-remediation-root\nWORKER_GOAL_MODE=1\nEXPECTED_MAX_AGENT_ACTIONS=2\nEXPECTED_MAX_IMPLEMENTATION_FILES=1\nEFFECTIVE_P95_TOKENS=100000\n' \
	> "$manager_remediation_prompt"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-measured-leaf" \
	manager_remediation gpt-5.5 "$manager_remediation_prompt" \
	"$TMP/manager-remediation-item-loop.jsonl" \
	"$TMP/manager-remediation-item-loop.stderr" \
	"$TMP/manager-remediation-item-loop.last"
manager_remediation_status=$?
set -e
(( manager_remediation_status != 0 ))
grep -q '^classification=agent_item_budget_exceeded$' \
	"$TMP/manager-remediation-item-loop.classification"
grep -q '^item_limit=13$' "$TMP/manager-remediation-item-loop.classification"
grep -q '^processed_token_limit=150000$' \
	"$TMP/manager-remediation-item-loop.classification"
[[ ! -e "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-manager-remediation-root.needs-human.md" ]]
[[ ! -e "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-manager-remediation-root.token-usage-anomaly.md" ]]

# Reviews have a tighter role-specific action budget. A review loop is a token
# anomaly requiring inspection, not a product/authorization decision.
cp "$TMP/env" "$TMP/env-review-items"
printf 'export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="80"\n' >> "$TMP/env-review-items"
printf 'export HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION="3"\n' >> "$TMP/env-review-items"
review_resource_prompt="$TMP/review-resource-prompt"
printf 'TASK_ID=review-resource\nTASK_ROOT=review-resource\n' > "$review_resource_prompt"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-review-items" manager_review gpt-5.5 \
	"$review_resource_prompt" "$TMP/review-item-loop.jsonl" "$TMP/review-item-loop.stderr" \
	"$TMP/review-item-loop.last"
review_item_status=$?
set -e
(( review_item_status != 0 ))
grep -q '^classification=agent_item_budget_exceeded$' "$TMP/review-item-loop.classification"
grep -q '^resource_guard=ITEM_LIMIT$' "$TMP/review-item-loop.classification"
[[ -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-review-resource.token-usage-anomaly.md" ]]
[[ ! -e "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-review-resource.needs-human.md" ]]
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-review-resource.token-usage-anomaly.md"

# Replanning has the same bounded-planning semantics as review. A replan that
# keeps revising a rejected publication is a token anomaly, not a human product
# decision, and receives its own role-specific action ceiling.
cp "$TMP/env" "$TMP/env-replan-items"
printf 'export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="80"\n' >> "$TMP/env-replan-items"
printf 'export HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION="3"\n' >> "$TMP/env-replan-items"
replan_resource_prompt="$TMP/replan-resource-prompt"
printf 'TASK_ID=replan-resource\nTASK_ROOT=replan-resource\n' > "$replan_resource_prompt"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-replan-items" manager_replan gpt-5.5 \
	"$replan_resource_prompt" "$TMP/replan-item-loop.jsonl" "$TMP/replan-item-loop.stderr" \
	"$TMP/replan-item-loop.last"
replan_item_status=$?
set -e
(( replan_item_status != 0 ))
grep -q '^classification=agent_item_budget_exceeded$' "$TMP/replan-item-loop.classification"
grep -q '^item_limit=3$' "$TMP/replan-item-loop.classification"
[[ -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-replan-resource.token-usage-anomaly.md" ]]
[[ ! -e "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-replan-resource.needs-human.md" ]]
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-replan-resource.token-usage-anomaly.md"

# Model policy never weakens investigation fuses. A Luna-only manager replan
# crossing the same resource boundary must publish the same durable anomaly
# and suppress subsequent project agent launches.
cp "$TMP/env-replan-items" "$TMP/env-replan-items-luna"
printf 'export HARNESS_MODEL_POLICY="luna_only"\n' >> "$TMP/env-replan-items-luna"
printf 'export MANAGER_MODEL="gpt-5.6-luna"\nexport DECOMPOSITION_MODEL="gpt-5.6-luna"\nexport CONVERGENCE_MODEL="gpt-5.6-luna"\nexport ORACLE_MODEL="gpt-5.6-luna"\nexport WORKER_MODEL="gpt-5.6-luna"\nexport LUNA_WORKER_MODEL="gpt-5.6-luna"\nexport TERRA_WORKER_MODEL="gpt-5.6-luna"\nexport HARNESS_ESCALATION_POLICY="decompose"\n' \
	>> "$TMP/env-replan-items-luna"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-replan-items-luna" \
	manager_replan gpt-5.6-luna "$replan_resource_prompt" \
	"$TMP/replan-item-loop-luna.jsonl" "$TMP/replan-item-loop-luna.stderr" \
	"$TMP/replan-item-loop-luna.last"
luna_replan_item_status=$?
set -e
(( luna_replan_item_status != 0 ))
grep -q '^classification=agent_item_budget_exceeded$' \
	"$TMP/replan-item-loop-luna.classification"
[[ -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-replan-resource.token-usage-anomaly.md" ]]
if MOCK_MODE=success "$ROOT/bin/codex-exec-jsonl" "$TMP/env-replan-items-luna" \
	worker gpt-5.6-luna "$prompt" "$TMP/anomaly-interlock-luna.jsonl" \
	"$TMP/anomaly-interlock-luna.stderr" "$TMP/anomaly-interlock-luna.last" \
	>"$TMP/anomaly-interlock-luna.out" 2>"$TMP/anomaly-interlock-luna.err"; then
	printf 'Luna-only policy bypassed an unresolved investigation fuse\n' >&2
	exit 1
fi
grep -q 'project has an unresolved TOKEN_USAGE_ANOMALY' \
	"$TMP/anomaly-interlock-luna.err"
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-replan-resource.token-usage-anomaly.md"

# A leaf-goal guard closes one semantic episode in worker-invoke-task. It must
# not be mislabeled as a human authorization/secret/external-state dependency.
goal_resource_prompt="$TMP/goal-resource-prompt"
printf 'TASK_ID=goal-resource\nTASK_ROOT=goal-resource\nWORKER_GOAL_MODE=1\n' > "$goal_resource_prompt"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-resource" worker gpt-5.5 \
	"$goal_resource_prompt" "$TMP/goal-item-loop.jsonl" "$TMP/goal-item-loop.stderr" "$TMP/goal-item-loop.last"
goal_item_status=$?
set -e
(( goal_item_status != 0 ))
grep -q '^classification=agent_item_budget_exceeded$' "$TMP/goal-item-loop.classification"
[[ ! -e "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-goal-resource.needs-human.md" ]]
grep -q 'task=goal-resource.*kind=ITEM_LIMIT' \
	"$TMP/state/projects/jsonltest/logs/agent-resource-alarms.log"

# A fresh leaf receives completed predecessor reads as cached evidence. One
# exact repetition is warned, while a second is interrupted before it consumes
# the rest of the worker item/token budget.
repeated_read_prompt="$TMP/repeated-read-prompt"
cat > "$repeated_read_prompt" <<'PROMPT'
TASK_ID=repeated-read-root
TASK_ROOT=repeated-read-root
WORKER_GOAL_MODE=1
## Immediate predecessor evidence

git_head_changed=0

## Command manifest

- command[1] exit=0 output_bytes=10: /bin/bash -lc 'rg -n target_symbol src/a.c | head -c 4096'

## Embedded bounded assignment
PROMPT
set +e
MOCK_MODE=repeated_read_once "$ROOT/bin/codex-exec-jsonl" "$TMP/env-resource" worker gpt-5.5 \
	"$repeated_read_prompt" "$TMP/repeated-read-once.jsonl" "$TMP/repeated-read-once.stderr" \
	"$TMP/repeated-read-once.last"
grep -q 'kind=REPEATED_EVIDENCE_WARNING' \
	"$TMP/state/projects/jsonltest/logs/agent-resource-alarms.log"
MOCK_MODE=repeated_read "$ROOT/bin/codex-exec-jsonl" "$TMP/env-resource" worker gpt-5.5 \
	"$repeated_read_prompt" "$TMP/repeated-read.jsonl" "$TMP/repeated-read.stderr" \
	"$TMP/repeated-read.last"
repeated_read_status=$?
set -e
(( repeated_read_status != 0 ))
grep -q '^classification=agent_repeated_evidence_command$' "$TMP/repeated-read.classification"
grep -q '^resource_guard=REPEATED_EVIDENCE_COMMAND$' "$TMP/repeated-read.classification"
[[ ! -e "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-repeated-read-root.needs-human.md" ]]

# Usage is authoritative only at turn completion, so a live transcript/context
# amplification estimate must stop a looping process before that event exists.
cp "$TMP/env" "$TMP/env-estimated-token"
printf 'export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="100"\n' >> "$TMP/env-estimated-token"
printf 'export HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION="1"\n' >> "$TMP/env-estimated-token"
estimated_prompt="$TMP/estimated-token-prompt"
printf 'TASK_ID=estimated-root\nTASK_ROOT=estimated-root\nWORKER_GOAL_MODE=1\n' > "$estimated_prompt"
set +e
MOCK_MODE=item_loop "$ROOT/bin/codex-exec-jsonl" "$TMP/env-estimated-token" worker gpt-5.5 \
	"$estimated_prompt" "$TMP/estimated-token.jsonl" "$TMP/estimated-token.stderr" "$TMP/estimated-token.last"
estimated_status=$?
set -e
(( estimated_status != 0 ))
grep -q '^classification=agent_estimated_token_budget_exceeded$' "$TMP/estimated-token.classification"
grep -q '^resource_guard=ESTIMATED_TOKEN_LIMIT$' "$TMP/estimated-token.classification"
grep -Eq '^estimated_processed_tokens=[1-9][0-9]*$' "$TMP/estimated-token.classification"
[[ -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-estimated-root.token-usage-anomaly.md" ]]
[[ ! -e "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-estimated-root.needs-human.md" ]]
set +e
MOCK_MODE=success "$ROOT/bin/codex-exec-jsonl" "$TMP/env-estimated-token" manager_review gpt-5.5 \
	"$prompt" "$TMP/anomaly-interlock.jsonl" "$TMP/anomaly-interlock.stderr" "$TMP/anomaly-interlock.last" \
	>"$TMP/anomaly-interlock.out" 2>"$TMP/anomaly-interlock-command.err"
interlock_status=$?
set -e
(( interlock_status != 0 ))
grep -q 'project has an unresolved TOKEN_USAGE_ANOMALY' "$TMP/anomaly-interlock-command.err"
test ! -s "$TMP/anomaly-interlock.jsonl"
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-estimated-root.token-usage-anomaly.md"

# One oversized command result is stopped before a subsequent reasoning item
# can repeatedly process it. This catches giant/minified source lines even
# when the command used a nominal line-count cap.
cp "$TMP/env" "$TMP/env-command-output"
printf 'export HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES="32"\n' >> "$TMP/env-command-output"
printf 'TASK_ID=command-output-root\nTASK_ROOT=command-output-root\nWORKER_GOAL_MODE=1\n' > "$TMP/command-output-prompt"
set +e
MOCK_MODE=command_output_heavy "$ROOT/bin/codex-exec-jsonl" "$TMP/env-command-output" worker gpt-5.5 \
	"$TMP/command-output-prompt" "$TMP/command-output.jsonl" "$TMP/command-output.stderr" "$TMP/command-output.last"
command_output_status=$?
set -e
(( command_output_status != 0 ))
grep -q '^classification=agent_command_output_budget_exceeded$' "$TMP/command-output.classification"
grep -q '^resource_guard=COMMAND_OUTPUT_LIMIT$' "$TMP/command-output.classification"
grep -q '^command_output_limit=32$' "$TMP/command-output.classification"
grep -Eq '^max_command_output_bytes=[3-9][0-9]+$' "$TMP/command-output.classification"
[[ -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-command-output-root.token-usage-anomaly.md" ]]
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-command-output-root.token-usage-anomaly.md"

# The generated manager review capsule may be larger than a worker source
# excerpt. Its separate limit prevents false anomalies without weakening the
# worker/build-output guard above.
cp "$TMP/env-command-output" "$TMP/env-manager-command-output"
printf 'export HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES="1024"\n' >> "$TMP/env-manager-command-output"
printf 'TASK_ID=manager-command-output-root\nTASK_ROOT=manager-command-output-root\n' > "$TMP/manager-command-output-prompt"
MOCK_MODE=command_output_completed "$ROOT/bin/codex-exec-jsonl" "$TMP/env-manager-command-output" manager_review gpt-5.5 \
	"$TMP/manager-command-output-prompt" "$TMP/manager-command-output.jsonl" \
	"$TMP/manager-command-output.stderr" "$TMP/manager-command-output.last"
grep -q '^classification=success$' "$TMP/manager-command-output.classification"
grep -q '^command_output_limit=1024$' "$TMP/manager-command-output.classification"

# Manager review/replan prompts promise the validation transcript boundary.
# The process monitor includes fixed headroom for harness-run-logged provenance
# around that payload, while the generic manager-command ceiling still wins.
cp "$TMP/env" "$TMP/env-manager-validation-output"
printf 'export HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES="8192"\nexport HARNESS_VALIDATION_OUTPUT_MAX_BYTES="32"\n' \
	>> "$TMP/env-manager-validation-output"
printf 'TASK_ID=manager-validation-output-root\nTASK_ROOT=manager-validation-output-root\n' \
	> "$TMP/manager-validation-output-prompt"
MOCK_MODE=command_output_completed "$ROOT/bin/codex-exec-jsonl" "$TMP/env-manager-validation-output" \
	manager_review gpt-5.5 "$TMP/manager-validation-output-prompt" \
	"$TMP/manager-validation-output.jsonl" "$TMP/manager-validation-output.stderr" \
	"$TMP/manager-validation-output.last"
grep -q '^classification=success$' \
	"$TMP/manager-validation-output.classification"
grep -q '^command_output_limit=4128$' "$TMP/manager-validation-output.classification"

printf 'TASK_ID=token-root\nTASK_ROOT=token-root\n' > "$resource_prompt"
printf 'export HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION="100"\n' >> "$TMP/env-resource"
set +e
MOCK_MODE=token_heavy "$ROOT/bin/codex-exec-jsonl" "$TMP/env-resource" worker gpt-5.5 \
	"$resource_prompt" "$TMP/token-heavy.jsonl" "$TMP/token-heavy.stderr" "$TMP/token-heavy.last"
token_status=$?
set -e
(( token_status != 0 ))
grep -q '^classification=agent_token_budget_exceeded$' "$TMP/token-heavy.classification"
grep -q '^invocation_processed_delta=110$' "$TMP/token-heavy.classification"
grep -q '^resource_guard=TOKEN_LIMIT$' "$TMP/token-heavy.classification"
[[ -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-token-root.token-usage-anomaly.md" ]]
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-token-root.token-usage-anomaly.md"

# The deterministic per-leaf p95 is also an invocation fuse even when the
# project-wide worker allowance is larger.
printf 'TASK_ID=predicted-token-root\nTASK_ROOT=predicted-token-root\nEXPECTED_MAX_AGENT_ACTIONS=8\nEFFECTIVE_P95_TOKENS=70\n' > "$TMP/predicted-token-prompt"
set +e
MOCK_MODE=token_heavy "$ROOT/bin/codex-exec-jsonl" "$TMP/env" worker gpt-5.5 \
	"$TMP/predicted-token-prompt" "$TMP/predicted-token.jsonl" "$TMP/predicted-token.stderr" "$TMP/predicted-token.last"
predicted_token_status=$?
set -e
(( predicted_token_status != 0 ))
grep -q '^classification=agent_token_budget_exceeded$' "$TMP/predicted-token.classification"
grep -q '^processed_token_limit=105$' "$TMP/predicted-token.classification"
rm -f "$TMP/state/projects/jsonltest/control/progress/jsonltest-task-predicted-token-root.token-usage-anomaly.md"

# Runtime worker budgets include generated prompt bytes and fixed provider
# framing for every expected model/tool round. This raises an implausibly tiny
# decomposition estimate without weakening the independent absolute fuse.
cp "$TMP/env" "$TMP/env-runtime-floor"
printf 'export HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND="100"\n' >> "$TMP/env-runtime-floor"
MOCK_MODE=success "$ROOT/bin/codex-exec-jsonl" "$TMP/env-runtime-floor" worker gpt-5.5 \
	"$TMP/predicted-token-prompt" "$TMP/runtime-floor.jsonl" "$TMP/runtime-floor.stderr" \
	"$TMP/runtime-floor.last"
runtime_floor="$(awk -F= '$1=="runtime_p95_floor" {print $2}' "$TMP/runtime-floor.classification")"
runtime_limit="$(awk -F= '$1=="processed_token_limit" {print $2}' "$TMP/runtime-floor.classification")"
(( runtime_floor > 70 ))
(( runtime_limit > 105 && runtime_limit <= 500000 ))
grep -q '^context_rounds=15$' "$TMP/runtime-floor.classification"

# The named specification-normalization phase has a separate bounded allowance
# while ordinary manager/worker turns retain the lower default limit.
phase_prompt="$TMP/specification-review-prompt"
printf 'AGENT_PHASE=specification_review\n' > "$phase_prompt"
printf 'export HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION="120"\n' >> "$TMP/env-resource"
MOCK_MODE=token_heavy "$ROOT/bin/codex-exec-jsonl" "$TMP/env-resource" manager_plan gpt-5.5 \
	"$phase_prompt" "$TMP/token-phase.jsonl" "$TMP/token-phase.stderr" "$TMP/token-phase.last"
grep -q '^classification=success$' "$TMP/token-phase.classification"
grep -q '^agent_phase=specification_review$' "$TMP/token-phase.classification"
grep -q '^processed_token_limit=120$' "$TMP/token-phase.classification"

# Candidate repair is still a global decomposition operation. It receives the
# decomposition allowance instead of the ordinary per-turn worker allowance.
repair_prompt="$TMP/decomposition-repair-prompt"
printf 'AGENT_PHASE=decomposition_repair\n' > "$repair_prompt"
printf 'export HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION="200"\n' >> "$TMP/env-resource"
MOCK_MODE=token_heavy "$ROOT/bin/codex-exec-jsonl" "$TMP/env-resource" decomposition gpt-5.5 \
	"$repair_prompt" "$TMP/decomposition-repair.jsonl" "$TMP/decomposition-repair.stderr" \
	"$TMP/decomposition-repair.last"
grep -q '^classification=success$' "$TMP/decomposition-repair.classification"
grep -q '^agent_phase=decomposition_repair$' "$TMP/decomposition-repair.classification"
grep -q '^processed_token_limit=200$' "$TMP/decomposition-repair.classification"

# One harness-start transaction has a hard process budget independent of the
# time-based limiter. Exhaustion must fail before the model executable starts.
startup_budget="$TMP/state/projects/jsonltest/control/test-startup-budget.env"
mkdir -p "$(dirname "$startup_budget")"
printf '%s\n' 'count=1' 'maximum=1' 'started_at=2026-01-01T00:00:00Z' > "$startup_budget"
set +e
MOCK_MODE=success HARNESS_START_AGENT_BUDGET_FILE="$startup_budget" \
	"$ROOT/bin/codex-exec-jsonl" "$TMP/env" manager_plan gpt-5.5 "$prompt" \
	"$TMP/budget.jsonl" "$TMP/budget.stderr" "$TMP/budget.last" \
	>"$TMP/budget.out" 2>"$TMP/budget-command.err"
budget_status=$?
set -e
(( budget_status != 0 ))
grep -q 'harness-start agent invocation budget exhausted (1/1)' "$TMP/budget-command.err"
test ! -s "$TMP/budget.jsonl"
grep -q 'STARTUP_AGENT_BUDGET_EXHAUSTED count=1 maximum=1 role=manager_plan' \
	"$TMP/state/projects/jsonltest/logs/events.log"

# One project-wide clock covers every role. An immediate manager launch after
# a worker launch must wait even though the role changed.
cp "$TMP/env" "$TMP/env-throttle"
printf 'export HARNESS_AGENT_MIN_INTERVAL_SECONDS="3"\n' >> "$TMP/env-throttle"
throttle_started="$(date +%s)"
MOCK_MODE=success "$ROOT/bin/codex-exec-jsonl" "$TMP/env-throttle" worker gpt-5.5 "$prompt" \
	"$TMP/throttle-worker.jsonl" "$TMP/throttle-worker.stderr" "$TMP/throttle-worker.last"
MOCK_MODE=success "$ROOT/bin/codex-exec-jsonl" "$TMP/env-throttle" manager_review gpt-5.5 "$prompt" \
	"$TMP/throttle-manager.jsonl" "$TMP/throttle-manager.stderr" "$TMP/throttle-manager.last"
throttle_elapsed=$(( $(date +%s) - throttle_started ))
(( throttle_elapsed >= 3 ))
grep -Eq 'AGENT_INVOCATION_THROTTLED role=manager_review wait_seconds=[1-3] min_interval_seconds=3' \
	"$TMP/state/projects/jsonltest/logs/events.log"
grep -Eq 'WARNING: attempt to launch "manager" process during the protected interval of 3 seconds; delaying [1-3] seconds; possible dead end \(role=manager_review\)\.' \
	"$TMP/state/projects/jsonltest/logs/agent-invocation-alerts.log"
grep -q '^role=manager_review$' \
	"$TMP/state/projects/jsonltest/control/agent-invocation-rate-limit.state"

# A durable harness transition (for example WAITING_DEPENDENCY) must stop the
# current model process without waiting for it to decide to end its turn.
stop_file="$TMP/stop-sentinel"
set +e
MOCK_MODE=stop_sentinel HARNESS_CODEX_STOP_FILE="$stop_file" \
	"$ROOT/bin/codex-exec-jsonl" "$TMP/env" worker gpt-5.5 "$prompt" \
	"$TMP/stop-sentinel.jsonl" "$TMP/stop-sentinel.stderr" "$TMP/stop-sentinel.last" &
stop_runner_pid=$!
set -e
sleep 1
: > "$stop_file"
set +e
wait "$stop_runner_pid"
stop_status=$?
set -e
(( stop_status != 0 ))
grep -q '^classification=harness_stop_requested$' "$TMP/stop-sentinel.classification"
grep -q '^stop_requested=1$' "$TMP/stop-sentinel.classification"
! pgrep -f "$TMP/mock-codex.*stop-sentinel" >/dev/null 2>&1
! git -C "$TMP/repo" diff --quiet --
printf 'Codex JSONL runner tests passed.\n'
