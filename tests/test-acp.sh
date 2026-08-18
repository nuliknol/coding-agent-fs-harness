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
assert_contains "$(acp_discovered_graph_file)" $'SPLIT\tcriterion-x then criterion-y'
assert_contains "$(acp_discovered_graph_file)" $'DEFERRED'
result="$acp_test_root/result.md"
printf 'ACP-Request-ID: %s\nACP-Request-Identifier: criterion-x then criterion-y\n' \
	"$split_id" > "$result"
acp_record_manager_disposition "$result" MANAGER_REPLAN manager-review.md
assert_contains "$(acp_events_file)" $'MANAGER_REPLAN\tSPLIT\tSEMANTIC_BOUNDARY'
acp_write_metrics
assert_contains "$(acp_metrics_file)" 'requests=3'
assert_contains "$(acp_metrics_file)" 'context_requests=2'
assert_contains "$(acp_metrics_file)" 'structural_requests=1'
assert_contains "$(acp_metrics_file)" 'manager_dispositions=1'
grep -Fq 'HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS="${HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS:-500000}"' \
	"$ROOT/lib/harness-common.sh" || fail '500K cumulative worker-task fuse changed'

printf 'ACP tests passed.\n'
