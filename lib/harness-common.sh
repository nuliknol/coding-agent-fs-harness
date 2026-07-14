#!/usr/bin/env bash

set -Eeuo pipefail

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

timestamp_utc()
{
	date -u '+%Y-%m-%dT%H:%M:%SZ'
}

timestamp_compact_utc()
{
	date -u '+%Y%m%dT%H%M%SZ'
}

epoch_now()
{
	date '+%s'
}

codex_provider_retry_kind()
{
	case "$1" in
		provider_quota_exhausted) printf 'quota\n' ;;
		provider_transient_error) printf 'transient\n' ;;
		*) return 1 ;;
	esac
}

codex_provider_retry_delay()
{
	case "$1" in
		provider_quota_exhausted) printf '%s\n' "$HARNESS_QUOTA_RETRY_SECONDS" ;;
		provider_transient_error) printf '%s\n' "$HARNESS_PROVIDER_RETRY_SECONDS" ;;
		*) return 1 ;;
	esac
}

codex_model_requires_narrow_prompt()
{
	[[ "$1" =~ (^|[-_:])terra($|[-_:]) || "$1" =~ gpt-5[.]6 ]]
}

resolve_from_env_dir()
{
	local path="$1"
	if [[ "$path" == /* ]]; then
		realpath -m "$path"
	else
		realpath -m "$HARNESS_ENV_DIR/$path"
	fi
}

resolve_command_path()
{
	local value="$1"
	if [[ "$value" == */* ]]; then
		resolve_from_env_dir "$value"
	else
		printf '%s\n' "$value"
	fi
}

load_harness_env()
{
	[[ $# -eq 1 ]] || die 'load_harness_env requires exactly one ENV_FILE argument'
	local input="$1"
	[[ -f "$input" ]] || die "environment file does not exist: $input"

	local canonical_file canonical_dir
	canonical_file="$(realpath "$input")"
	canonical_dir="$(dirname "$canonical_file")"

	local owner mode_octal mode
	owner="$(stat -c '%u' "$canonical_file")"
	mode_octal="$(stat -c '%a' "$canonical_file")"
	mode=$((8#$mode_octal))
	(( owner == UID || owner == 0 )) || die "environment file must be owned by UID $UID or root: $canonical_file"
	(( (mode & 8#022) == 0 )) || die "environment file must not be group/world writable: $canonical_file"

	unset PROJECT REPOSITORY SPECIFICATION HARNESS_HOME HARNESS_BIN HARNESS_ROOT PROJECT_TMP_DIR
	unset HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY
	unset HARNESS_MAX_IDENTICAL_BLOCKERS
	unset HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS
	unset HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	unset HARNESS_CODEX_WALL_TIMEOUT_SECONDS HARNESS_CODEX_IDLE_TIMEOUT_SECONDS HARNESS_CODEX_KILL_GRACE_SECONDS
	unset MANAGER_FALLBACK_MODEL WORKER_FALLBACK_MODEL
	unset ORACLE_MODEL ORACLE_REASONING_EFFORT ORACLE_SANDBOX ORACLE_CODEX_BIN ORACLE_CODEX_HOME ORACLE_CODEX_EXTRA_ARGS ORACLE_ENABLED
	unset HARNESS_MANAGER_INVOKER HARNESS_MANAGER_PLAN_INVOKER HARNESS_WORKER_INVOKER HARNESS_ORACLE_INVOKER
	unset CODEX_BIN CODEX_HOME
	unset CODEX_EXTRA_ARGS
	unset MANAGER_CODEX_BIN MANAGER_CODEX_HOME MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX
	unset MANAGER_CODEX_EXTRA_ARGS
	unset WORKER_CODEX_BIN WORKER_CODEX_HOME WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX
	unset WORKER_CODEX_EXTRA_ARGS
	unset WORKER_HEARTBEAT_SECONDS

	# The environment file is trusted Bash input.
	# shellcheck disable=SC1090
	source "$canonical_file"
	HARNESS_ENV_FILE="$canonical_file"
	HARNESS_ENV_DIR="$canonical_dir"

	[[ -n "${PROJECT:-}" ]] || die "PROJECT is not set in $HARNESS_ENV_FILE"
	[[ -n "${REPOSITORY:-}" ]] || die "REPOSITORY is not set in $HARNESS_ENV_FILE"
	[[ -n "${HARNESS_HOME:-}" ]] || die "HARNESS_HOME is not set in $HARNESS_ENV_FILE"

	HARNESS_HOME="$(resolve_from_env_dir "$HARNESS_HOME")"
	HARNESS_BIN="${HARNESS_BIN:-$HARNESS_HOME/bin}"
	HARNESS_BIN="$(resolve_from_env_dir "$HARNESS_BIN")"
	HARNESS_ROOT="${HARNESS_ROOT:-${XDG_RUNTIME_DIR:-/tmp}/coding-harness-${UID}}"
	HARNESS_ROOT="$(resolve_from_env_dir "$HARNESS_ROOT")"
	REPOSITORY="$(resolve_from_env_dir "$REPOSITORY")"
	PROJECT_TMP_DIR="/tmp/$PROJECT"

	SPECIFICATION="${SPECIFICATION:-}"
	if [[ -n "$SPECIFICATION" ]]; then
		SPECIFICATION="$(resolve_from_env_dir "$SPECIFICATION")"
	fi

	HARNESS_POLL_SECONDS="${HARNESS_POLL_SECONDS:-2}"
	HARNESS_WAIT_SECONDS="${HARNESS_WAIT_SECONDS:-300}"
	HARNESS_STALE_SECONDS="${HARNESS_STALE_SECONDS:-900}"
	HARNESS_USE_INOTIFY="${HARNESS_USE_INOTIFY:-1}"
	# A repeated deterministic blocker cannot be changed by another no-op worker
	# turn.  Managers may still explore a few bounded diagnostic slices, but the
	# harness converts the Nth identical zero-progress rejection into BLOCKED.
	HARNESS_MAX_IDENTICAL_BLOCKERS="${HARNESS_MAX_IDENTICAL_BLOCKERS:-3}"
	# Provider-side failures retry forever. Short transient failures use a
	# one-minute cadence; account usage-window exhaustion reports and probes every
	# five minutes until Codex confirms quota is available again.
	HARNESS_PROVIDER_RETRY_SECONDS="${HARNESS_PROVIDER_RETRY_SECONDS:-${HARNESS_CAPACITY_RETRY_SECONDS:-60}}"
	HARNESS_QUOTA_RETRY_SECONDS="${HARNESS_QUOTA_RETRY_SECONDS:-300}"
	# Retained only for backwards-compatible environment parsing. Provider
	# retries are intentionally unlimited regardless of this legacy value.
	HARNESS_CAPACITY_RETRY_SECONDS="$HARNESS_PROVIDER_RETRY_SECONDS"
	HARNESS_CAPACITY_MAX_RETRIES="${HARNESS_CAPACITY_MAX_RETRIES:-0}"
	# Correctly progressing tasks are allowed to run without an arbitrary turn
	# deadline. Operators may opt back into either watchdog with a nonzero value.
	HARNESS_CODEX_WALL_TIMEOUT_SECONDS="${HARNESS_CODEX_WALL_TIMEOUT_SECONDS:-0}"
	HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="${HARNESS_CODEX_IDLE_TIMEOUT_SECONDS:-0}"
	HARNESS_CODEX_KILL_GRACE_SECONDS="${HARNESS_CODEX_KILL_GRACE_SECONDS:-15}"
	WORKER_HEARTBEAT_SECONDS="${WORKER_HEARTBEAT_SECONDS:-60}"

	MANAGER_MODEL="${MANAGER_MODEL:-gpt-5.5}"
	MANAGER_REASONING_EFFORT="${MANAGER_REASONING_EFFORT:-high}"
	MANAGER_SANDBOX="${MANAGER_SANDBOX:-workspace-write}"
	WORKER_MODEL="${WORKER_MODEL:-gpt-5.4-mini}"
	WORKER_REASONING_EFFORT="${WORKER_REASONING_EFFORT:-high}"
	WORKER_SANDBOX="${WORKER_SANDBOX:-workspace-write}"
	MANAGER_FALLBACK_MODEL="${MANAGER_FALLBACK_MODEL:-gpt-5.5}"
	WORKER_FALLBACK_MODEL="${WORKER_FALLBACK_MODEL:-gpt-5.4-mini}"
	ORACLE_MODEL="${ORACLE_MODEL:-}"
	ORACLE_ENABLED="${ORACLE_ENABLED:-$([[ -n "$ORACLE_MODEL" ]] && printf 1 || printf 0)}"
	ORACLE_REASONING_EFFORT="${ORACLE_REASONING_EFFORT:-xhigh}"
	ORACLE_SANDBOX="${ORACLE_SANDBOX:-$MANAGER_SANDBOX}"

	MANAGER_CODEX_BIN="${MANAGER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	WORKER_CODEX_BIN="${WORKER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	MANAGER_CODEX_HOME="${MANAGER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
	WORKER_CODEX_HOME="${WORKER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
	ORACLE_CODEX_BIN="${ORACLE_CODEX_BIN:-$MANAGER_CODEX_BIN}"
	ORACLE_CODEX_HOME="${ORACLE_CODEX_HOME:-$MANAGER_CODEX_HOME}"
	MANAGER_CODEX_BIN="$(resolve_command_path "$MANAGER_CODEX_BIN")"
	WORKER_CODEX_BIN="$(resolve_command_path "$WORKER_CODEX_BIN")"
	MANAGER_CODEX_HOME="$(resolve_from_env_dir "$MANAGER_CODEX_HOME")"
	WORKER_CODEX_HOME="$(resolve_from_env_dir "$WORKER_CODEX_HOME")"
	ORACLE_CODEX_BIN="$(resolve_command_path "$ORACLE_CODEX_BIN")"
	ORACLE_CODEX_HOME="$(resolve_from_env_dir "$ORACLE_CODEX_HOME")"

	HARNESS_MANAGER_INVOKER="${HARNESS_MANAGER_INVOKER:-}"
	HARNESS_MANAGER_PLAN_INVOKER="${HARNESS_MANAGER_PLAN_INVOKER:-}"
	HARNESS_WORKER_INVOKER="${HARNESS_WORKER_INVOKER:-}"
	HARNESS_ORACLE_INVOKER="${HARNESS_ORACLE_INVOKER:-}"
	if [[ -n "$HARNESS_MANAGER_INVOKER" ]]; then
		HARNESS_MANAGER_INVOKER="$(resolve_command_path "$HARNESS_MANAGER_INVOKER")"
	fi
	if [[ -n "$HARNESS_MANAGER_PLAN_INVOKER" ]]; then
		HARNESS_MANAGER_PLAN_INVOKER="$(resolve_command_path "$HARNESS_MANAGER_PLAN_INVOKER")"
	fi
	if [[ -n "$HARNESS_WORKER_INVOKER" ]]; then
		HARNESS_WORKER_INVOKER="$(resolve_command_path "$HARNESS_WORKER_INVOKER")"
	fi
	if [[ -n "$HARNESS_ORACLE_INVOKER" ]]; then
		HARNESS_ORACLE_INVOKER="$(resolve_command_path "$HARNESS_ORACLE_INVOKER")"
	fi

	local -a shared_codex_extra_args manager_codex_extra_args worker_codex_extra_args oracle_codex_extra_args
	shared_codex_extra_args=()
	manager_codex_extra_args=()
	worker_codex_extra_args=()
	oracle_codex_extra_args=()
	load_codex_extra_args shared_codex_extra_args CODEX_EXTRA_ARGS
	load_codex_extra_args manager_codex_extra_args MANAGER_CODEX_EXTRA_ARGS
	load_codex_extra_args worker_codex_extra_args WORKER_CODEX_EXTRA_ARGS
	if declare -p ORACLE_CODEX_EXTRA_ARGS >/dev/null 2>&1; then
		load_codex_extra_args oracle_codex_extra_args ORACLE_CODEX_EXTRA_ARGS
	else
		oracle_codex_extra_args=("${manager_codex_extra_args[@]}")
	fi
	MANAGER_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${manager_codex_extra_args[@]}")
	WORKER_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${worker_codex_extra_args[@]}")
	ORACLE_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${oracle_codex_extra_args[@]}")
	if (( ${#shared_codex_extra_args[@]} > 0 )); then
		CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}")
	else
		unset CODEX_EXTRA_ARGS
	fi

	validate_project "$PROJECT"
	[[ "$HARNESS_POLL_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] || die 'HARNESS_POLL_SECONDS must be numeric'
	[[ "$HARNESS_WAIT_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_WAIT_SECONDS must be an integer'
	[[ "$HARNESS_STALE_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_STALE_SECONDS must be an integer'
	[[ "$WORKER_HEARTBEAT_SECONDS" =~ ^[0-9]+$ ]] || die 'WORKER_HEARTBEAT_SECONDS must be an integer'
	(( WORKER_HEARTBEAT_SECONDS > 0 )) || die 'WORKER_HEARTBEAT_SECONDS must be greater than zero'
	[[ "$HARNESS_USE_INOTIFY" =~ ^[01]$ ]] || die 'HARNESS_USE_INOTIFY must be 0 or 1'
	[[ "$HARNESS_MAX_IDENTICAL_BLOCKERS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_IDENTICAL_BLOCKERS must be a positive integer'
	[[ "$HARNESS_PROVIDER_RETRY_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_PROVIDER_RETRY_SECONDS must be an integer'
	(( HARNESS_PROVIDER_RETRY_SECONDS > 0 )) || die 'HARNESS_PROVIDER_RETRY_SECONDS must be greater than zero'
	[[ "$HARNESS_QUOTA_RETRY_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_QUOTA_RETRY_SECONDS must be an integer'
	(( HARNESS_QUOTA_RETRY_SECONDS > 0 )) || die 'HARNESS_QUOTA_RETRY_SECONDS must be greater than zero'
	[[ "$HARNESS_CAPACITY_MAX_RETRIES" =~ ^[0-9]+$ ]] || die 'HARNESS_CAPACITY_MAX_RETRIES must be an integer'
	[[ "$HARNESS_CODEX_WALL_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_CODEX_WALL_TIMEOUT_SECONDS must be an integer'
	[[ "$HARNESS_CODEX_IDLE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_CODEX_IDLE_TIMEOUT_SECONDS must be an integer'
	[[ "$HARNESS_CODEX_KILL_GRACE_SECONDS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_CODEX_KILL_GRACE_SECONDS must be a positive integer'
	[[ "$MANAGER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid MANAGER_MODEL: $MANAGER_MODEL"
	[[ "$WORKER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid WORKER_MODEL: $WORKER_MODEL"
	[[ "$MANAGER_FALLBACK_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid MANAGER_FALLBACK_MODEL: $MANAGER_FALLBACK_MODEL"
	[[ "$WORKER_FALLBACK_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid WORKER_FALLBACK_MODEL: $WORKER_FALLBACK_MODEL"
	[[ "$ORACLE_ENABLED" =~ ^[01]$ ]] || die 'ORACLE_ENABLED must be 0 or 1'
	if [[ "$ORACLE_ENABLED" == 1 ]]; then
		[[ "$ORACLE_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid ORACLE_MODEL: $ORACLE_MODEL"
	fi
	[[ "$MANAGER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh)$ ]] || die "invalid MANAGER_REASONING_EFFORT: $MANAGER_REASONING_EFFORT"
	[[ "$WORKER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh)$ ]] || die "invalid WORKER_REASONING_EFFORT: $WORKER_REASONING_EFFORT"
	[[ "$MANAGER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid MANAGER_SANDBOX: $MANAGER_SANDBOX"
	[[ "$WORKER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid WORKER_SANDBOX: $WORKER_SANDBOX"
	[[ "$ORACLE_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh)$ ]] || die "invalid ORACLE_REASONING_EFFORT: $ORACLE_REASONING_EFFORT"
	[[ "$ORACLE_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid ORACLE_SANDBOX: $ORACLE_SANDBOX"
	[[ "$MANAGER_CODEX_BIN" != *[[:space:]]* ]] || die 'MANAGER_CODEX_BIN must not contain arguments'
	[[ "$WORKER_CODEX_BIN" != *[[:space:]]* ]] || die 'WORKER_CODEX_BIN must not contain arguments'
	[[ "$ORACLE_CODEX_BIN" != *[[:space:]]* ]] || die 'ORACLE_CODEX_BIN must not contain arguments'
	[[ -d "$HARNESS_HOME" ]] || die "HARNESS_HOME does not exist: $HARNESS_HOME"
	[[ -d "$HARNESS_BIN" ]] || die "HARNESS_BIN does not exist: $HARNESS_BIN"

	local invoked_bin
	invoked_bin="$(realpath -m "$(dirname "${BASH_SOURCE[1]}")")"
	[[ "$invoked_bin" == "$HARNESS_BIN" ]] || die "this command was launched from $invoked_bin but ENV_FILE selects HARNESS_BIN=$HARNESS_BIN"

	export HARNESS_ENV_FILE HARNESS_ENV_DIR PROJECT REPOSITORY SPECIFICATION PROJECT_TMP_DIR
	export HARNESS_HOME HARNESS_BIN HARNESS_ROOT HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS
	export HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY HARNESS_MAX_IDENTICAL_BLOCKERS HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS
	export HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	export HARNESS_CODEX_WALL_TIMEOUT_SECONDS HARNESS_CODEX_IDLE_TIMEOUT_SECONDS HARNESS_CODEX_KILL_GRACE_SECONDS
	export WORKER_HEARTBEAT_SECONDS
	export MANAGER_CODEX_BIN MANAGER_CODEX_HOME MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX
	export WORKER_CODEX_BIN WORKER_CODEX_HOME WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX
	export MANAGER_FALLBACK_MODEL WORKER_FALLBACK_MODEL
	export ORACLE_MODEL ORACLE_ENABLED ORACLE_REASONING_EFFORT ORACLE_SANDBOX ORACLE_CODEX_BIN ORACLE_CODEX_HOME
	export HARNESS_MANAGER_INVOKER HARNESS_MANAGER_PLAN_INVOKER HARNESS_WORKER_INVOKER HARNESS_ORACLE_INVOKER
}

load_codex_extra_args()
{
	local dest_name="$1"
	local source_name="$2"
	local decl
	declare -p "$source_name" >/dev/null 2>&1 || return 0
	decl="$(declare -p "$source_name")"
	case "$decl" in
		"declare -a "*|"declare -ax "*)
			local -n dest_ref="$dest_name"
			local -n source_ref="$source_name"
			dest_ref=("${source_ref[@]}")
			;;
		*)
			die "$source_name must be a Bash array, for example: $source_name=(--config key=value)"
			;;
	esac
}

require_repository()
{
	[[ -d "$REPOSITORY" ]] || die "repository directory does not exist: $REPOSITORY"
}

require_manager_configuration()
{
	require_repository
	[[ -n "$SPECIFICATION" ]] || die "SPECIFICATION is not set in $HARNESS_ENV_FILE"
	[[ -f "$SPECIFICATION" ]] || die "specification file does not exist: $SPECIFICATION"
}

require_manager_codex()
{
	if [[ "$MANAGER_CODEX_BIN" == */* ]]; then
		[[ -x "$MANAGER_CODEX_BIN" ]] || die "manager Codex executable not found: $MANAGER_CODEX_BIN"
	else
		command -v "$MANAGER_CODEX_BIN" >/dev/null 2>&1 || die "manager Codex command not found: $MANAGER_CODEX_BIN"
	fi
	[[ -d "$MANAGER_CODEX_HOME" ]] || die "MANAGER_CODEX_HOME does not exist: $MANAGER_CODEX_HOME"
}

require_worker_codex()
{
	if [[ "$WORKER_CODEX_BIN" == */* ]]; then
		[[ -x "$WORKER_CODEX_BIN" ]] || die "worker Codex executable not found: $WORKER_CODEX_BIN"
	else
		command -v "$WORKER_CODEX_BIN" >/dev/null 2>&1 || die "worker Codex command not found: $WORKER_CODEX_BIN"
	fi
	[[ -d "$WORKER_CODEX_HOME" ]] || die "WORKER_CODEX_HOME does not exist: $WORKER_CODEX_HOME"
}

oracle_enabled()
{
	[[ "$ORACLE_ENABLED" == 1 ]]
}

require_oracle_codex()
{
	oracle_enabled || return 0
	if [[ "$ORACLE_CODEX_BIN" == */* ]]; then
		[[ -x "$ORACLE_CODEX_BIN" ]] || die "oracle Codex executable not found: $ORACLE_CODEX_BIN"
	else
		command -v "$ORACLE_CODEX_BIN" >/dev/null 2>&1 || die "oracle Codex command not found: $ORACLE_CODEX_BIN"
	fi
	[[ -d "$ORACLE_CODEX_HOME" ]] || die "ORACLE_CODEX_HOME does not exist: $ORACLE_CODEX_HOME"
}

validate_project()
{
	local project="$1"
	[[ "$project" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid project name: $project"
}

validate_task_id()
{
	local task_id="$1"
	[[ "$task_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid task id: $task_id"
}

validate_session()
{
	local session="$1"
	[[ "$session" =~ ^[A-Za-z0-9][A-Za-z0-9._:@-]*$ ]] || die "invalid session id: $session"
}

project_dir()
{
	printf '%s/projects/%s' "$HARNESS_ROOT" "$PROJECT"
}

project_tmp_dir()
{
	printf '%s\n' "$PROJECT_TMP_DIR"
}

ensure_project()
{
	local dir config stored_project stored_repository
	validate_project "$PROJECT"
	dir="$(project_dir)"
	[[ -d "$dir" ]] || die "project is not initialized for ENV_FILE $HARNESS_ENV_FILE; run harness-init"
	config="$dir/project.conf"
	[[ -f "$config" ]] || die "project configuration is missing: $config"
	stored_project="$(kv_file_value "$config" project)"
	stored_repository="$(kv_file_value "$config" repository)"
	[[ "$stored_project" == "$PROJECT" ]] || die "ENV_FILE project '$PROJECT' does not match initialized project '$stored_project'"
	[[ "$stored_repository" == "$REPOSITORY" ]] || die "REPOSITORY changed from '$stored_repository' to '$REPOSITORY'; rerun harness-init with $HARNESS_ENV_FILE"
}

task_base()
{
	local task_id="$1"
	printf '%s-task-%s' "$PROJECT" "$task_id"
}

task_root_id()
{
	local task_id="$1"
	if [[ "$task_id" =~ ^(.+)-revision-[0-9]+$ ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
	else
		printf '%s' "$task_id"
	fi
}

task_progress_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.progress.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_assignment_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.root-assignment.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_block_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.blocked.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_is_blocked()
{
	[[ -f "$(task_root_block_file "$1")" ]]
}

task_progress_percent()
{
	local file
	file="$(task_progress_file "$1")"
	if [[ -f "$file" ]]; then
		awk -F': ' '$1 == "Progress-Percent" {gsub(/%/, "", $2); print $2; exit}' "$file"
	else
		printf '0\n'
	fi
}

review_percent()
{
	local file="$1"
	local field="$2"
	awk -F': ' -v field="$field" '$1 == field {gsub(/%/, "", $2); print $2; exit}' "$file"
}

validate_percent()
{
	local value="$1"
	local label="$2"
	[[ "$value" =~ ^(100|[1-9]?[0-9])$ ]] || die "$label must be an integer from 0 through 100"
}

initialize_task_progress()
{
	local task_id="$1"
	local assignment="$2"
	local root progress root_assignment archived_root_assignment tmp
	root="$(task_root_id "$task_id")"
	progress="$(task_progress_file "$root")"
	root_assignment="$(task_root_assignment_file "$root")"
	mkdir -p "$(dirname "$progress")"
	chmod 700 "$(dirname "$progress")"
	if [[ ! -f "$root_assignment" ]]; then
		archived_root_assignment="$(project_dir)/archive/$(task_base "$root").assignment.md"
		if [[ -f "$archived_root_assignment" ]]; then
			install -m 600 "$archived_root_assignment" "$root_assignment"
		else
			install -m 600 "$assignment" "$root_assignment"
		fi
	fi
	if [[ ! -f "$progress" ]]; then
		tmp="$progress.tmp.$$"
		{
			printf '# Root Task Progress\n\n'
			printf 'Project: %s\n' "$PROJECT"
			printf 'Task-Root: %s\n' "$root"
			printf 'Progress-Percent: 0%%\n'
			printf 'Improvement-Percent: 0%%\n'
			printf 'Last-Reviewed-Task: none\n'
			printf 'Updated-At: %s\n\n' "$(timestamp_utc)"
			printf '## Evidence checkpoint\n\nNo reviewed implementation evidence yet.\n\n'
			printf '## Remaining work\n\nReconcile the repository against the root assignment.\n'
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$progress"
	fi
}

update_task_progress()
{
	local task_id="$1"
	local progress_percent="$2"
	local improvement_percent="$3"
	local decision="$4"
	local review_file="${5:-}"
	local root progress tmp
	root="$(task_root_id "$task_id")"
	progress="$(task_progress_file "$root")"
	validate_percent "$progress_percent" 'Progress-Percent'
	validate_percent "$improvement_percent" 'Improvement-Percent'
	tmp="$progress.tmp.$$"
	{
		printf '# Root Task Progress\n\n'
		printf 'Project: %s\n' "$PROJECT"
		printf 'Task-Root: %s\n' "$root"
		printf 'Progress-Percent: %s%%\n' "$progress_percent"
		printf 'Improvement-Percent: %s%%\n' "$improvement_percent"
		printf 'Last-Reviewed-Task: %s\n' "$task_id"
		printf 'Last-Decision: %s\n' "$decision"
		printf 'Updated-At: %s\n' "$(timestamp_utc)"
		if [[ -n "$review_file" && -f "$review_file" ]]; then
			printf '\n## Evidence checkpoint\n\n'
			cat "$review_file"
			printf '\n'
		fi
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$progress"
	log_event "TASK_PROGRESS_UPDATED root=$root task=$task_id progress=$progress_percent improvement=$improvement_percent decision=$decision"
}

task_id_from_filename()
{
	local filename="$1"
	filename="${filename##*/}"
	filename="${filename#${PROJECT}-task-}"
	filename="${filename%.ready.md}"
	filename="${filename%.running.md}"
	filename="${filename%.result.md}"
	printf '%s' "$filename"
}

config_value()
{
	local key="$1"
	local config
	config="$(project_dir)/project.conf"
	awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$config"
}

session_file()
{
	local session="$1"
	printf '%s/control/sessions/%s.session' "$(project_dir)" "$session"
}

ensure_session()
{
	local session="$1"
	local file
	validate_session "$session"
	file="$(session_file "$session")"
	[[ -f "$file" ]] || die "unknown session: $session"
}

lease_value()
{
	local lease="$1"
	local key="$2"
	awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$lease"
}

log_event()
{
	local dir
	dir="$(project_dir)"
	printf '%s\t%s\n' "$(timestamp_utc)" "$*" >> "$dir/logs/events.log"
}

trace_log_file()
{
	printf '%s/logs/trace.log' "$(project_dir)"
}

trace_init()
{
	local component="$1"
	local parent_trace_id="${HARNESS_TRACE_ID:-}"
	local nonce
	nonce="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || printf '%s-%s' "$$" "$(epoch_now)")"
	HARNESS_TRACE_PARENT_ID="$parent_trace_id"
	HARNESS_TRACE_COMPONENT="$component"
	HARNESS_TRACE_ID="${component}-$(date -u '+%Y%m%dT%H%M%SZ')-${nonce%%-*}"
	export HARNESS_TRACE_PARENT_ID HARNESS_TRACE_COMPONENT HARNESS_TRACE_ID
}

trace_event()
{
	local event="$1"
	shift || true
	local line
	line="$(timestamp_utc)"
	line+=" trace_id=$(printf '%q' "${HARNESS_TRACE_ID:-unknown}")"
	line+=" parent_trace_id=$(printf '%q' "${HARNESS_TRACE_PARENT_ID:-}")"
	line+=" component=$(printf '%q' "${HARNESS_TRACE_COMPONENT:-unknown}")"
	line+=" pid=$(printf '%q' "$$")"
	line+=" ppid=$(printf '%q' "$PPID")"
	line+=" event=$(printf '%q' "$event")"
	for field in "$@"; do
		line+=" $(printf '%q' "$field")"
	done
	printf '%s\n' "$line" >> "$(trace_log_file)"
}

trace_script_start()
{
	trace_event SCRIPT_START "argv_count=$#"
}

trace_script_exit()
{
	local status="$1"
	trace_event SCRIPT_EXIT "status=$status"
}

acquire_project_lock()
{
	local dir
	dir="$(project_dir)"
	exec 9>"$dir/control/project.lock"
	flock -x 9
}

kv_file_value()
{
	local file="$1"
	local key="$2"
	[[ -f "$file" ]] || die "key-value file does not exist: $file"
	awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

env_sha256()
{
	sha256sum "$HARNESS_ENV_FILE" | awk '{print $1}'
}

env_path_sha256()
{
	printf '%s' "$HARNESS_ENV_FILE" | sha256sum | awk '{print $1}'
}

env_command_lock_path()
{
	local dir
	dir="$HARNESS_ROOT/control/env-locks"
	mkdir -p "$dir"
	chmod 700 "$HARNESS_ROOT" "$HARNESS_ROOT/control" "$dir" 2>/dev/null || true
	printf '%s/%s.lock' "$dir" "$(env_path_sha256)"
}

acquire_env_command_lock()
{
	local operation="$1"
	local lock_file lock_pid
	lock_file="$(env_command_lock_path)"
	while true; do
		if ( set -o noclobber; printf 'pid=%s\nstarted_at=%s\noperation=%s\nenv_file=%s\n' \
			"${BASHPID:-$$}" "$(timestamp_utc)" "$operation" "$HARNESS_ENV_FILE" > "$lock_file" ) 2>/dev/null; then
			chmod 600 "$lock_file"
			export HARNESS_ENV_COMMAND_LOCK_FILE="$lock_file"
			trap 'release_env_command_lock' EXIT
			return 0
		fi

		lock_pid="$(kv_file_value "$lock_file" pid 2>/dev/null || true)"
		if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
			die "$operation is already running for ENV_FILE $HARNESS_ENV_FILE"
		fi
		rm -f "$lock_file"
	done
}

release_env_command_lock()
{
	local lock_file lock_pid
	lock_file="${HARNESS_ENV_COMMAND_LOCK_FILE:-}"
	[[ -n "$lock_file" && -f "$lock_file" ]] || return 0
	lock_pid="$(kv_file_value "$lock_file" pid 2>/dev/null || true)"
	if [[ "$lock_pid" == "${BASHPID:-$$}" ]]; then
		rm -f "$lock_file"
	fi
}

env_process_lines()
{
	local ignore_pids pid ppid
	ignore_pids=""
	pid="${BASHPID:-$$}"
	while [[ -n "$pid" && "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; do
		ignore_pids+="${ignore_pids:+,}$pid"
		ppid="$(ps -o ppid= -p "$pid" | tr -d '[:space:]')"
		[[ -n "$ppid" && "$ppid" != "$pid" ]] || break
		pid="$ppid"
	done

	ps -eo pid=,comm=,args= | awk -v env="$HARNESS_ENV_FILE" -v bin="$HARNESS_BIN/" -v ignore="$ignore_pids" '
		BEGIN {
			split(ignore, list, ",")
			for (i in list) {
				if (list[i] != "") {
					skip[list[i]] = 1
				}
			}
		}
		($2 == "bash" || $2 == "sh") && index($0, bin) && index($0, env) && !($1 in skip) { print }
	'
}

env_has_running_processes()
{
	[[ -n "$(env_process_lines)" ]]
}

confirm_reset_state()
{
	local reason="$1"
	local reply
	printf '%s\n' "$reason" >&2
	printf 'Reset current state for %s? [y/N] ' "$HARNESS_ENV_FILE" >&2
	if ! IFS= read -r reply; then
		die 'reset confirmation was not provided'
	fi
	[[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

reset_project_state()
{
	local dir backup_root backup_dir
	dir="$(project_dir)"

	if [[ -d "$dir" ]]; then
		if [[ -f "$dir/control/worker-supervisor.pid" || -f "$dir/control/supervisor.pid" ]]; then
			"$HARNESS_BIN/worker-supervisor-stop" "$HARNESS_ENV_FILE" >/dev/null 2>&1 || true
			"$HARNESS_BIN/manager-supervisor-stop" "$HARNESS_ENV_FILE" >/dev/null 2>&1 || true
		fi
		sleep 0.2
	fi

	if env_has_running_processes; then
		printf 'Active processes still reference %s:\n' "$HARNESS_ENV_FILE" >&2
		env_process_lines >&2
		die 'refusing to reset while environment-bound processes are still running'
	fi

	[[ -d "$dir" ]] || return 0

	backup_root="$HARNESS_ROOT/resets"
	backup_dir="$backup_root/${PROJECT}-$(timestamp_compact_utc)-$$"
	mkdir -p "$backup_root"
	chmod 700 "$backup_root"
	mv "$dir" "$backup_dir"
	printf 'Previous state moved to %s\n' "$backup_dir" >&2
}

initialize_project_state()
{
	umask 077
	mkdir -p "$HARNESS_ROOT"
	chmod 700 "$HARNESS_ROOT"
	mkdir -p "$(project_tmp_dir)"
	chmod 700 "$(project_tmp_dir)"
	mkdir -p "$(project_dir)"/{tasks,running,results,archive,control/sessions,control/progress,logs}
	chmod 700 "$(project_dir)" "$(project_dir)"/{tasks,running,results,archive,control,control/sessions,control/progress,logs}

	write_project_snapshot
	write_manager_snapshot
	write_worker_snapshot
	write_oracle_snapshot
}

project_complete_file()
{
	printf '%s/control/project.complete' "$(project_dir)"
}

project_oracle_dir()
{
	printf '%s/control/oracle' "$(project_dir)"
}

project_oracle_pending_file()
{
	printf '%s/oracle.pending.md' "$(project_oracle_dir)"
}

project_block_file()
{
	printf '%s/control/project.blocked.md' "$(project_dir)"
}

project_is_blocked()
{
	[[ -f "$(project_block_file)" ]]
}

mark_project_awaiting_oracle()
{
	local task_id="$1" note_file="${2:-}" dir pending audit_id tmp
	oracle_enabled || return 0
	dir="$(project_oracle_dir)"
	mkdir -p "$dir"
	chmod 700 "$dir"
	pending="$(project_oracle_pending_file)"
	[[ -f "$pending" ]] && return 0
	audit_id=$(( $(find "$dir" -maxdepth 1 -name 'audit-*.md' -type f 2>/dev/null | wc -l) + 1 ))
	tmp="$pending.tmp.$$"
	{
		printf '# Oracle Audit Pending\n\n'
		printf 'Project: %s\n\n' "$PROJECT"
		printf 'Audit-ID: %s\n\n' "$audit_id"
		printf 'Triggered-By-Task: %s\n\n' "$task_id"
		printf 'Triggered-At: %s\n' "$(timestamp_utc)"
		if [[ -n "$note_file" ]]; then printf '\nTrigger-Review: %s\n' "$note_file"; fi
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$pending"
	log_event "ORACLE_AUDIT_PENDING audit_id=$audit_id task=$task_id"
}

project_plan_definition_file()
{
	printf '%s/control/project-plan.tsv' "$(project_dir)"
}

project_plan_state_file()
{
	printf '%s/control/project-plan-state.tsv' "$(project_dir)"
}

project_plan_exists()
{
	[[ -f "$(project_plan_definition_file)" && -f "$(project_plan_state_file)" ]]
}

project_plan_total_count()
{
	local file
	file="$(project_plan_state_file)"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	awk -F '\t' '!/^#/ && NF >= 4 {count++} END {print count + 0}' "$file"
}

project_plan_complete_count()
{
	local file
	file="$(project_plan_state_file)"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	awk -F '\t' '!/^#/ && $2 == "COMPLETE" {count++} END {print count + 0}' "$file"
}

project_plan_pending_count()
{
	local file
	file="$(project_plan_state_file)"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	awk -F '\t' '!/^#/ && $2 != "COMPLETE" {count++} END {print count + 0}' "$file"
}

project_plan_progress_percent()
{
	local total complete
	total="$(project_plan_total_count)"
	complete="$(project_plan_complete_count)"
	if (( total == 0 )); then
		printf '0\n'
	else
		printf '%s\n' "$((complete * 100 / total))"
	fi
}

project_plan_item_status()
{
	local item_id="$1"
	awk -F '\t' -v item="$item_id" '!/^#/ && $1 == item {print $2; exit}' "$(project_plan_state_file)"
}

project_plan_item_root()
{
	local item_id="$1"
	awk -F '\t' -v item="$item_id" '!/^#/ && $1 == item {print $3; exit}' "$(project_plan_state_file)"
}

project_plan_item_for_root()
{
	local root="$1"
	awk -F '\t' -v root="$root" '!/^#/ && $3 == root {print $1; exit}' "$(project_plan_state_file)"
}

project_plan_all_complete()
{
	local total pending
	project_plan_exists || return 1
	total="$(project_plan_total_count)"
	pending="$(project_plan_pending_count)"
	(( total > 0 && pending == 0 ))
}

root_has_accepted_task()
{
	local root="$1"
	local file task
	shopt -s nullglob
	for file in "$(project_dir)/archive/$PROJECT-task-$root.accepted.md" \
		"$(project_dir)/archive/$PROJECT-task-$root-revision-"*.accepted.md; do
		task="${file##*/}"
		task="${task#${PROJECT}-task-}"
		task="${task%.accepted.md}"
		[[ "$(task_root_id "$task")" == "$root" ]] && return 0
	done
	return 1
}

initialize_project_plan()
{
	local source_file="$1"
	local definition state definition_tmp state_tmp item_id title accepted_root extra
	local seen_file
	[[ -f "$source_file" ]] || die "project plan source does not exist: $source_file"
	! project_plan_exists || die "project plan already exists: $(project_plan_definition_file)"
	definition="$(project_plan_definition_file)"
	state="$(project_plan_state_file)"
	definition_tmp="$definition.tmp.$$"
	state_tmp="$state.tmp.$$"
	seen_file="$state.seen.$$"
	: > "$seen_file"
	{
		printf '# coding-harness-project-plan-v1\n'
		printf '# project=%s\n' "$PROJECT"
		printf '# specification=%s\n' "$SPECIFICATION"
		if [[ -n "$SPECIFICATION" && -f "$SPECIFICATION" ]]; then
			printf '# specification_sha256=%s\n' "$(sha256sum "$SPECIFICATION" | awk '{print $1}')"
		fi
		printf '# created_at=%s\n' "$(timestamp_utc)"
	} > "$definition_tmp"
	{
		printf '# coding-harness-project-plan-state-v1\n'
		printf '# item_id\tstatus\ttask_root\tupdated_at\n'
	} > "$state_tmp"
	while IFS=$'\t' read -r item_id title accepted_root extra || [[ -n "${item_id:-}${title:-}${accepted_root:-}${extra:-}" ]]; do
		[[ -n "${item_id:-}" ]] || continue
		[[ "$item_id" != \#* ]] || continue
		[[ -z "${extra:-}" ]] || die "project plan item has more than three tab-separated fields: $item_id"
		[[ "$item_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid project plan item ID: $item_id"
		[[ -n "${title:-}" ]] || die "project plan item has no title: $item_id"
		! grep -Fqx -- "$item_id" "$seen_file" || die "duplicate project plan item ID: $item_id"
		printf '%s\n' "$item_id" >> "$seen_file"
		printf '%s\t%s\n' "$item_id" "$title" >> "$definition_tmp"
		if [[ -n "${accepted_root:-}" && "$accepted_root" != '-' ]]; then
			validate_task_id "$accepted_root"
			[[ "$(task_root_id "$accepted_root")" == "$accepted_root" ]] || die "accepted project plan task must be a root ID: $accepted_root"
			root_has_accepted_task "$accepted_root" || die "cannot reconcile project plan item $item_id; no accepted task exists for root $accepted_root"
			[[ "$(task_progress_percent "$accepted_root")" == 100 ]] || die "cannot reconcile project plan item $item_id; root $accepted_root is not at 100%"
			printf '%s\tCOMPLETE\t%s\t%s\n' "$item_id" "$accepted_root" "$(timestamp_utc)" >> "$state_tmp"
		else
			printf '%s\tPENDING\t-\t%s\n' "$item_id" "$(timestamp_utc)" >> "$state_tmp"
		fi
	done < "$source_file"
	rm -f "$seen_file"
	(( $(awk -F '\t' '!/^#/ && NF == 2 {count++} END {print count + 0}' "$definition_tmp") > 0 )) || die 'project plan must contain at least one item'
	chmod 600 "$definition_tmp" "$state_tmp"
	mv "$definition_tmp" "$definition"
	mv "$state_tmp" "$state"
	log_event "PROJECT_PLAN_INITIALIZED items=$(project_plan_total_count) complete=$(project_plan_complete_count) file=$definition"
	trace_event PROJECT_PLAN_INITIALIZED "items=$(project_plan_total_count)" "complete=$(project_plan_complete_count)" "definition_file=$definition" "state_file=$state"
}

activate_project_plan_item()
{
	local item_id="$1"
	local root="$2"
	local state status existing_root tmp
	state="$(project_plan_state_file)"
	project_plan_exists || die 'project plan is missing; initialize it before publishing tasks'
	status="$(project_plan_item_status "$item_id")"
	[[ -n "$status" ]] || die "unknown project plan item: $item_id"
	existing_root="$(project_plan_item_root "$item_id")"
	if [[ "$status" == ACTIVE && "$existing_root" == "$root" ]]; then
		return 0
	fi
	[[ "$status" == PENDING ]] || die "project plan item is not pending: $item_id ($status)"
	[[ -z "$(project_plan_item_for_root "$root")" ]] || die "task root is already assigned to a project plan item: $root"
	[[ -z "$(awk -F '\t' '!/^#/ && $2 == "ACTIVE" {print $1; exit}' "$state")" ]] || die 'another project plan item is already active'
	tmp="$state.tmp.$$"
	awk -F '\t' -v OFS='\t' -v item="$item_id" -v root="$root" -v now="$(timestamp_utc)" '
		/^#/ {print; next}
		$1 == item {$2 = "ACTIVE"; $3 = root; $4 = now}
		{print}
	' "$state" > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$state"
	log_event "PROJECT_PLAN_ITEM_ACTIVATED item=$item_id root=$root"
}

complete_project_plan_item_for_task()
{
	local task_id="$1"
	local root item_id state status tmp
	root="$(task_root_id "$task_id")"
	item_id="$(project_plan_item_for_root "$root")"
	[[ -n "$item_id" ]] || die "task root is not assigned to the project plan: $root"
	status="$(project_plan_item_status "$item_id")"
	[[ "$status" == ACTIVE || "$status" == COMPLETE ]] || die "project plan item cannot be completed from state $status: $item_id"
	[[ "$status" != COMPLETE ]] || return 0
	state="$(project_plan_state_file)"
	tmp="$state.tmp.$$"
	awk -F '\t' -v OFS='\t' -v item="$item_id" -v now="$(timestamp_utc)" '
		/^#/ {print; next}
		$1 == item {$2 = "COMPLETE"; $4 = now}
		{print}
	' "$state" > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$state"
	log_event "PROJECT_PLAN_ITEM_COMPLETED item=$item_id root=$root task=$task_id progress=$(project_plan_progress_percent)"
}

project_completion_recorded()
{
	[[ -f "$(project_complete_file)" ]]
}

mark_project_complete()
{
	local task_id="$1"
	local note_file="${2:-}"
	local file tmp
	project_plan_exists || die 'refusing project completion without a persistent project plan'
	project_plan_all_complete || die "refusing project completion with $(project_plan_pending_count) unfinished project plan item(s)"
	file="$(project_complete_file)"
	tmp="$file.tmp.$$"
	{
		printf 'project=%s\n' "$PROJECT"
		printf 'task_id=%s\n' "$task_id"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'completed_at=%s\n' "$(timestamp_utc)"
		if [[ -n "$note_file" ]]; then
			printf 'note_file=%s\n' "$note_file"
		fi
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
	log_event "PROJECT_COMPLETED task=$task_id file=$file"
	trace_event PROJECT_COMPLETED "task_id=$task_id" "completion_file=$file" "note_file=${note_file:-}"
}

list_descendants_of_pid()
{
	local root_pid="$1"
	ps -eo pid=,ppid= | awk -v root="$root_pid" '
		{ children[$2] = children[$2] " " $1 }
		function walk(pid,    n, ids, i) {
			n = split(children[pid], ids, /[[:space:]]+/)
			for (i = 1; i <= n; i++) {
				if (ids[i] != "") {
					print ids[i]
					walk(ids[i])
				}
			}
		}
		END { walk(root) }
	'
}

terminate_descendants_of_pid()
{
	local root_pid="$1"
	local descendants
	descendants="$(list_descendants_of_pid "$root_pid" | tr '\n' ' ' | xargs -r printf '%s ')"
	[[ -n "$descendants" ]] || return 0
	kill $descendants 2>/dev/null || true
	sleep 0.2
	kill -9 $descendants 2>/dev/null || true
}

write_project_snapshot()
{
	local config tmp
	config="$(project_dir)/project.conf"
	tmp="$config.tmp.$$"
	{
		printf 'project=%s\n' "$PROJECT"
		printf 'repository=%s\n' "$REPOSITORY"
		printf 'harness_home=%s\n' "$HARNESS_HOME"
		printf 'harness_bin=%s\n' "$HARNESS_BIN"
		printf 'project_tmp_dir=%s\n' "$(project_tmp_dir)"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}

write_manager_snapshot()
{
	local config tmp
	config="$(project_dir)/control/manager.conf"
	tmp="$config.tmp.$$"
	{
		printf 'specification=%s\n' "$SPECIFICATION"
		printf 'model=%s\n' "$MANAGER_MODEL"
		printf 'reasoning_effort=%s\n' "$MANAGER_REASONING_EFFORT"
		printf 'sandbox=%s\n' "$MANAGER_SANDBOX"
		printf 'codex_bin=%s\n' "$MANAGER_CODEX_BIN"
		printf 'codex_home=%s\n' "$MANAGER_CODEX_HOME"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}

write_worker_snapshot()
{
	local config tmp
	config="$(project_dir)/control/worker.conf"
	tmp="$config.tmp.$$"
	{
		printf 'model=%s\n' "$WORKER_MODEL"
		printf 'reasoning_effort=%s\n' "$WORKER_REASONING_EFFORT"
		printf 'sandbox=%s\n' "$WORKER_SANDBOX"
		printf 'codex_bin=%s\n' "$WORKER_CODEX_BIN"
		printf 'codex_home=%s\n' "$WORKER_CODEX_HOME"
		printf 'heartbeat_seconds=%s\n' "$WORKER_HEARTBEAT_SECONDS"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}

write_oracle_snapshot()
{
	local config tmp
	config="$(project_dir)/control/oracle.conf"
	tmp="$config.tmp.$$"
	{
		printf 'enabled=%s\n' "$ORACLE_ENABLED"
		printf 'model=%s\n' "$ORACLE_MODEL"
		printf 'reasoning_effort=%s\n' "$ORACLE_REASONING_EFFORT"
		printf 'sandbox=%s\n' "$ORACLE_SANDBOX"
		printf 'codex_bin=%s\n' "$ORACLE_CODEX_BIN"
		printf 'codex_home=%s\n' "$ORACLE_CODEX_HOME"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}
