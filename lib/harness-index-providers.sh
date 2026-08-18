#!/usr/bin/env bash

repository_index_provider_ledger_initialize()
{
	local ledger="$1"
	[[ -f "$ledger" ]] || printf 'recorded_at\tprovider\tdigest\tstate\tdetail\n' |
		harness_artifact_write_text "$ledger" 600
}

repository_index_provider_record()
{
	local ledger="$1" provider="$2" digest="$3" state="$4" detail="$5"
	harness_artifact_append_tsv "$ledger" $'recorded_at\tprovider\tdigest\tstate\tdetail' \
		"$(timestamp_utc)" "$provider" "$digest" "$state" "$detail"
}

repository_index_provider_run()
{
	local provider="$1" log="$2" working_directory="$3"
	shift 3
	[[ "${1:-}" == -- ]] || die 'repository index provider runner requires -- before the command'
	shift
	(( $# > 0 )) || die "repository index provider command is empty: $provider"
	[[ -d "$working_directory" ]] || die "repository index provider working directory is missing: $working_directory"
	local status
	if (repository_index_close_inherited_lock_fds; cd "$working_directory"; exec "$@") > "$log" 2>&1; then
		return 0
	else
		status=$?
	fi
	printf 'provider=%s exit_status=%s command=%q\n' "$provider" "$status" "$1" >> "$log"
	return "$status"
}

repository_index_run_without_lifetime_locks()
{
	(repository_index_close_inherited_lock_fds; exec "$@")
}
