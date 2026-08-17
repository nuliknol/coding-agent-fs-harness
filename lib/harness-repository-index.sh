#!/usr/bin/env bash

# Repository-index helpers. Source lib/harness-common.sh first.

HARNESS_REPOSITORY_INDEX_SCHEMA_VERSION=5

repository_index_project_pointer_file()
{
	printf '%s/control/repository-index.env\n' "$(project_dir)"
}

repository_index_schema_file()
{
	printf '%s/formats/repository-index-schema.sql\n' "$HARNESS_HOME"
}

repository_index_build_importer_file()
{
	printf '%s/tools/import_compile_commands.py\n' "$HARNESS_HOME"
}

repository_index_build_scanner_file()
{
	printf '%s/tools/scan_compile_inputs.py\n' "$HARNESS_HOME"
}

repository_index_command_path()
{
	local command_name="$1" resolved
	if [[ "$command_name" == */* ]]; then
		resolved="$(realpath -m "$command_name")"
		[[ -x "$resolved" ]] || die "repository-index command is not executable: $resolved"
	else
		resolved="$(command -v "$command_name" 2>/dev/null || true)"
		[[ -n "$resolved" ]] || die "repository-index command not found: $command_name"
	fi
	printf '%s\n' "$resolved"
}

# Return the first requested CPUs from the caller's current Linux affinity
# mask. Joern launches frontend JVMs beneath wrapper processes, so JVM
# ActiveProcessorCount is only a scheduling hint; an inherited taskset mask is
# the enforceable bound for the complete descendant tree.
repository_index_cpu_affinity_list()
{
	local requested="$1" allowed part start end cpu selected="" count=0
	[[ "$requested" =~ ^[1-9][0-9]*$ ]] || return 1
	allowed="$(awk '$1 == "Cpus_allowed_list:" {print $2; exit}' /proc/self/status 2>/dev/null || true)"
	[[ -n "$allowed" ]] || return 1
	local IFS=,
	for part in $allowed; do
		if [[ "$part" == *-* ]]; then
			start="${part%-*}"
			end="${part#*-}"
		else
			start="$part"
			end="$part"
		fi
		[[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$start" -le "$end" ]] || return 1
		for (( cpu=start; cpu<=end && count<requested; cpu++ )); do
			selected="${selected:+$selected,}$cpu"
			count=$((count + 1))
		done
		(( count < requested )) || break
	done
	(( count > 0 )) || return 1
	printf '%s\n' "$selected"
}

repository_index_repository_id()
{
	local identity common_dir
	if git -C "$REPOSITORY" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		common_dir="$(git -C "$REPOSITORY" rev-parse --git-common-dir)"
		if [[ "$common_dir" != /* ]]; then
			common_dir="$(realpath -m "$REPOSITORY/$common_dir")"
		else
			common_dir="$(realpath -m "$common_dir")"
		fi
		identity="git-common-dir:$common_dir"
	else
		identity="repository-path:$(realpath "$REPOSITORY")"
	fi
	printf '%s' "$identity" | sha256sum | awk '{print $1}'
}

repository_index_source_revision()
{
	if git -C "$REPOSITORY" rev-parse --verify HEAD >/dev/null 2>&1; then
		git -C "$REPOSITORY" rev-parse HEAD
	else
		die 'repository indexing currently requires a Git repository with a committed HEAD'
	fi
}

repository_index_require_clean_tracked_tree()
{
	git -C "$REPOSITORY" diff --quiet --ignore-submodules -- ||
		die 'repository index requires a clean tracked worktree; checkpoint or commit tracked changes first'
	git -C "$REPOSITORY" diff --cached --quiet --ignore-submodules -- ||
		die 'repository index requires an empty Git index; commit staged changes first'
}

repository_index_worktree_overlay_file()
{
	printf '%s/control/repository-worktree-overlay.tsv\n' "$(project_dir)"
}

# Record the tracked workspace delta without rebuilding the immutable baseline
# generation. Context Closure reads source from the live worktree and uses this
# manifest to relocate stale indexed regions and bind the capsule to exact
# changed-file content.
repository_index_write_worktree_overlay()
{
	local output="${1:-$(repository_index_worktree_overlay_file)}" tmp relative source status digest bytes
	tmp="$output.tmp.$$"
	mkdir -p "$(dirname "$output")"
	printf 'repository_path\tstatus\tcontent_sha256\tcontent_bytes\n' > "$tmp"
	while IFS= read -r -d '' relative; do
		[[ -n "$relative" ]] || continue
		source="$REPOSITORY/$relative"
		if [[ -f "$source" ]]; then
			status=MODIFIED
			digest="$(sha256sum "$source" | awk '{print $1}')"
			bytes="$(stat -c %s "$source")"
		else
			status=DELETED
			digest=-
			bytes=0
		fi
		printf '%s\t%s\t%s\t%s\n' "$relative" "$status" "$digest" "$bytes" >> "$tmp"
	done < <(git -C "$REPOSITORY" diff --name-only -z HEAD --)
	chmod 600 "$tmp"
	mv "$tmp" "$output"
	printf '%s\n' "$output"
}

repository_index_compile_commands_file()
{
	local candidate
	if [[ -n "$HARNESS_COMPILE_COMMANDS" ]]; then
		[[ -f "$HARNESS_COMPILE_COMMANDS" ]] ||
			die "HARNESS_COMPILE_COMMANDS does not exist: $HARNESS_COMPILE_COMMANDS"
		printf '%s\n' "$HARNESS_COMPILE_COMMANDS"
		return 0
	fi
	if [[ -f "$REPOSITORY/compile_commands.json" ]]; then
		printf '%s\n' "$REPOSITORY/compile_commands.json"
		return 0
	fi
	mapfile -t candidates < <(find "$REPOSITORY" -mindepth 2 -maxdepth 4 -type f \
		-name compile_commands.json -not -path '*/.git/*' -print | LC_ALL=C sort)
	case "${#candidates[@]}" in
		0) die 'compile_commands.json was not found; generate it or set HARNESS_COMPILE_COMMANDS' ;;
		1) printf '%s\n' "${candidates[0]}" ;;
		*) die 'multiple compilation databases were found; select one with HARNESS_COMPILE_COMMANDS' ;;
	esac
}

repository_index_normalize_compile_commands()
{
	local input="$1" output="$2"
	command -v jq >/dev/null 2>&1 || die 'repository indexing requires jq'
	jq -e '
		type == "array" and length > 0 and
		all(.[]; (.directory | type == "string") and (.file | type == "string") and
			(((.command // "") | type == "string" and length > 0) or
			 ((.arguments // []) | type == "array" and length > 0)))
	' "$input" >/dev/null || die "invalid compilation database: $input"
	jq -S '
		map(({
			directory: .directory,
			file: .file,
			command: (.command // null),
			arguments: (.arguments // null),
			output: (.output // null)
		} | with_entries(select(.value != null)))) |
		sort_by(.file, .directory, (.command // ""), ((.arguments // []) | join("\u0000")))
	' "$input" > "$output"
}

repository_index_tool_fingerprint()
{
	local executable="$1" version content_hash
	# Optional analysis tools are not guaranteed to implement a terminating
	# --version action.  In particular, some Joern launchers enter the REPL.
	# Reuse the bounded probe so tool identity can never stall index startup.
	version="$(repository_index_tool_version "$executable")"
	content_hash="$(sha256sum "$executable" | awk '{print $1}')"
	[[ -n "$version" ]] || version='no-version-output'
	printf '%s\n%s\n%s\n' "$executable" "$content_hash" "$version" | sha256sum | awk '{print $1}'
}

repository_index_joern_fingerprint()
{
	local enabled="$1" command_name="$2" executable content_hash
	if [[ "$enabled" != 1 ]]; then
		printf 'disabled'
		return 0
	fi
	executable="$(repository_index_command_path "$command_name")"
	content_hash="$(sha256sum "$executable" | awk '{print $1}')"
	# Joern's launcher does not implement a non-interactive --version action;
	# it enters the REPL and emits timestamped JLine diagnostics instead.  Do
	# not launch a JVM from status/freshness checks.  Keep the stable capability
	# sentinel used by successful unsupported-option probes so existing
	# immutable generations retain the same identity.
	printf '%s\n%s\n%s\n' "$executable" "$content_hash" version-probe-unsupported |
		sha256sum | awk '{print $1}'
}

repository_index_tool_version()
{
	local executable="$1" output status=0
	if output="$(timeout --signal=TERM --kill-after=2 5 "$executable" --version 2>&1 | head -n 4)"; then
		status=0
	else
		status=$?
	fi
	if (( status != 0 )); then
		# Discard partial REPL banners or startup diagnostics after every failed
		# probe, including SIGPIPE from a verbose command truncated by head.  Such
		# output may contain timestamps and must never enter immutable identity.
		output="version-probe-failed-$status"
	fi
	case "$output" in
		*'Unknown option'*|*'unknown option'*|*'Unrecognized option'*|*'unrecognized option'*|*'Invalid option'*|*'invalid option'*)
			# Some launchers (notably Joern) report an unsupported version flag on
			# stdout and still exit successfully.  Their startup banner contains
			# timestamps, so retain only a stable capability result.
			output=version-probe-unsupported
			;;
	esac
	# Try the single-dash spelling only when the first command terminated.  A
	# timed-out launcher is already known to have unsafe version semantics.
	if [[ -z "$output" && "$status" != 124 && "$status" != 137 ]]; then
		output="$(timeout --signal=TERM --kill-after=2 5 "$executable" -version 2>&1 | head -n 4 || true)"
	fi
	[[ -n "$output" ]] || output=no-version-output
	printf '%s' "$output" | tr '\n\t' '  '
}

repository_index_optional_fingerprint()
{
	local enabled="$1" command_name="$2"
	if [[ "$enabled" == 1 ]]; then
		repository_index_tool_fingerprint "$(repository_index_command_path "$command_name")"
	else
		printf 'disabled'
	fi
}

repository_index_prepare_identity()
{
	local normalized_compile_commands="$1" generated_inputs="$2" identity_material schema_file build_importer_file build_scanner_file provider_files
	REPOSITORY_INDEX_REPOSITORY_ID="$(repository_index_repository_id)"
	REPOSITORY_INDEX_SOURCE_REVISION="$(repository_index_source_revision)"
	REPOSITORY_INDEX_COMPILE_COMMANDS_SHA256="$(sha256sum "$normalized_compile_commands" | awk '{print $1}')"
	REPOSITORY_INDEX_GENERATED_INPUTS_SHA256="$(sha256sum "$generated_inputs" | awk '{print $1}')"
	REPOSITORY_INDEX_SCIP_CLANG_PATH="$(repository_index_command_path "$HARNESS_SCIP_CLANG_BIN")"
	REPOSITORY_INDEX_SCIP_PATH="$(repository_index_command_path "$HARNESS_SCIP_BIN")"
	REPOSITORY_INDEX_IMPORTER_PATH="$(repository_index_command_path "$HARNESS_SCIP_IMPORTER_BIN")"
	REPOSITORY_INDEX_SCIP_CLANG_FINGERPRINT="$(repository_index_tool_fingerprint "$REPOSITORY_INDEX_SCIP_CLANG_PATH")"
	REPOSITORY_INDEX_SCIP_FINGERPRINT="$(repository_index_tool_fingerprint "$REPOSITORY_INDEX_SCIP_PATH")"
	REPOSITORY_INDEX_IMPORTER_FINGERPRINT="$(repository_index_tool_fingerprint "$REPOSITORY_INDEX_IMPORTER_PATH")"
	REPOSITORY_INDEX_JOERN_FINGERPRINT="$(repository_index_joern_fingerprint "$HARNESS_JOERN_ENABLED" "$HARNESS_JOERN_BIN")"
	REPOSITORY_INDEX_RECOLL_FINGERPRINT="$(repository_index_optional_fingerprint "$HARNESS_RECOLL_ENABLED" "$HARNESS_RECOLL_BIN")"
	build_importer_file="$(repository_index_build_importer_file)"
	[[ -f "$build_importer_file" ]] || die "build-target importer is missing: $build_importer_file"
	build_scanner_file="$(repository_index_build_scanner_file)"
	[[ -f "$build_scanner_file" ]] || die "compile-input scanner is missing: $build_scanner_file"
	REPOSITORY_INDEX_BUILD_IMPORTER_PATH="$(realpath "$build_importer_file")"
	REPOSITORY_INDEX_BUILD_SCANNER_PATH="$(realpath "$build_scanner_file")"
	REPOSITORY_INDEX_BUILD_IMPORTER_FINGERPRINT="$({ sha256sum "$build_importer_file" "$build_scanner_file"; } | sha256sum | awk '{print $1}')"
	provider_files=("$HARNESS_HOME/tools/import_joern_graphml.py" "$HARNESS_HOME/tools/import_recoll_candidates.py" "$HARNESS_HOME/tools/import_index_diagnostics.py" "$HARNESS_HOME/tools/normalize_repository_architecture.py")
	REPOSITORY_INDEX_PROVIDER_FINGERPRINT="$({ sha256sum "${provider_files[@]}"; } | sha256sum | awk '{print $1}')"
	schema_file="$(repository_index_schema_file)"
	[[ -f "$schema_file" ]] || die "repository-index schema is missing: $schema_file"
	REPOSITORY_INDEX_SCHEMA_SHA256="$(sha256sum "$schema_file" | awk '{print $1}')"
	identity_material="schema=$HARNESS_REPOSITORY_INDEX_SCHEMA_VERSION
repository=$REPOSITORY_INDEX_REPOSITORY_ID
revision=$REPOSITORY_INDEX_SOURCE_REVISION
compile_commands=$REPOSITORY_INDEX_COMPILE_COMMANDS_SHA256
generated_inputs=$REPOSITORY_INDEX_GENERATED_INPUTS_SHA256
scip_clang=$REPOSITORY_INDEX_SCIP_CLANG_FINGERPRINT
scip=$REPOSITORY_INDEX_SCIP_FINGERPRINT
importer=$REPOSITORY_INDEX_IMPORTER_FINGERPRINT
build_importer=$REPOSITORY_INDEX_BUILD_IMPORTER_FINGERPRINT
joern=$REPOSITORY_INDEX_JOERN_FINGERPRINT
joern_execution_mode=$HARNESS_JOERN_EXECUTION_MODE
joern_source_root=$HARNESS_JOERN_SOURCE_ROOT
joern_exclude_regex=$HARNESS_JOERN_EXCLUDE_REGEX
joern_timeout_seconds=$HARNESS_JOERN_TIMEOUT_SECONDS
joern_analysis_classes=$HARNESS_JOERN_ANALYSIS_CLASSES
recoll=$REPOSITORY_INDEX_RECOLL_FINGERPRINT
providers=$REPOSITORY_INDEX_PROVIDER_FINGERPRINT
schema=$REPOSITORY_INDEX_SCHEMA_SHA256"
	REPOSITORY_INDEX_GENERATION="$(printf '%s\n' "$identity_material" | sha256sum | awk '{print $1}')"
	REPOSITORY_INDEX_REPOSITORY_ROOT="$HARNESS_REPOSITORY_INDEX_ROOT/$REPOSITORY_INDEX_REPOSITORY_ID"
	REPOSITORY_INDEX_GENERATION_DIR="$REPOSITORY_INDEX_REPOSITORY_ROOT/generations/$REPOSITORY_INDEX_GENERATION"
	export REPOSITORY_INDEX_REPOSITORY_ID REPOSITORY_INDEX_SOURCE_REVISION
	export REPOSITORY_INDEX_COMPILE_COMMANDS_SHA256 REPOSITORY_INDEX_GENERATED_INPUTS_SHA256 REPOSITORY_INDEX_SCIP_CLANG_PATH
	export REPOSITORY_INDEX_SCIP_PATH REPOSITORY_INDEX_IMPORTER_PATH
	export REPOSITORY_INDEX_SCIP_CLANG_FINGERPRINT REPOSITORY_INDEX_SCIP_FINGERPRINT
	export REPOSITORY_INDEX_IMPORTER_FINGERPRINT REPOSITORY_INDEX_SCHEMA_SHA256
	export REPOSITORY_INDEX_JOERN_FINGERPRINT REPOSITORY_INDEX_RECOLL_FINGERPRINT REPOSITORY_INDEX_PROVIDER_FINGERPRINT
	export REPOSITORY_INDEX_BUILD_IMPORTER_PATH REPOSITORY_INDEX_BUILD_SCANNER_PATH REPOSITORY_INDEX_BUILD_IMPORTER_FINGERPRINT
	export REPOSITORY_INDEX_GENERATION
	export REPOSITORY_INDEX_REPOSITORY_ROOT REPOSITORY_INDEX_GENERATION_DIR
}

repository_index_reconcile_interrupted_generations()
{
	local repository_root="$1" candidate base quarantine
	[[ "$repository_root" == "$HARNESS_REPOSITORY_INDEX_ROOT"/* ]] ||
		die "refusing to reconcile repository-index path outside configured root: $repository_root"
	quarantine="$repository_root/quarantine"
	mkdir -p "$quarantine"
	while IFS= read -r candidate; do
		[[ -d "$candidate" ]] || continue
		base="${candidate##*/}"
		mv "$candidate" "$quarantine/interrupted-${base#.}-$(timestamp_compact_utc)"
	done < <(find "$repository_root/generations" -mindepth 1 -maxdepth 1 -type d -name '.*.tmp.*' -print 2>/dev/null | LC_ALL=C sort)
}

repository_index_apply_retention()
{
	local repository_root="$1" keep="$2" active="$3" candidate count=0
	[[ "$repository_root" == "$HARNESS_REPOSITORY_INDEX_ROOT"/* ]] ||
		die "refusing to retain repository-index path outside configured root: $repository_root"
	while IFS= read -r candidate; do
		[[ -d "$candidate" ]] || continue
		[[ "$candidate" == "$active" ]] && continue
		count=$((count + 1))
		if (( count >= keep )); then
			rm -rf -- "$candidate"
		fi
	done < <(find "$repository_root/generations" -mindepth 1 -maxdepth 1 -type d -not -name '.*' \
		-printf '%T@ %p\n' | LC_ALL=C sort -rn | cut -d' ' -f2-)
}

repository_index_refresh_at_safe_boundary()
{
	local task_id="$1" outcome="$2" accepted_count pending tmp
	[[ "$HARNESS_REPOSITORY_INDEX_MODE" != off ]] || return 0
	if repository_index_project_pointer_is_current; then
		rm -f "$(project_dir)/control/repository-index-refresh.pending.env" \
			"$(project_dir)/control/repository-index-refresh.failed.md"
		return 0
	fi
	accepted_count="$(project_plan_complete_count 2>/dev/null || printf 0)"
	[[ "$accepted_count" =~ ^[0-9]+$ ]] || accepted_count=0
	if [[ "$HARNESS_REPOSITORY_INDEX_MODE" == advisory ]] &&
		(( accepted_count % HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES != 0 )); then
		log_event "REPOSITORY_INDEX_REFRESH_DEFERRED task=$task_id outcome=$outcome reason=${REPOSITORY_INDEX_POINTER_REASON:-stale} accepted=$accepted_count"
		return 0
	fi
	# Manager terminal commands run inside a bounded agent tool action. SCIP and
	# Joern may legitimately outlive that action, so rebuilding here can be
	# terminated after the accepted/checkpoint transaction has committed but
	# before the new generation is published. Hand the durable request to the
	# persistent supervisor, which serializes it before any new planning turn.
	pending="$(project_dir)/control/repository-index-refresh.pending.env"
	tmp="$pending.tmp.$$"
	{
		printf 'task_id=%s\n' "$task_id"
		printf 'outcome=%s\n' "$outcome"
		printf 'reason=%s\n' "${REPOSITORY_INDEX_POINTER_REASON:-stale}"
		printf 'requested_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$pending"
	log_event "REPOSITORY_INDEX_REFRESH_SCHEDULED task=$task_id outcome=$outcome reason=${REPOSITORY_INDEX_POINTER_REASON:-stale} marker=$pending"
	return 0
}

repository_index_sql_quote()
{
	local value="${1//\'/\'\'}"
	printf "'%s'" "$value"
}

repository_index_generation_artifact_fingerprint()
{
	local generation_dir="$1" database scip
	database="$generation_dir/architecture.sqlite"
	scip="$generation_dir/index.scip"
	[[ -f "$database" && -s "$scip" ]] || return 1
	# Published generations are immutable.  Size, inode, and nanosecond mtime /
	# ctime metadata therefore provide a cheap invalidation key for the durable
	# integrity result without rereading a multi-gigabyte SQLite database on
	# every context-closure or status request.
	{
		stat -Lc $'%s\t%y\t%z\t%i' "$database"
		stat -Lc $'%s\t%y\t%z\t%i' "$scip"
	} | sha256sum | awk '{print $1}'
}

repository_index_verification_marker_is_current()
{
	local generation_dir="$1" marker artifact_fingerprint marker_schema marker_fingerprint
	marker="$generation_dir/integrity.env"
	[[ -f "$marker" ]] || return 1
	[[ "$(kv_file_value "$marker" status 2>/dev/null || true)" == READY ]] || return 1
	marker_schema="$(kv_file_value "$marker" schema_version 2>/dev/null || true)"
	[[ "$marker_schema" == "$HARNESS_REPOSITORY_INDEX_SCHEMA_VERSION" ]] || return 1
	artifact_fingerprint="$(repository_index_generation_artifact_fingerprint "$generation_dir" 2>/dev/null || true)"
	marker_fingerprint="$(kv_file_value "$marker" artifact_fingerprint 2>/dev/null || true)"
	[[ -n "$artifact_fingerprint" && "$artifact_fingerprint" == "$marker_fingerprint" ]]
}

repository_index_write_verification_marker()
{
	local generation_dir="$1" check_kind="$2" marker tmp artifact_fingerprint
	marker="$generation_dir/integrity.env"
	tmp="$marker.tmp.$$.$RANDOM"
	artifact_fingerprint="$(repository_index_generation_artifact_fingerprint "$generation_dir")" || return 1
	{
		printf 'status=READY\n'
		printf 'schema_version=%s\n' "$HARNESS_REPOSITORY_INDEX_SCHEMA_VERSION"
		printf 'artifact_fingerprint=%s\n' "$artifact_fingerprint"
		printf 'check=%s\n' "$check_kind"
		printf 'verified_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$marker"
}

repository_index_verify_generation()
{
	local generation_dir="$1" manifest database generation status manifest_schema schema_version verification_fd
	local had_marker=0 check_kind=legacy_publication_integrity_check
	manifest="$generation_dir/manifest.env"
	database="$generation_dir/architecture.sqlite"
	[[ -f "$manifest" && -s "$generation_dir/index.scip" && -f "$database" ]] || return 1
	generation="$(kv_file_value "$manifest" generation 2>/dev/null || true)"
	status="$(kv_file_value "$manifest" status 2>/dev/null || true)"
	[[ "$generation" == "${generation_dir##*/}" && "$status" == READY ]] || return 1
	manifest_schema="$(kv_file_value "$manifest" schema_version 2>/dev/null || true)"
	[[ "$manifest_schema" == "$HARNESS_REPOSITORY_INDEX_SCHEMA_VERSION" ]] || return 1
	[[ ! -f "$generation_dir/integrity.env" ]] || had_marker=1
	if repository_index_verification_marker_is_current "$generation_dir"; then
		return 0
	fi
	# Older generations do not have the publication marker. Serialize enrollment
	# so simultaneous status/closure callers cannot repeat even the cheap schema
	# probe. Every READY legacy generation was already gated by integrity_check
	# before atomic publication, so it can inherit that durable result. A stale
	# or changed existing marker is different: re-run quick_check before trusting
	# the new artifact metadata.
	exec {verification_fd}> "$generation_dir/.integrity.lock" || return 1
	flock -x "$verification_fd" || { exec {verification_fd}>&-; return 1; }
	if repository_index_verification_marker_is_current "$generation_dir"; then
		flock -u "$verification_fd"
		exec {verification_fd}>&-
		return 0
	fi
	schema_version="$(sqlite3 "$database" 'PRAGMA user_version;' 2>/dev/null || true)"
	if [[ "$schema_version" != "$HARNESS_REPOSITORY_INDEX_SCHEMA_VERSION" ]]; then
		flock -u "$verification_fd"
		exec {verification_fd}>&-
		return 1
	fi
	if (( had_marker == 1 )); then
		if [[ "$(sqlite3 "$database" 'PRAGMA quick_check;' 2>/dev/null || true)" != ok ]]; then
			flock -u "$verification_fd"
			exec {verification_fd}>&-
			return 1
		fi
		check_kind=quick_check
	fi
	repository_index_write_verification_marker "$generation_dir" "$check_kind" || {
		flock -u "$verification_fd"
		exec {verification_fd}>&-
		return 1
	}
	flock -u "$verification_fd"
	exec {verification_fd}>&-
	return 0
}

# Verify that the project pointer names an intact generation for the exact
# committed source, compilation database, and structural-index toolchain that
# are active now.  Callers may report REPOSITORY_INDEX_POINTER_REASON.
repository_index_project_pointer_is_current()
{
	local pointer generation_dir recorded_revision recorded_compdb recorded_generated manifest normalized generated_inputs
	local current_compdb current_generated current_scip_clang current_scip current_importer current_build_importer current_build_importer_path current_build_scanner_path current_schema current_joern current_recoll current_providers
	REPOSITORY_INDEX_POINTER_REASON=-
	pointer="$(repository_index_project_pointer_file)"
	if [[ ! -f "$pointer" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=missing-pointer
		return 1
	fi
	if [[ "$(kv_file_value "$pointer" status 2>/dev/null || true)" != READY ]]; then
		REPOSITORY_INDEX_POINTER_REASON=pointer-not-ready
		return 1
	fi
	generation_dir="$(kv_file_value "$pointer" generation_dir 2>/dev/null || true)"
	if [[ -z "$generation_dir" ]] || ! repository_index_verify_generation "$generation_dir"; then
		REPOSITORY_INDEX_POINTER_REASON=generation-verification-failed
		return 1
	fi
	if ! git -C "$REPOSITORY" diff --quiet --ignore-submodules -- ||
		! git -C "$REPOSITORY" diff --cached --quiet --ignore-submodules --; then
		if [[ "$HARNESS_REPOSITORY_OVERLAY_MODE" == tracked ]]; then
			REPOSITORY_INDEX_POINTER_REASON=worktree-overlay
		else
			REPOSITORY_INDEX_POINTER_REASON=tracked-worktree-changed
			return 1
		fi
	fi
	recorded_revision="$(kv_file_value "$pointer" source_revision 2>/dev/null || true)"
	if [[ "$(repository_index_source_revision)" != "$recorded_revision" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=source-revision-changed
		return 1
	fi
	mkdir -p "$PROJECT_TMP_DIR"
	normalized="$PROJECT_TMP_DIR/compile-commands.current.$$.$RANDOM.json"
	repository_index_normalize_compile_commands \
		"$(repository_index_compile_commands_file)" "$normalized"
	current_compdb="$(sha256sum "$normalized" | awk '{print $1}')"
	recorded_compdb="$(kv_file_value "$pointer" compile_commands_sha256 2>/dev/null || true)"
	if [[ "$current_compdb" != "$recorded_compdb" ]]; then
		rm -f -- "$normalized"
		REPOSITORY_INDEX_POINTER_REASON=compile-commands-changed
		return 1
	fi
	generated_inputs="$PROJECT_TMP_DIR/compile-inputs.current.$$.$RANDOM.tsv"
	current_build_scanner_path="$(repository_index_build_scanner_file)"
	if [[ ! -f "$current_build_scanner_path" ]]; then
		rm -f -- "$normalized"
		REPOSITORY_INDEX_POINTER_REASON=compile-input-scanner-missing
		return 1
	fi
	python3 "$current_build_scanner_path" --compile-commands "$normalized" \
		--repository "$REPOSITORY" --output "$generated_inputs"
	current_generated="$(sha256sum "$generated_inputs" | awk '{print $1}')"
	rm -f -- "$normalized" "$generated_inputs"
	recorded_generated="$(kv_file_value "$pointer" generated_inputs_sha256 2>/dev/null || true)"
	if [[ "$current_generated" != "$recorded_generated" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=generated-inputs-changed
		return 1
	fi
	manifest="$generation_dir/manifest.env"
	current_scip_clang="$(repository_index_tool_fingerprint \
		"$(repository_index_command_path "$HARNESS_SCIP_CLANG_BIN")")"
	current_scip="$(repository_index_tool_fingerprint \
		"$(repository_index_command_path "$HARNESS_SCIP_BIN")")"
	current_importer="$(repository_index_tool_fingerprint \
		"$(repository_index_command_path "$HARNESS_SCIP_IMPORTER_BIN")")"
	current_build_importer_path="$(repository_index_build_importer_file)"
	current_build_scanner_path="$(repository_index_build_scanner_file)"
	if [[ ! -f "$current_build_importer_path" || ! -f "$current_build_scanner_path" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=build-target-importer-missing
		return 1
	fi
	current_build_importer="$({ sha256sum "$current_build_importer_path" "$current_build_scanner_path"; } | sha256sum | awk '{print $1}')"
	current_schema="$(sha256sum "$(repository_index_schema_file)" | awk '{print $1}')"
	current_joern="$(repository_index_joern_fingerprint "$HARNESS_JOERN_ENABLED" "$HARNESS_JOERN_BIN")"
	current_recoll="$(repository_index_optional_fingerprint "$HARNESS_RECOLL_ENABLED" "$HARNESS_RECOLL_BIN")"
	current_providers="$({ sha256sum "$HARNESS_HOME/tools/import_joern_graphml.py" "$HARNESS_HOME/tools/import_recoll_candidates.py" "$HARNESS_HOME/tools/import_index_diagnostics.py" "$HARNESS_HOME/tools/normalize_repository_architecture.py"; } | sha256sum | awk '{print $1}')"
	if [[ "$current_scip_clang" != "$(kv_file_value "$manifest" scip_clang_fingerprint 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=scip-clang-toolchain-changed
		return 1
	fi
	if [[ "$current_scip" != "$(kv_file_value "$manifest" scip_fingerprint 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=scip-toolchain-changed
		return 1
	fi
	if [[ "$current_importer" != "$(kv_file_value "$manifest" importer_fingerprint 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=scip-importer-changed
		return 1
	fi
	if [[ "$current_build_importer" != "$(kv_file_value "$manifest" build_importer_fingerprint 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=build-target-importer-changed
		return 1
	fi
	if [[ "$current_schema" != "$(kv_file_value "$manifest" schema_sha256 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=repository-index-schema-changed
		return 1
	fi
	if [[ "$current_joern" != "$(kv_file_value "$manifest" joern_fingerprint 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=joern-toolchain-changed
		return 1
	fi
	if [[ "$HARNESS_JOERN_SOURCE_ROOT" != "$(kv_file_value "$manifest" joern_source_root 2>/dev/null || true)" ||
		"$HARNESS_JOERN_EXCLUDE_REGEX" != "$(kv_file_value "$manifest" joern_exclude_regex 2>/dev/null || true)" ||
		"$HARNESS_JOERN_TIMEOUT_SECONDS" != "$(kv_file_value "$manifest" joern_timeout_seconds 2>/dev/null || true)" ||
		"$HARNESS_JOERN_ANALYSIS_CLASSES" != "$(kv_file_value "$manifest" joern_analysis_classes 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=joern-configuration-changed
		return 1
	fi
	if [[ "$current_recoll" != "$(kv_file_value "$manifest" recoll_fingerprint 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=recoll-toolchain-changed
		return 1
	fi
	if [[ "$current_providers" != "$(kv_file_value "$manifest" provider_fingerprint 2>/dev/null || true)" ]]; then
		REPOSITORY_INDEX_POINTER_REASON=repository-provider-changed
		return 1
	fi
	return 0
}

repository_index_publish_project_pointer()
{
	local generation_dir="$1" pointer tmp
	pointer="$(repository_index_project_pointer_file)"
	tmp="$pointer.tmp.$$"
	{
		printf 'status=READY\n'
		printf 'repository_id=%s\n' "$REPOSITORY_INDEX_REPOSITORY_ID"
		printf 'generation=%s\n' "$REPOSITORY_INDEX_GENERATION"
		printf 'generation_dir=%s\n' "$generation_dir"
		printf 'source_revision=%s\n' "$REPOSITORY_INDEX_SOURCE_REVISION"
		printf 'compile_commands_sha256=%s\n' "$REPOSITORY_INDEX_COMPILE_COMMANDS_SHA256"
		printf 'generated_inputs_sha256=%s\n' "$REPOSITORY_INDEX_GENERATED_INPUTS_SHA256"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$pointer"
}
