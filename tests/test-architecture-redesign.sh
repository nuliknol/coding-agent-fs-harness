#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-architecture-redesign.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\n" "$TEST_ROOT" >&2' EXIT
else
	trap 'rm -rf -- "$TEST_ROOT"' EXIT
fi

repo="$TEST_ROOT/repo"
state="$TEST_ROOT/state"
mkdir -p "$repo/src" "$repo/spec-review" "$TEST_ROOT/configs" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
cat > "$repo/spec.md" <<'EOF'
REQ-ARCH: publish ownership transfers atomically without changing the public compatibility contract.
EOF
cat > "$repo/src/architecture.c" <<'EOF'
/* Current design has split owners and no atomic publication boundary. */
int legacy_split_owner_publication(void) { return 0; }
EOF
git -C "$repo" init -q
git -C "$repo" add spec.md src/architecture.c
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed

env_file="$TEST_ROOT/configs/redesign.env"
cat > "$env_file" <<ENV
export PROJECT="redesign-test"
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
export MANAGER_MODEL="gpt-5.6-terra"
export DECOMPOSITION_MODEL="gpt-5.6-sol"
export WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export HARNESS_DECOMPOSITION_V2="1"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="1"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="1"
export HARNESS_ARCHITECTURE_GUARDS="1"
export HARNESS_MIN_LUNA_CODING_NODE_PERCENT="100"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$env_file"
"$HARNESS_BIN/harness-init" "$env_file" >/dev/null
project_dir="$state/projects/redesign-test"

spec_sha="$(sha256sum "$repo/spec.md" | awk '{print $1}')"
baseline="$(git -C "$repo" rev-parse HEAD)"
domain_sha="$(bash -c 'source "$1"; load_harness_env "$2"; domain_profiles_sha256' _ "$HARNESS_HOME/lib/harness-common.sh" "$env_file")"
cat > "$repo/spec-review/accepted.md" <<EOF
# Specification Review

Project: redesign-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Decision: ACCEPT
EOF
cat > "$repo/spec-review/obligations.tsv" <<'EOF'
obligation_id	authority	source_requirement	source_location	obligation_type	statement	observable_outcome	acceptance_authority
REQ-ARCH	SPECIFIED	REQ-ARCH	spec.md:1	CONTRACT	Atomic ownership publication	One atomic compatibility-preserving publication	SPECIFICATION
EOF
cat > "$repo/spec-review/relations.tsv" <<'EOF'
relation_id	relation_type	subject	object	authority	evidence
EOF
cat > "$repo/spec-review/facts.tsv" <<'EOF'
fact_id	kind	subject	value	evidence	authority	confidence
FACT-ARCH	OWNERSHIP	publication	split owners	src/architecture.c:1	OBSERVED	HIGH
EOF
printf 'path\tkind\n' > "$repo/spec-review/inventory.tsv"
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

report="$TEST_ROOT/redesign-report.md"
issues="$TEST_ROOT/redesign-issues.tsv"
brief="$TEST_ROOT/redesign-brief.md"
cat > "$report" <<EOF
# Architecture Redesign Required

Project: redesign-test
Specification-SHA256: $spec_sha
Repository-Baseline: $baseline
Decision: ARCHITECTURE_REDESIGN_REQUIRED

The required atomic transfer cannot be represented by the split-owner publication boundary.
EOF
cat > "$issues" <<'EOF'
issue_id	class	requirement_ids	source_locations	architecture_evidence	violated_boundary	why_no_bounded_dag	required_capability	acceptance_evidence	severity
ARCH-ownership	OWNERSHIP_MODEL_INCOMPATIBLE	REQ-ARCH	spec.md:1	src/architecture.c:1	Single authoritative publication owner	Every feature implementation path would preserve split authority or silently change the public contract.	Introduce one authoritative atomic publication boundary with compatibility-preserving migration.	A focused failure-atomicity test and compatibility smoke pass.	CRITICAL
EOF
cat > "$brief" <<'EOF'
# Architecture Redesign Specification

## ARCH-ownership

- Provide one authoritative owner and atomic publication boundary.
- Preserve the existing public compatibility contract.
- Supply migration, rollback, failure-atomicity, and compatibility evidence.
- Do not patch feature call sites around split ownership.
EOF

recorded="$($HARNESS_BIN/manager-record-architecture-redesign "$env_file" "$report" "$issues" "$brief")"
[[ "$recorded" =~ ^architecture-review/architecture-redesign-.*[.]md$ ]]
grep -Fqx 'status=ARCHITECTURE_REDESIGN_REQUIRED' "$project_dir/control/architecture-redesign-review.env"
test -f "$repo/$recorded"

status_output="$($HARNESS_BIN/harness-status --machine "$env_file" || true)"
grep -Fq "Architecture fit: ARCHITECTURE_REDESIGN_REQUIRED ($recorded)" <<< "$status_output"
grep -Fq "Project status: ARCHITECTURE_REDESIGN_REQUIRED. Foundational architecture cannot safely support the accepted specification; review $recorded before DAG registration." <<< "$status_output"
show_output="$($HARNESS_BIN/harness-show-redesign-request "$env_file")"
grep -Fq '# Architecture Redesign Action Required' <<< "$show_output"
grep -Fq '### ARCH-ownership — OWNERSHIP_MODEL_INCOMPATIBLE' <<< "$show_output"
grep -Fq 'Configure and run a separate Full harness' <<< "$show_output"
grep -Fq 'harness-start --background --force-decomposition' <<< "$show_output"
watch_output="$(HARNESS_WATCH_COLOR=always COLUMNS=120 LINES=30 "$HARNESS_BIN/harness-watch-many" --once "$TEST_ROOT/configs")"
grep -Eq $'^redesign-test +\| *0\| \033\[31mredesign\033\[0m +\|' <<< "$watch_output"

set +e
start_output="$($HARNESS_BIN/harness-start "$env_file" 2>&1)"
start_status=$?
set -e
(( start_status == 6 ))
grep -Fq "Architecture redesign required: $recorded" <<< "$start_output"
grep -Fq 'Action request: harness-show-redesign-request' <<< "$start_output"
test ! -f "$project_dir/control/project-decomposition-v2.tsv"

background_output="$($HARNESS_BIN/harness-start --background "$env_file")"
background_status_file="$(awk -F': ' '$1 == "Status" {print $2}' <<< "$background_output")"
for _ in $(seq 1 300); do
	background_state="$(awk -F= '$1 == "state" {print $2}' "$background_status_file" 2>/dev/null || true)"
	[[ "$background_state" == RUNNING || -z "$background_state" ]] || break
	sleep 0.01
done
grep -Fqx 'state=ARCHITECTURE_REDESIGN_REQUIRED' "$background_status_file"
grep -Fqx 'exit_status=6' "$background_status_file"

# Force is an auditable controlled-integration waiver. The mock model fails,
# but startup must persist the waiver and construct a Sol prompt that requires
# prerequisite Terra remediation and critical debt rather than dismissing it.
set +e
force_output="$($HARNESS_BIN/harness-start --force-decomposition "$env_file" 2>&1)"
force_status=$?
set -e
(( force_status != 0 ))
force_file="$project_dir/control/architecture-redesign-force.env"
grep -Fqx 'status=FORCE_DECOMPOSITION_AUTHORIZED' "$force_file"
waiver_id="$(awk -F= '$1 == "waiver_id" {print $2}' "$force_file")"
[[ "$waiver_id" =~ ^[0-9a-f]{64}$ ]]
critic_prompt="$project_dir/control/manager-decomposition-critic.prompt.md"
grep -Fqx 'FORCE_DECOMPOSITION=1' "$critic_prompt"
grep -Fq 'prerequisite Terra CROSS_COMPONENT_ARCHITECTURE nodes' "$critic_prompt"
grep -Fq 'one OPEN CRITICAL architecture debt row named DEBT-ARCH-... per ARCH-... issue' "$critic_prompt"

# Forced plans are machine checked. A feature node that does not depend on the
# required remediation node must be rejected even if Sol emitted plausible
# architecture prose and a matching debt row.
architecture="$TEST_ROOT/architecture"
mkdir -p "$architecture"
cat > "$architecture/invariants.tsv" <<'EOF'
invariant_id	category	authority	severity	statement	scope	source_requirement	validation_kind	validation_ref	affected_nodes
INV-atomic	OWNERSHIP	SPECIFIED	CRITICAL	Publication has one atomic owner.	src/architecture.c	REQ-ARCH	COMMAND	test -f src/architecture.c	archfix,feature
EOF
cat > "$architecture/decisions.tsv" <<'EOF'
decision_id	status	producer_node	problem	chosen_contract	affected_interfaces	supersedes	evidence
ADR-atomic	PROPOSED	archfix	Replace split publication ownership.	One owner publishes atomically.	legacy_split_owner_publication	-	design/adr/atomic-publication.md
EOF
cat > "$architecture/edges.tsv" <<'EOF'
edge_id	producer_node	consumer_node	contract_artifact	public_symbols	ownership_model	representation	versioning_rule	compatibility_validation	decision_ids	invariant_ids
EDGE-atomic	archfix	feature	decision:ADR-atomic	legacy_split_owner_publication	single-owner	compatible state	additive migration	test -f src/architecture.c	ADR-atomic	INV-atomic
EOF
cat > "$architecture/node-bindings.tsv" <<'EOF'
node_id	invariant_ids	consumes_decisions	produces_decisions	edge_contracts	health_gates
archfix	INV-atomic	-	ADR-atomic	EDGE-atomic	GATE-atomic
feature	INV-atomic	ADR-atomic	-	EDGE-atomic	-
EOF
cat > "$architecture/health-gates.tsv" <<'EOF'
gate_id	trigger_node	depends_on	validation	severity	invariant_ids	edge_ids
GATE-atomic	archfix	-	test -f src/architecture.c	CRITICAL	INV-atomic	-
EOF
cat > "$architecture/debt.tsv" <<EOF
debt_id	introduced_by_task	introduced_by_commit	category	affected_invariants	consequence	remediation_node	severity	expires_at	status	waiver_authority
DEBT-ARCH-ownership	decomposition	-	OWNERSHIP	INV-atomic	ARCH-ownership blocks safe feature decomposition.	archfix	CRITICAL	2099-12-31	OPEN	COMMAND_LINE_FORCE_DECOMPOSITION:$waiver_id
EOF
"$HARNESS_BIN/manager-init-architecture" "$env_file" "$architecture" >/dev/null
cat > "$TEST_ROOT/bad-plan.tsv" <<'EOF'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
archfix	-	-	Create atomic ownership architecture	ADR and focused gate pass	test -f src/architecture.c	src/architecture.c,design/adr/atomic-publication.md	legacy_split_owner_publication	CROSS_COMPONENT_ARCHITECTURE	HIGH	TERRA	1	1	1	0	1	1	6	200000	ARCHITECTURE_DECISION
feature	-	-	Implement atomic feature behavior	Focused feature test passes	test -f src/architecture.c	src/architecture.c	legacy_split_owner_publication	LOCAL_IMPLEMENTATION	LOW	LUNA	1	1	1	0	1	1	5	200000	-
EOF
cat > "$TEST_ROOT/coverage.tsv" <<'EOF'
obligation_id	node_ids	evidence_plan
REQ-ARCH	archfix,feature	Architecture remediation and dependent feature evidence
EOF
if "$HARNESS_BIN/manager-init-project-plan" "$env_file" "$TEST_ROOT/bad-plan.tsv" "$TEST_ROOT/coverage.tsv" \
	> "$TEST_ROOT/bad-plan.out" 2>&1; then
	printf 'forced feature plan bypassed required architecture remediation dependency\n' >&2
	exit 1
fi
grep -Fq 'coverage node feature for forced redesign issue ARCH-ownership does not depend on remediation node archfix' "$TEST_ROOT/bad-plan.out"

sed 's/^feature\t-\t-\t/feature\t-\tarchfix\t/' "$TEST_ROOT/bad-plan.tsv" > "$TEST_ROOT/good-plan.tsv"
"$HARNESS_BIN/manager-init-project-plan" "$env_file" "$TEST_ROOT/good-plan.tsv" "$TEST_ROOT/coverage.tsv" >/dev/null
grep -Eq $'^feature\tPENDING\t-' "$project_dir/control/project-plan-state.tsv"
grep -Fq 'Architecture fit: ACCEPTED' <<< "$($HARNESS_BIN/harness-status --machine "$env_file")"

# A repository-baseline change makes the old architecture decision stale. The
# next pre-DAG project would therefore receive a fresh specification and
# architecture review rather than reusing the old refusal or force waiver.
printf 'int redesigned_owner(void) { return 1; }\n' >> "$repo/src/architecture.c"
git -C "$repo" add src/architecture.c
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm redesign-baseline
if bash -c 'source "$1"; load_harness_env "$2"; architecture_redesign_matches_current_inputs' \
	_ "$HARNESS_HOME/lib/harness-common.sh" "$env_file"; then
	printf 'stale architecture redesign review remained current after baseline change\n' >&2
	exit 1
fi

printf 'architecture redesign gate tests passed\n'
