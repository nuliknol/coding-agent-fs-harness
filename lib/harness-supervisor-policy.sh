#!/usr/bin/env bash

harness_supervisor_process_cycle()
{
	HARNESS_SUPERVISOR_CYCLE_RESULT=CONTINUE
	if project_has_integrity_anomaly; then
		HARNESS_SUPERVISOR_CYCLE_RESULT=WAIT
		return 0
	fi
	process_dependency_requests
	process_repository_index_refresh || { HARNESS_SUPERVISOR_CYCLE_RESULT=WAIT; return 0; }
	handle_project_completion && { HARNESS_SUPERVISOR_CYCLE_RESULT=COMPLETE; return 0; }
	process_results
	handle_project_completion && { HARNESS_SUPERVISOR_CYCLE_RESULT=COMPLETE; return 0; }
	process_repository_index_refresh || { HARNESS_SUPERVISOR_CYCLE_RESULT=WAIT; return 0; }
	reclassify_legacy_hard_block_markers
	reclassify_legacy_convergence_human_markers
	process_context_closure_provider_repairs
	process_auto_replans
	process_parallel_planning_capacity
	handle_project_completion && { HARNESS_SUPERVISOR_CYCLE_RESULT=COMPLETE; return 0; }
	process_planning_gap
	handle_project_completion && { HARNESS_SUPERVISOR_CYCLE_RESULT=COMPLETE; return 0; }
	return 0
}
