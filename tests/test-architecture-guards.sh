#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-architecture-guards.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\n" "$TEST_ROOT" >&2' EXIT
else
	trap 'rm -rf -- "$TEST_ROOT"' EXIT
fi

mkdir -p "$TEST_ROOT/repo/src" "$TEST_ROOT/repo/include" "$TEST_ROOT/repo/design/adr" \
	"$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home" "$TEST_ROOT/architecture"
printf 'Widget ownership is store-authoritative and widget values have one canonical representation.\n' > "$TEST_ROOT/repo/spec.md"
printf 'int widget_value(void) { return 0; }\n' > "$TEST_ROOT/repo/src/widget.c"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name test
git -C "$TEST_ROOT/repo" config user.email test@example.invalid
git -C "$TEST_ROOT/repo" add spec.md src/widget.c
git -C "$TEST_ROOT/repo" commit -qm seed

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT="archguard"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="$TEST_ROOT/repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export MANAGER_MODEL="gpt-5.6-terra"
export WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="100"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"

cat > "$TEST_ROOT/plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
contract	-	-	Define widget ownership contract	ADR and public contract exist	test -f design/adr/widget-ownership.md && test -f include/widget.h	design/adr/widget-ownership.md,include/widget.h	widget_value	CONTRACT_DESIGN	HIGH	TERRA
coding	-	contract	Implement canonical widget behavior	widget_value returns one	grep -q 'return 1' src/widget.c	src/widget.c	widget_value	LOCAL_IMPLEMENTATION	LOW	LUNA
PLAN
cat > "$TEST_ROOT/architecture/invariants.tsv" <<'TSV'
invariant_id	category	authority	severity	statement	scope	source_requirement	validation_kind	validation_ref	affected_nodes
INV-widget	CANONICAL_REPRESENTATION	SPECIFIED	CRITICAL	Widget values use one canonical representation.	include/widget.h,src/widget.c	spec.md:1	COMMAND	test -f include/widget.h	contract,coding
TSV
cat > "$TEST_ROOT/architecture/decisions.tsv" <<'TSV'
decision_id	status	producer_node	problem	chosen_contract	affected_interfaces	supersedes	evidence
ADR-widget	PROPOSED	contract	Choose widget ownership.	Store owns values and callers borrow views.	widget_value	-	design/adr/widget-ownership.md
TSV
cat > "$TEST_ROOT/architecture/edges.tsv" <<'TSV'
edge_id	producer_node	consumer_node	contract_artifact	public_symbols	ownership_model	representation	versioning_rule	compatibility_validation	decision_ids	invariant_ids
EDGE-widget	contract	coding	include/widget.h	widget_value	store-owned	canonical integer	additive only	test -f include/widget.h	ADR-widget	INV-widget
TSV
cat > "$TEST_ROOT/architecture/node-bindings.tsv" <<'TSV'
node_id	invariant_ids	consumes_decisions	produces_decisions	edge_contracts	health_gates
contract	INV-widget	-	ADR-widget	EDGE-widget	-
coding	INV-widget	ADR-widget	-	EDGE-widget	GATE-widget
TSV
cat > "$TEST_ROOT/architecture/health-gates.tsv" <<'TSV'
gate_id	trigger_node	depends_on	validation	severity	invariant_ids	edge_ids
GATE-widget	coding	contract	grep -q 'return 1' src/widget.c	CRITICAL	INV-widget	EDGE-widget
TSV
printf 'debt_id\tintroduced_by_task\tintroduced_by_commit\tcategory\taffected_invariants\tconsequence\tremediation_node\tseverity\texpires_at\tstatus\twaiver_authority\n' > "$TEST_ROOT/architecture/debt.tsv"

"$HARNESS_BIN/harness-init" "$TEST_ROOT/harness.env" >/dev/null
if "$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" "$TEST_ROOT/plan.tsv" >/dev/null 2>&1; then
	printf 'guarded plan initialized without an architecture registry\n' >&2
	exit 1
fi
"$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$TEST_ROOT/architecture" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" "$TEST_ROOT/plan.tsv" >/dev/null

write_task()
{
	local file="$1" task="$2" goal="$3" criterion="$4" leaf_type="$5" complexity="$6" route="$7"
	local depends="$8" deliverable="$9" evidence="${10}" validation="${11}" scope="${12}" decisions="${13}"
	local consumes="${14}" produces="${15}" gates="${16}"
	cat > "$file" <<TASK
# Leaf-Goal Task Assignment

Project: archguard
Task-ID: $task
Task-Root: $task
Starting-Progress: 0%
Status: READY
Execution-Mode: LEAF_GOAL
Goal-ID: $goal
Target-Criterion: $criterion
Goal-Success-Evidence: $evidence
Focused-Validation: $validation
Allowed-Scope: $scope
Baseline-Boundary: registered architecture boundary is not implemented
Hard-Block-Conditions: NONE
Leaf-Type: $leaf_type
Complexity-Class: $complexity
Worker-Route: $route
Depends-On: $depends
Deliverable: $deliverable
Required-Symbols: widget_value
Context-Paths: $scope
Architecture-Decisions: $decisions
Affected-Invariants: INV-widget
Consumed-Decisions: $consumes
Produced-Decisions: $produces
Edge-Contracts: EDGE-widget
Health-Gates: $gates
Expected-Max-Implementation-Files: 2
Expected-Max-Worker-Turns: 2
Root-Criterion: $criterion

## Objective

Complete the registered node.

## Acceptance criteria

- Registered evidence passes.

## Validation commands

\`\`\`text
$validation
\`\`\`
TASK
}

write_result()
{
	local file="$1" task="$2" goal="$3"
	cat > "$file" <<RESULT
# Task Result

Task-ID: $task
Status: COMPLETED
Goal-ID: $goal
Goal-Outcome: COMPLETE
Changed-Public-Symbols: widget_value
Changed-Representations: canonical-widget
Changed-Ownership: store-owned
Changed-Serialization: -
Changed-Dependencies: -
Affected-Invariants: INV-widget
Affected-Edges: EDGE-widget

## Summary

Implemented the bounded node.

## Modified files

- registered source files

## Implemented behavior

- Registered behavior exists.

## Validation performed

Focused validation passed.

## Deviations from assignment

None.

## Remaining concerns

None.

## Worker assessment

Ready for review.
RESULT
}

write_review()
{
	local file="$1" task="$2" criterion="$3" debt="$4"
	cat > "$file" <<REVIEW
# Manager Review Record

Task-ID: $task
Decision: ACCEPT
Progress-Percent: 100%
Impact-Assessment: PASS
Reviewed-Invariants: INV-widget
Reviewed-Edges: EDGE-widget
Debt-Recorded: $debt
Verified-Criterion: $criterion

## Specification comparison

The registered behavior matches the specification.

## Acceptance-criteria verification

- [PASS] registered criterion — direct source evidence

## Feature verification

- [PASS] bounded feature — focused behavior evidence

## Validation executed

- [PASS] focused command — exit status 0

## Scope and regression review

The declared architecture impact and source scope were reviewed.

## Conclusion

All required behavior was independently verified. Accept.
REVIEW
}

write_task "$TEST_ROOT/contract-task.md" 001 contract.goal contract.done CONTRACT_DESIGN HIGH TERRA - \
	'Define widget ownership contract' 'ADR and public contract exist' \
	'test -f design/adr/widget-ownership.md && test -f include/widget.h' \
	'design/adr/widget-ownership.md,include/widget.h' ADR-widget - ADR-widget -
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/contract-task.md" contract >/dev/null
worker_1="$("$HARNESS_BIN/harness-new-session" "$TEST_ROOT/harness.env" worker)"
"$HARNESS_BIN/worker-claim-task" "$TEST_ROOT/harness.env" 001 "$worker_1" >/dev/null
printf '# Widget ownership\n\nThe store owns values; callers borrow views.\n' > "$TEST_ROOT/repo/design/adr/widget-ownership.md"
printf 'int widget_value(void);\n' > "$TEST_ROOT/repo/include/widget.h"
printf 'Record the widget ownership contract.\n' > "$TEST_ROOT/contract-message.txt"
"$HARNESS_BIN/harness-commit-source" "$TEST_ROOT/harness.env" 001 "$worker_1" \
	"$TEST_ROOT/contract-message.txt" design/adr/widget-ownership.md include/widget.h >/dev/null
write_result "$TEST_ROOT/contract-result.md" 001 contract.goal
"$HARNESS_BIN/worker-complete-task" "$TEST_ROOT/harness.env" 001 "$worker_1" "$TEST_ROOT/contract-result.md" >/dev/null
"$HARNESS_BIN/manager-accept-architecture-decision" "$TEST_ROOT/harness.env" ADR-widget 001 \
	"$TEST_ROOT/repo/design/adr/widget-ownership.md" >/dev/null
write_review "$TEST_ROOT/contract-review.md" 001 contract.done NONE
"$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/contract-review.md" >/dev/null

write_task "$TEST_ROOT/coding-task.md" 002 coding.goal coding.done LOCAL_IMPLEMENTATION LOW LUNA contract \
	'Implement canonical widget behavior' 'widget_value returns one' "grep -q 'return 1' src/widget.c" \
	'src/widget.c' NONE ADR-widget - GATE-widget
"$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 002 "$TEST_ROOT/coding-task.md" coding >/dev/null
worker_2="$("$HARNESS_BIN/harness-new-session" "$TEST_ROOT/harness.env" worker)"
"$HARNESS_BIN/worker-claim-task" "$TEST_ROOT/harness.env" 002 "$worker_2" >/dev/null
printf 'int widget_value(void) { return 1; }\n' > "$TEST_ROOT/repo/src/widget.c"
printf 'Implement canonical widget behavior.\n' > "$TEST_ROOT/coding-message.txt"
commit_output="$("$HARNESS_BIN/harness-commit-source" "$TEST_ROOT/harness.env" 002 "$worker_2" \
	"$TEST_ROOT/coding-message.txt" src/widget.c)"
implementation_commit="$(awk -F= '$1=="COMMIT" {print $2}' <<< "$commit_output")"
write_result "$TEST_ROOT/coding-result.md" 002 coding.goal
"$HARNESS_BIN/worker-complete-task" "$TEST_ROOT/harness.env" 002 "$worker_2" "$TEST_ROOT/coding-result.md" >/dev/null

expires="$(date -u -d tomorrow +%Y-%m-%d)"
printf 'DEBT-widget\t002\t%s\tCANONICAL_REPRESENTATION\tINV-widget\tTemporary duplicate representation remains.\tcoding\tCRITICAL\t%s\tWAIVED\ttest-owner\n' \
	"$implementation_commit" "$expires" > "$TEST_ROOT/debt-row.tsv"
"$HARNESS_BIN/manager-record-debt" "$TEST_ROOT/harness.env" "$TEST_ROOT/debt-row.tsv" >/dev/null
write_review "$TEST_ROOT/coding-review.md" 002 coding.done DEBT-widget
if "$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" 002 "$TEST_ROOT/coding-review.md" >/dev/null 2>&1; then
	printf 'critical architecture debt did not block final acceptance\n' >&2
	exit 1
fi
printf 'Duplicate representation removed and focused gate passes.\n' > "$TEST_ROOT/debt-resolution.md"
"$HARNESS_BIN/manager-resolve-debt" "$TEST_ROOT/harness.env" DEBT-widget "$TEST_ROOT/debt-resolution.md" >/dev/null
"$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" 002 "$TEST_ROOT/coding-review.md" >/dev/null

project_dir="$TEST_ROOT/state/projects/archguard"
test -f "$project_dir/control/project.complete"
test "$(find "$project_dir/control/architecture/impacts" -name '*.impact.md' | wc -l)" -eq 2
grep -Eq $'^GATE-widget\tPASSED\t002\t' "$project_dir/control/architecture/health-ledger.tsv"
grep -Eq $'^GATE-widget\tFINAL_PASSED\tcompletion\t' "$project_dir/control/architecture/health-ledger.tsv"
grep -Eq $'^DEBT-widget\tRECORDED\t002\t' "$project_dir/control/architecture/debt-ledger.tsv"
grep -Eq $'^DEBT-widget\tRESOLVED\tmanager\t' "$project_dir/control/architecture/debt-ledger.tsv"
status_output="$("$HARNESS_BIN/harness-architecture-status" --details "$TEST_ROOT/harness.env")"
grep -Fqx 'Debt: 1 total, 0 unresolved critical, 0 expired' <<< "$status_output"
tree_output="$("$HARNESS_BIN/harness-decomposition-tree" --details --ascii "$TEST_ROOT/harness.env")"
grep -Fq 'invariants: INV-widget' <<< "$tree_output"
grep -Fq 'decisions: in=ADR-widget out=-' <<< "$tree_output"
metrics_output="$("$HARNESS_BIN/harness-decomposition-metrics" "$TEST_ROOT/harness.env")"
grep -Fqx $'planned_luna_coding_share_percent\t100.00' <<< "$metrics_output"
grep -Fqx $'architecture_health_gate_pass_percent\t100.00' <<< "$metrics_output"
grep -Fqx $'architecture_debt_open\t0' <<< "$metrics_output"

# A standalone test-only task receives a deterministic minimal architecture
# profile. It must not invent graph edges or decisions, and the complete task
# lifecycle must still pass the architecture review and final health gate.
MIN_ROOT="$TEST_ROOT/minimal"
mkdir -p "$MIN_ROOT/repo/src" "$MIN_ROOT/repo/tests" "$MIN_ROOT/manager-home" "$MIN_ROOT/worker-home"
printf 'Add a focused unit test proving value returns one.\n' > "$MIN_ROOT/repo/spec.md"
printf 'int value(void) { return 1; }\n' > "$MIN_ROOT/repo/src/value.c"
git -C "$MIN_ROOT/repo" init -q
git -C "$MIN_ROOT/repo" config user.name test
git -C "$MIN_ROOT/repo" config user.email test@example.invalid
git -C "$MIN_ROOT/repo" add spec.md src/value.c
git -C "$MIN_ROOT/repo" commit -qm seed
cat > "$MIN_ROOT/harness.env" <<ENV
export PROJECT="minimaltest"
export REPOSITORY="$MIN_ROOT/repo"
export SPECIFICATION="$MIN_ROOT/repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$MIN_ROOT/state"
export MANAGER_CODEX_HOME="$MIN_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$MIN_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export MANAGER_MODEL="gpt-5.6-terra"
export WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="100"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$MIN_ROOT/harness.env"
cat > "$MIN_ROOT/plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
tests	-	-	Add focused unit coverage for value	Unit test proves value returns one	bash tests/test_value.sh	tests/test_value.sh	value	TEST_IMPLEMENTATION	LOW	LUNA
PLAN
"$HARNESS_BIN/harness-init" "$MIN_ROOT/harness.env" >/dev/null
test ! -e "$MIN_ROOT/state/projects/minimaltest/control/architecture"
"$HARNESS_BIN/manager-init-project-plan" "$MIN_ROOT/harness.env" "$MIN_ROOT/plan.tsv" >/dev/null
min_project="$MIN_ROOT/state/projects/minimaltest"
grep -Fqx 'profile=minimal-single-node-test' "$min_project/control/architecture/profile.env"
"$HARNESS_BIN/harness-architecture-status" "$MIN_ROOT/harness.env" > "$MIN_ROOT/architecture-status.txt"
grep -Fqx 'Profile: minimal-single-node-test' "$MIN_ROOT/architecture-status.txt"
test "$(wc -l < "$min_project/control/architecture/decisions.tsv")" -eq 1
test "$(wc -l < "$min_project/control/architecture/edges.tsv")" -eq 1
test "$(wc -l < "$min_project/control/architecture/debt.tsv")" -eq 1
grep -Fqx $'tests\tINV-tests-test-obligation\t-\t-\t-\tGATE-tests-test-acceptance' \
	"$min_project/control/architecture/node-bindings.tsv"

cat > "$MIN_ROOT/task.md" <<'TASK'
# Leaf-Goal Task Assignment

Project: minimaltest
Task-ID: 001
Task-Root: 001
Starting-Progress: 0%
Status: READY
Execution-Mode: LEAF_GOAL
Goal-ID: tests.goal
Target-Criterion: tests.done
Goal-Success-Evidence: Unit test proves value returns one
Focused-Validation: bash tests/test_value.sh
Allowed-Scope: tests/test_value.sh
Baseline-Boundary: focused unit coverage is absent
Hard-Block-Conditions: NONE
Leaf-Type: TEST_IMPLEMENTATION
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: -
Deliverable: Add focused unit coverage for value
Required-Symbols: value
Context-Paths: tests/test_value.sh
Architecture-Decisions: NONE
Affected-Invariants: INV-tests-test-obligation
Consumed-Decisions: -
Produced-Decisions: -
Edge-Contracts: -
Health-Gates: GATE-tests-test-acceptance
Expected-Max-Implementation-Files: 1
Expected-Max-Worker-Turns: 1
Root-Criterion: tests.done

## Objective

Add the focused unit test.

## Acceptance criteria

- The unit test passes.

## Validation commands

```text
bash tests/test_value.sh
```
TASK
"$HARNESS_BIN/manager-publish-task" "$MIN_ROOT/harness.env" 001 "$MIN_ROOT/task.md" tests >/dev/null
min_worker="$("$HARNESS_BIN/harness-new-session" "$MIN_ROOT/harness.env" worker)"
"$HARNESS_BIN/worker-claim-task" "$MIN_ROOT/harness.env" 001 "$min_worker" >/dev/null
cat > "$MIN_ROOT/repo/tests/test_value.sh" <<'TEST'
#!/usr/bin/env bash
set -Eeuo pipefail
grep -Fq 'return 1' src/value.c
TEST
printf 'Add focused value unit coverage.\n' > "$MIN_ROOT/message.txt"
"$HARNESS_BIN/harness-commit-source" "$MIN_ROOT/harness.env" 001 "$min_worker" \
	"$MIN_ROOT/message.txt" tests/test_value.sh >/dev/null
cat > "$MIN_ROOT/result.md" <<'RESULT'
# Task Result

Task-ID: 001
Status: COMPLETED
Goal-ID: tests.goal
Goal-Outcome: COMPLETE
Changed-Public-Symbols: -
Changed-Representations: -
Changed-Ownership: -
Changed-Serialization: -
Changed-Dependencies: -
Affected-Invariants: INV-tests-test-obligation
Affected-Edges: -

## Summary

Added the focused unit test.

## Modified files

- tests/test_value.sh

## Implemented behavior

- The test verifies value returns one.

## Validation performed

bash tests/test_value.sh passed.

## Deviations from assignment

None.

## Remaining concerns

None.

## Worker assessment

Ready for review.
RESULT
"$HARNESS_BIN/worker-complete-task" "$MIN_ROOT/harness.env" 001 "$min_worker" "$MIN_ROOT/result.md" >/dev/null
cat > "$MIN_ROOT/review.md" <<'REVIEW'
# Manager Review Record

Task-ID: 001
Decision: ACCEPT
Progress-Percent: 100%
Impact-Assessment: PASS
Reviewed-Invariants: INV-tests-test-obligation
Reviewed-Edges: -
Debt-Recorded: NONE
Verified-Criterion: tests.done

## Specification comparison

The requested unit coverage exists.

## Acceptance-criteria verification

- [PASS] unit test exists — committed test source

## Feature verification

- [PASS] requested coverage — test observes the production behavior

## Validation executed

- [PASS] bash tests/test_value.sh — exit status 0

## Scope and regression review

Only the declared test file changed; no production contract changed.

## Conclusion

All requested test behavior was independently verified. Accept.
REVIEW
"$HARNESS_BIN/manager-accept-task" "$MIN_ROOT/harness.env" 001 "$MIN_ROOT/review.md" >/dev/null
test -f "$min_project/control/project.complete"
grep -Eq $'^GATE-tests-test-acceptance\tFINAL_PASSED\tcompletion\t' \
	"$min_project/control/architecture/health-ledger.tsv"
"$HARNESS_BIN/harness-decomposition-metrics" "$MIN_ROOT/harness.env" > "$MIN_ROOT/decomposition-metrics.tsv"
grep -Fqx $'architecture_profile\tminimal-single-node-test' "$MIN_ROOT/decomposition-metrics.tsv"

printf 'architecture guard tests passed\n'
