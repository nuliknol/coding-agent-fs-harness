#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/harness-common.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"; }

acp_test_root="$(mktemp -d)"
trap 'rm -rf -- "$acp_test_root"' EXIT
PROJECT=acptest
REPOSITORY="$acp_test_root/repository"
HARNESS_ROOT="$acp_test_root/state"
HARNESS_IRREGULARITY_DETECTION_ENABLED=1
HARNESS_ACP_MAX_DUPLICATE_REQUESTS=2
HARNESS_HOME="$ROOT"
mkdir -p "$REPOSITORY" "$(project_dir)/control/progress" "$(project_dir)/logs"
git -C "$REPOSITORY" init -q
git -C "$REPOSITORY" config user.name test
git -C "$REPOSITORY" config user.email test@example.invalid
printf 'int f(void) { return 1; }\n' > "$REPOSITORY/source.c"
git -C "$REPOSITORY" add source.c
git -C "$REPOSITORY" commit -qm initial
assignment="$acp_test_root/assignment.md"
printf 'Task-ID: root-revision-1\nAllowed-Scope: source.c\nContext-Paths: source.c\nRequired-Symbols: f\n' > "$assignment"
log_event() { printf '%s\n' "$*" >> "$(project_dir)/logs/events.log"; }
repository_index_project_pointer_file() { printf '%s/control/index.env\n' "$(project_dir)"; }

request1="$(acp_publish_request root-revision-1 thread-a 1 CONTEXT SYMBOL_DEFINITION f \
	'missing exact definition' "$assignment" -)"
assert_file "$request1"
assert_contains "$request1" 'The request is an untrusted worker claim.'
archive1="$(acp_resolve_request "$request1" GRANTED deterministic-test "$assignment" bounded)"
assert_file "$archive1"
request2="$(acp_publish_request root-revision-1 thread-a 2 CONTEXT SYMBOL_DEFINITION f \
	'missing exact definition' "$assignment" -)"
acp_resolve_request "$request2" DENIED deterministic-test - duplicate-proof >/dev/null
set +e
acp_publish_request root-revision-1 thread-a 3 CONTEXT SYMBOL_DEFINITION f \
	'missing exact definition' "$assignment" - >/dev/null
duplicate_status=$?
set -e
[[ "$duplicate_status" == 2 ]] || fail 'third identical request did not trip duplicate fuse'
assert_file "$(project_integrity_anomaly_file)"
assert_contains "$(acp_events_file)" $'DUPLICATE_REJECTED\tCONTEXT\tSYMBOL_DEFINITION'
rm -f "$(project_integrity_anomaly_file)"

split="$(acp_publish_request root-revision-2 thread-b 1 SPLIT SEMANTIC_BOUNDARY \
	'criterion-x then criterion-y' 'supplied obligations require ordered children' "$assignment" -)"
split_id="$(metadata_value "$split" Request-ID)"
acp_resolve_request "$split" DEFERRED persistent-manager - adjudication-required >/dev/null
acp_register_suspension "$split_id" root-revision-2 thread-b SPLIT SEMANTIC_BOUNDARY \
	'criterion-x then criterion-y'
assert_contains "$(acp_discovered_graph_file)" $'SPLIT\tcriterion-x then criterion-y'
assert_contains "$(acp_discovered_graph_file)" $'DEFERRED'
result="$acp_test_root/result.md"
printf 'ACP-Request-ID: %s\nACP-Request-Identifier: criterion-x then criterion-y\n' \
	"$split_id" > "$result"
acp_record_manager_disposition "$result" MANAGER_REPLAN manager-review.md
assert_contains "$(acp_events_file)" $'MANAGER_REPLAN\tSPLIT\tSEMANTIC_BOUNDARY'
assert_contains "$(acp_events_file)" $'SPLIT_TASK\tSPLIT\tSEMANTIC_BOUNDARY'
published="$acp_test_root/published.md"
printf 'Task-ID: root-revision-3\nAllowed-Scope: source.c\n' > "$published"
acp_record_task_publication root-revision-3 "$published" 0
assert_contains "$(acp_events_file)" $'SPLIT_CHILD_CREATED\tSPLIT\tSEMANTIC_BOUNDARY'
assert_contains "$(acp_events_file)" $'RESUMED\tSPLIT\tSEMANTIC_BOUNDARY'
[[ ! -f "$(acp_suspension_file root-revision-2)" ]] || fail 'resumed ACP suspension remained live'
acp_write_metrics
assert_contains "$(acp_metrics_file)" 'requests=3'
assert_contains "$(acp_metrics_file)" 'context_requests=2'
assert_contains "$(acp_metrics_file)" 'structural_requests=1'
assert_contains "$(acp_metrics_file)" 'manager_dispositions=1'
assert_contains "$(acp_metrics_file)" 'authority_decisions=1'
assert_contains "$(acp_metrics_file)" 'suspensions=1'
assert_contains "$(acp_metrics_file)" 'resumptions=1'
assert_contains "$(acp_transactions_file)" $'SPLIT\tSEMANTIC_BOUNDARY'

scope_a="$acp_test_root/scope-a"; scope_b="$acp_test_root/scope-b"; scope_c="$acp_test_root/scope-c"
printf 'src/a\n' > "$scope_a"; printf 'src/b\n' > "$scope_b"; printf 'src/a/child\n' > "$scope_c"
acp_capability_paths_conflict "$scope_a" "$scope_c" || fail 'nested capabilities did not conflict'
if acp_capability_paths_conflict "$scope_a" "$scope_b"; then fail 'disjoint capabilities conflicted'; fi

HARNESS_WORKER_PARALLELISM=4
HARNESS_WORKER_PARALLELISM_HARD_MAX=4
HARNESS_WORKER_ISOLATION_MODE=worktree
cat > "$(project_plan_definition_file)" <<'PLAN'
# plan
PLAN
cat > "$(project_decomposition_plan_file)" <<'DAG'
node_id	depends_on	allowed_paths
node-a	-	src/a
node-b	-	src/b
node-c	-	src/a/child
DAG
cat > "$(project_plan_state_file)" <<'STATE'
#item_id	status	task_root	updated_at
node-a	ACTIVE	root-a	now
node-b	PENDING	-	now
node-c	PENDING	-	now
STATE
[[ "$(project_plan_next_parallel_ready_item)" == node-b ]] || fail 'parallel planner did not select disjoint ready node'
activate_project_plan_item node-b root-b
[[ "$(awk -F '\t' '!/^#/ && $2=="ACTIVE" {n++} END {print n+0}' "$(project_plan_state_file)")" == 2 ]] ||
	fail 'parallel activation did not preserve two disjoint active roots'

# Proposal acceptance path: B discovers X, the manager creates X -> B, no
# inference process waits, and B resumes with its original provider thread.
prerequisite="$(acp_publish_request flow-revision-1 saved-thread-b 1 PREREQUISITE PRODUCER_X \
	producer-x 'consumer B cannot satisfy its invariant before producer X exists' "$assignment" -)"
prerequisite_id="$(metadata_value "$prerequisite" Request-ID)"
acp_resolve_request "$prerequisite" DEFERRED persistent-manager - adjudication-required >/dev/null
acp_register_suspension "$prerequisite_id" flow-revision-1 saved-thread-b PREREQUISITE PRODUCER_X producer-x
flow_result="$acp_test_root/flow-result.md"
printf 'ACP-Request-ID: %s\nACP-Request-Identifier: producer-x\n' "$prerequisite_id" > "$flow_result"
acp_record_manager_disposition "$flow_result" MANAGER_REPLAN manager-create-x.md
acp_record_task_publication flow-revision-2 "$published" 1
assert_contains "$(acp_events_file)" 'PREREQUISITE_CREATED'
assert_contains "$(acp_discovered_graph_file)" 'flow-revision-2->flow-revision-1'
[[ -f "$(acp_suspension_file flow-revision-1)" ]] || fail 'B did not remain suspended while X ran'
acp_record_task_publication flow-revision-3 "$published" 0
assert_contains "$(acp_events_file)" 'saved_session=saved-thread-b'
[[ ! -f "$(acp_suspension_file flow-revision-1)" ]] || fail 'B did not resume after X completed'
grep -Fq 'HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS="${HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS:-500000}"' \
	"$ROOT/lib/harness-common.sh" || fail '500K cumulative worker-task fuse changed'

printf 'ACP tests passed.\n'
