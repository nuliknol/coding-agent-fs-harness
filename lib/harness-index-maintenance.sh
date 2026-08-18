#!/usr/bin/env bash

# Safe-boundary repository-index maintenance policy.  The supervisor supplies
# its project directory and retry fingerprint as process-local state.

process_repository_index_refresh()
{
	local pending failed task_id outcome reason current status log pointer recorded_revision source_revision
	pending="$dir/control/repository-index-refresh.pending.env"
	failed="$dir/control/repository-index-refresh.failed.md"
	if [[ ! -f "$pending" && "$HARNESS_REPOSITORY_INDEX_MODE" == required ]]; then
		pointer="$(repository_index_project_pointer_file)"
		recorded_revision="$(kv_file_value "$pointer" source_revision 2>/dev/null || true)"
		source_revision="$(repository_index_source_revision 2>/dev/null || true)"
		if [[ -z "$recorded_revision" || -z "$source_revision" || "$recorded_revision" != "$source_revision" ]]; then
			repository_index_refresh_at_safe_boundary supervisor REQUIRED_BARRIER
		fi
	fi
	[[ -f "$pending" ]] || return 0
	if repository_index_project_pointer_is_current; then
		rm -f "$pending" "$failed"
		repository_index_failed_fingerprint=""
		return 0
	fi
	if ! git -C "$REPOSITORY" diff --quiet --ignore-submodules -- ||
		! git -C "$REPOSITORY" diff --cached --quiet --ignore-submodules --; then
		return 0
	fi
	current="$({ sha256sum "$pending" "$HARNESS_ENV_FILE" "$HARNESS_HOME/VERSION"; git -C "$REPOSITORY" rev-parse HEAD; } | sha256sum | awk '{print "sha256:" $1}')"
	[[ "$current" != "$repository_index_failed_fingerprint" ]] || return 1
	task_id="$(kv_file_value "$pending" task_id 2>/dev/null || printf supervisor)"
	outcome="$(kv_file_value "$pending" outcome 2>/dev/null || printf SAFE_BOUNDARY)"
	reason="$(kv_file_value "$pending" reason 2>/dev/null || printf stale)"
	log="$dir/logs/repository-index-refresh-$task_id-$(timestamp_compact_utc).log"
	log_event "SUPERVISOR_REPOSITORY_INDEX_REFRESH_STARTED task=$task_id outcome=$outcome reason=$reason log=$log"
	if "$HARNESS_BIN/harness-index-repository" "$HARNESS_ENV_FILE" > "$log" 2>&1; then
		rm -f "$pending" "$failed"
		repository_index_failed_fingerprint=""
		log_event "REPOSITORY_INDEX_REFRESHED task=$task_id outcome=$outcome log=$log owner=supervisor"
		if "$HARNESS_BIN/harness-architecture-scorecard" "$HARNESS_ENV_FILE" \
			> "$dir/logs/architecture-scorecard-$task_id-$(timestamp_compact_utc).log" 2>&1; then
			:
		else
			log_event "ARCHITECTURE_SCORECARD_FAILED task=$task_id outcome=$outcome"
		fi
		return 0
	else
		status=$?
	fi
	repository_index_failed_fingerprint="$current"
	{
		printf '# Repository Index Refresh Failed\n\n'
		printf 'Project: %s\n\n' "$PROJECT"
		printf 'Task-ID: %s\n\n' "$task_id"
		printf 'Outcome: %s\n\n' "$outcome"
		printf 'State-Fingerprint: %s\n\n' "$current"
		printf 'Exit-Status: %s\n\n' "$status"
		printf 'Log: %s\n\n' "$log"
		printf 'The required index remains fail-closed. Correct the provider failure or restart the supervisor to retry this unchanged request.\n'
	} | harness_artifact_write_text "$failed" 600
	log_event "REPOSITORY_INDEX_REFRESH_FAILED task=$task_id outcome=$outcome status=$status log=$log owner=supervisor"
	return 1
}
