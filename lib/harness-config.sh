#!/usr/bin/env bash

# Configuration trust and canonicalization primitives.  The full environment
# schema remains exposed through load_harness_env for compatibility, while this
# module owns the security boundary and reusable scalar validators.

harness_config_require_secure_file()
{
	local input="$1" owner mode_octal mode
	[[ -f "$input" ]] || die "environment file does not exist: $input"
	HARNESS_CONFIG_CANONICAL_FILE="$(realpath "$input")"
	HARNESS_CONFIG_CANONICAL_DIR="$(dirname "$HARNESS_CONFIG_CANONICAL_FILE")"
	owner="$(stat -c '%u' "$HARNESS_CONFIG_CANONICAL_FILE")"
	mode_octal="$(stat -c '%a' "$HARNESS_CONFIG_CANONICAL_FILE")"
	mode=$((8#$mode_octal))
	(( owner == UID || owner == 0 )) ||
		die "environment file must be owned by UID $UID or root: $HARNESS_CONFIG_CANONICAL_FILE"
	(( (mode & 8#022) == 0 )) ||
		die "environment file must not be group/world writable: $HARNESS_CONFIG_CANONICAL_FILE"
}

harness_config_resolve_path()
{
	local base="$1" path="$2"
	if [[ "$path" == /* ]]; then
		realpath -m "$path"
	else
		realpath -m "$base/$path"
	fi
}

harness_config_validate_reasoning_effort()
{
	local name="$1" value="$2"
	[[ "$value" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] || die "invalid $name: $value"
}

harness_config_validate_sandbox()
{
	local name="$1" value="$2"
	[[ "$value" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid $name: $value"
}

