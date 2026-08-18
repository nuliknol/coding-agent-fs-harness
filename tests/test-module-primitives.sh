#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-module-primitives.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
timestamp_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
metadata_value() { awk -v field="$2" 'index($0, field ":") == 1 {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$1"; }

source "$ROOT/lib/harness-config.sh"
source "$ROOT/lib/harness-artifact-store.sh"
source "$ROOT/lib/harness-task-state.sh"
source "$ROOT/lib/harness-assignment.sh"

config="$TEST_ROOT/project.env"
printf 'PROJECT=test\n' > "$config"
chmod 600 "$config"
harness_config_require_secure_file "$config"
[[ "$HARNESS_CONFIG_CANONICAL_FILE" == "$config" ]]
[[ "$(harness_config_resolve_path "$TEST_ROOT" nested/file)" == "$TEST_ROOT/nested/file" ]]
harness_config_validate_reasoning_effort effort high
harness_config_validate_sandbox sandbox workspace-write
chmod 666 "$config"
if (harness_config_require_secure_file "$config") >/dev/null 2>&1; then
	printf 'configuration trust boundary accepted a writable file\n' >&2
	exit 1
fi
chmod 600 "$config"

state="$TEST_ROOT/state.env"
harness_artifact_write_kv "$state" 600 schema_version 1 status OBSERVE detail baseline
harness_artifact_compare_and_swap_kv "$state" status OBSERVE 600 \
	schema_version 1 status READY detail transitioned
[[ "$(harness_artifact_get "$state" status)" == READY ]]
if (harness_artifact_compare_and_swap_kv "$state" status OBSERVE 600 \
	schema_version 1 status FAILED detail stale) >/dev/null 2>&1; then
	printf 'artifact compare-and-swap accepted stale state\n' >&2
	exit 1
fi
[[ "$(harness_artifact_get "$state" status)" == READY ]]

harness_task_root_transition_is_legal ACTIVE NEEDS_REPLAN
if harness_task_root_transition_is_legal COMPLETE ACTIVE; then
	printf 'task transition table accepted a terminal rollback\n' >&2
	exit 1
fi
REPOSITORY="$TEST_ROOT/repository"
mkdir -p "$REPOSITORY/lib"
printf 'source\n' > "$REPOSITORY/lib/state.sh"
assignment="$TEST_ROOT/assignment.md"
printf 'Allowed-Scope: lib/state.sh\nObjective: old\n' > "$assignment"
harness_task_validate_repository_scope lib/state.sh "$assignment"
if (harness_task_validate_repository_scope '../escape' "$assignment") >/dev/null 2>&1; then
	printf 'task scope validator accepted repository escape\n' >&2
	exit 1
fi
harness_assignment_replace_metadata "$assignment" Objective new
grep -Fqx 'Objective: new' "$assignment"
ready="$TEST_ROOT/ready.md"
harness_assignment_publish "$assignment" "$ready"
[[ -f "$ready" && ! -e "$assignment" ]]

printf 'module primitive tests passed\n'

