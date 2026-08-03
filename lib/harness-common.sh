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

load_array_setting()
{
	local destination="$1"
	local variable="$2"
	local declaration
	eval "$destination=()"
	declaration="$(declare -p "$variable" 2>/dev/null || true)"
	[[ -n "$declaration" ]] || return 0
	[[ "$declaration" == "declare -a "* ]] ||
		die "$variable must be a Bash array"
	eval "$destination=(\"\${$variable[@]}\")"
}

load_harness_env()
{
	[[ $# -eq 1 ]] || die 'load_harness_env requires ENV_FILE'
	local input="$1"
	[[ -f "$input" ]] || die "environment file does not exist: $input"

	local canonical_file owner mode_octal mode
	canonical_file="$(realpath "$input")"
	owner="$(stat -c '%u' "$canonical_file")"
	mode_octal="$(stat -c '%a' "$canonical_file")"
	mode=$((8#$mode_octal))
	(( owner == UID || owner == 0 )) ||
		die "environment file must be owned by UID $UID or root: $canonical_file"
	(( (mode & 8#022) == 0 )) ||
		die "environment file must not be group/world writable: $canonical_file"

	unset PROJECT REPOSITORY SPECIFICATION DEVELOPMENT_POLICY HARNESS_HOME HARNESS_ROOT HARNESS_BIN
	unset MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX MANAGER_CODEX_BIN MANAGER_CODEX_HOME
	unset WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX WORKER_CODEX_BIN WORKER_CODEX_HOME
	unset MANAGER_CODEX_EXTRA_ARGS WORKER_CODEX_EXTRA_ARGS CODEX_EXTRA_ARGS CODEX_BIN CODEX_HOME
	unset HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS HARNESS_MAX_MANAGER_REVIEWS
	unset HARNESS_MAX_REPEATED_FINDING_REVIEWS
	unset HARNESS_MANAGER_REVIEW_CHECKLIST
	unset HARNESS_CODEX_WALL_TIMEOUT_SECONDS HARNESS_CODEX_IDLE_TIMEOUT_SECONDS
	unset HARNESS_CODEX_KILL_GRACE_SECONDS
	unset HARNESS_CODEX_DIAGNOSTIC_PROFILE
	unset HARNESS_CODEX_RUST_LOG HARNESS_CODEX_STRACE
	unset HARNESS_CODEX_STRACE_STRING_BYTES HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS
	unset HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS

	# The environment file is trusted Bash configuration.
	# shellcheck disable=SC1090
	source "$canonical_file"
	HARNESS_ENV_FILE="$canonical_file"
	HARNESS_ENV_DIR="$(dirname "$canonical_file")"

	[[ -n "${PROJECT:-}" ]] || die "PROJECT is not set in $canonical_file"
	[[ "$PROJECT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
		die "invalid PROJECT: $PROJECT"
	[[ -n "${REPOSITORY:-}" ]] || die "REPOSITORY is not set in $canonical_file"
	[[ -n "${SPECIFICATION:-}" ]] || die "SPECIFICATION is not set in $canonical_file"
	[[ -n "${DEVELOPMENT_POLICY:-}" ]] ||
		die "DEVELOPMENT_POLICY is not set in $canonical_file"
	[[ -n "${HARNESS_HOME:-}" ]] || die "HARNESS_HOME is not set in $canonical_file"

	REPOSITORY="$(resolve_from_env_dir "$REPOSITORY")"
	SPECIFICATION="$(resolve_from_env_dir "$SPECIFICATION")"
	DEVELOPMENT_POLICY="$(resolve_from_env_dir "$DEVELOPMENT_POLICY")"
	HARNESS_HOME="$(resolve_from_env_dir "$HARNESS_HOME")"
	HARNESS_BIN="${HARNESS_BIN:-$HARNESS_HOME/bin}"
	HARNESS_BIN="$(resolve_from_env_dir "$HARNESS_BIN")"
	HARNESS_ROOT="${HARNESS_ROOT:-${XDG_STATE_HOME:-$HARNESS_ENV_DIR/.state}/coding-harness-light}"
	HARNESS_ROOT="$(resolve_from_env_dir "$HARNESS_ROOT")"

	[[ -d "$REPOSITORY" ]] || die "repository directory does not exist: $REPOSITORY"
	[[ -f "$SPECIFICATION" ]] || die "specification does not exist: $SPECIFICATION"
	[[ -f "$DEVELOPMENT_POLICY" ]] ||
		die "development policy does not exist: $DEVELOPMENT_POLICY"
	[[ -d "$HARNESS_HOME" ]] || die "HARNESS_HOME does not exist: $HARNESS_HOME"
	[[ -d "$HARNESS_BIN" ]] || die "HARNESS_BIN does not exist: $HARNESS_BIN"

	MANAGER_MODEL="${MANAGER_MODEL:-gpt-5.6-terra}"
	MANAGER_REASONING_EFFORT="${MANAGER_REASONING_EFFORT:-high}"
	MANAGER_SANDBOX="${MANAGER_SANDBOX:-workspace-write}"
	WORKER_MODEL="${WORKER_MODEL:-gpt-5.6-luna}"
	WORKER_REASONING_EFFORT="${WORKER_REASONING_EFFORT:-high}"
	WORKER_SANDBOX="${WORKER_SANDBOX:-workspace-write}"

	MANAGER_CODEX_BIN="${MANAGER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	WORKER_CODEX_BIN="${WORKER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	MANAGER_CODEX_HOME="${MANAGER_CODEX_HOME:-${CODEX_HOME:-${HOME}/.codex}}"
	WORKER_CODEX_HOME="${WORKER_CODEX_HOME:-${CODEX_HOME:-${HOME}/.codex}}"
	MANAGER_CODEX_BIN="$(resolve_command_path "$MANAGER_CODEX_BIN")"
	WORKER_CODEX_BIN="$(resolve_command_path "$WORKER_CODEX_BIN")"
	MANAGER_CODEX_HOME="$(resolve_from_env_dir "$MANAGER_CODEX_HOME")"
	WORKER_CODEX_HOME="$(resolve_from_env_dir "$WORKER_CODEX_HOME")"

	HARNESS_PROVIDER_RETRY_SECONDS="${HARNESS_PROVIDER_RETRY_SECONDS:-60}"
	HARNESS_QUOTA_RETRY_SECONDS="${HARNESS_QUOTA_RETRY_SECONDS:-600}"
	HARNESS_MAX_MANAGER_REVIEWS="${HARNESS_MAX_MANAGER_REVIEWS:-50}"
	HARNESS_MAX_REPEATED_FINDING_REVIEWS="${HARNESS_MAX_REPEATED_FINDING_REVIEWS:-3}"
	HARNESS_MANAGER_REVIEW_CHECKLIST="${HARNESS_MANAGER_REVIEW_CHECKLIST:-none}"
	HARNESS_CODEX_WALL_TIMEOUT_SECONDS="${HARNESS_CODEX_WALL_TIMEOUT_SECONDS:-0}"
	HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="${HARNESS_CODEX_IDLE_TIMEOUT_SECONDS:-0}"
	HARNESS_CODEX_KILL_GRACE_SECONDS="${HARNESS_CODEX_KILL_GRACE_SECONDS:-15}"
	HARNESS_CODEX_DIAGNOSTIC_PROFILE="${HARNESS_CODEX_DIAGNOSTIC_PROFILE:-0}"
	[[ "$HARNESS_CODEX_DIAGNOSTIC_PROFILE" =~ ^(0|1)$ ]] ||
		die 'HARNESS_CODEX_DIAGNOSTIC_PROFILE must be 0 or 1'
	if (( HARNESS_CODEX_DIAGNOSTIC_PROFILE )); then
		HARNESS_CODEX_RUST_LOG="${HARNESS_CODEX_RUST_LOG-codex_core=debug}"
		HARNESS_CODEX_STRACE="${HARNESS_CODEX_STRACE:-1}"
		HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS="${HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS:-1800}"
		HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS="${HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS:-900}"
	else
		HARNESS_CODEX_RUST_LOG="${HARNESS_CODEX_RUST_LOG-}"
		HARNESS_CODEX_STRACE="${HARNESS_CODEX_STRACE:-0}"
		HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS="${HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS:-0}"
		HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS="${HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS:-0}"
	fi
	HARNESS_CODEX_STRACE_STRING_BYTES="${HARNESS_CODEX_STRACE_STRING_BYTES:-80}"

	[[ "$MANAGER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid MANAGER_MODEL: $MANAGER_MODEL"
	[[ "$WORKER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid WORKER_MODEL: $WORKER_MODEL"
	[[ "$MANAGER_REASONING_EFFORT" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] ||
		die "invalid MANAGER_REASONING_EFFORT: $MANAGER_REASONING_EFFORT"
	[[ "$WORKER_REASONING_EFFORT" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] ||
		die "invalid WORKER_REASONING_EFFORT: $WORKER_REASONING_EFFORT"
	[[ "$MANAGER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] ||
		die "invalid MANAGER_SANDBOX: $MANAGER_SANDBOX"
	[[ "$WORKER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] ||
		die "invalid WORKER_SANDBOX: $WORKER_SANDBOX"
	[[ "$HARNESS_MANAGER_REVIEW_CHECKLIST" =~ ^(none|c-strict)$ ]] ||
		die "invalid HARNESS_MANAGER_REVIEW_CHECKLIST: $HARNESS_MANAGER_REVIEW_CHECKLIST"
	for value in HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS \
		HARNESS_MAX_MANAGER_REVIEWS HARNESS_MAX_REPEATED_FINDING_REVIEWS \
		HARNESS_CODEX_WALL_TIMEOUT_SECONDS \
		HARNESS_CODEX_IDLE_TIMEOUT_SECONDS HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS \
		HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS; do
		[[ "${!value}" =~ ^[0-9]+$ ]] || die "$value must be a nonnegative integer"
	done
	[[ "$HARNESS_CODEX_STRACE" =~ ^(0|1)$ ]] ||
		die 'HARNESS_CODEX_STRACE must be 0 or 1'
	[[ "$HARNESS_CODEX_STRACE_STRING_BYTES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_CODEX_STRACE_STRING_BYTES must be a positive integer'
	[[ "$HARNESS_CODEX_RUST_LOG" != *$'\n'* &&
		"$HARNESS_CODEX_RUST_LOG" != *$'\r'* ]] ||
		die 'HARNESS_CODEX_RUST_LOG must be a single line'
	[[ "$HARNESS_CODEX_KILL_GRACE_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_CODEX_KILL_GRACE_SECONDS must be a positive integer'
	(( HARNESS_PROVIDER_RETRY_SECONDS > 0 )) ||
		die 'HARNESS_PROVIDER_RETRY_SECONDS must be positive'
	(( HARNESS_QUOTA_RETRY_SECONDS > 0 )) ||
		die 'HARNESS_QUOTA_RETRY_SECONDS must be positive'

	local -a shared_args manager_args worker_args
	load_array_setting shared_args CODEX_EXTRA_ARGS
	load_array_setting manager_args MANAGER_CODEX_EXTRA_ARGS
	load_array_setting worker_args WORKER_CODEX_EXTRA_ARGS
	MANAGER_CODEX_EXTRA_ARGS=("${shared_args[@]}" "${manager_args[@]}")
	WORKER_CODEX_EXTRA_ARGS=("${shared_args[@]}" "${worker_args[@]}")
}

project_dir()
{
	printf '%s/projects/%s\n' "$HARNESS_ROOT" "$PROJECT"
}

state_file()
{
	printf '%s/control/state.env\n' "$(project_dir)"
}

events_file()
{
	printf '%s/logs/events.log\n' "$(project_dir)"
}

project_config_value()
{
	local key="$1"
	local file="$(project_dir)/project.conf"
	[[ -f "$file" ]] || return 1
	awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$file"
}

repository_head_commit()
{
	git -C "$REPOSITORY" rev-parse --verify 'HEAD^{commit}' 2>/dev/null
}

require_repository_initialization_state()
{
	local allow_dirty="$1"
	local changes
	git -C "$REPOSITORY" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
		die "repository is not a Git working tree: $REPOSITORY"
	repository_head_commit >/dev/null ||
		die "repository does not have a valid HEAD commit: $REPOSITORY"
	changes="$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)"
	if [[ -n "$changes" && "$allow_dirty" != 1 ]]; then
		printf '%s\n' "$changes" >&2
		die 'repository has uncommitted or untracked files; commit/clean it or rerun harness-init with --force'
	fi
}

state_value()
{
	local key="$1"
	local file
	file="$(state_file)"
	[[ -f "$file" ]] || return 1
	awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$file"
}

write_state()
{
	local status="$1"
	local phase="$2"
	local cycle="$3"
	local dir file tmp started completed
	dir="$(project_dir)"
	file="$(state_file)"
	tmp="$file.tmp.$$"
	started="$(state_value started_at 2>/dev/null || true)"
	[[ -n "$started" ]] || started="$(timestamp_utc)"
	completed="$(state_value completed_at 2>/dev/null || true)"
	if [[ "$status" == COMPLETE && -z "$completed" ]]; then
		completed="$(timestamp_utc)"
	fi
	{
		printf 'status=%s\n' "$status"
		printf 'phase=%s\n' "$phase"
		printf 'cycle=%s\n' "$cycle"
		printf 'started_at=%s\n' "$started"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
		printf 'completed_at=%s\n' "$completed"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
}

ensure_project()
{
	[[ -f "$(state_file)" ]] || die "project is not initialized; run harness-init $HARNESS_ENV_FILE"
}

initialize_project()
{
	local dir baseline_commit
	dir="$(project_dir)"
	baseline_commit="$(repository_head_commit)" ||
		die "repository does not have a valid HEAD commit: $REPOSITORY"
	[[ ! -e "$dir" ]] || die "project state already exists: $dir"
	umask 077
	mkdir -p "$dir"/{addenda,control,inputs,logs,outputs,prompts,reviews}
	cp "$SPECIFICATION" "$dir/inputs/specification.txt"
	cp "$DEVELOPMENT_POLICY" "$dir/inputs/development-policy.txt"
	{
		printf 'project=%s\n' "$PROJECT"
		printf 'repository=%s\n' "$REPOSITORY"
		printf 'repository_launch_commit=%s\n' "$baseline_commit"
		printf 'environment=%s\n' "$HARNESS_ENV_FILE"
		printf 'source_specification=%s\n' "$SPECIFICATION"
		printf 'source_development_policy=%s\n' "$DEVELOPMENT_POLICY"
		printf 'specification_sha256=%s\n' "$(sha256sum "$SPECIFICATION" | awk '{print $1}')"
		printf 'development_policy_sha256=%s\n' "$(sha256sum "$DEVELOPMENT_POLICY" | awk '{print $1}')"
		printf 'manager_model=%s\n' "$MANAGER_MODEL"
		printf 'worker_model=%s\n' "$WORKER_MODEL"
		printf 'manager_review_checklist=%s\n' "$HARNESS_MANAGER_REVIEW_CHECKLIST"
		printf 'max_manager_reviews=%s\n' "$HARNESS_MAX_MANAGER_REVIEWS"
		printf 'max_repeated_finding_reviews=%s\n' \
			"$HARNESS_MAX_REPEATED_FINDING_REVIEWS"
		printf 'codex_rust_log=%s\n' "$HARNESS_CODEX_RUST_LOG"
		printf 'codex_diagnostic_profile=%s\n' \
			"$HARNESS_CODEX_DIAGNOSTIC_PROFILE"
		printf 'codex_strace=%s\n' "$HARNESS_CODEX_STRACE"
		printf 'codex_stall_diagnostic_seconds=%s\n' \
			"$HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS"
		printf 'codex_stall_diagnostic_repeat_seconds=%s\n' \
			"$HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS"
	} > "$dir/project.conf"
	chmod 600 "$dir/project.conf"
	: > "$dir/logs/events.log"
	write_state ACTIVE GOAL_REQUIRED 0
}

log_event()
{
	printf '%s\t%s\n' "$(timestamp_utc)" "$*" >> "$(events_file)"
}

codex_thread_id_from_jsonl()
{
	local file="$1"
	jq -rs '[.[] | select(.type == "thread.started") | .thread_id][0] // empty' \
		"$file" 2>/dev/null
}

codex_classification()
{
	local jsonl="$1"
	local file="${jsonl%.jsonl}.classification"
	[[ -f "$file" ]] || {
		printf 'unknown\n'
		return
	}
	awk -F= '$1 == "classification" { print $2; exit }' "$file"
}

provider_retry_delay()
{
	case "$1" in
		provider_quota_exhausted) printf '%s\n' "$HARNESS_QUOTA_RETRY_SECONDS" ;;
		provider_transient_error) printf '%s\n' "$HARNESS_PROVIDER_RETRY_SECONDS" ;;
		*) return 1 ;;
	esac
}

manager_finding_ids()
{
	local file="$1"
	awk '
		{
			line = $0
			gsub(/[`*]/, "", line)
			sub(/^[[:space:]]*/, "", line)
			sub(/^([0-9]+[.)]|[-+]|#+)[[:space:]]+/, "", line)
			sub(/^[[:space:]]*/, "", line)
			if (match(line, /^ADD-[0-9][0-9][0-9]([^0-9]|$)/))
				print substr(line, 1, 7)
		}
	' "$file"
}

manager_finding_keys()
{
	local file="$1"
	awk '
		{
			line = $0
			gsub(/[`*]/, "", line)
			sub(/^[[:space:]]*/, "", line)
			sub(/^([0-9]+[.)]|[-+]|#+)[[:space:]]+/, "", line)
			sub(/^[[:space:]]*/, "", line)
			if (line ~ /^Finding-Key[[:space:]]*:/) {
				sub(/^Finding-Key[[:space:]]*:[[:space:]]*/, "", line)
				sub(/[[:space:]]+$/, "", line)
				print line
			}
		}
	' "$file"
}

validate_manager_findings()
{
	local file="$1"
	local decision="$2"
	local finding_count key key_count=0
	local -A seen=()
	[[ "$decision" == REVISE || "$decision" == ACTIONABLE ]] || return 0

	finding_count="$(manager_finding_ids "$file" | wc -l | tr -d ' ')"
	(( finding_count > 0 )) || {
		printf '%s requires at least one ADD-NNN finding\n' "$decision" >&2
		return 1
	}
	while IFS= read -r key; do
		((key_count += 1))
		[[ "$key" =~ ^[a-z0-9][a-z0-9._-]*$ && ${#key} -le 128 ]] || {
			printf 'invalid Finding-Key: %s\n' "$key" >&2
			return 1
		}
		[[ -z "${seen[$key]:-}" ]] || {
			printf 'duplicate Finding-Key: %s\n' "$key" >&2
			return 1
		}
		seen[$key]=1
	done < <(manager_finding_keys "$file")
	(( key_count == finding_count )) || {
		printf '%s has %s ADD-NNN findings but %s Finding-Key lines\n' \
			"$decision" "$finding_count" "$key_count" >&2
		return 1
	}
}

repeated_manager_finding_keys()
{
	local review_dir="$1"
	local cycle="$2"
	local threshold="$3"
	local last_audit_cycle="${4:-0}"
	local current key review streak
	(( threshold > 0 && cycle - last_audit_cycle >= threshold )) || return 0
	current="$review_dir/review-$(printf '%03d' "$cycle").md"
	[[ -f "$current" ]] || return 0
	while IFS= read -r key; do
		streak=0
		for ((review = cycle; review > last_audit_cycle; review--)); do
			if ! manager_finding_keys \
				"$review_dir/review-$(printf '%03d' "$review").md" \
				2>/dev/null | grep -Fqx -- "$key"; then
				break
			fi
			streak=$((streak + 1))
		done
		(( streak < threshold )) || printf '%s\n' "$key"
	done < <(manager_finding_keys "$current")
}

usage_sum_by_thread()
{
	local directory="$1"
	local pattern="$2"
	local field="$3"
	while IFS= read -r -d '' file; do
		jq -rs --arg field "$field" --arg fallback "$file" '
			([.[] | select(.type == "thread.started") | .thread_id] |
			 first // $fallback) as $thread
			| ([.[] | select(.type == "turn.completed") |
				(.usage[$field] // 0)] | max // 0) as $value
			| [$thread, $value] | @tsv
		' "$file" 2>/dev/null
	done < <(find "$directory" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null) |
		awk -F '\t' '
			NF >= 2 && $2 > maximum[$1] { maximum[$1] = $2 }
			END {
				for (thread in maximum) total += maximum[thread]
				print total + 0
			}'
}

require_runtime()
{
	local value="$1"
	if [[ "$value" == */* ]]; then
		[[ -x "$value" ]] || die "Codex executable is not executable: $value"
	else
		command -v "$value" >/dev/null 2>&1 ||
			die "Codex command was not found: $value"
	fi
}

require_dependencies()
{
	local command
	for command in cmp diff flock jq mktemp realpath setsid sha256sum stat timeout; do
		command -v "$command" >/dev/null 2>&1 ||
			die "required command was not found: $command"
	done
	if (( HARNESS_CODEX_STRACE )); then
		command -v strace >/dev/null 2>&1 ||
			die 'HARNESS_CODEX_STRACE=1 requires strace'
	fi
	require_runtime "$MANAGER_CODEX_BIN"
	require_runtime "$WORKER_CODEX_BIN"
}

supervisor_pid()
{
	local file
	file="$(project_dir)/control/supervisor.pid"
	[[ -f "$file" ]] || return 1
	awk 'NR == 1 { print; exit }' "$file"
}

supervisor_running()
{
	local pid command_line
	pid="$(supervisor_pid 2>/dev/null || true)"
	[[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
	kill -0 "$pid" 2>/dev/null || return 1
	[[ -r "/proc/$pid/cmdline" ]] || return 1
	command_line="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
	[[ "$command_line" == *harness-supervisor* &&
		"$command_line" == *"$HARNESS_ENV_FILE"* ]]
}
