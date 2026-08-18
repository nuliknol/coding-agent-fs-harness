#!/usr/bin/env bash

# Typed, atomic project artifact primitives.  This module deliberately has no
# source-time dependency on harness-common.sh; callers provide die() and
# timestamp_utc() through the normal compatibility facade.

harness_artifact_require_safe_path()
{
	local target="$1" parent
	[[ "$target" == /* ]] || die "artifact path must be absolute: $target"
	parent="${target%/*}"
	[[ -n "$parent" && "$parent" != "$target" ]] || die "artifact path has no parent: $target"
	mkdir -p "$parent"
}

harness_artifact_validate_key()
{
	[[ "$1" =~ ^[a-z][a-z0-9_]*$ ]] || die "invalid artifact key: $1"
}

harness_artifact_validate_value()
{
	local key="$1" value="$2"
	[[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] ||
		die "artifact value for $key must be one tab-free line"
}

harness_artifact_write_text()
{
	local target="$1" mode="${2:-600}" temporary
	harness_artifact_require_safe_path "$target"
	temporary="${target}.tmp.$$.$RANDOM"
	if ! cat > "$temporary"; then
		rm -f -- "$temporary"
		return 1
	fi
	chmod "$mode" "$temporary"
	mv -f -- "$temporary" "$target"
}

harness_artifact_install_file()
{
	local source="$1" target="$2" mode="${3:-600}" temporary
	[[ -f "$source" ]] || die "artifact source does not exist: $source"
	harness_artifact_require_safe_path "$target"
	temporary="${target}.tmp.$$.$RANDOM"
	if ! install -m "$mode" -- "$source" "$temporary"; then
		rm -f -- "$temporary"
		return 1
	fi
	mv -f -- "$temporary" "$target"
}

harness_artifact_write_kv()
{
	local target="$1" mode="${2:-600}" key value
	shift 2
	(( $# > 0 && $# % 2 == 0 )) || die 'artifact key/value writer requires one or more KEY VALUE pairs'
	{
		while (( $# > 0 )); do
			key="$1"; value="$2"; shift 2
			harness_artifact_validate_key "$key"
			harness_artifact_validate_value "$key" "$value"
			printf '%s=%s\n' "$key" "$value"
		done
	} | harness_artifact_write_text "$target" "$mode"
}

harness_artifact_get()
{
	local file="$1" key="$2"
	harness_artifact_validate_key "$key"
	[[ -f "$file" ]] || return 1
	awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; found=1; exit} END {exit !found}' "$file"
}

harness_artifact_require_schema()
{
	local file="$1" required_csv="$2" key value
	local -A seen=()
	[[ -f "$file" ]] || die "artifact does not exist: $file"
	while IFS='=' read -r key value; do
		[[ -n "$key" ]] || continue
		harness_artifact_validate_key "$key"
		harness_artifact_validate_value "$key" "$value"
		[[ -z "${seen[$key]:-}" ]] || die "duplicate artifact key $key in $file"
		seen[$key]=1
	done < "$file"
	while IFS= read -r key; do
		[[ -n "$key" ]] || continue
		[[ -n "${seen[$key]:-}" ]] || die "artifact $file is missing required key: $key"
	done < <(printf '%s\n' "$required_csv" | tr ',' '\n')
}

harness_artifact_append_tsv()
{
	local ledger="$1" header="$2"
	shift 2
	local lock="${ledger}.lock" fd field line=""
	harness_artifact_require_safe_path "$ledger"
	exec {fd}>"$lock"
	flock -x "$fd"
	if [[ ! -f "$ledger" ]]; then
		printf '%s\n' "$header" | harness_artifact_write_text "$ledger" 600
	fi
	for field in "$@"; do
		[[ "$field" != *$'\t'* && "$field" != *$'\n'* && "$field" != *$'\r'* ]] ||
			die 'TSV artifact fields must be single tab-free lines'
		if [[ -n "$line" ]]; then line+=$'\t'; fi
		line+="$field"
	done
	printf '%s\n' "$line" >> "$ledger"
	exec {fd}>&-
}

harness_artifact_compare_and_swap_kv()
{
	local target="$1" expected_key="$2" expected_value="$3" mode="$4"
	shift 4
	local lock="${target}.lock" fd current
	harness_artifact_require_safe_path "$target"
	exec {fd}>"$lock"
	flock -x "$fd"
	current="$(harness_artifact_get "$target" "$expected_key" 2>/dev/null || true)"
	if [[ "$current" != "$expected_value" ]]; then
		exec {fd}>&-
		die "artifact transition conflict for $target: expected $expected_key=$expected_value, found ${current:-<missing>}"
	fi
	harness_artifact_write_kv "$target" "$mode" "$@"
	exec {fd}>&-
}

harness_artifact_update_kv()
{
	local target="$1" wanted="$2" replacement="$3" mode="${4:-600}" lock fd temporary status
	harness_artifact_validate_key "$wanted"
	harness_artifact_validate_value "$wanted" "$replacement"
	[[ -f "$target" ]] || die "artifact does not exist: $target"
	lock="${target}.lock"
	exec {fd}>"$lock"
	flock -x "$fd"
	temporary="${target}.tmp.$$.$RANDOM"
	awk -F= -v key="$wanted" -v value="$replacement" '
		$1 == key {if(seen++) exit 70; print key "=" value; next}
		{print}
		END {if(!seen) print key "=" value}
	' "$target" > "$temporary" || {
		status=$?; rm -f -- "$temporary"; exec {fd}>&-; return "$status"
	}
	chmod "$mode" "$temporary"
	mv -f -- "$temporary" "$target"
	exec {fd}>&-
}
