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

	unset PROJECT REPOSITORY SPECIFICATION DEVELOPMENT_POLICY HARNESS_MODE harness_mode HARNESS_MODE_HOME HARNESS_HOME HARNESS_ROOT HARNESS_BIN
	unset MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX MANAGER_CODEX_BIN MANAGER_CODEX_HOME
	unset WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX WORKER_CODEX_BIN WORKER_CODEX_HOME
	unset ORACLE_MODEL ORACLE_REASONING_EFFORT ORACLE_SANDBOX ORACLE_CODEX_BIN ORACLE_CODEX_HOME
	unset CONVERGENCE_MODEL CONVERGENCE_REASONING_EFFORT CONVERGENCE_SANDBOX
	unset CONVERGENCE_CODEX_BIN CONVERGENCE_CODEX_HOME
	unset MANAGER_CODEX_EXTRA_ARGS WORKER_CODEX_EXTRA_ARGS ORACLE_CODEX_EXTRA_ARGS
	unset CONVERGENCE_CODEX_EXTRA_ARGS
	unset CODEX_EXTRA_ARGS CODEX_BIN CODEX_HOME MAX_ORACLE_RUNS
	unset HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS HARNESS_MAX_MANAGER_REVIEWS
	unset HARNESS_MAX_PROTOCOL_REPAIR_ATTEMPTS
	unset HARNESS_MAX_REPEATED_FINDING_REVIEWS
	unset HARNESS_MAX_NO_SOURCE_PROGRESS_REVIEWS
	unset HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS
	unset HARNESS_MAX_MANAGER_REVIEWS_AFTER_ORACLE
	unset HARNESS_MAX_LOW_YIELD_REVIEWS HARNESS_MAX_WORKTREE_OSCILLATIONS
	unset HARNESS_MAX_FINDING_REAPPEARANCES HARNESS_MAX_COMPLETION_STAGNANT_AUDITS
	unset HARNESS_PROGRESS_AUDIT_EVERY_REVIEWS
	unset HARNESS_METRICS_ENABLED HARNESS_METRICS_IMAGE_WIDTH HARNESS_METRICS_IMAGE_HEIGHT
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
	HARNESS_MODE="${HARNESS_MODE:-${harness_mode:-light}}"
	[[ "$HARNESS_MODE" == light ]] || die "light-mode command received HARNESS_MODE=$HARNESS_MODE"

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
	if [[ -f "$HARNESS_HOME/prompts/manager-goal.md" ]]; then
		HARNESS_MODE_HOME="$HARNESS_HOME"
	else
		HARNESS_MODE_HOME="$HARNESS_HOME/modes/light"
	fi
	HARNESS_ROOT="${HARNESS_ROOT:-${XDG_STATE_HOME:-$HARNESS_ENV_DIR/.state}/coding-harness-light}"
	HARNESS_ROOT="$(resolve_from_env_dir "$HARNESS_ROOT")"

	[[ -d "$REPOSITORY" ]] || die "repository directory does not exist: $REPOSITORY"
	[[ -f "$SPECIFICATION" ]] || die "specification does not exist: $SPECIFICATION"
	[[ -f "$DEVELOPMENT_POLICY" ]] ||
		die "development policy does not exist: $DEVELOPMENT_POLICY"
	[[ -d "$HARNESS_HOME" ]] || die "HARNESS_HOME does not exist: $HARNESS_HOME"
	[[ -d "$HARNESS_BIN" ]] || die "HARNESS_BIN does not exist: $HARNESS_BIN"
	[[ -d "$HARNESS_MODE_HOME/prompts" ]] || die "light-mode prompts do not exist: $HARNESS_MODE_HOME/prompts"

	MANAGER_MODEL="${MANAGER_MODEL:-gpt-5.6-terra}"
	MANAGER_REASONING_EFFORT="${MANAGER_REASONING_EFFORT:-high}"
	MANAGER_SANDBOX="${MANAGER_SANDBOX:-workspace-write}"
	WORKER_MODEL="${WORKER_MODEL:-gpt-5.6-luna}"
	WORKER_REASONING_EFFORT="${WORKER_REASONING_EFFORT:-high}"
	WORKER_SANDBOX="${WORKER_SANDBOX:-workspace-write}"
	ORACLE_MODEL="${ORACLE_MODEL:-gpt-5.6-sol}"
	ORACLE_REASONING_EFFORT="${ORACLE_REASONING_EFFORT:-xhigh}"
	ORACLE_SANDBOX="${ORACLE_SANDBOX:-$MANAGER_SANDBOX}"
	MAX_ORACLE_RUNS="${MAX_ORACLE_RUNS:-1}"
	CONVERGENCE_MODEL="${CONVERGENCE_MODEL:-gpt-5.6-terra}"
	CONVERGENCE_REASONING_EFFORT="${CONVERGENCE_REASONING_EFFORT:-xhigh}"
	CONVERGENCE_SANDBOX="${CONVERGENCE_SANDBOX:-$MANAGER_SANDBOX}"

	MANAGER_CODEX_BIN="${MANAGER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	WORKER_CODEX_BIN="${WORKER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	ORACLE_CODEX_BIN="${ORACLE_CODEX_BIN:-$MANAGER_CODEX_BIN}"
	CONVERGENCE_CODEX_BIN="${CONVERGENCE_CODEX_BIN:-$MANAGER_CODEX_BIN}"
	MANAGER_CODEX_HOME="${MANAGER_CODEX_HOME:-${CODEX_HOME:-${HOME}/.codex}}"
	WORKER_CODEX_HOME="${WORKER_CODEX_HOME:-${CODEX_HOME:-${HOME}/.codex}}"
	ORACLE_CODEX_HOME="${ORACLE_CODEX_HOME:-$MANAGER_CODEX_HOME}"
	CONVERGENCE_CODEX_HOME="${CONVERGENCE_CODEX_HOME:-$MANAGER_CODEX_HOME}"
	MANAGER_CODEX_BIN="$(resolve_command_path "$MANAGER_CODEX_BIN")"
	WORKER_CODEX_BIN="$(resolve_command_path "$WORKER_CODEX_BIN")"
	ORACLE_CODEX_BIN="$(resolve_command_path "$ORACLE_CODEX_BIN")"
	CONVERGENCE_CODEX_BIN="$(resolve_command_path "$CONVERGENCE_CODEX_BIN")"
	MANAGER_CODEX_HOME="$(resolve_from_env_dir "$MANAGER_CODEX_HOME")"
	WORKER_CODEX_HOME="$(resolve_from_env_dir "$WORKER_CODEX_HOME")"
	ORACLE_CODEX_HOME="$(resolve_from_env_dir "$ORACLE_CODEX_HOME")"
	CONVERGENCE_CODEX_HOME="$(resolve_from_env_dir "$CONVERGENCE_CODEX_HOME")"

	HARNESS_PROVIDER_RETRY_SECONDS="${HARNESS_PROVIDER_RETRY_SECONDS:-60}"
	HARNESS_QUOTA_RETRY_SECONDS="${HARNESS_QUOTA_RETRY_SECONDS:-600}"
	HARNESS_MAX_MANAGER_REVIEWS="${HARNESS_MAX_MANAGER_REVIEWS:-20}"
	HARNESS_MAX_MANAGER_REVIEWS_AFTER_ORACLE="${HARNESS_MAX_MANAGER_REVIEWS_AFTER_ORACLE:-5}"
	HARNESS_MAX_PROTOCOL_REPAIR_ATTEMPTS="${HARNESS_MAX_PROTOCOL_REPAIR_ATTEMPTS:-2}"
	HARNESS_MAX_REPEATED_FINDING_REVIEWS="${HARNESS_MAX_REPEATED_FINDING_REVIEWS:-3}"
	HARNESS_MAX_NO_SOURCE_PROGRESS_REVIEWS="${HARNESS_MAX_NO_SOURCE_PROGRESS_REVIEWS:-5}"
	HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS="${HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS:-3}"
	HARNESS_MAX_LOW_YIELD_REVIEWS="${HARNESS_MAX_LOW_YIELD_REVIEWS:-4}"
	HARNESS_MAX_WORKTREE_OSCILLATIONS="${HARNESS_MAX_WORKTREE_OSCILLATIONS:-2}"
	HARNESS_MAX_FINDING_REAPPEARANCES="${HARNESS_MAX_FINDING_REAPPEARANCES:-2}"
	HARNESS_MAX_COMPLETION_STAGNANT_AUDITS="${HARNESS_MAX_COMPLETION_STAGNANT_AUDITS:-2}"
	HARNESS_PROGRESS_AUDIT_EVERY_REVIEWS="${HARNESS_PROGRESS_AUDIT_EVERY_REVIEWS:-10}"
	HARNESS_METRICS_ENABLED="${HARNESS_METRICS_ENABLED:-1}"
	HARNESS_METRICS_IMAGE_WIDTH="${HARNESS_METRICS_IMAGE_WIDTH:-1800}"
	HARNESS_METRICS_IMAGE_HEIGHT="${HARNESS_METRICS_IMAGE_HEIGHT:-1200}"
	HARNESS_MANAGER_REVIEW_CHECKLIST="${HARNESS_MANAGER_REVIEW_CHECKLIST:-none}"
	HARNESS_CODEX_WALL_TIMEOUT_SECONDS="${HARNESS_CODEX_WALL_TIMEOUT_SECONDS:-0}"
	HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="${HARNESS_CODEX_IDLE_TIMEOUT_SECONDS:-0}"
	HARNESS_CODEX_KILL_GRACE_SECONDS="${HARNESS_CODEX_KILL_GRACE_SECONDS:-15}"
	HARNESS_CODEX_DIAGNOSTIC_PROFILE="${HARNESS_CODEX_DIAGNOSTIC_PROFILE:-0}"
	[[ "$HARNESS_CODEX_DIAGNOSTIC_PROFILE" =~ ^(0|1)$ ]] ||
		die 'HARNESS_CODEX_DIAGNOSTIC_PROFILE must be 0 or 1'
	if (( HARNESS_CODEX_DIAGNOSTIC_PROFILE )); then
		HARNESS_CODEX_RUST_LOG="${HARNESS_CODEX_RUST_LOG-codex_core=debug}"
		HARNESS_CODEX_STRACE="${HARNESS_CODEX_STRACE:-0}"
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
	[[ "$ORACLE_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid ORACLE_MODEL: $ORACLE_MODEL"
	[[ "$CONVERGENCE_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid CONVERGENCE_MODEL: $CONVERGENCE_MODEL"
	[[ "$MANAGER_REASONING_EFFORT" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] ||
		die "invalid MANAGER_REASONING_EFFORT: $MANAGER_REASONING_EFFORT"
	[[ "$WORKER_REASONING_EFFORT" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] ||
		die "invalid WORKER_REASONING_EFFORT: $WORKER_REASONING_EFFORT"
	[[ "$ORACLE_REASONING_EFFORT" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] ||
		die "invalid ORACLE_REASONING_EFFORT: $ORACLE_REASONING_EFFORT"
	[[ "$CONVERGENCE_REASONING_EFFORT" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] ||
		die "invalid CONVERGENCE_REASONING_EFFORT: $CONVERGENCE_REASONING_EFFORT"
	[[ "$MANAGER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] ||
		die "invalid MANAGER_SANDBOX: $MANAGER_SANDBOX"
	[[ "$WORKER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] ||
		die "invalid WORKER_SANDBOX: $WORKER_SANDBOX"
	[[ "$ORACLE_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] ||
		die "invalid ORACLE_SANDBOX: $ORACLE_SANDBOX"
	[[ "$CONVERGENCE_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] ||
		die "invalid CONVERGENCE_SANDBOX: $CONVERGENCE_SANDBOX"
	[[ "$HARNESS_MANAGER_REVIEW_CHECKLIST" =~ ^(none|c-strict)$ ]] ||
		die "invalid HARNESS_MANAGER_REVIEW_CHECKLIST: $HARNESS_MANAGER_REVIEW_CHECKLIST"
	[[ "$HARNESS_METRICS_ENABLED" =~ ^(0|1)$ ]] ||
		die 'HARNESS_METRICS_ENABLED must be 0 or 1'
	for value in HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS \
		HARNESS_MAX_MANAGER_REVIEWS HARNESS_MAX_MANAGER_REVIEWS_AFTER_ORACLE \
		HARNESS_MAX_PROTOCOL_REPAIR_ATTEMPTS \
		HARNESS_MAX_REPEATED_FINDING_REVIEWS \
		HARNESS_MAX_NO_SOURCE_PROGRESS_REVIEWS \
		HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS \
		HARNESS_MAX_LOW_YIELD_REVIEWS HARNESS_MAX_WORKTREE_OSCILLATIONS \
		HARNESS_MAX_FINDING_REAPPEARANCES HARNESS_MAX_COMPLETION_STAGNANT_AUDITS \
		HARNESS_PROGRESS_AUDIT_EVERY_REVIEWS HARNESS_METRICS_IMAGE_WIDTH \
		HARNESS_METRICS_IMAGE_HEIGHT MAX_ORACLE_RUNS \
		HARNESS_CODEX_WALL_TIMEOUT_SECONDS \
		HARNESS_CODEX_IDLE_TIMEOUT_SECONDS HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS \
		HARNESS_CODEX_STALL_DIAGNOSTIC_REPEAT_SECONDS; do
		[[ "${!value}" =~ ^[0-9]+$ ]] || die "$value must be a non-negative integer"
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
	(( HARNESS_METRICS_IMAGE_WIDTH >= 640 )) ||
		die 'HARNESS_METRICS_IMAGE_WIDTH must be at least 640'
	(( HARNESS_METRICS_IMAGE_HEIGHT >= 480 )) ||
		die 'HARNESS_METRICS_IMAGE_HEIGHT must be at least 480'

	local -a shared_args manager_args worker_args oracle_args convergence_args
	load_array_setting shared_args CODEX_EXTRA_ARGS
	load_array_setting manager_args MANAGER_CODEX_EXTRA_ARGS
	load_array_setting worker_args WORKER_CODEX_EXTRA_ARGS
	load_array_setting oracle_args ORACLE_CODEX_EXTRA_ARGS
	if declare -p CONVERGENCE_CODEX_EXTRA_ARGS >/dev/null 2>&1; then
		load_array_setting convergence_args CONVERGENCE_CODEX_EXTRA_ARGS
	else
		convergence_args=("${manager_args[@]}")
	fi
	MANAGER_CODEX_EXTRA_ARGS=("${shared_args[@]}" "${manager_args[@]}")
	WORKER_CODEX_EXTRA_ARGS=("${shared_args[@]}" "${worker_args[@]}")
	ORACLE_CODEX_EXTRA_ARGS=("${shared_args[@]}" "${oracle_args[@]}")
	CONVERGENCE_CODEX_EXTRA_ARGS=("${shared_args[@]}" "${convergence_args[@]}")
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

# The metrics repository is deliberately separate from REPOSITORY/.git.  It owns
# snapshots only; it never writes the project's index, refs, or commit history.
metrics_dir()
{
	printf '%s/metrics\n' "$(project_dir)"
}

metrics_git_dir()
{
	printf '%s/git\n' "$(metrics_dir)"
}

metrics_index_file()
{
	printf '%s/index\n' "$(metrics_dir)"
}

metrics_ref_for_cycle()
{
	local cycle="$1"
	[[ "$cycle" =~ ^[0-9]+$ ]] || die "invalid metrics cycle: $cycle"
	printf 'refs/harness-metrics/cycles/%03d\n' "$((10#$cycle))"
}

metrics_git()
{
	local git_dir index
	git_dir="$(metrics_git_dir)"
	index="$(metrics_index_file)"
	GIT_DIR="$git_dir" GIT_INDEX_FILE="$index" GIT_WORK_TREE="$REPOSITORY" \
		git -C "$REPOSITORY" "$@"
}

metrics_bare_git()
{
	git --git-dir="$(metrics_git_dir)" "$@"
}

metrics_path_category()
{
	local path="$1" lower
	lower="${path,,}"
	case "$lower" in
		*/test/*|*/tests/*|test_*|*_test.*|*_tests.*|*/fixtures/*|*/spec/*|*/specs/*)
			printf 'tests\n'
			;;
		*.md|*.rst|*.adoc|*.txt)
			printf 'docs\n'
			;;
		makefile|*/makefile|cmakelists.txt|*/cmakelists.txt|*.cmake|*.mk|configure|configure.ac|meson.build|meson_options.txt|package.json|cargo.toml|go.mod)
			printf 'build\n'
			;;
		*.c|*.h|*.cc|*.cp|*.cpp|*.cxx|*.hpp|*.hh|*.hxx|*.m|*.mm|*.hip|*.cu|*.py|*.rs|*.go|*.java|*.kt|*.kts|*.js|*.jsx|*.ts|*.tsx|*.cs|*.swift|*.sh|*.bash|*.zsh|*.fish|*.pl|*.pm|*.rb|*.php|*.lua|*.sql)
			printf 'source\n'
			;;
		*)
			printf 'other\n'
			;;
	esac
}

metrics_numstat()
{
	local from="$1" to="$2" detail="$3" summary="$4"
	local added deleted path category
	local source_added=0 source_deleted=0 source_files=0
	local tests_added=0 tests_deleted=0 tests_files=0
	local docs_added=0 docs_deleted=0 docs_files=0
	local build_added=0 build_deleted=0 build_files=0
	local other_added=0 other_deleted=0 other_files=0 binary_files=0
	[[ -z "$detail" ]] || printf 'path\tcategory\tadded\tdeleted\n' > "$detail"
	while IFS=$'\t' read -r added deleted path; do
		[[ -n "$path" ]] || continue
		category="$(metrics_path_category "$path")"
		if [[ "$added" == - || "$deleted" == - ]]; then
			binary_files=$((binary_files + 1))
			added=0
			deleted=0
		fi
		[[ -z "$detail" ]] || printf '%s\t%s\t%s\t%s\n' \
			"$path" "$category" "$added" "$deleted" >> "$detail"
		case "$category" in
			source)
				source_added=$((source_added + added)); source_deleted=$((source_deleted + deleted)); source_files=$((source_files + 1))
				;;
			tests)
				tests_added=$((tests_added + added)); tests_deleted=$((tests_deleted + deleted)); tests_files=$((tests_files + 1))
				;;
			docs)
				docs_added=$((docs_added + added)); docs_deleted=$((docs_deleted + deleted)); docs_files=$((docs_files + 1))
				;;
			build)
				build_added=$((build_added + added)); build_deleted=$((build_deleted + deleted)); build_files=$((build_files + 1))
				;;
			*)
				other_added=$((other_added + added)); other_deleted=$((other_deleted + deleted)); other_files=$((other_files + 1))
				;;
		esac
	done < <(metrics_bare_git diff --no-ext-diff --numstat "$from" "$to")
	{
		printf 'source_added=%s\nsource_deleted=%s\nsource_files=%s\n' "$source_added" "$source_deleted" "$source_files"
		printf 'tests_added=%s\ntests_deleted=%s\ntests_files=%s\n' "$tests_added" "$tests_deleted" "$tests_files"
		printf 'docs_added=%s\ndocs_deleted=%s\ndocs_files=%s\n' "$docs_added" "$docs_deleted" "$docs_files"
		printf 'build_added=%s\nbuild_deleted=%s\nbuild_files=%s\n' "$build_added" "$build_deleted" "$build_files"
		printf 'other_added=%s\nother_deleted=%s\nother_files=%s\nbinary_files=%s\n' "$other_added" "$other_deleted" "$other_files" "$binary_files"
	} > "$summary"
}

metrics_value()
{
	local file="$1" key="$2"
	awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$file"
}

metrics_write_cycle_record()
{
	local cycle="$1" commit="$2" parent="$3" initial="$4"
	local metrics record detail patch delta cumulative csv header diff_base
	metrics="$(metrics_dir)"
	record="$metrics/cycles/cycle-$(printf '%03d' "$((10#$cycle))").env"
	detail="$metrics/cycles/cycle-$(printf '%03d' "$((10#$cycle))").numstat.tsv"
	patch="$metrics/cycles/cycle-$(printf '%03d' "$((10#$cycle))").patch"
	delta="$metrics/cycles/cycle-$(printf '%03d' "$((10#$cycle))").delta.env"
	cumulative="$metrics/cycles/cycle-$(printf '%03d' "$((10#$cycle))").cumulative.env"
	csv="$metrics/cycles.csv"
	if (( initial )); then
		: > "$detail"
		printf 'path\tcategory\tadded\tdeleted\n' > "$detail"
		diff_base='4b825dc642cb6eb9a060e54bf8d69288fbee4904'
		metrics_bare_git diff --binary --no-ext-diff "$diff_base" "$commit" > "$patch"
		metrics_numstat "$commit" "$commit" '' "$delta"
		metrics_numstat "$commit" "$commit" '' "$cumulative"
	else
		metrics_bare_git diff --binary --no-ext-diff "$parent" "$commit" > "$patch"
		metrics_numstat "$parent" "$commit" "$detail" "$delta"
		metrics_numstat "$(metrics_ref_for_cycle 0)" "$commit" '' "$cumulative"
	fi
	{
		printf 'cycle=%s\nrecorded_at=%s\nsnapshot=%s\nparent_snapshot=%s\n' \
			"$cycle" "$(timestamp_utc)" "$commit" "${parent:-none}"
		cat "$delta"
		while IFS= read -r line; do printf 'cumulative_%s\n' "$line"; done < "$cumulative"
	} > "$record"
	chmod 600 "$record" "$detail" "$patch" "$delta" "$cumulative"
	header='cycle,recorded_at,snapshot,parent_snapshot,source_added,source_deleted,source_files,tests_added,tests_deleted,tests_files,docs_added,docs_deleted,docs_files,build_added,build_deleted,build_files,other_added,other_deleted,other_files,binary_files,cumulative_source_added,cumulative_source_deleted,cumulative_source_files'
	if [[ ! -f "$csv" ]]; then
		printf '%s\n' "$header" > "$csv"
	fi
	# A retry of a completed cycle must not silently produce a duplicate row.
	grep -q "^${cycle}," "$csv" 2>/dev/null || {
		printf '%s,%s,%s,%s' "$cycle" "$(metrics_value "$record" recorded_at)" "$commit" "${parent:-none}"
		for key in source_added source_deleted source_files tests_added tests_deleted tests_files \
			docs_added docs_deleted docs_files build_added build_deleted build_files other_added \
			other_deleted other_files binary_files cumulative_source_added \
			cumulative_source_deleted cumulative_source_files; do
			printf ',%s' "$(metrics_value "$record" "$key")"
		done
		printf '\n'
	} >> "$csv"
	chmod 600 "$csv"
}

metrics_snapshot()
{
	local cycle="$1" kind="${2:-worker}" metrics git_dir ref latest parent tree commit
	[[ "$HARNESS_METRICS_ENABLED" == 1 ]] || return 0
	metrics="$(metrics_dir)"
	git_dir="$(metrics_git_dir)"
	[[ -d "$git_dir" ]] || {
		printf 'metrics repository is unavailable: %s\n' "$git_dir" >&2
		return 1
	}
	ref="$(metrics_ref_for_cycle "$cycle")"
	if metrics_bare_git rev-parse --verify -q "$ref" >/dev/null; then
		return 0
	fi
	latest='refs/harness-metrics/latest'
	parent="$(metrics_bare_git rev-parse --verify -q "$latest" 2>/dev/null || true)"
	if [[ -n "$parent" ]]; then
		metrics_git read-tree "$parent^{tree}" || return 1
	else
		metrics_git read-tree --empty || return 1
	fi
	metrics_git add -A -- . || return 1
	tree="$(metrics_git write-tree)" || return 1
	if [[ -n "$parent" ]]; then
		commit="$(GIT_DIR="$git_dir" GIT_INDEX_FILE="$(metrics_index_file)" GIT_WORK_TREE="$REPOSITORY" \
			GIT_AUTHOR_NAME='Harness metrics' GIT_AUTHOR_EMAIL='harness-metrics@local' \
			GIT_COMMITTER_NAME='Harness metrics' GIT_COMMITTER_EMAIL='harness-metrics@local' \
			git -C "$REPOSITORY" commit-tree "$tree" -p "$parent" <<EOF
Harness metrics snapshot: cycle $cycle ($kind)
EOF
)"
	else
		commit="$(GIT_DIR="$git_dir" GIT_INDEX_FILE="$(metrics_index_file)" GIT_WORK_TREE="$REPOSITORY" \
			GIT_AUTHOR_NAME='Harness metrics' GIT_AUTHOR_EMAIL='harness-metrics@local' \
			GIT_COMMITTER_NAME='Harness metrics' GIT_COMMITTER_EMAIL='harness-metrics@local' \
			git -C "$REPOSITORY" commit-tree "$tree" <<EOF
Harness metrics snapshot: cycle $cycle ($kind)
EOF
)"
	fi
	metrics_bare_git update-ref "$ref" "$commit" || return 1
	metrics_bare_git update-ref "$latest" "$commit" || return 1
	metrics_write_cycle_record "$cycle" "$commit" "$parent" \
		"$([[ "$cycle" == 0 ]] && printf 1 || printf 0)" || return 1
}

metrics_initialize()
{
	local metrics git_dir
	[[ "$HARNESS_METRICS_ENABLED" == 1 ]] || return 0
	metrics="$(metrics_dir)"
	git_dir="$(metrics_git_dir)"
	mkdir -p "$metrics/cycles" "$metrics/graphs"
	git init --bare -q "$git_dir"
	{
		printf 'repository=%s\n' "$REPOSITORY"
		printf 'initialized_at=%s\n' "$(timestamp_utc)"
		printf 'launch_commit=%s\n' "$(repository_head_commit)"
		printf 'description=Sidecar Git snapshots; this repository never changes the project Git history or index.\n'
	} > "$metrics/metadata.env"
	chmod 600 "$metrics/metadata.env"
	metrics_snapshot 0 initial
}

metrics_generate_provenance()
{
	local metrics git_dir latest provenance path hash cycle total_agent_lines=0
	local -a snapshot_cycles
	local -A cycle_by_commit origin_count
	metrics="$(metrics_dir)"
	git_dir="$(metrics_git_dir)"
	provenance="$metrics/provenance.csv"
	[[ -d "$git_dir" ]] || die "metrics repository is unavailable: $git_dir"
	latest="$(metrics_bare_git rev-parse --verify -q refs/harness-metrics/latest 2>/dev/null)" ||
		die 'metrics repository has no snapshots'
	while IFS=' ' read -r hash cycle; do
		[[ -n "$hash" && "$cycle" =~ ^[0-9]+$ ]] || continue
		cycle="$((10#$cycle))"
		cycle_by_commit["$hash"]="$cycle"
		snapshot_cycles+=("$cycle")
	done < <(metrics_bare_git for-each-ref --format='%(objectname) %(refname:lstrip=3)' \
		refs/harness-metrics/cycles)
	while IFS= read -r -d '' path; do
		[[ "$(metrics_path_category "$path")" == source ]] || continue
		while IFS= read -r hash; do
			hash="${hash#^}"
			cycle="${cycle_by_commit[$hash]:-unknown}"
			origin_count["$cycle"]=$(( ${origin_count[$cycle]:-0} + 1 ))
		done < <(metrics_bare_git blame --line-porcelain "$latest" -- "$path" 2>/dev/null |
			awk 'length($1) == 40 && $1 ~ /^\^?[0-9a-f]+$/ { print $1 }')
	done < <(metrics_bare_git ls-tree -r -z --name-only "$latest")
	for cycle in "${!origin_count[@]}"; do
		[[ "$cycle" =~ ^[0-9]+$ ]] && (( cycle > 0 )) || continue
		total_agent_lines=$((total_agent_lines + origin_count[$cycle]))
	done
	{
		printf 'cycle,source_lines,origin,percent_of_agent_attributed_source\n'
		for cycle in "${snapshot_cycles[@]}"; do
			local count="${origin_count[$cycle]:-0}" percent=0
			if (( cycle > 0 && total_agent_lines > 0 )); then
				percent=$(( count * 10000 / total_agent_lines ))
			fi
			printf '%s,%s,%s,%s.%02d\n' "$cycle" "$count" \
				"$([[ "$cycle" == 0 ]] && printf baseline || printf worker-cycle)" \
			"$((percent / 100))" "$((percent % 100))"
		done
		if [[ -n "${origin_count[unknown]:-}" ]]; then
			printf 'unknown,%s,unmapped,0.00\n' "${origin_count[unknown]}"
		fi
	} > "$provenance"
	chmod 600 "$provenance"
}

metrics_generate_survival()
{
	local metrics csv provenance survival cycle source_added current_lines percent
	local -A current_by_cycle
	metrics="$(metrics_dir)"
	csv="$metrics/cycles.csv"
	provenance="$metrics/provenance.csv"
	survival="$metrics/survival.csv"
	while IFS=, read -r cycle current_lines _origin _percent; do
		[[ "$cycle" =~ ^[0-9]+$ ]] || continue
		current_by_cycle["$cycle"]="$current_lines"
	done < "$provenance"
	{
		printf 'cycle,source_added,source_deleted,current_source_lines_attributed,retained_percent_of_source_added\n'
		while IFS=, read -r cycle _recorded _snapshot _parent source_added source_deleted _rest; do
			[[ "$cycle" =~ ^[0-9]+$ ]] || continue
			current_lines="${current_by_cycle[$cycle]:-0}"
			percent=0
			if (( source_added > 0 )); then
				percent=$((current_lines * 10000 / source_added))
			fi
			printf '%s,%s,%s,%s,%s.%02d\n' "$cycle" "$source_added" \
				"$source_deleted" "$current_lines" "$((percent / 100))" "$((percent % 100))"
		done < "$csv"
	} > "$survival"
	chmod 600 "$survival"
}

metrics_generate_report()
{
	local metrics csv provenance survival report status phase cycle
	metrics="$(metrics_dir)"
	csv="$metrics/cycles.csv"
	provenance="$metrics/provenance.csv"
	survival="$metrics/survival.csv"
	report="$metrics/report.md"
	[[ -f "$csv" ]] || die "metrics report is unavailable: $csv"
	metrics_generate_provenance
	metrics_generate_survival
	status="$(state_value status 2>/dev/null || printf unknown)"
	phase="$(state_value phase 2>/dev/null || printf unknown)"
	cycle="$(state_value cycle 2>/dev/null || printf unknown)"
	{
		printf '# Harness code metrics\n\n'
		printf 'This report is generated only from the sidecar Git snapshots in `%s`.  It does not invoke an LLM and does not change the project Git history or index.\n\n' \
			"$(metrics_git_dir)"
		printf 'Current harness state: **%s / %s**, cycle **%s**.\n\n' "$status" "$phase" "$cycle"
		printf '## Per-worker source deltas\n\n'
		printf '| Cycle | Source + | Source - | Source files | Tests + | Tests - | Build + | Build - |\n'
		printf '| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n'
		while IFS=, read -r row_cycle row_recorded row_snapshot row_parent \
			source_added source_deleted source_files tests_added tests_deleted tests_files \
			docs_added docs_deleted docs_files build_added build_deleted _rest; do
			[[ "$row_cycle" == cycle ]] && continue
			printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
				"$row_cycle" "$source_added" "$source_deleted" "$source_files" \
				"$tests_added" "$tests_deleted" "$build_added" "$build_deleted"
		done < "$csv"
		printf '\n## Latest source-line provenance\n\n'
		printf 'A source line is attributed to the worker cycle that last introduced or materially changed it in the snapshot history. Cycle 0 is the launch baseline.\n\n'
		printf '| Origin | Source lines | Share of worker-attributed source |\n'
		printf '| --- | ---: | ---: |\n'
		while IFS=, read -r row_cycle source_lines origin percent; do
			[[ "$row_cycle" == cycle ]] && continue
			printf '| %s (%s) | %s | %s%% |\n' "$origin" "$row_cycle" "$source_lines" "$percent"
		done < "$provenance"
		printf '\n## Source retention by cycle\n\n'
		printf 'This is mechanical line provenance, not an LLM judgment: it compares source lines added in a cycle with current source lines whose final sidecar `git blame` origin is that cycle. Refactors can lower this value even when the behavior survives.\n\n'
		printf '| Cycle | Source + | Source - | Current source lines attributed | Retained of additions |\n'
		printf '| ---: | ---: | ---: | ---: | ---: |\n'
		while IFS=, read -r row_cycle source_added source_deleted current_lines retained; do
			[[ "$row_cycle" == cycle ]] && continue
			printf '| %s | %s | %s | %s | %s%% |\n' \
				"$row_cycle" "$source_added" "$source_deleted" "$current_lines" "$retained"
		done < "$survival"
		printf '\n## Inspecting a range\n\n'
		printf 'Use `harness-diff-range %q FROM_CYCLE TO_CYCLE` to inspect the exact sidecar Git diff for any cycle range.\n' "$HARNESS_ENV_FILE"
	} > "$report"
	chmod 600 "$report"
	printf '%s\n' "$report"
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

repository_worktree_fingerprint()
{
	(
		cd "$REPOSITORY"
		{
			printf 'tracked-and-index\0'
			git diff --binary --no-ext-diff HEAD --
			printf '\0untracked\0'
			while IFS= read -r -d '' path; do
				printf '%s\0' "$path"
				if [[ -L "$path" ]]; then
					printf 'symlink\0%s\0' "$(readlink "$path")"
				elif [[ -f "$path" ]]; then
					git hash-object --no-filters -- "$path"
				else
					printf 'special\0'
				fi
			done < <(git ls-files --others --exclude-standard -z | sort -z)
		} | sha256sum | awk '{ print $1 }'
	)
}

no_source_progress_count()
{
	local file="$(project_dir)/control/no-source-progress-count"
	local value=0
	[[ ! -f "$file" ]] || value="$(awk 'NR == 1 { print; exit }' "$file")"
	[[ "$value" =~ ^[0-9]+$ ]] || value=0
	printf '%s\n' "$value"
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
	local configured_mode
	[[ -f "$(state_file)" ]] || die "project is not initialized; run harness-init $HARNESS_ENV_FILE"
	configured_mode="$(project_config_value harness_mode 2>/dev/null || true)"
	[[ -z "$configured_mode" || "$configured_mode" == "$HARNESS_MODE" ]] ||
		die "project state was initialized in HARNESS_MODE=$configured_mode, not $HARNESS_MODE"
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
		printf 'harness_mode=%s\n' "$HARNESS_MODE"
		printf 'repository_launch_commit=%s\n' "$baseline_commit"
		printf 'environment=%s\n' "$HARNESS_ENV_FILE"
		printf 'source_specification=%s\n' "$SPECIFICATION"
		printf 'source_development_policy=%s\n' "$DEVELOPMENT_POLICY"
		printf 'specification_sha256=%s\n' "$(sha256sum "$SPECIFICATION" | awk '{print $1}')"
		printf 'development_policy_sha256=%s\n' "$(sha256sum "$DEVELOPMENT_POLICY" | awk '{print $1}')"
		printf 'manager_model=%s\n' "$MANAGER_MODEL"
		printf 'worker_model=%s\n' "$WORKER_MODEL"
		printf 'oracle_model=%s\n' "$ORACLE_MODEL"
		printf 'oracle_reasoning_effort=%s\n' "$ORACLE_REASONING_EFFORT"
		printf 'convergence_model=%s\n' "$CONVERGENCE_MODEL"
		printf 'convergence_reasoning_effort=%s\n' "$CONVERGENCE_REASONING_EFFORT"
		printf 'max_oracle_runs=%s\n' "$MAX_ORACLE_RUNS"
		printf 'manager_review_checklist=%s\n' "$HARNESS_MANAGER_REVIEW_CHECKLIST"
		printf 'max_manager_reviews=%s\n' "$HARNESS_MAX_MANAGER_REVIEWS"
		printf 'max_manager_reviews_after_oracle=%s\n' \
			"$HARNESS_MAX_MANAGER_REVIEWS_AFTER_ORACLE"
		printf 'max_protocol_repair_attempts=%s\n' \
			"$HARNESS_MAX_PROTOCOL_REPAIR_ATTEMPTS"
		printf 'max_repeated_finding_reviews=%s\n' \
			"$HARNESS_MAX_REPEATED_FINDING_REVIEWS"
		printf 'max_no_source_progress_reviews=%s\n' \
			"$HARNESS_MAX_NO_SOURCE_PROGRESS_REVIEWS"
		printf 'max_repeated_convergence_audits=%s\n' \
			"$HARNESS_MAX_REPEATED_CONVERGENCE_AUDITS"
		printf 'max_low_yield_reviews=%s\n' "$HARNESS_MAX_LOW_YIELD_REVIEWS"
		printf 'max_worktree_oscillations=%s\n' "$HARNESS_MAX_WORKTREE_OSCILLATIONS"
		printf 'max_finding_reappearances=%s\n' "$HARNESS_MAX_FINDING_REAPPEARANCES"
		printf 'max_completion_stagnant_audits=%s\n' \
			"$HARNESS_MAX_COMPLETION_STAGNANT_AUDITS"
		printf 'progress_audit_every_reviews=%s\n' \
			"$HARNESS_PROGRESS_AUDIT_EVERY_REVIEWS"
		printf 'metrics_enabled=%s\n' "$HARNESS_METRICS_ENABLED"
		printf 'metrics_image_width=%s\n' "$HARNESS_METRICS_IMAGE_WIDTH"
		printf 'metrics_image_height=%s\n' "$HARNESS_METRICS_IMAGE_HEIGHT"
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
	metrics_initialize
	if [[ "$HARNESS_METRICS_ENABLED" == 1 ]]; then
		log_event "METRICS_INITIALIZED snapshot=$(metrics_ref_for_cycle 0) directory=$(metrics_dir)"
	fi
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
	[[ "$decision" == REVISE || "$decision" == ACTIONABLE || \
		"$decision" == CONTINUE ]] || return 0

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

manager_progress_value()
{
	local report="$1"
	local key="$2"
	awk -v key="$key" '
		$0 == "PROGRESS-DELTA: BEGIN" { active = 1; next }
		$0 == "PROGRESS-DELTA-COMPLETE" { exit }
		active && index($0, key ":") == 1 {
			value = substr($0, length(key) + 2)
			sub(/^[[:space:]]+/, "", value)
			sub(/[[:space:]]+$/, "", value)
			if (!seen++) print value
		}
	' "$report"
}

manager_progress_value_count()
{
	local report="$1"
	local key="$2"
	awk -v key="$key" '
		$0 == "PROGRESS-DELTA: BEGIN" { active = 1; next }
		$0 == "PROGRESS-DELTA-COMPLETE" { exit }
		active && index($0, key ":") == 1 { count += 1 }
		END { print count + 0 }
	' "$report"
}

progress_list_items()
{
	local value="$1"
	[[ "$value" != none ]] || return 0
	tr ',' '\n' <<< "$value" | awk '
		{
			gsub(/^[[:space:]]+|[[:space:]]+$/, "")
			if ($0 != "") print
		}
	' | sort -u
}

validate_progress_identifier_list()
{
	local field="$1"
	local value="$2"
	local item count=0
	[[ "$value" == none ]] && return 0
	while IFS= read -r item; do
		((count += 1))
		[[ "$item" =~ ^[a-z0-9][a-z0-9._-]*$ && ${#item} -le 128 ]] || {
			printf 'invalid %s progress identifier: %s\n' "$field" "$item" >&2
			return 1
		}
	done < <(progress_list_items "$value")
	(( count > 0 )) || {
		printf '%s must be none or a comma-separated identifier list\n' "$field" >&2
		return 1
	}
}

validate_manager_progress_delta()
{
	local report="$1"
	local cycle="$2"
	local review_dir="$3"
	local field value resolved new gained lost net previous
	local expected_resolved expected_new actual
	local tmp_root
	[[ "$(grep -Fxc 'PROGRESS-DELTA: BEGIN' "$report" || true)" == 1 &&
		"$(grep -Fxc 'PROGRESS-DELTA-COMPLETE' "$report" || true)" == 1 ]] || {
		printf 'manager report requires exactly one progress-delta block\n' >&2
		return 1
	}
	for field in Resolved-Findings New-Findings Verification-Gained \
		Verification-Lost Net-Progress; do
		[[ "$(manager_progress_value_count "$report" "$field")" == 1 ]] || {
			printf 'progress delta requires exactly one %s field\n' "$field" >&2
			return 1
		}
	done
	resolved="$(manager_progress_value "$report" Resolved-Findings)"
	new="$(manager_progress_value "$report" New-Findings)"
	gained="$(manager_progress_value "$report" Verification-Gained)"
	lost="$(manager_progress_value "$report" Verification-Lost)"
	net="$(manager_progress_value "$report" Net-Progress)"
	validate_progress_identifier_list Resolved-Findings "$resolved" || return 1
	validate_progress_identifier_list New-Findings "$new" || return 1
	validate_progress_identifier_list Verification-Gained "$gained" || return 1
	validate_progress_identifier_list Verification-Lost "$lost" || return 1
	[[ "$net" == YES || "$net" == NO ]] || {
		printf 'Net-Progress must be YES or NO\n' >&2
		return 1
	}

	tmp_root="$(mktemp -d)"
	previous="$review_dir/../addenda/addendum-$(printf '%03d' "$((cycle - 1))").md"
	[[ -f "$previous" ]] ||
		previous="$review_dir/review-$(printf '%03d' "$((cycle - 1))").md"
	if [[ -f "$previous" ]]; then
		manager_finding_keys "$previous" | sort -u > "$tmp_root/previous"
	else
		: > "$tmp_root/previous"
	fi
	manager_finding_keys "$report" | sort -u > "$tmp_root/current"
	comm -23 "$tmp_root/previous" "$tmp_root/current" > "$tmp_root/expected-resolved"
	comm -13 "$tmp_root/previous" "$tmp_root/current" > "$tmp_root/expected-new"
	progress_list_items "$resolved" > "$tmp_root/actual-resolved"
	progress_list_items "$new" > "$tmp_root/actual-new"
	expected_resolved="$(paste -sd, "$tmp_root/expected-resolved")"
	expected_new="$(paste -sd, "$tmp_root/expected-new")"
	if ! cmp -s "$tmp_root/expected-resolved" "$tmp_root/actual-resolved"; then
		actual="$(paste -sd, "$tmp_root/actual-resolved")"
		rm -rf -- "$tmp_root"
		printf 'Resolved-Findings mismatch: expected %s, received %s\n' \
			"${expected_resolved:-none}" "${actual:-none}" >&2
		return 1
	fi
	if ! cmp -s "$tmp_root/expected-new" "$tmp_root/actual-new"; then
		actual="$(paste -sd, "$tmp_root/actual-new")"
		rm -rf -- "$tmp_root"
		printf 'New-Findings mismatch: expected %s, received %s\n' \
			"${expected_new:-none}" "${actual:-none}" >&2
		return 1
	fi
	rm -rf -- "$tmp_root"
	if [[ "$net" == YES && "$resolved" == none && "$gained" == none ]]; then
		printf 'Net-Progress YES requires a resolved finding or gained verification\n' >&2
		return 1
	fi
	if [[ "$net" == NO && ( "$resolved" != none || "$gained" != none ) ]]; then
		printf 'Net-Progress NO conflicts with resolved findings or gained verification\n' >&2
		return 1
	fi
}

# The manager's ADD records are substantive reviewer output and must remain
# model-authored and strictly validated.  The PROGRESS-DELTA block, however,
# contains mechanical bookkeeping: its finding-key sets are fully determined
# by the current report and the preceding effective review.  Normalize that
# block only when it exists as a single delimited block but fails validation.
# This prevents a valid review from being stranded solely because the model put
# prose (rather than an identifier) in Verification-Gained or miscomputed a
# set difference.  Missing/multiple delimiters remain protocol errors and are
# still sent through the ordinary repair path.
normalize_manager_progress_delta()
{
	local report="$1"
	local cycle="$2"
	local review_dir="$3"
	local previous tmp_root normalized
	local resolved new gained lost net
	[[ "$(grep -Fxc 'PROGRESS-DELTA: BEGIN' "$report" || true)" == 1 &&
		"$(grep -Fxc 'PROGRESS-DELTA-COMPLETE' "$report" || true)" == 1 ]] || {
		printf 'manager report does not have one normalizable progress-delta block\n' >&2
		return 1
	}

	tmp_root="$(mktemp -d)"
	previous="$review_dir/../addenda/addendum-$(printf '%03d' "$((cycle - 1))").md"
	[[ -f "$previous" ]] ||
		previous="$review_dir/review-$(printf '%03d' "$((cycle - 1))").md"
	if [[ -f "$previous" ]]; then
		manager_finding_keys "$previous" | sort -u > "$tmp_root/previous"
	else
		: > "$tmp_root/previous"
	fi
	manager_finding_keys "$report" | sort -u > "$tmp_root/current"
	comm -23 "$tmp_root/previous" "$tmp_root/current" > "$tmp_root/resolved"
	comm -13 "$tmp_root/previous" "$tmp_root/current" > "$tmp_root/new"
	resolved="$(paste -sd, "$tmp_root/resolved")"
	new="$(paste -sd, "$tmp_root/new")"
	[[ -n "$resolved" ]] || resolved=none
	[[ -n "$new" ]] || new=none

	# Evidence IDs are not inferable from a report.  Retain them only when they
	# already satisfy the machine-readable contract; prose belongs in Evidence,
	# not in this identifier list.
	gained="$(manager_progress_value "$report" Verification-Gained)"
	lost="$(manager_progress_value "$report" Verification-Lost)"
	validate_progress_identifier_list Verification-Gained "$gained" \
		2>/dev/null || gained=none
	validate_progress_identifier_list Verification-Lost "$lost" \
		2>/dev/null || lost=none
	[[ -n "$gained" ]] || gained=none
	[[ -n "$lost" ]] || lost=none
	net=NO
	[[ "$resolved" == none && "$gained" == none ]] || net=YES

	normalized="$tmp_root/report.md"
	awk -v resolved="$resolved" -v new="$new" -v gained="$gained" \
		-v lost="$lost" -v net="$net" '
		$0 == "PROGRESS-DELTA: BEGIN" {
			print "PROGRESS-DELTA: BEGIN"
			print "Resolved-Findings: " resolved
			print "New-Findings: " new
			print "Verification-Gained: " gained
			print "Verification-Lost: " lost
			print "Net-Progress: " net
			print "PROGRESS-DELTA-COMPLETE"
			in_progress = 1
			next
		}
		$0 == "PROGRESS-DELTA-COMPLETE" { in_progress = 0; next }
		!in_progress { print }
	' "$report" > "$normalized"
	cat "$normalized" > "$report"
	rm -rf -- "$tmp_root"
}

record_manager_progress_delta()
{
	local cycle="$1"
	local report="$2"
	local file="$(project_dir)/control/manager-progress-$(printf '%03d' "$cycle").env"
	local resolved new gained lost net
	resolved="$(manager_progress_value "$report" Resolved-Findings)"
	new="$(manager_progress_value "$report" New-Findings)"
	gained="$(manager_progress_value "$report" Verification-Gained)"
	lost="$(manager_progress_value "$report" Verification-Lost)"
	net="$(manager_progress_value "$report" Net-Progress)"
	{
		printf 'cycle=%s\n' "$cycle"
		printf 'resolved_findings=%s\n' "$resolved"
		printf 'new_findings=%s\n' "$new"
		printf 'verification_gained=%s\n' "$gained"
		printf 'verification_lost=%s\n' "$lost"
		printf 'net_progress=%s\n' "$net"
	} > "$file"
	chmod 600 "$file"
}

specification_requirement_ids()
{
	local file="$1"
	awk '
		{
			line = $0
			gsub(/[`*]/, "", line)
			sub(/^[[:space:]]*/, "", line)
			sub(/^([0-9]+[.)]|[-+]|#+)[[:space:]]+/, "", line)
			sub(/^[[:space:]]*/, "", line)
			if (line ~ /^Requirement([ -])ID[[:space:]]*:/) {
				sub(/^Requirement([ -])ID[[:space:]]*:[[:space:]]*/, "", line)
				sub(/[[:space:]]+$/, "", line)
				if (line != "" && !seen[line]++) print line
			}
		}
	' "$file"
}

oracle_expected_requirement_ids()
{
	local file="$1"
	local ids
	ids="$(specification_requirement_ids "$file")"
	if [[ -n "$ids" ]]; then
		printf '%s\n' "$ids"
	else
		printf '%s\n' SPECIFICATION-WHOLE
	fi
}

oracle_pass_records()
{
	local file="$1"
	awk '
		function emit_record() {
			if (have_record) printf "%s\t%s\t%s\n", id, evidence, verification
		}
		{
			line = $0
			if (line ~ /^REQUIREMENT:[[:space:]]*/) {
				emit_record()
				id = line
				sub(/^REQUIREMENT:[[:space:]]*/, "", id)
				gsub(/`/, "", id)
				sub(/[[:space:]]+$/, "", id)
				evidence = ""
				verification = ""
				have_record = 1
				next
			}
			if (have_record && line ~ /^Evidence:[[:space:]]*/) {
				evidence = line
				sub(/^Evidence:[[:space:]]*/, "", evidence)
				next
			}
			if (have_record && line ~ /^Verification:[[:space:]]*/) {
				verification = line
				sub(/^Verification:[[:space:]]*/, "", verification)
				next
			}
		}
		END { emit_record() }
	' "$file"
}

validate_oracle_pass()
{
	local specification="$1"
	local report="$2"
	local id evidence verification record_count=0
	local -a expected_ids=()
	local -A expected=() seen=()

	mapfile -t expected_ids < <(oracle_expected_requirement_ids "$specification")
	for id in "${expected_ids[@]}"; do
		[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ && ${#id} -le 128 ]] || {
			printf 'invalid specification Requirement ID: %s\n' "$id" >&2
			return 1
		}
		expected[$id]=1
	done

	while IFS=$'\t' read -r id evidence verification; do
		[[ -n "$id" ]] || continue
		((record_count += 1))
		[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ && ${#id} -le 128 ]] || {
			printf 'invalid Oracle PASS requirement ID: %s\n' "$id" >&2
			return 1
		}
		[[ -n "${expected[$id]:-}" ]] || {
			printf 'unknown Oracle PASS requirement ID: %s\n' "$id" >&2
			return 1
		}
		[[ -z "${seen[$id]:-}" ]] || {
			printf 'duplicate Oracle PASS requirement ID: %s\n' "$id" >&2
			return 1
		}
		[[ -n "$evidence" ]] || {
			printf 'Oracle PASS requirement %s has empty Evidence\n' "$id" >&2
			return 1
		}
		[[ -n "$verification" ]] || {
			printf 'Oracle PASS requirement %s has empty Verification\n' "$id" >&2
			return 1
		}
		seen[$id]=1
	done < <(oracle_pass_records "$report")

	(( record_count > 0 )) || {
		printf 'Oracle PASS requires structured requirement evidence\n' >&2
		return 1
	}
	for id in "${expected_ids[@]}"; do
		[[ -n "${seen[$id]:-}" ]] || {
			printf 'Oracle PASS is missing requirement evidence for %s\n' "$id" >&2
			return 1
		}
	done
}

validate_dead_end_report()
{
	local report="$1"
	local field value
	for field in Dead-End-Category Evidence Why-Local-Remediation-Cannot-Work; do
		[[ "$(grep -Ec "^${field}:[[:space:]]*[^[:space:]].*" "$report" || true)" == 1 ]] || {
			printf 'DEAD_END requires exactly one non-empty %s field\n' "$field" >&2
			return 1
		}
	done
	value="$(sed -n 's/^Dead-End-Category:[[:space:]]*//p' "$report")"
	[[ "$value" =~ ^(contradictory-specification|invalid-architecture|unavailable-contract|irreconcilable-assignment)$ ]] || {
		printf 'invalid Dead-End-Category: %s\n' "$value" >&2
		return 1
	}
}

post_oracle_remediation_value()
{
	local key="$1"
	local marker="$(project_dir)/control/post-oracle-remediation.env"
	[[ -f "$marker" ]] || return 1
	awk -F= -v key="$key" '$1 == key { print substr($0, length($1) + 2); exit }' \
		"$marker"
}

post_oracle_remediation_active()
{
	[[ -f "$(project_dir)/control/post-oracle-remediation.env" ]]
}

completion_progress_audit_due()
{
	local cycle="$1"
	[[ "$cycle" =~ ^[1-9][0-9]*$ ]] || return 1
	(( HARNESS_PROGRESS_AUDIT_EVERY_REVIEWS > 0 &&
		cycle % HARNESS_PROGRESS_AUDIT_EVERY_REVIEWS == 0 ))
}

completion_progress_audit_value()
{
	local report="$1"
	local key="$2"
	awk -v key="$key" '
		$0 == "COMPLETION-AUDIT: BEGIN" { active = 1; next }
		$0 == "COMPLETION-AUDIT-COMPLETE" { exit }
		active && index($0, key ":") == 1 {
			value = substr($0, length(key) + 2)
			sub(/^[[:space:]]+/, "", value)
			sub(/[[:space:]]+$/, "", value)
			if (!seen++) print value
		}
	' "$report"
}

completion_progress_audit_value_count()
{
	local report="$1"
	local key="$2"
	awk -v key="$key" '
		$0 == "COMPLETION-AUDIT: BEGIN" { active = 1; next }
		$0 == "COMPLETION-AUDIT-COMPLETE" { exit }
		active && index($0, key ":") == 1 { count += 1 }
		END { print count + 0 }
	' "$report"
}

completion_progress_audit_records()
{
	local report="$1"
	awk '
		function emit_record() {
			if (have_record)
				printf "%s\t%s\t%s\t%s\n", id, status, evidence, verification
		}
		$0 == "COMPLETION-AUDIT: BEGIN" { active = 1; next }
		$0 == "COMPLETION-AUDIT-COMPLETE" {
			if (active) emit_record()
			exit
		}
		!active { next }
		/^REQUIREMENT:[[:space:]]*/ {
			emit_record()
			id = $0
			sub(/^REQUIREMENT:[[:space:]]*/, "", id)
			gsub(/`/, "", id)
			sub(/[[:space:]]+$/, "", id)
			status = ""
			evidence = ""
			verification = ""
			have_record = 1
			next
		}
		have_record && /^Status:[[:space:]]*/ {
			status = $0
			sub(/^Status:[[:space:]]*/, "", status)
			sub(/[[:space:]]+$/, "", status)
			next
		}
		have_record && /^Evidence:[[:space:]]*/ {
			evidence = $0
			sub(/^Evidence:[[:space:]]*/, "", evidence)
			next
		}
		have_record && /^Verification:[[:space:]]*/ {
			verification = $0
			sub(/^Verification:[[:space:]]*/, "", verification)
			next
		}
	' "$report"
}

completion_progress_audit_extract()
{
	local report="$1"
	awk '
		$0 == "COMPLETION-AUDIT: BEGIN" { active = 1 }
		active { print }
		active && $0 == "COMPLETION-AUDIT-COMPLETE" { exit }
	' "$report"
}

validate_completion_progress_audit()
{
	local specification="$1"
	local report="$2"
	local cycle="$3"
	local decision="$4"
	local begin_count end_count audit_cycle coverage_basis requirements_total
	local verified_complete implemented_unverified remaining_gap blocked
	local verified_percent claimed_percent id status evidence verification expected_id
	local record_count=0 expected_total calculated_verified calculated_claimed
	local verified_count=0 implemented_count=0 gap_count=0 blocked_count=0
	local -a expected_ids=()
	local -A expected=() seen=()

	begin_count="$(grep -Fxc 'COMPLETION-AUDIT: BEGIN' "$report" || true)"
	end_count="$(grep -Fxc 'COMPLETION-AUDIT-COMPLETE' "$report" || true)"
	[[ "$begin_count" == 1 && "$end_count" == 1 ]] || {
		printf 'completion-progress audit requires exactly one BEGIN and COMPLETE marker\n' >&2
		return 1
	}
	for value in Audit-Cycle Coverage-Basis Requirements-Total Verified-Complete \
		Implemented-Unverified Remaining-Gap Blocked Verified-Percent Claimed-Percent; do
		[[ "$(completion_progress_audit_value_count "$report" "$value")" == 1 ]] || {
			printf 'completion-progress audit requires exactly one %s field\n' "$value" >&2
			return 1
		}
	done
	audit_cycle="$(completion_progress_audit_value "$report" Audit-Cycle)"
	coverage_basis="$(completion_progress_audit_value "$report" Coverage-Basis)"
	requirements_total="$(completion_progress_audit_value "$report" Requirements-Total)"
	verified_complete="$(completion_progress_audit_value "$report" Verified-Complete)"
	implemented_unverified="$(completion_progress_audit_value "$report" Implemented-Unverified)"
	remaining_gap="$(completion_progress_audit_value "$report" Remaining-Gap)"
	blocked="$(completion_progress_audit_value "$report" Blocked)"
	verified_percent="$(completion_progress_audit_value "$report" Verified-Percent)"
	claimed_percent="$(completion_progress_audit_value "$report" Claimed-Percent)"
	[[ "$audit_cycle" == "$cycle" ]] || {
		printf 'completion-progress audit cycle %s does not match manager cycle %s\n' \
			"${audit_cycle:-missing}" "$cycle" >&2
		return 1
	}
	for value in requirements_total verified_complete implemented_unverified \
		remaining_gap blocked verified_percent claimed_percent; do
		[[ "${!value}" =~ ^[0-9]+$ ]] || {
			printf 'completion-progress audit has invalid %s: %s\n' \
			"$value" "${!value:-missing}" >&2
			return 1
		}
	done

	mapfile -t expected_ids < <(oracle_expected_requirement_ids "$specification")
	expected_total="${#expected_ids[@]}"
	if [[ "${expected_ids[0]:-}" == SPECIFICATION-WHOLE ]]; then
		[[ "$coverage_basis" == SPECIFICATION-WHOLE ]] || {
			printf 'completion-progress audit must use SPECIFICATION-WHOLE coverage\n' >&2
			return 1
		}
	else
		[[ "$coverage_basis" == REQUIREMENT-IDS ]] || {
			printf 'completion-progress audit must use REQUIREMENT-IDS coverage\n' >&2
			return 1
		}
	fi
	[[ "$requirements_total" == "$expected_total" ]] || {
		printf 'completion-progress audit total %s does not match expected requirement count %s\n' \
			"$requirements_total" "$expected_total" >&2
		return 1
	}
	for id in "${expected_ids[@]}"; do
		[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ && ${#id} -le 128 ]] || {
			printf 'invalid specification Requirement ID: %s\n' "$id" >&2
			return 1
		}
		expected[$id]=1
	done

	while IFS=$'\t' read -r id status evidence verification; do
		[[ -n "$id" ]] || continue
		expected_id="${expected_ids[$record_count]:-}"
		[[ "$id" == "$expected_id" ]] || {
			printf 'completion-progress audit expected requirement %s but received %s\n' \
				"${expected_id:-missing}" "$id" >&2
			return 1
		}
		record_count=$((record_count + 1))
		[[ -n "${expected[$id]:-}" ]] || {
			printf 'unknown completion-progress requirement ID: %s\n' "$id" >&2
			return 1
		}
		[[ -z "${seen[$id]:-}" ]] || {
			printf 'duplicate completion-progress requirement ID: %s\n' "$id" >&2
			return 1
		}
		[[ -n "$evidence" && -n "$verification" ]] || {
			printf 'completion-progress requirement %s requires Evidence and Verification\n' \
				"$id" >&2
			return 1
		}
		case "$status" in
			VERIFIED) verified_count=$((verified_count + 1)) ;;
			IMPLEMENTED) implemented_count=$((implemented_count + 1)) ;;
			GAP) gap_count=$((gap_count + 1)) ;;
			BLOCKED) blocked_count=$((blocked_count + 1)) ;;
			*)
				printf 'invalid completion-progress status for %s: %s\n' "$id" \
					"${status:-missing}" >&2
				return 1
				;;
		esac
		seen[$id]=1
	done < <(completion_progress_audit_records "$report")
	[[ "$record_count" == "$expected_total" ]] || {
		printf 'completion-progress audit has %s records but requires %s\n' \
			"$record_count" "$expected_total" >&2
		return 1
	}
	for id in "${expected_ids[@]}"; do
		[[ -n "${seen[$id]:-}" ]] || {
			printf 'completion-progress audit is missing %s\n' "$id" >&2
			return 1
		}
	done
	[[ "$verified_complete" == "$verified_count" &&
		"$implemented_unverified" == "$implemented_count" &&
		"$remaining_gap" == "$gap_count" && "$blocked" == "$blocked_count" ]] || {
		printf 'completion-progress summary counts do not match requirement records\n' >&2
		return 1
	}
	calculated_verified=$((verified_count * 100 / expected_total))
	calculated_claimed=$(((verified_count + implemented_count) * 100 / expected_total))
	[[ "$verified_percent" == "$calculated_verified" &&
		"$claimed_percent" == "$calculated_claimed" ]] || {
		printf 'completion-progress percentages do not match requirement records\n' >&2
		return 1
	}
	case "$decision" in
		ACCEPT)
			(( verified_count == expected_total )) || {
				printf 'manager ACCEPT conflicts with incomplete completion-progress audit\n' >&2
				return 1
				}
			;;
		REVISE)
			(( verified_count < expected_total )) || {
				printf 'manager REVISE conflicts with fully verified completion-progress audit\n' >&2
				return 1
				}
			;;
	esac
}

write_completion_progress_state()
{
	local report="$1"
	local audit_report="$2"
	local file tmp audit_cycle coverage_basis requirements_total
	local verified_complete implemented_unverified remaining_gap blocked
	local verified_percent claimed_percent percentage_available
	file="$(project_dir)/control/completion-progress.env"
	tmp="$file.tmp.$$"
	audit_cycle="$(completion_progress_audit_value "$report" Audit-Cycle)"
	coverage_basis="$(completion_progress_audit_value "$report" Coverage-Basis)"
	requirements_total="$(completion_progress_audit_value "$report" Requirements-Total)"
	verified_complete="$(completion_progress_audit_value "$report" Verified-Complete)"
	implemented_unverified="$(completion_progress_audit_value "$report" Implemented-Unverified)"
	remaining_gap="$(completion_progress_audit_value "$report" Remaining-Gap)"
	blocked="$(completion_progress_audit_value "$report" Blocked)"
	verified_percent="$(completion_progress_audit_value "$report" Verified-Percent)"
	claimed_percent="$(completion_progress_audit_value "$report" Claimed-Percent)"
	percentage_available=1
	[[ "$coverage_basis" != SPECIFICATION-WHOLE ]] || percentage_available=0
	{
		printf 'audit_cycle=%s\n' "$audit_cycle"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
		printf 'coverage_basis=%s\n' "$coverage_basis"
		printf 'requirements_total=%s\n' "$requirements_total"
		printf 'verified_complete=%s\n' "$verified_complete"
		printf 'implemented_unverified=%s\n' "$implemented_unverified"
		printf 'remaining_gap=%s\n' "$remaining_gap"
		printf 'blocked=%s\n' "$blocked"
		printf 'verified_percent=%s\n' "$verified_percent"
		printf 'claimed_percent=%s\n' "$claimed_percent"
		printf 'percentage_available=%s\n' "$percentage_available"
		printf 'audit_report=%s\n' "$audit_report"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
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

repeated_convergence_finding_keys()
{
	local review_dir="$1"
	local threshold="$2"
	local reset_cycle="${3:-0}"
	local audit cycle key candidate
	local -a audits=() recent=()
	(( threshold > 0 )) || return 0
	while IFS= read -r audit; do
		cycle="${audit##*/convergence-audit-}"
		cycle="${cycle%.md}"
		[[ "$cycle" =~ ^[0-9]+$ ]] || continue
		(( 10#$cycle > reset_cycle )) || continue
		audits+=("$audit")
	done < <(find "$review_dir" -maxdepth 1 \
		-name 'convergence-audit-[0-9][0-9][0-9]*.md' -type f | sort)
	(( ${#audits[@]} >= threshold )) || return 0
	recent=("${audits[@]: -threshold}")
	candidate="${recent[${#recent[@]} - 1]}"
	while IFS= read -r key; do
		for audit in "${recent[@]}"; do
			manager_finding_keys "$audit" | grep -Fqx -- "$key" || continue 2
		done
		printf '%s\n' "$key"
	done < <(manager_finding_keys "$candidate")
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

oracle_audit_run_count()
{
	find "$(project_dir)/reviews" -maxdepth 1 \
		-name 'oracle-audit-[0-9][0-9][0-9].md' -type f 2>/dev/null |
		wc -l | tr -d ' '
}

oracle_enabled()
{
	(( MAX_ORACLE_RUNS > 0 ))
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
	require_runtime "$CONVERGENCE_CODEX_BIN"
	if oracle_enabled; then
		require_runtime "$ORACLE_CODEX_BIN"
	fi
}

supervisor_pid()
{
	local file
	file="$(project_dir)/control/supervisor.pid"
	[[ -f "$file" ]] || return 1
	awk 'NR == 1 { print; exit }' "$file"
}

supervisor_unit_name()
{
	local digest
	digest="$(printf '%s' "$(project_dir)" | sha256sum | awk '{ print $1 }')"
	printf 'coding-harness-light-%s-%s.service\n' "$PROJECT" "${digest:0:16}"
}

supervisor_unit_file()
{
	printf '%s/control/supervisor.unit\n' "$(project_dir)"
}

process_token_file()
{
	printf '%s/control/process-token\n' "$(project_dir)"
}

harness_process_token()
{
	local file token
	file="$(process_token_file)"
	[[ -f "$file" ]] || return 1
	token="$(awk 'NR == 1 { print; exit }' "$file")"
	[[ "$token" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "$token"
}

systemd_user_available()
{
	command -v systemctl >/dev/null 2>&1 &&
		command -v systemd-run >/dev/null 2>&1 &&
		systemctl --user show-environment >/dev/null 2>&1
}

tagged_process_pids()
{
	local token="$1"
	local process_dir pid
	[[ "$token" =~ ^[0-9a-f]{64}$ ]] || return 1
	for process_dir in /proc/[1-9]*; do
		[[ -r "$process_dir/environ" ]] || continue
		pid="${process_dir##*/}"
		if grep -zFqx -- "HARNESS_PROCESS_TOKEN=$token" \
			"$process_dir/environ" 2>/dev/null; then
			printf '%s\n' "$pid"
		fi
	done
}

project_environment_process_pids()
{
	local process_dir pid
	for process_dir in /proc/[1-9]*; do
		[[ -r "$process_dir/environ" ]] || continue
		pid="${process_dir##*/}"
		[[ "$pid" != "$$" ]] || continue
		if grep -zFqx -- "PROJECT=$PROJECT" "$process_dir/environ" 2>/dev/null &&
			grep -zFqx -- "REPOSITORY=$REPOSITORY" "$process_dir/environ" 2>/dev/null; then
			printf '%s\n' "$pid"
		fi
	done
}

lock_holder_pids()
{
	local lock="$1"
	local process_dir fd target pid
	for process_dir in /proc/[1-9]*; do
		[[ -d "$process_dir/fd" ]] || continue
		pid="${process_dir##*/}"
		for fd in "$process_dir/fd"/*; do
			[[ -L "$fd" ]] || continue
			target="$(readlink "$fd" 2>/dev/null || true)"
			if [[ "$target" == "$lock" ]]; then
				printf '%s\n' "$pid"
				break
			fi
		done
	done
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
