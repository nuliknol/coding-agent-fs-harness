#!/usr/bin/env bash

# Source Code Transaction Manager layout and protocol helpers.  Callers load a
# harness environment through harness-common.sh before using these functions.

sctm_dir()
{
	printf '%s/control/sctm\n' "$(project_dir)"
}

sctm_transactions_dir() { printf '%s/transactions\n' "$(sctm_dir)"; }
sctm_queue_dir() { printf '%s/queue\n' "$(sctm_dir)"; }
sctm_staging_dir() { printf '%s/staging\n' "$(sctm_dir)"; }
sctm_pid_file() { printf '%s/daemon.pid\n' "$(sctm_dir)"; }
sctm_daemon_lock() { printf '%s/daemon.lock\n' "$(sctm_dir)"; }
sctm_repository_lock() { printf '%s/repository.lock\n' "$(sctm_dir)"; }
sctm_queue_lock() { printf '%s/queue.lock\n' "$(sctm_dir)"; }

sctm_ensure_state()
{
	local path
	for path in "$(sctm_dir)" "$(sctm_transactions_dir)" "$(sctm_queue_dir)" \
		"$(sctm_staging_dir)"; do
		mkdir -p "$path"
		chmod 700 "$path"
	done
}

sctm_validate_identity()
{
	[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] ||
		die "invalid SCTM identity: $1"
}

sctm_validate_paths_file()
{
	local file="$1" kind="$2" path seen=0
	while IFS= read -r path || [[ -n "$path" ]]; do
		seen=1
		[[ -n "$path" && "$path" != /* && "$path" != . && "$path" != .. &&
			"$path" != ../* && "$path" != */../* && "$path" != */.. &&
			"$path" != *','* && "$path" != *$'\t'* && "$path" != *$'\r'* ]] ||
			die "invalid SCTM $kind path: $path"
	done < "$file"
	(( seen == 1 )) || die "SCTM $kind path set is empty"
	[[ -z "$(LC_ALL=C sort "$file" | uniq -d)" ]] ||
		die "SCTM $kind path set contains duplicates"
}

sctm_pid_is_live()
{
	local pid_file pid cmdline
	pid_file="$(sctm_pid_file)"
	[[ -f "$pid_file" ]] || return 1
	pid="$(cat "$pid_file" 2>/dev/null || true)"
	[[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null || return 1
	cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
	[[ "$cmdline" == *"$HARNESS_BIN/sctm-daemon"* && "$cmdline" == *"$HARNESS_ENV_FILE"* ]]
}

sctm_transaction_dir()
{
	printf '%s/%s\n' "$(sctm_transactions_dir)" "$1"
}

sctm_result_status()
{
	kv_file_value "$1" status 2>/dev/null || true
}

sctm_result_exit_status()
{
	case "$1" in
		APPLIED) return 0 ;;
		CONFLICT|STALE_BASE) return 75 ;;
		SCOPE_VIOLATION|INVALID_PATCH|INVALID_REQUEST|VALIDATION_FAILED|INTERNAL_ERROR) return 1 ;;
		*) return 1 ;;
	esac
}

sctm_write_result()
{
	local transaction_dir="$1" status="$2" reason="$3" tmp
	shift 3
	tmp="$transaction_dir/result.tmp.$$"
	{
		printf 'status=%s\ntransaction_id=%s\nreason=%s\n' \
			"$status" "$(basename "$transaction_dir")" "$reason"
		printf '%s\n' "$@"
		printf 'completed_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$transaction_dir/result"
	printf '%s\n' "$status" > "$transaction_dir/state.tmp.$$"
	chmod 600 "$transaction_dir/state.tmp.$$"
	mv "$transaction_dir/state.tmp.$$" "$transaction_dir/state"
	sync -f "$transaction_dir/result" 2>/dev/null || true
	sync -f "$transaction_dir" 2>/dev/null || true
}
