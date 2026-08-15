#!/usr/bin/env bash

# Controlled source provenance for independently verified checkpoints.
# The caller must have loaded harness-common.sh and harness-git-commit.sh and
# must hold the project lock.

checkpoint_manifest_path_matches_workspace()
{
	local artifact_dir="$1" path="$2" manifest row field expected_type="" expected_sha="" expected_target=""
	manifest="$artifact_dir/manifest.txt"
	[[ -f "$manifest" ]] || return 1
	row="$(awk -F '\t' -v wanted="path=$path" '$1 == wanted {print; exit}' "$manifest")"
	[[ -n "$row" ]] || return 1
	IFS=$'\t' read -r _ field rest <<< "$row"
	expected_type="${field#type=}"
	case "$expected_type" in
		file)
			expected_sha="$(awk -F '\t' -v wanted="path=$path" '$1 == wanted {for (i=2;i<=NF;i++) if ($i ~ /^sha256=/) {sub(/^sha256=/,"",$i); print $i; exit}}' "$manifest")"
			[[ -f "$REPOSITORY/$path" && ! -L "$REPOSITORY/$path" && -n "$expected_sha" ]] || return 1
			[[ "$(sha256sum "$REPOSITORY/$path" | awk '{print $1}')" == "$expected_sha" ]]
			;;
		symlink)
			expected_target="${rest#target=}"
			[[ -L "$REPOSITORY/$path" && "$(readlink "$REPOSITORY/$path")" == "$expected_target" ]]
			;;
		deleted)
			[[ ! -e "$REPOSITORY/$path" && ! -L "$REPOSITORY/$path" ]]
			;;
		*) return 1 ;;
	esac
}

checkpoint_record_controlled_commit()
{
	local task_id="$1" session="$2" commit="$3"
	shift 3
	local ledger
	ledger="$(project_dir)/control/agent-commits.tsv"
	if [[ ! -f "$ledger" ]]; then
		printf 'commit\ttask_id\tsession\tcreated_at\tpaths\n' > "$ledger"
		chmod 600 "$ledger"
	fi
	printf '%s\t%s\t%s\t%s\t%s\n' "$commit" "$task_id" "$session" "$(timestamp_utc)" \
		"$(IFS=,; printf '%s' "$*")" >> "$ledger"
	log_event "CHECKPOINT_SOURCE_COMMIT task=$task_id session=$session commit=$commit paths=$(printf '%q' "$*")"
}

checkpoint_commit_verified_artifact()
{
	local task_id="$1" artifact_dir="$2" assignment ledger candidate candidate_root path commit message_file
	local root prior_paths=""
	local -a dirty_paths=()
	(( HARNESS_AGENT_COMMITS_ENABLED == 1 )) || return 0
	[[ -f "$artifact_dir/checkpoint-paths.txt" && -f "$artifact_dir/manifest.txt" ]] || return 0
	root="$(task_root_id "$task_id")"
	assignment="$(project_dir)/archive/$(task_base "$task_id").assignment.md"
	[[ -f "$assignment" ]] || die "checkpoint source commit lacks archived assignment: $task_id"
	while IFS= read -r path; do
		[[ -n "$path" && "$path" != NONE ]] || continue
		if [[ -n "$(git -C "$REPOSITORY" status --porcelain=v1 -- "$path")" ]]; then
			checkpoint_manifest_path_matches_workspace "$artifact_dir" "$path" ||
				die "checkpoint workspace no longer matches independently reviewed artifact: $path"
			dirty_paths+=("$path")
		fi
	done < "$artifact_dir/checkpoint-paths.txt"
	(( ${#dirty_paths[@]} > 0 )) || return 0

	ledger="$(project_dir)/control/agent-commits.tsv"
	if [[ -f "$ledger" ]]; then
		while IFS=$'\t' read -r _ candidate _ _ candidate_paths; do
			[[ -n "$candidate" && "$candidate" != "$task_id" ]] || continue
			candidate_root="$(task_root_id "$candidate")"
			[[ "$candidate_root" == "$root" ]] || continue
			prior_paths="${prior_paths:+$prior_paths,}$candidate_paths"
		done < <(tail -n +2 "$ledger")
	fi
	AGENT_COMMIT_SCOPE="$(metadata_value "$assignment" Allowed-Scope)"
	AGENT_COMMIT_MAX_FILES="$(metadata_value "$assignment" Expected-Max-Implementation-Files)"
	AGENT_COMMIT_PRIOR_PATHS="$prior_paths"
	AGENT_COMMIT_ACTOR="task=$task_id session=manager-checkpoint"
	message_file="$artifact_dir/.checkpoint-commit-message.$$"
	{
		printf 'Checkpoint verified source increment for %s\n\n' "$task_id"
		printf 'The harness manager independently validated this bounded increment before committing its reviewed paths.\n'
	} > "$message_file"
	commit="$(agent_commit_source "$message_file" "${dirty_paths[@]}")"
	rm -f "$message_file"
	checkpoint_record_controlled_commit "$task_id" manager-checkpoint "$commit" "${dirty_paths[@]}"
	printf 'controlled_source_commit=%s\n' "$commit" >> "$artifact_dir/manifest.txt"
}

checkpoint_reconcile_root_source_provenance()
{
	local current_task="$1" assignment expected_files root marker checkpoint_task artifact
	assignment="$(project_dir)/archive/$(task_base "$current_task").assignment.md"
	[[ -f "$assignment" ]] || return 0
	expected_files="$(metadata_value "$assignment" Expected-Max-Implementation-Files)"
	[[ "$expected_files" == 0 ]] || return 0
	root="$(task_root_id "$current_task")"
	shopt -s nullglob
	for marker in "$(project_dir)/archive/$PROJECT-task-$root"*.checkpointed.md; do
		checkpoint_task="$(metadata_value "$marker" Task-ID)"
		[[ -n "$checkpoint_task" && "$(task_root_id "$checkpoint_task")" == "$root" ]] || continue
		artifact="$(metadata_value "$marker" Artifact-Directory)"
		[[ -n "$artifact" && -d "$artifact" ]] || continue
		checkpoint_commit_verified_artifact "$checkpoint_task" "$artifact"
	done
	shopt -u nullglob
}
