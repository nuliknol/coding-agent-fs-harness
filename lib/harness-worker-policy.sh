#!/usr/bin/env bash

harness_worker_select_execution_policy()
{
	local assignment="$1" task_id="$2"
	manager_remediation=0
	execution_role=worker
	execution_model="$WORKER_MODEL"
	execution_fallback_model="$WORKER_FALLBACK_MODEL"
	execution_mode=WORKER
	worker_route=LEGACY
	luna_bounded_execution=0
	leaf_expected_turns=0
	if assignment_is_manager_remediation "$assignment"; then
		manager_remediation=1
		execution_role=manager_remediation
		execution_model="$MANAGER_MODEL"
		execution_fallback_model="$MANAGER_FALLBACK_MODEL"
		execution_mode=MANAGER_REMEDIATION
		worker_route=MANAGER_REMEDIATION
		if (( HARNESS_DECOMPOSITION_V2 == 1 )); then
			leaf_expected_turns="$(require_single_metadata_value "$assignment" Expected-Max-Worker-Turns 'v2 manager remediation assignment')"
			[[ "$leaf_expected_turns" =~ ^[1-9][0-9]*$ ]] || die 'invalid v2 Expected-Max-Worker-Turns'
		fi
		if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
			luna_bounded_execution=1
			require_worker_codex
			write_worker_snapshot
		else
			require_manager_codex
			write_manager_snapshot
		fi
	else
		if (( HARNESS_DECOMPOSITION_V2 == 1 )); then
			worker_route="$(require_single_metadata_value "$assignment" Worker-Route 'v2 worker assignment')"
			leaf_expected_turns="$(require_single_metadata_value "$assignment" Expected-Max-Worker-Turns 'v2 worker assignment')"
			[[ "$leaf_expected_turns" =~ ^[1-9][0-9]*$ ]] || die 'invalid v2 Expected-Max-Worker-Turns'
			case "$worker_route" in
				LUNA)
					luna_bounded_execution=1
					execution_role=worker_luna
					execution_model="$LUNA_WORKER_MODEL"
					if [[ "$HARNESS_ESCALATION_POLICY" == decompose ]]; then
						execution_fallback_model="$WORKER_FALLBACK_MODEL"
					else
						execution_fallback_model="$TERRA_WORKER_MODEL"
					fi
					execution_mode=LUNA_LEAF
					;;
				TERRA)
					if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
						mark_project_integrity_anomaly MODEL_POLICY_VIOLATION "$task_id" \
							'Luna-only project published a TERRA worker assignment' \
							"assignment=$assignment route=$worker_route" >/dev/null
						die 'Luna-only policy rejected a TERRA worker assignment; decompose it into Luna children'
					fi
					execution_role=worker_terra
					execution_model="$TERRA_WORKER_MODEL"
					execution_fallback_model="$MANAGER_FALLBACK_MODEL"
					execution_mode=TERRA_LEAF
					;;
				*) die "invalid v2 Worker-Route: $worker_route" ;;
			esac
		fi
		require_worker_codex
		write_worker_snapshot
	fi
}

harness_worker_context_admission_requires_repair()
{
	(( luna_bounded_execution == 1 )) &&
		[[ "$HARNESS_CONTEXT_CLOSURE_MODE" =~ ^(required|patch_only)$ ]] &&
		[[ "$context_closure_status" != READY ]]
}

