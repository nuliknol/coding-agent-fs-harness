#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for module in harness-config harness-project-layout harness-artifact-store harness-task-state \
	harness-rebuild harness-assignment harness-worker-policy; do
	grep -Fq "/$module.sh\"" "$ROOT/lib/harness-common.sh"
done

[[ "$(rg -l '^project_dir\(\)' "$ROOT/lib")" == "$ROOT/lib/harness-project-layout.sh" ]]
[[ "$(rg -l '^task_root_id\(\)' "$ROOT/lib")" == "$ROOT/lib/harness-project-layout.sh" ]]
[[ "$(rg -l '^process_repository_index_refresh\(\)' "$ROOT/lib" "$ROOT/bin")" == \
	"$ROOT/lib/harness-index-maintenance.sh" ]]
[[ "$(rg -l '^harness_worker_select_execution_policy\(\)' "$ROOT/lib" "$ROOT/bin")" == \
	"$ROOT/lib/harness-worker-policy.sh" ]]

grep -Fq 'source "$SCRIPT_DIR/../lib/harness-index-generation.sh"' "$ROOT/bin/harness-index-repository"
grep -Fq 'source "$SCRIPT_DIR/../lib/harness-index-providers.sh"' "$ROOT/bin/harness-index-repository"
grep -Fq 'harness_supervisor_process_cycle' "$ROOT/bin/harness-supervisor"
! grep -Fq 'execution_model="$WORKER_MODEL"' "$ROOT/bin/worker-invoke-task"
! grep -Eq '^process_repository_index_refresh\(\)' "$ROOT/bin/harness-supervisor"

# Compatibility CLIs remain thin; provider and scorecard behavior is importable.
(( $(wc -l < "$ROOT/tools/normalize_repository_architecture.py") < 80 ))
(( $(wc -l < "$ROOT/tools/architecture_scorecard.py") < 80 ))
grep -Fq 'from architecture.providers import BashProvider, PythonProvider' \
	"$ROOT/tools/source_architecture.py"

# Rebuild state mutation is owned by the artifact store, never an ad hoc state
# redirection in the coordinator or command facade.
! grep -Eq '>[[:space:]]*"?\$\(architecture_rebuild_state_file' "$ROOT/lib/harness-rebuild.sh" \
	"$ROOT/bin/harness-architecture-rebuild"
grep -Fq 'harness_artifact_write_kv' "$ROOT/lib/harness-rebuild.sh"

printf 'module boundary tests passed\n'

