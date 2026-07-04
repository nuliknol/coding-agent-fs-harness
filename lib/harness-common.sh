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

epoch_now()
{
	date '+%s'
}

codex_log_has_capacity_error()
{
	local log_file="$1"
	[[ -f "$log_file" ]] || return 1
	grep -Fqi 'selected model is at capacity' "$log_file"
}

capacity_retry_allowed()
{
	local retries_already_scheduled="$1"
	(( HARNESS_CAPACITY_MAX_RETRIES == 0 || retries_already_scheduled < HARNESS_CAPACITY_MAX_RETRIES ))
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

	unset PROJECT REPOSITORY SPECIFICATION HARNESS_HOME HARNESS_BIN HARNESS_ROOT
	unset HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY
	unset HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	unset HARNESS_MANAGER_INVOKER HARNESS_WORKER_INVOKER
	unset CODEX_BIN CODEX_HOME
	unset MANAGER_CODEX_BIN MANAGER_CODEX_HOME MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX
	unset WORKER_CODEX_BIN WORKER_CODEX_HOME WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX
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

	SPECIFICATION="${SPECIFICATION:-}"
	if [[ -n "$SPECIFICATION" ]]; then
		SPECIFICATION="$(resolve_from_env_dir "$SPECIFICATION")"
	fi

	HARNESS_POLL_SECONDS="${HARNESS_POLL_SECONDS:-2}"
	HARNESS_WAIT_SECONDS="${HARNESS_WAIT_SECONDS:-300}"
	HARNESS_STALE_SECONDS="${HARNESS_STALE_SECONDS:-900}"
	HARNESS_USE_INOTIFY="${HARNESS_USE_INOTIFY:-1}"
	HARNESS_CAPACITY_RETRY_SECONDS="${HARNESS_CAPACITY_RETRY_SECONDS:-60}"
	HARNESS_CAPACITY_MAX_RETRIES="${HARNESS_CAPACITY_MAX_RETRIES:-0}"
	WORKER_HEARTBEAT_SECONDS="${WORKER_HEARTBEAT_SECONDS:-60}"

	MANAGER_MODEL="${MANAGER_MODEL:-gpt-5.5}"
	MANAGER_REASONING_EFFORT="${MANAGER_REASONING_EFFORT:-high}"
	MANAGER_SANDBOX="${MANAGER_SANDBOX:-workspace-write}"
	WORKER_MODEL="${WORKER_MODEL:-gpt-5.4-mini}"
	WORKER_REASONING_EFFORT="${WORKER_REASONING_EFFORT:-high}"
	WORKER_SANDBOX="${WORKER_SANDBOX:-workspace-write}"

	MANAGER_CODEX_BIN="${MANAGER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	WORKER_CODEX_BIN="${WORKER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	MANAGER_CODEX_HOME="${MANAGER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
	WORKER_CODEX_HOME="${WORKER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
	MANAGER_CODEX_BIN="$(resolve_command_path "$MANAGER_CODEX_BIN")"
	WORKER_CODEX_BIN="$(resolve_command_path "$WORKER_CODEX_BIN")"
	MANAGER_CODEX_HOME="$(resolve_from_env_dir "$MANAGER_CODEX_HOME")"
	WORKER_CODEX_HOME="$(resolve_from_env_dir "$WORKER_CODEX_HOME")"

	HARNESS_MANAGER_INVOKER="${HARNESS_MANAGER_INVOKER:-}"
	HARNESS_WORKER_INVOKER="${HARNESS_WORKER_INVOKER:-}"
	if [[ -n "$HARNESS_MANAGER_INVOKER" ]]; then
		HARNESS_MANAGER_INVOKER="$(resolve_command_path "$HARNESS_MANAGER_INVOKER")"
	fi
	if [[ -n "$HARNESS_WORKER_INVOKER" ]]; then
		HARNESS_WORKER_INVOKER="$(resolve_command_path "$HARNESS_WORKER_INVOKER")"
	fi

	validate_project "$PROJECT"
	[[ "$HARNESS_POLL_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] || die 'HARNESS_POLL_SECONDS must be numeric'
	[[ "$HARNESS_WAIT_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_WAIT_SECONDS must be an integer'
	[[ "$HARNESS_STALE_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_STALE_SECONDS must be an integer'
	[[ "$WORKER_HEARTBEAT_SECONDS" =~ ^[0-9]+$ ]] || die 'WORKER_HEARTBEAT_SECONDS must be an integer'
	(( WORKER_HEARTBEAT_SECONDS > 0 )) || die 'WORKER_HEARTBEAT_SECONDS must be greater than zero'
	[[ "$HARNESS_USE_INOTIFY" =~ ^[01]$ ]] || die 'HARNESS_USE_INOTIFY must be 0 or 1'
	[[ "$HARNESS_CAPACITY_RETRY_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_CAPACITY_RETRY_SECONDS must be an integer'
	(( HARNESS_CAPACITY_RETRY_SECONDS > 0 )) || die 'HARNESS_CAPACITY_RETRY_SECONDS must be greater than zero'
	[[ "$HARNESS_CAPACITY_MAX_RETRIES" =~ ^[0-9]+$ ]] || die 'HARNESS_CAPACITY_MAX_RETRIES must be an integer'
	[[ "$MANAGER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid MANAGER_MODEL: $MANAGER_MODEL"
	[[ "$WORKER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid WORKER_MODEL: $WORKER_MODEL"
	[[ "$MANAGER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh)$ ]] || die "invalid MANAGER_REASONING_EFFORT: $MANAGER_REASONING_EFFORT"
	[[ "$WORKER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh)$ ]] || die "invalid WORKER_REASONING_EFFORT: $WORKER_REASONING_EFFORT"
	[[ "$MANAGER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid MANAGER_SANDBOX: $MANAGER_SANDBOX"
	[[ "$WORKER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid WORKER_SANDBOX: $WORKER_SANDBOX"
	[[ "$MANAGER_CODEX_BIN" != *[[:space:]]* ]] || die 'MANAGER_CODEX_BIN must not contain arguments'
	[[ "$WORKER_CODEX_BIN" != *[[:space:]]* ]] || die 'WORKER_CODEX_BIN must not contain arguments'
	[[ -d "$HARNESS_HOME" ]] || die "HARNESS_HOME does not exist: $HARNESS_HOME"
	[[ -d "$HARNESS_BIN" ]] || die "HARNESS_BIN does not exist: $HARNESS_BIN"

	local invoked_bin
	invoked_bin="$(realpath -m "$(dirname "${BASH_SOURCE[1]}")")"
	[[ "$invoked_bin" == "$HARNESS_BIN" ]] || die "this command was launched from $invoked_bin but ENV_FILE selects HARNESS_BIN=$HARNESS_BIN"

	export HARNESS_ENV_FILE HARNESS_ENV_DIR PROJECT REPOSITORY SPECIFICATION
	export HARNESS_HOME HARNESS_BIN HARNESS_ROOT HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS
	export HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	export WORKER_HEARTBEAT_SECONDS
	export MANAGER_CODEX_BIN MANAGER_CODEX_HOME MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX
	export WORKER_CODEX_BIN WORKER_CODEX_HOME WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX
	export HARNESS_MANAGER_INVOKER HARNESS_WORKER_INVOKER
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
