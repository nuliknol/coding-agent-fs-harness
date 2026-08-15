#!/usr/bin/env bash

# Controlled source provenance for independently verified checkpoints.
# The caller must have loaded harness-common.sh and harness-git-commit.sh and
# must hold the project lock.

checkpoint_scope_dirty_paths()
{
	local assignment="$1" allowed_scope path
	local -A seen=()
	git -C "$REPOSITORY" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
	allowed_scope="$(metadata_value "$assignment" Allowed-Scope)"
	[[ -n "$allowed_scope" ]] || return 0
	while IFS= read -r path; do
		[[ -n "$path" && -z "${seen[$path]:-}" ]] || continue
		agent_commit_path_in_scope "$path" "$allowed_scope" || continue
		seen[$path]=1
		printf '%s\n' "$path"
	done < <({
		git -C "$REPOSITORY" diff --name-only HEAD -- 2>/dev/null || true
		git -C "$REPOSITORY" ls-files --others --exclude-standard 2>/dev/null || true
	} | LC_ALL=C sort -u)
}

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

checkpoint_effective_commit_max_files()
{
	local task_id="$1" assignment="$2" configured root root_assignment root_scope scope_override additional_scope entry allowance=0
	local -a entries=()
	configured="$(metadata_value "$assignment" Expected-Max-Implementation-Files)"
	[[ "$configured" =~ ^[0-9]+$ ]] || { printf '%s\n' "$configured"; return 0; }
	[[ "$(metadata_value "$assignment" Manager-Remediation)" == 1 ]] || { printf '%s\n' "$configured"; return 0; }
	root="$(task_root_id "$task_id")"
	root_assignment="$(task_root_assignment_file "$root")"
	[[ -f "$root_assignment" ]] || { printf '%s\n' "$configured"; return 0; }
	scope_override="$(task_root_architecture_scope_override_file "$root")"
	[[ -f "$scope_override" ]] || { printf '%s\n' "$configured"; return 0; }
	[[ "$(kv_file_value "$scope_override" authorized_for 2>/dev/null || true)" == manager_remediation ]] ||
		{ printf '%s\n' "$configured"; return 0; }
	root_scope="$(metadata_value "$root_assignment" Allowed-Scope)"
	additional_scope="$(kv_file_value "$scope_override" additional_scope 2>/dev/null || true)"
	IFS=',' read -r -a entries <<< "${additional_scope//;/,}"
	for entry in "${entries[@]}"; do
		entry="$(trim_surrounding_whitespace "$entry")"
		[[ -n "$entry" ]] || continue
		agent_commit_path_in_scope "$entry" "$root_scope" && continue
		allowance=$((allowance + 1))
	done
	configured=$((configured + allowance))
	printf '%s\n' "$configured"
}

acceptance_commit_reviewed_scope()
{
	local task_id="$1" assignment="$2" review="$3" ledger candidate candidate_root candidate_paths
	local root prior_paths="" commit message_file review_sha
	local -a dirty_paths=()
	mapfile -t dirty_paths < <(checkpoint_scope_dirty_paths "$assignment")
	(( ${#dirty_paths[@]} > 0 )) || return 0
	(( HARNESS_AGENT_COMMITS_ENABLED == 1 )) ||
		die 'final acceptance has reviewed source changes but controlled agent commits are disabled'

	root="$(task_root_id "$task_id")"
	ledger="$(project_dir)/control/agent-commits.tsv"
	if [[ -f "$ledger" ]]; then
		while IFS=$'\t' read -r _ candidate _ _ candidate_paths; do
			[[ -n "$candidate" && "$candidate" != "$task_id" ]] || continue
			candidate_root="$(task_root_id "$candidate")"
			[[ "$candidate_root" == "$root" ]] || continue
			prior_paths="${prior_paths:+$prior_paths,}$candidate_paths"
		done < <(tail -n +2 "$ledger")
	fi

	# The manager has already validated the result, review schema, architecture
	# impact, current diff, and focused behavior before entering this locked
	# transaction. Commit only the dirty paths inside the immutable assignment
	# scope; unrelated operator changes remain untouched.
	AGENT_COMMIT_SCOPE="$(metadata_value "$assignment" Allowed-Scope)"
	AGENT_COMMIT_MAX_FILES="$(checkpoint_effective_commit_max_files "$task_id" "$assignment")"
	AGENT_COMMIT_PRIOR_PATHS="$prior_paths"
	AGENT_COMMIT_ACTOR="task=$task_id session=manager-accept"
	review_sha="$(sha256sum "$review" | awk '{print $1}')"
	message_file="$(project_dir)/control/.$(task_base "$task_id").accept-commit-message.$$"
	{
		printf 'Accept independently reviewed source for %s\n\n' "$task_id"
		printf 'Manager review SHA-256: %s\n' "$review_sha"
		printf 'The harness committed only reviewed paths within the immutable task scope.\n'
	} > "$message_file"
	commit="$(agent_commit_source "$message_file" "${dirty_paths[@]}")"
	rm -f "$message_file"
	checkpoint_record_controlled_commit "$task_id" manager-accept "$commit" "${dirty_paths[@]}"
	log_event "ACCEPTANCE_SOURCE_COMMIT task=$task_id commit=$commit review_sha256=$review_sha paths=$(printf '%q' "${dirty_paths[*]}")"
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
	AGENT_COMMIT_MAX_FILES="$(checkpoint_effective_commit_max_files "$task_id" "$assignment")"
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

checkpoint_upgrade_legacy_comma_artifact()
{
	local checkpoint_task="$1" artifact_dir="$2" acceptance_review="$3" raw_path assignment allowed_scope
	local backup_dir path resolved snapshot_path manifest_tmp review_sha legacy_file
	local -a paths=() raw_parts=()
	[[ -f "$acceptance_review" ]] || return 0
	[[ "$(metadata_value "$acceptance_review" Decision)" == ACCEPT ]] || return 0
	[[ "$(wc -l < "$artifact_dir/checkpoint-paths.txt")" == 1 ]] || return 0
	raw_path="$(< "$artifact_dir/checkpoint-paths.txt")"
	[[ "$raw_path" == *,* ]] || return 0
	grep -Fqx "path=$raw_path"$'\t''type=deleted' "$artifact_dir/manifest.txt" || return 0
	assignment="$(project_dir)/archive/$(task_base "$checkpoint_task").assignment.md"
	[[ -f "$assignment" ]] || die "legacy checkpoint repair lacks archived assignment: $checkpoint_task"
	allowed_scope="$(metadata_value "$assignment" Allowed-Scope)"
	IFS=',' read -r -a raw_parts <<< "$raw_path"
	for path in "${raw_parts[@]}"; do
		path="${path#"${path%%[![:space:]]*}"}"
		path="${path%"${path##*[![:space:]]}"}"
		[[ -n "$path" && "$path" != NONE ]] || die 'legacy checkpoint contains an empty path-list item'
		[[ "$path" != /* && "$path" != '.' && "$path" != '..' && "$path" != ../* && "$path" != */../* && "$path" != */.. ]] ||
			die "legacy checkpoint path is unsafe: $path"
		resolved="$(realpath -m "$REPOSITORY/$path")"
		[[ "$resolved" == "$REPOSITORY"/* ]] || die "legacy checkpoint path escapes repository: $path"
		agent_commit_path_in_scope "$path" "$allowed_scope" || die "legacy checkpoint path is outside original assignment scope: $path"
		paths+=("$path")
	done
	(( ${#paths[@]} > 1 )) || return 0
	git -C "$REPOSITORY" diff --check -- "${paths[@]}"
	review_sha="$(sha256sum "$acceptance_review" | awk '{print $1}')"
	backup_dir="$artifact_dir/legacy-comma-path-artifact"
	[[ ! -e "$backup_dir" ]] || die "legacy checkpoint repair backup already exists: $backup_dir"
	mkdir -p "$backup_dir" "$artifact_dir/files"
	chmod 700 "$backup_dir"
	for legacy_file in checkpoint-paths.txt manifest.txt workspace.patch git-status.txt; do
		[[ ! -f "$artifact_dir/$legacy_file" ]] || mv "$artifact_dir/$legacy_file" "$backup_dir/$legacy_file"
	done
	: > "$artifact_dir/checkpoint-paths.txt"
	for path in "${paths[@]}"; do
		printf '%s\n' "$path" >> "$artifact_dir/checkpoint-paths.txt"
		snapshot_path="$artifact_dir/files/$path"
		if [[ -L "$REPOSITORY/$path" ]]; then
			mkdir -p "$(dirname "$snapshot_path")"
			cp -P -- "$REPOSITORY/$path" "$snapshot_path"
		elif [[ -f "$REPOSITORY/$path" ]]; then
			mkdir -p "$(dirname "$snapshot_path")"
			cp -p -- "$REPOSITORY/$path" "$snapshot_path"
		elif [[ -d "$REPOSITORY/$path" ]]; then
			die "legacy checkpoint path must name a file, symlink, or deletion: $path"
		fi
	done
	git -C "$REPOSITORY" diff --binary --full-index HEAD -- "${paths[@]}" > "$artifact_dir/workspace.patch" 2>/dev/null || true
	git -C "$REPOSITORY" status --porcelain=v1 -- "${paths[@]}" > "$artifact_dir/git-status.txt"
	manifest_tmp="$artifact_dir/manifest.txt.tmp.$$"
	awk '!/^path=/ && !/^controlled_source_commit=/ && !/^legacy_comma_path_repaired_/' \
		"$backup_dir/manifest.txt" > "$manifest_tmp"
	printf 'legacy_comma_path_repaired_at=%s\n' "$(timestamp_utc)" >> "$manifest_tmp"
	printf 'legacy_comma_path_repaired_by_review_sha256=%s\n' "$review_sha" >> "$manifest_tmp"
	for path in "${paths[@]}"; do
		if [[ -L "$REPOSITORY/$path" ]]; then
			printf 'path=%s\ttype=symlink\ttarget=%s\n' "$path" "$(readlink "$REPOSITORY/$path")" >> "$manifest_tmp"
		elif [[ -f "$REPOSITORY/$path" ]]; then
			printf 'path=%s\ttype=file\tmode=%s\tsha256=%s\n' "$path" \
				"$(stat -c '%a' "$REPOSITORY/$path")" \
				"$(sha256sum "$REPOSITORY/$path" | awk '{print $1}')" >> "$manifest_tmp"
		else
			printf 'path=%s\ttype=deleted\n' "$path" >> "$manifest_tmp"
		fi
	done
	mv "$manifest_tmp" "$artifact_dir/manifest.txt"
	chmod 600 "$artifact_dir/checkpoint-paths.txt" "$artifact_dir/manifest.txt" \
		"$artifact_dir/workspace.patch" "$artifact_dir/git-status.txt"
	log_event "LEGACY_CHECKPOINT_PATH_LIST_REPAIRED task=$checkpoint_task paths=$(printf '%q' "${paths[*]}") review_sha256=$review_sha"
}

checkpoint_reconcile_root_source_provenance()
{
	local current_task="$1" acceptance_review="${2:-}" assignment expected_files root marker checkpoint_task artifact
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
		checkpoint_upgrade_legacy_comma_artifact "$checkpoint_task" "$artifact" "$acceptance_review"
		checkpoint_commit_verified_artifact "$checkpoint_task" "$artifact"
	done
	shopt -u nullglob
}
