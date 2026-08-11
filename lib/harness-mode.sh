#!/usr/bin/env bash

# Lightweight pre-loader used by shared entry points before either mode's
# complete environment loader is sourced. Environment files are trusted Bash
# configuration in both harness implementations; retain the same ownership and
# write-permission checks before reading HARNESS_MODE.

harness_mode_env_file()
{
	local argument
	for argument in "$@"; do
		[[ "$argument" != --* && -f "$argument" ]] || continue
		realpath "$argument"
		return 0
	done
	return 1
}

harness_mode_from_env()
{
	local env_file="$1" owner mode_octal mode selected_mode
	owner="$(stat -c '%u' "$env_file")"
	mode_octal="$(stat -c '%a' "$env_file")"
	mode=$((8#$mode_octal))
	(( owner == UID || owner == 0 )) || {
		printf 'ERROR: environment file must be owned by UID %s or root: %s\n' "$UID" "$env_file" >&2
		return 1
	}
	(( (mode & 8#022) == 0 )) || {
		printf 'ERROR: environment file must not be group/world writable: %s\n' "$env_file" >&2
		return 1
	}
	selected_mode="$({
		unset HARNESS_MODE harness_mode DEVELOPMENT_POLICY
		# shellcheck disable=SC1090
		source "$env_file"
		if [[ -n "${HARNESS_MODE:-}" ]]; then
			printf '%s\n' "$HARNESS_MODE"
		elif [[ -n "${harness_mode:-}" ]]; then
			printf '%s\n' "$harness_mode"
		elif [[ -n "${DEVELOPMENT_POLICY:-}" ]]; then
			# Compatibility for existing Light environment files created before
			# HARNESS_MODE existed. New files should always set it explicitly.
			printf 'light\n'
		else
			printf 'full\n'
		fi
	} 2>/dev/null)" || return 1
	[[ "$selected_mode" =~ ^(light|full)$ ]] || {
		printf 'ERROR: HARNESS_MODE must be light or full in %s\n' "$env_file" >&2
		return 1
	}
	printf '%s\n' "$selected_mode"
}

harness_dispatch_mode()
{
	local source_root="$1" command_name="$2"
	shift 2
	local env_file selected_mode light_command
	env_file="$(harness_mode_env_file "$@" 2>/dev/null || true)"
	[[ -n "$env_file" ]] || return 0
	selected_mode="$(harness_mode_from_env "$env_file")" || return 1
	[[ "$selected_mode" == light ]] || return 0
	light_command="$source_root/modes/light/bin/$command_name"
	[[ -x "$light_command" ]] || {
		printf 'ERROR: command %s is not available in light mode\n' "$command_name" >&2
		return 1
	}
	exec "$light_command" "$@"
}
