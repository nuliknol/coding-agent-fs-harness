#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"

bash -c 'set -Eeuo pipefail; source "$1/lib/harness-common.sh"; metadata_identifier_list_is_subset "DECISION-C,DECISION-A" "DECISION-A,DECISION-B,DECISION-C"' \
	_ "$HARNESS_HOME"
if bash -c 'set -Eeuo pipefail; source "$1/lib/harness-common.sh"; metadata_identifier_list_is_subset "DECISION-A,DECISION-X" "DECISION-A,DECISION-B,DECISION-C"' \
	_ "$HARNESS_HOME"; then
	printf 'architecture identifier subset helper accepted unauthorized authority\n' >&2
	exit 1
fi
bash -c 'set -Eeuo pipefail; source "$1/lib/harness-common.sh"; recovery_terra_architecture_implementation_allowed 0 TERRA CROSS_COMPONENT_ARCHITECTURE LOCAL_IMPLEMENTATION' \
	_ "$HARNESS_HOME"
if bash -c 'set -Eeuo pipefail; source "$1/lib/harness-common.sh"; recovery_terra_architecture_implementation_allowed 1 TERRA CROSS_COMPONENT_ARCHITECTURE LOCAL_IMPLEMENTATION' \
	_ "$HARNESS_HOME"; then
	printf 'resolved Terra architecture decision retained exceptional coding authority\n' >&2
	exit 1
fi
if bash -c 'set -Eeuo pipefail; source "$1/lib/harness-common.sh"; recovery_terra_architecture_implementation_allowed 0 LUNA LOCAL_IMPLEMENTATION LOCAL_IMPLEMENTATION' \
	_ "$HARNESS_HOME"; then
	printf 'ordinary Luna coding node received Terra architecture recovery authority\n' >&2
	exit 1
fi
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
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
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
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="100"
export HARNESS_PREFERRED_WORKER_ROUTE="LUNA"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/harness.env"

cat > "$TEST_ROOT/plan.tsv" <<'PLAN'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
contract	-	-	Define widget ownership contract	ADR and public contract exist	test -f design/adr/widget-ownership.md && printf "contract PASS\n"	design/adr/widget-ownership.md,include/widget.h	widget_value	CONTRACT_DESIGN	HIGH	TERRA
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
EDGE-widget	contract	coding	decision:ADR-widget	widget_value	store-owned	canonical integer	additive only	grep -q 'return 1' src/widget.c	ADR-widget	INV-widget
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
self_architecture="$TEST_ROOT/self-architecture"
cp -a "$TEST_ROOT/architecture" "$self_architecture"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "GATE-widget" {$3="contract,coding"} {print}' \
	"$self_architecture/health-gates.tsv" > "$self_architecture/health-gates.tsv.tmp"
mv "$self_architecture/health-gates.tsv.tmp" "$self_architecture/health-gates.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$self_architecture" \
	> "$TEST_ROOT/self-gate.out" 2>&1; then
	printf 'self-dependent architecture health gate was accepted\n' >&2
	exit 1
fi
grep -Fq 'health gate GATE-widget cannot depend on its own trigger node: coding' \
	"$TEST_ROOT/self-gate.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"
malformed_decision_architecture="$TEST_ROOT/malformed-decision-architecture"
cp -a "$TEST_ROOT/architecture" "$malformed_decision_architecture"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "ADR-widget" {$8=$8 "; Architecture fit ACCEPT; ARCH-WIDGET"} {print}' \
	"$malformed_decision_architecture/decisions.tsv" > "$malformed_decision_architecture/decisions.tsv.tmp"
mv "$malformed_decision_architecture/decisions.tsv.tmp" "$malformed_decision_architecture/decisions.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$malformed_decision_architecture" \
	> "$TEST_ROOT/malformed-decision.out" 2>&1; then
	printf 'decision evidence with an appended prose suffix was accepted\n' >&2
	exit 1
fi
grep -Fq 'evidence must be exactly one bounded repository-relative path' \
	"$TEST_ROOT/malformed-decision.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"
wrong_binding_architecture="$TEST_ROOT/wrong-binding-architecture"
cp -a "$TEST_ROOT/architecture" "$wrong_binding_architecture"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "contract" {$6="GATE-widget"} {print}' \
	"$wrong_binding_architecture/node-bindings.tsv" > "$wrong_binding_architecture/node-bindings.tsv.tmp"
mv "$wrong_binding_architecture/node-bindings.tsv.tmp" "$wrong_binding_architecture/node-bindings.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$wrong_binding_architecture" \
	> "$TEST_ROOT/wrong-binding.out" 2>&1; then
	printf 'health gate bound to a node other than its trigger was accepted\n' >&2
	exit 1
fi
grep -Fq 'health gate GATE-widget is bound to node contract but declares trigger node coding' \
	"$TEST_ROOT/wrong-binding.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"
prose_architecture="$TEST_ROOT/prose-architecture"
cp -a "$TEST_ROOT/architecture" "$prose_architecture"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "GATE-widget" {$4="Run the focused widget test and retain its output."} {print}' \
	"$prose_architecture/health-gates.tsv" > "$prose_architecture/health-gates.tsv.tmp"
mv "$prose_architecture/health-gates.tsv.tmp" "$prose_architecture/health-gates.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$prose_architecture" \
	> "$TEST_ROOT/prose-gate.out" 2>&1; then
	printf 'English prose in an executable architecture health gate was accepted\n' >&2
	exit 1
fi
grep -Fq 'health gate GATE-widget validation must be an executable shell command or a FOCUSED:, INCREMENTAL:, or CLEAN_GLOBAL: review descriptor; prose is not executable' \
	"$TEST_ROOT/prose-gate.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"
broad_architecture="$TEST_ROOT/broad-architecture"
cp -a "$TEST_ROOT/architecture" "$broad_architecture"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "GATE-widget" {$4="./widget-smoke --computing-all"} {print}' \
	"$broad_architecture/health-gates.tsv" > "$broad_architecture/health-gates.tsv.tmp"
mv "$broad_architecture/health-gates.tsv.tmp" "$broad_architecture/health-gates.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$broad_architecture" \
	> "$TEST_ROOT/broad-gate.out" 2>&1; then
	printf 'mandatory unrelated aggregate architecture gate was accepted\n' >&2
	exit 1
fi
grep -Fq 'uses a broad aggregate as a mandatory success condition' "$TEST_ROOT/broad-gate.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"
# A typed review descriptor is not an executable ctest command. Its explicit
# FOCUSED class must not be rejected merely because the prose names ctest.
if bash -c '
	source "$1/lib/harness-common.sh"
	source "$1/lib/harness-architecture.sh"
	architecture_validation_is_broad_aggregate "FOCUSED: ctest in the external build with exact selector ^IT-RCP-000$"
' _ "$HARNESS_HOME"; then
	printf 'focused ctest review descriptor was misclassified as a broad command\n' >&2
	exit 1
fi
broad_edge_architecture="$TEST_ROOT/broad-edge-architecture"
cp -a "$TEST_ROOT/architecture" "$broad_edge_architecture"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "EDGE-widget" {$9="./widget-smoke --computing-all"} {print}' \
	"$broad_edge_architecture/edges.tsv" > "$broad_edge_architecture/edges.tsv.tmp"
mv "$broad_edge_architecture/edges.tsv.tmp" "$broad_edge_architecture/edges.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$broad_edge_architecture" \
	> "$TEST_ROOT/broad-edge.out" 2>&1; then
	printf 'mandatory unrelated aggregate edge check was accepted\n' >&2
	exit 1
fi
grep -Fq 'edge EDGE-widget uses a broad aggregate as a mandatory success condition' \
	"$TEST_ROOT/broad-edge.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"

# Candidate preflight reports every unscoped broad validation at once so Sol
# does not spend one repair turn discovering each row serially.
batch_broad_plan="$TEST_ROOT/batch-broad-plan.tsv"
awk -F '\t' 'BEGIN {OFS=FS} NR > 1 {$6="./widget-smoke --computing-all"} {print}' \
	"$TEST_ROOT/plan.tsv" > "$batch_broad_plan"
batch_broad_architecture="$TEST_ROOT/batch-broad-architecture"
cp -a "$TEST_ROOT/architecture" "$batch_broad_architecture"
awk -F '\t' 'BEGIN {OFS=FS} NR > 1 {$9="./widget-smoke --computing-all"} {print}' \
	"$batch_broad_architecture/invariants.tsv" > "$batch_broad_architecture/invariants.tsv.tmp"
mv "$batch_broad_architecture/invariants.tsv.tmp" "$batch_broad_architecture/invariants.tsv"
awk -F '\t' 'BEGIN {OFS=FS} NR > 1 {$9="./widget-smoke --computing-all"} {print}' \
	"$batch_broad_architecture/edges.tsv" > "$batch_broad_architecture/edges.tsv.tmp"
mv "$batch_broad_architecture/edges.tsv.tmp" "$batch_broad_architecture/edges.tsv"
awk -F '\t' 'BEGIN {OFS=FS} NR > 1 {$4="./widget-smoke --computing-all"} {print}' \
	"$batch_broad_architecture/health-gates.tsv" > "$batch_broad_architecture/health-gates.tsv.tmp"
mv "$batch_broad_architecture/health-gates.tsv.tmp" "$batch_broad_architecture/health-gates.tsv"
if (
	source "$HARNESS_HOME/lib/harness-architecture.sh"
	architecture_report_unscoped_candidate_validations \
		"$batch_broad_plan" "$batch_broad_architecture"
) > "$TEST_ROOT/batch-broad.out" 2>&1; then
	printf 'batch broad-validation preflight accepted invalid candidate\n' >&2
	exit 1
fi
grep -Fq 'plan node contract focused_validation uses a broad aggregate' "$TEST_ROOT/batch-broad.out"
grep -Fq 'plan node coding focused_validation uses a broad aggregate' "$TEST_ROOT/batch-broad.out"
grep -Fq 'invariant INV-widget uses a broad aggregate' "$TEST_ROOT/batch-broad.out"
grep -Fq 'edge EDGE-widget uses a broad aggregate' "$TEST_ROOT/batch-broad.out"
grep -Fq 'health gate GATE-widget uses a broad aggregate' "$TEST_ROOT/batch-broad.out"

unsupported_artifact_architecture="$TEST_ROOT/unsupported-artifact-architecture"
cp -a "$TEST_ROOT/architecture" "$unsupported_artifact_architecture"
sed -i 's/decision:ADR-widget/architecture:ADR-widget/' \
	"$unsupported_artifact_architecture/edges.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" \
	"$unsupported_artifact_architecture" > "$TEST_ROOT/unsupported-artifact.out" 2>&1; then
	printf 'unsupported architecture contract-artifact namespace was accepted\n' >&2
	exit 1
fi
grep -Fq 'edge EDGE-widget uses unsupported contract artifact namespace: architecture:ADR-widget' \
	"$TEST_ROOT/unsupported-artifact.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"
unknown_decision_architecture="$TEST_ROOT/unknown-decision-architecture"
cp -a "$TEST_ROOT/architecture" "$unknown_decision_architecture"
sed -i 's/decision:ADR-widget/decision:ADR-missing/' \
	"$unknown_decision_architecture/edges.tsv"
if "$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" \
	"$unknown_decision_architecture" > "$TEST_ROOT/unknown-decision.out" 2>&1; then
	printf 'unknown decision contract artifact was accepted\n' >&2
	exit 1
fi
grep -Fq 'edge EDGE-widget contract artifact references unknown decision: ADR-missing' \
	"$TEST_ROOT/unknown-decision.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/architecture"
"$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/harness.env" "$TEST_ROOT/architecture" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/harness.env" "$TEST_ROOT/plan.tsv" >/dev/null

# Operators can replace a defective immutable registry only while stopped. The
# complete candidate is validated against the durable DAG, ledgers survive,
# and the prior registry remains recoverable.
revision_architecture="$TEST_ROOT/revision-architecture"
cp -a "$TEST_ROOT/architecture" "$revision_architecture"
sed -i 's/Widget values use one canonical representation\./Widget values retain one canonical representation./' \
	"$revision_architecture/invariants.tsv"
printf 'Correct a defective generated registry without resetting verified work.\n' > "$TEST_ROOT/revision-note.md"
decision_ledger="$TEST_ROOT/state/projects/archguard/control/architecture/decision-ledger.tsv"
ledger_before="$(sha256sum "$decision_ledger")"
cat > "$TEST_ROOT/state/projects/archguard/control/manager-plan-stalled.md" <<'STALL'
# Manager Planning Stalled

State-Fingerprint: sha256:stale-before-architecture-repair
STALL
revision_output="$("$HARNESS_BIN/harness-revise-architecture" "$TEST_ROOT/harness.env" \
	"$revision_architecture" "$TEST_ROOT/revision-note.md")"
grep -Fq 'Widget values retain one canonical representation.' \
	"$TEST_ROOT/state/projects/archguard/control/architecture/invariants.tsv"
[[ "$(sha256sum "$decision_ledger")" == "$ledger_before" ]]
revision_backup="${revision_output##*Previous registry: }"
test -f "$revision_backup/invariants.tsv"
test -f "$revision_backup/revision-note.md"
test ! -e "$TEST_ROOT/state/projects/archguard/control/manager-plan-stalled.md"
grep -Fq 'ARCHITECTURE_PLANNING_STALL_CLEARED reason=validated_registry_revision' \
	"$TEST_ROOT/state/projects/archguard/logs/events.log"

invalid_revision="$TEST_ROOT/invalid-revision-architecture"
cp -a "$revision_architecture" "$invalid_revision"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "contract" {$2="-"} {print}' \
	"$invalid_revision/node-bindings.tsv" > "$invalid_revision/node-bindings.tsv.tmp"
mv "$invalid_revision/node-bindings.tsv.tmp" "$invalid_revision/node-bindings.tsv"
installed_before="$(sha256sum "$TEST_ROOT/state/projects/archguard/control/architecture/invariants.tsv")"
if "$HARNESS_BIN/harness-revise-architecture" "$TEST_ROOT/harness.env" \
	"$invalid_revision" "$TEST_ROOT/revision-note.md" > "$TEST_ROOT/invalid-revision.out" 2>&1; then
	printf 'inconsistent architecture registry revision was accepted\n' >&2
	exit 1
fi
grep -Fq 'invariant INV-widget is absent from affected node binding contract' \
	"$TEST_ROOT/invalid-revision.out"
[[ "$(sha256sum "$TEST_ROOT/state/projects/archguard/control/architecture/invariants.tsv")" == "$installed_before" ]]

# Existing architecture state is revalidated before startup. This protects
# projects initialized by an older harness from launching any agent with a
# newly forbidden graph cycle.
stored_health_gates="$TEST_ROOT/state/projects/archguard/control/architecture/health-gates.tsv"
cp "$stored_health_gates" "$stored_health_gates.valid"
awk -F '\t' 'BEGIN {OFS=FS} $1 == "GATE-widget" {$3="contract,coding"} {print}' \
	"$stored_health_gates.valid" > "$stored_health_gates"
if "$HARNESS_BIN/harness-start" "$TEST_ROOT/harness.env" > "$TEST_ROOT/start-invalid.out" 2>&1; then
	printf 'harness-start accepted persisted self-dependent architecture\n' >&2
	exit 1
fi
grep -Fq 'health gate GATE-widget cannot depend on its own trigger node: coding' \
	"$TEST_ROOT/start-invalid.out"
test ! -e "$TEST_ROOT/state/projects/archguard/control/supervisor.pid"
test ! -e "$TEST_ROOT/state/projects/archguard/control/worker-supervisor.pid"
mv "$stored_health_gates.valid" "$stored_health_gates"

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

# Planning publication restores architecture-binding metadata from durable
# registries instead of spending model corrections on five exact TSV fields.
sed \
	-e 's/export PROJECT="archguard"/export PROJECT="archguardplanned"/' \
	-e "s|export HARNESS_ROOT=\"$TEST_ROOT/state\"|export HARNESS_ROOT=\"$TEST_ROOT/planned-state\"|" \
	"$TEST_ROOT/harness.env" > "$TEST_ROOT/planned-harness.env"
chmod 600 "$TEST_ROOT/planned-harness.env"
"$HARNESS_BIN/harness-init" "$TEST_ROOT/planned-harness.env" >/dev/null
"$HARNESS_BIN/manager-init-architecture" "$TEST_ROOT/planned-harness.env" \
	"$TEST_ROOT/architecture" >/dev/null
"$HARNESS_BIN/manager-init-project-plan" "$TEST_ROOT/planned-harness.env" \
	"$TEST_ROOT/plan.tsv" >/dev/null
write_task "$TEST_ROOT/planned-contract-source.md" invented contract.planned.goal contract.done \
	CONTRACT_DESIGN HIGH TERRA - 'Define widget ownership contract' \
	'ADR and public contract exist' \
	'test -f design/adr/widget-ownership.md && printf "contract PASS\n"' \
	'design/adr/widget-ownership.md,include/widget.h' ADR-widget - ADR-widget -
grep -Ev '^(Affected-Invariants|Consumed-Decisions|Produced-Decisions|Edge-Contracts|Health-Gates):' \
	"$TEST_ROOT/planned-contract-source.md" > "$TEST_ROOT/planned-contract.md"
sed -i 's/^Validation-Class: FOCUSED$/Validation-Class: FOCUSED_LOCAL/' \
	"$TEST_ROOT/planned-contract.md"
"$HARNESS_BIN/manager-publish-planned-task" "$TEST_ROOT/planned-harness.env" \
	"$TEST_ROOT/planned-contract.md" >/dev/null
planned_ready="$TEST_ROOT/planned-state/projects/archguardplanned/tasks/archguardplanned-task-contract.ready.md"
grep -Fqx 'Affected-Invariants: INV-widget' "$planned_ready"
grep -Fqx 'Consumed-Decisions: -' "$planned_ready"
grep -Fqx 'Produced-Decisions: ADR-widget' "$planned_ready"
grep -Fqx 'Edge-Contracts: EDGE-widget' "$planned_ready"
grep -Fqx 'Health-Gates: -' "$planned_ready"
grep -Fqx 'Validation-Class: FOCUSED' "$planned_ready"
grep -Fqx 'Focused-Validation: test -f design/adr/widget-ownership.md && printf "contract PASS\n"' \
	"$planned_ready"

write_task "$TEST_ROOT/contract-task.md" 001 contract.goal contract.done CONTRACT_DESIGN HIGH TERRA - \
	'Define widget ownership contract' 'ADR and public contract exist' \
	'test -f design/adr/widget-ownership.md && printf "contract PASS\n"' \
	'design/adr/widget-ownership.md,include/widget.h' ADR-widget - ADR-widget -
# One rejected publication reports the complete architecture metadata defect
# set so a bounded manager correction does not discover omissions serially.
grep -Ev '^(Affected-Invariants|Consumed-Decisions):' "$TEST_ROOT/contract-task.md" \
	> "$TEST_ROOT/contract-task-missing-metadata.md"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 001 \
	"$TEST_ROOT/contract-task-missing-metadata.md" contract \
	> "$TEST_ROOT/missing-metadata.out" 2>&1; then
	printf 'assignment with two missing architecture fields was accepted\n' >&2
	exit 1
fi
grep -Fq 'architecture-guarded assignment metadata has 2 defect(s)' \
	"$TEST_ROOT/missing-metadata.out"
grep -Fq 'Affected-Invariants must occur exactly once (found 0)' \
	"$TEST_ROOT/missing-metadata.out"
grep -Fq 'Consumed-Decisions must occur exactly once (found 0)' \
	"$TEST_ROOT/missing-metadata.out"
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
write_review "$TEST_ROOT/contract-review.md" 001 contract.done NONE
installed_edges="$TEST_ROOT/state/projects/archguard/control/architecture/edges.tsv"
cp "$installed_edges" "$installed_edges.valid"
sed 's/decision:ADR-widget/include\/missing-contract.h/' "$installed_edges.valid" > "$installed_edges"
if "$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" 001 \
	"$TEST_ROOT/contract-review.md" > "$TEST_ROOT/missing-producer-artifact.out" 2>&1; then
	printf 'producer acceptance ignored a missing outgoing contract artifact\n' >&2
	exit 1
fi
grep -Fq 'edge EDGE-widget contract artifact is absent: include/missing-contract.h' \
	"$TEST_ROOT/missing-producer-artifact.out"
grep -Fq $'ADR-widget\tACCEPTED\t001\t' \
	"$TEST_ROOT/state/projects/archguard/control/architecture/decision-ledger.tsv"
mv "$installed_edges.valid" "$installed_edges"
"$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" 001 "$TEST_ROOT/contract-review.md" >/dev/null
grep -Fqx 'validation_kind=DEFERRED_CUMULATIVE_INVARIANT' \
	"$TEST_ROOT/state/projects/archguard/control/architecture/health-logs/001-invariant-INV-widget.log"
printf '# Historical aborted revision\n' > \
	"$TEST_ROOT/state/projects/archguard/control/archguard-task-001-revision-99.abort.md"
! "$HARNESS_BIN/harness-status" "$TEST_ROOT/harness.env" | \
	grep -Fq 'Project status: ABORTED.'

write_task "$TEST_ROOT/coding-task.md" 002 coding.goal coding.done LOCAL_IMPLEMENTATION LOW LUNA contract \
	'Implement canonical widget behavior' 'widget_value returns one' "grep -q 'return 1' src/widget.c" \
	'src/widget.c' NONE ADR-widget - GATE-widget
mv "$TEST_ROOT/repo/design/adr/widget-ownership.md" \
	"$TEST_ROOT/repo/design/adr/widget-ownership.md.temporarily-absent"
if "$HARNESS_BIN/manager-publish-task" "$TEST_ROOT/harness.env" 002 \
	"$TEST_ROOT/coding-task.md" coding > "$TEST_ROOT/missing-consumer-artifact.out" 2>&1; then
	printf 'consumer scheduling ignored a missing decision evidence artifact\n' >&2
	exit 1
fi
grep -Fq 'edge EDGE-widget contract artifact is absent: design/adr/widget-ownership.md' \
	"$TEST_ROOT/missing-consumer-artifact.out"
mv "$TEST_ROOT/repo/design/adr/widget-ownership.md.temporarily-absent" \
	"$TEST_ROOT/repo/design/adr/widget-ownership.md"
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

# A manager may transactionally correct a defective registry while reviewing
# an idle committed result, even though both supervisors are alive. This is the
# recovery path for a gate error discovered only by focused acceptance.
project_dir="$TEST_ROOT/state/projects/archguard"
live_revision="$TEST_ROOT/live-review-revision"
cp -a "$project_dir/control/architecture" "$live_revision"
rm -rf "$live_revision/health-logs" "$live_revision/impacts" "$live_revision/revisions"
rm -f "$live_revision/decision-ledger.tsv" "$live_revision/health-ledger.tsv" "$live_revision/debt-ledger.tsv" "$live_revision/profile.env"
sed -i 's/Widget values retain one canonical representation\./Widget values retain exactly one canonical representation./' \
	"$live_revision/invariants.tsv"
printf 'Correct a registry defect discovered during the active manager review.\n' > "$TEST_ROOT/live-revision-note.md"
printf '%s\n' "$$" > "$project_dir/control/supervisor.pid"
printf '%s\n' "$$" > "$project_dir/control/worker-supervisor.pid"
live_revision_output="$("$HARNESS_BIN/manager-revise-architecture" "$TEST_ROOT/harness.env" 002 \
	"$live_revision" "$TEST_ROOT/live-revision-note.md")"
rm -f "$project_dir/control/supervisor.pid" "$project_dir/control/worker-supervisor.pid"
grep -Fq 'Architecture registry revised during review.' <<< "$live_revision_output"
grep -Fq 'Widget values retain exactly one canonical representation.' \
	"$project_dir/control/architecture/invariants.tsv"
test -f "$project_dir/control/archguard-task-002.architecture-revised-event"

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
printf 'int widget_value(void) { return 1; } /* uncommitted after review */\n' > \
	"$TEST_ROOT/repo/src/widget.c"
review_diff_output="$("$HARNESS_BIN/harness-review-diff" "$TEST_ROOT/harness.env" 002)"
grep -Fq 'Diff-Check-Status: 0' <<< "$review_diff_output"
grep -Fq '/* uncommitted after review */' <<< "$review_diff_output"
(( ${#review_diff_output} <= 32768 ))
test -s /tmp/archguard/archguard-task-002.manager-review-diff.log
"$HARNESS_BIN/manager-accept-task" "$TEST_ROOT/harness.env" 002 "$TEST_ROOT/coding-review.md" >/dev/null
test -z "$(git -C "$TEST_ROOT/repo" status --porcelain=v1 -- src/widget.c)"
grep -Eq $'^[0-9a-f]+\t002\tmanager-accept\t.*\tsrc/widget.c$' \
	"$project_dir/control/agent-commits.tsv"
grep -Fq '/* uncommitted after review */' "$TEST_ROOT/repo/src/widget.c"

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
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
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
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
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

# Oracle remediation extends the legacy plan, typed decomposition DAG, and
# architecture bindings as one validated transaction. A partial addendum must
# leave every durable registry unchanged.
sed -i 's/export MAX_ORACLE_RUNS="0"/export MAX_ORACLE_RUNS="1"/' "$TEST_ROOT/harness.env"
rm -f "$project_dir/control/project.complete"
mkdir -p "$project_dir/control/oracle"
printf '# Oracle Audit Pending\n\nProject: archguard\n\nAudit-ID: 1\n' > \
	"$project_dir/control/oracle/oracle.pending.md"
cat > "$TEST_ROOT/oracle-verdict.md" <<'VERDICT'
# Oracle Audit Verdict

Decision: FAIL

## Traceability verification

- [FAIL] widget remediation is missing

## Acceptance verification

- [FAIL] focused widget regression reproduces the defect

## Architecture verification

- [FAIL] INV-widget is not preserved

## Debt verification

- [PASS] no unresolved debt exists

## Findings

REQ-widget requires a bounded automatic repair.

## Conclusion

Automatic remediation is required.
VERDICT
cat > "$TEST_ROOT/oracle-partial-addendum.md" <<'ADDENDUM'
# Oracle Audit Addendum

Original-Requirement-ID: REQ-widget
Remediation-Authority: AUTOMATIC

## Harness plan items
ORACLE-widget-fix	Repair and regress the widget invariant

## Harness decomposition nodes
ORACLE-widget-fix	-	coding	Repair and regress the widget invariant	Focused regression proves the widget invariant	bash tests/test_widget.sh	src/widget.c,tests/test_widget.sh	widget_value	FOCUSED_BUG	LOW	LUNA
ADDENDUM
definition_before="$(sha256sum "$project_dir/control/project-plan.tsv")"
state_before="$(sha256sum "$project_dir/control/project-plan-state.tsv")"
dag_before="$(sha256sum "$project_dir/control/project-decomposition-v2.tsv")"
bindings_before="$(sha256sum "$project_dir/control/architecture/node-bindings.tsv")"
if "$HARNESS_BIN/oracle-complete-audit" "$TEST_ROOT/harness.env" \
	"$TEST_ROOT/oracle-verdict.md" "$TEST_ROOT/oracle-partial-addendum.md" \
	>"$TEST_ROOT/oracle-partial.out" 2>"$TEST_ROOT/oracle-partial.err"; then
	printf 'Partial architecture-guarded Oracle addendum was accepted.\n' >&2
	exit 1
fi
grep -q 'must include matching rows under ## Architecture node bindings' \
	"$TEST_ROOT/oracle-partial.err"
[[ "$(sha256sum "$project_dir/control/project-plan.tsv")" == "$definition_before" ]]
[[ "$(sha256sum "$project_dir/control/project-plan-state.tsv")" == "$state_before" ]]
[[ "$(sha256sum "$project_dir/control/project-decomposition-v2.tsv")" == "$dag_before" ]]
[[ "$(sha256sum "$project_dir/control/architecture/node-bindings.tsv")" == "$bindings_before" ]]
cat >> "$TEST_ROOT/oracle-partial-addendum.md" <<'ADDENDUM'

## Architecture node bindings
ORACLE-widget-fix	INV-widget	ADR-widget	-	-	-
ADDENDUM
"$HARNESS_BIN/oracle-complete-audit" "$TEST_ROOT/harness.env" \
	"$TEST_ROOT/oracle-verdict.md" "$TEST_ROOT/oracle-partial-addendum.md" >/dev/null
grep -Fqx $'ORACLE-widget-fix\tRepair and regress the widget invariant' \
	"$project_dir/control/project-plan.tsv"
grep -Eq $'^ORACLE-widget-fix\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"
grep -Fqx $'ORACLE-widget-fix\t-\tcoding\tRepair and regress the widget invariant\tFocused regression proves the widget invariant\tbash tests/test_widget.sh\tsrc/widget.c,tests/test_widget.sh\twidget_value\tFOCUSED_BUG\tLOW\tLUNA' \
	"$project_dir/control/project-decomposition-v2.tsv"
grep -Fqx $'ORACLE-widget-fix\tINV-widget\tADR-widget\t-\t-\t-' \
	"$project_dir/control/architecture/node-bindings.tsv"
"$HARNESS_BIN/harness-architecture-status" "$TEST_ROOT/harness.env" >/dev/null

# Review-scoped validation descriptors are manager-attested evidence classes,
# not shell commands named `FOCUSED:`.
bash -c '
	set -Eeuo pipefail
	source "$1/lib/harness-common.sh"
	source "$1/lib/harness-architecture.sh"
	load_harness_env "$2"
	architecture_run_command "FOCUSED: independently reviewed bounded evidence" "$3"
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env" "$TEST_ROOT/review-attested-gate.log"
grep -Fqx 'validation_kind=REVIEW_ATTESTED' "$TEST_ROOT/review-attested-gate.log"
grep -Fqx 'descriptor=FOCUSED: independently reviewed bounded evidence' \
	"$TEST_ROOT/review-attested-gate.log"

# An architecture leaf may derive a registered decision from the already
# accepted governing specification. It must not rewrite or recommit that
# immutable authority merely to satisfy producer provenance.
printf '%s\n' $'ADR-spec\tPROPOSED\tcoding\tBind the accepted widget authority.\tThe accepted specification remains authoritative.\twidget_value\t-\tspec.md' >> \
	"$project_dir/control/architecture/decisions.tsv"
cp "$project_dir/archive/archguard-task-002.result.md" \
	"$project_dir/results/archguard-task-002.result.md"
bash -c '
	set -Eeuo pipefail
	source "$1/lib/harness-common.sh"
	source "$1/lib/harness-architecture.sh"
	load_harness_env "$2"
	ensure_project
	architecture_accept_decision ADR-spec 002 "$REPOSITORY/spec.md"
' _ "$HARNESS_HOME" "$TEST_ROOT/harness.env"
grep -Fq $'ADR-spec\tACCEPTED\t002\t' \
	"$project_dir/control/architecture/decision-ledger.tsv"

printf 'architecture guard tests passed\n'
