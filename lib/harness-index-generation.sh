#!/usr/bin/env bash

repository_index_generation_prepare_store()
{
	local repository_root="$1"
	mkdir -p "$repository_root/generations" "$repository_root/quarantine"
	chmod 700 "$repository_root" "$repository_root/generations" "$repository_root/quarantine"
}

repository_index_generation_acquire_lock()
{
	local repository_root="$1"
	exec 9>"$repository_root/index.lock"
	flock -x 9
	repository_index_reconcile_interrupted_generations "$repository_root"
}

repository_index_generation_quarantine_existing()
{
	local generation_dir="$1" repository_root="$2" generation="$3" quarantine
	[[ -e "$generation_dir" ]] || return 0
	quarantine="$repository_root/quarantine/$generation-$(timestamp_compact_utc)"
	mv -- "$generation_dir" "$quarantine"
}

repository_index_generation_temporary_dir()
{
	local repository_root="$1" generation="$2"
	printf '%s/generations/.%s.tmp.%s.%s\n' "$repository_root" "$generation" "$$" "$RANDOM"
}

repository_index_generation_publish()
{
	local temporary="$1" generation_dir="$2" repository_root="$3" retention="$4"
	repository_index_write_verification_marker "$temporary" integrity_check ||
		die 'could not record repository-index publication integrity marker'
	mv -- "$temporary" "$generation_dir"
	repository_index_verify_generation "$generation_dir" ||
		die 'published repository-index generation failed verification'
	repository_index_publish_project_pointer "$generation_dir"
	repository_index_apply_retention "$repository_root" "$retention" "$generation_dir"
}
