#!/usr/bin/env bash

# Domain validation shared by task lifecycle commands.  File movement remains
# in compatibility entry points until each transition has characterization
# coverage, but semantic validation has one owner here.

harness_task_scope_entries()
{
	printf '%s\n' "$1" | tr ',;[:space:]' '\n' | sed '/^$/d' | LC_ALL=C sort -u
}

harness_task_validate_repository_scope()
{
	local scope="$1" assignment="$2" assignment_scope entry resolved
	local -a entries=()
	assignment_scope="$(metadata_value "$assignment" Allowed-Scope)"
	if [[ "$scope" == - ]]; then
		[[ "$assignment_scope" == - ]] ||
			die 'repository-local Remediation-Scope may be - only for an immutable read-only assignment'
		return 0
	fi
	mapfile -t entries < <(harness_task_scope_entries "$scope")
	(( ${#entries[@]} > 0 )) ||
		die 'repository-local Remediation-Scope must name at least one exact repository path'
	for entry in "${entries[@]}"; do
		[[ -n "$entry" && "$entry" != - && "$entry" != /* && "$entry" != ../* &&
			"$entry" != */../* && "$entry" != *'*'* && "$entry" != *'?'* && "$entry" != *'['* ]] ||
			die "repository-local Remediation-Scope is not an exact repository-relative path: $entry"
		resolved="$(realpath -m "$REPOSITORY/$entry")"
		case "$resolved" in "$REPOSITORY"/*) ;; *) die "repository-local Remediation-Scope escapes the repository: $entry" ;; esac
		[[ -e "$resolved" ]] || die "repository-local Remediation-Scope path does not exist: $entry"
	done
}

harness_task_root_transition_is_legal()
{
	local from="$1" to="$2"
	case "$from:$to" in
		ACTIVE:NEEDS_REPLAN|ACTIVE:NEEDS_HUMAN|ACTIVE:ARCHITECTURE_REASSESSMENT_REQUIRED|\
		ACTIVE:TOKEN_USAGE_ANOMALY|ACTIVE:COMPLETE|NEEDS_REPLAN:ACTIVE|\
		NEEDS_REPLAN:ARCHITECTURE_REASSESSMENT_REQUIRED|NEEDS_HUMAN:ACTIVE|\
		ARCHITECTURE_REASSESSMENT_REQUIRED:NEEDS_REPLAN|TOKEN_USAGE_ANOMALY:ACTIVE) return 0 ;;
		*) return 1 ;;
	esac
}
