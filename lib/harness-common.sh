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

	unset PROJECT REPOSITORY SPECIFICATION HARNESS_HOME HARNESS_BIN HARNESS_ROOT PROJECT_TMP_DIR
	unset HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY
	unset HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	unset HARNESS_MANAGER_INVOKER HARNESS_WORKER_INVOKER
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

	local -a shared_codex_extra_args manager_codex_extra_args worker_codex_extra_args
	shared_codex_extra_args=()
	manager_codex_extra_args=()
	worker_codex_extra_args=()
	load_codex_extra_args shared_codex_extra_args CODEX_EXTRA_ARGS
	load_codex_extra_args manager_codex_extra_args MANAGER_CODEX_EXTRA_ARGS
	load_codex_extra_args worker_codex_extra_args WORKER_CODEX_EXTRA_ARGS
	MANAGER_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${manager_codex_extra_args[@]}")
	WORKER_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${worker_codex_extra_args[@]}")
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

	export HARNESS_ENV_FILE HARNESS_ENV_DIR PROJECT REPOSITORY SPECIFICATION PROJECT_TMP_DIR
	export HARNESS_HOME HARNESS_BIN HARNESS_ROOT HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS
	export HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	export WORKER_HEARTBEAT_SECONDS
	export MANAGER_CODEX_BIN MANAGER_CODEX_HOME MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX
	export WORKER_CODEX_BIN WORKER_CODEX_HOME WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX
	export HARNESS_MANAGER_INVOKER HARNESS_WORKER_INVOKER
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
	mkdir -p "$(project_dir)"/{tasks,running,results,archive,control/sessions,logs}
	chmod 700 "$(project_dir)" "$(project_dir)"/{tasks,running,results,archive,control,control/sessions,logs}

	write_project_snapshot
	write_manager_snapshot
	write_worker_snapshot
}

project_complete_file()
{
	printf '%s/control/project.complete' "$(project_dir)"
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
