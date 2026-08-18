#!/usr/bin/env bash

# Agent Coordination Protocol (ACP) durable control-plane primitives.
# This file is sourced by harness-common.sh.  It deliberately contains no
# model invocation: workers make claims, deterministic code records and checks
# them, and existing manager policy remains the only authority that may change
# scope or decomposition.

ACP_PROTOCOL_VERSION=1

acp_control_dir()
{
	printf '%s/control/acp\n' "$(project_dir)"
}

acp_pending_dir()
{
	printf '%s/pending\n' "$(acp_control_dir)"
}

acp_archive_dir()
{
	printf '%s/archive\n' "$(acp_control_dir)"
}

acp_artifact_dir()
{
	printf '%s/artifacts\n' "$(acp_control_dir)"
}

acp_events_file()
{
	printf '%s/events.tsv\n' "$(acp_control_dir)"
}

acp_metrics_file()
{
	printf '%s/metrics.env\n' "$(acp_control_dir)"
}

acp_transactions_file()
{
	printf '%s/transactions.tsv\n' "$(acp_control_dir)"
}

acp_discovered_graph_file()
{
	printf '%s/discovered-graph.tsv\n' "$(acp_control_dir)"
}

acp_suspension_dir()
{
	printf '%s/suspensions\n' "$(acp_control_dir)"
}

acp_capability_lease_dir()
{
	printf '%s/capability-leases\n' "$(acp_control_dir)"
}

acp_worktree_dir()
{
	printf '%s/worktrees\n' "$(acp_control_dir)"
}

acp_integration_dir()
{
	printf '%s/integration\n' "$(acp_control_dir)"
}

ensure_acp_state()
{
	local dir events init_lock
	dir="$(acp_control_dir)"
	mkdir -p "$(acp_pending_dir)" "$(acp_archive_dir)" "$(acp_artifact_dir)" \
		"$(acp_suspension_dir)" "$(acp_capability_lease_dir)" \
		"$(acp_worktree_dir)" "$(acp_integration_dir)"
	chmod 700 "$dir" "$(acp_pending_dir)" "$(acp_archive_dir)" "$(acp_artifact_dir)" \
		"$(acp_suspension_dir)" "$(acp_capability_lease_dir)" \
		"$(acp_worktree_dir)" "$(acp_integration_dir)"
	events="$(acp_events_file)"
	init_lock="$dir/state-init.lock"
	(
		flock -x 9
		if [[ ! -f "$events" ]]; then
			printf '#timestamp\trequest_id\tproject\ttask_id\tthread_id\tsequence\tevent\ttype\tkind\tfingerprint\tdetail\n' > "$events.tmp.$$"
			chmod 600 "$events.tmp.$$"
			mv "$events.tmp.$$" "$events"
		fi
		if [[ ! -f "$(acp_discovered_graph_file)" ]]; then
			printf '#timestamp\trequest_id\ttask_id\trelation\tidentifier\tfingerprint\tstatus\n' > "$(acp_discovered_graph_file).tmp.$$"
			chmod 600 "$(acp_discovered_graph_file).tmp.$$"
			mv "$(acp_discovered_graph_file).tmp.$$" "$(acp_discovered_graph_file)"
		fi
	) 9>"$init_lock"
	chmod 600 "$init_lock"
}

acp_discovered_graph_append()
{
	local request_id="$1" task_id="$2" relation="$3" identifier="$4" fingerprint="$5" status="$6"
	local graph
	ensure_acp_state
	graph="$(acp_discovered_graph_file)"
	(
		flock -x 9
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(timestamp_utc)" "$request_id" "$task_id" \
			"$relation" "$(tr '\t\r\n' '   ' <<< "$identifier")" "$fingerprint" "$status" >&9
	) 9>>"$graph"
}

acp_validate_atom()
{
	local label="$1" value="$2"
	[[ -n "$value" && ${#value} -le 256 && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] ||
		die "ACP $label must be a non-empty single-line value of at most 256 characters"
}

acp_validate_type()
{
	case "$1" in
		CONTEXT|SCOPE|PREREQUISITE|SPLIT|CHALLENGE|CANCEL) ;;
		*) die "unsupported ACP request type: $1" ;;
	esac
}

acp_validate_context_kind()
{
	case "$1" in
		TYPE_DEFINITION|SYMBOL_DEFINITION|CALLER_CONTRACT|CALLEE_CONTRACT|\
		FAILING_ASSERTION|TEST_TARGET|TEST_OWNER|BUILD_TARGET|BUILD_OWNER|OWNER|PRODUCER|CONSUMER|\
		REPRESENTATION_WRITER|SOURCE_WINDOW) ;;
		*) die "unsupported ACP context kind: $1" ;;
	esac
}

acp_workspace_fingerprint()
{
	local assignment="$1" pointer revision
	pointer="$(repository_index_project_pointer_file)"
	revision="$(git -C "$REPOSITORY" rev-parse HEAD 2>/dev/null || printf unavailable)"
	{
		sha256sum "$assignment"
		printf 'revision=%s\n' "$revision"
		if [[ -f "$pointer" ]]; then sha256sum "$pointer"; else printf 'index=unavailable\n'; fi
	} | sha256sum | awk '{print "sha256:" $1}'
}

acp_artifact_install()
{
	local source="$1" digest target
	[[ -f "$source" && -s "$source" ]] || die "ACP evidence artifact is missing or empty: $source"
	digest="$(sha256sum "$source" | awk '{print $1}')"
	target="$(acp_artifact_dir)/sha256-$digest"
	if [[ ! -f "$target" ]]; then
		install -m 600 "$source" "$target.tmp.$$"
		mv "$target.tmp.$$" "$target"
	fi
	printf '%s\n' "$target"
}

acp_event_append()
{
	local request_id="$1" task_id="$2" thread_id="$3" sequence="$4" event="$5"
	local type="$6" kind="$7" fingerprint="$8" detail="${9:--}" events
	ensure_acp_state
	events="$(acp_events_file)"
	# One append is smaller than PIPE_BUF, and the project lock serializes normal
	# writers.  flock also protects diagnostic/admin callers that do not own it.
	(
		flock -x 9
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$(timestamp_utc)" "$request_id" "$PROJECT" "$task_id" "${thread_id:--}" \
			"$sequence" "$event" "$type" "$kind" "$fingerprint" \
			"$(tr '\t\r\n' '   ' <<< "$detail" | head -c 1024)" >&9
	) 9>>"$events"
}

acp_request_fingerprint()
{
	local task_id="$1" thread_id="$2" type="$3" kind="$4" identifier="$5" workspace="$6"
	printf '%s\0%s\0%s\0%s\0%s\0%s\0' \
		"$task_id" "$thread_id" "$type" "$kind" "$identifier" "$workspace" |
		sha256sum | awk '{print "sha256:" $1}'
}

acp_duplicate_count()
{
	local fingerprint="$1" events
	events="$(acp_events_file)"
	[[ -f "$events" ]] || { printf '0\n'; return; }
	awk -F '\t' -v fingerprint="$fingerprint" '!/^#/ && $7 == "REQUESTED" && $10 == fingerprint {count++} END {print count + 0}' "$events"
}

acp_publish_request()
{
	local task_id="$1" thread_id="$2" sequence="$3" type="$4" kind="$5"
	local identifier="$6" reason="$7" assignment="$8" evidence_source="${9:--}"
	local request_id workspace fingerprint duplicates evidence='-' request tmp
	local initial_scope initial_context scope_fingerprint context_fingerprint leaf_type planner
	validate_task_id "$task_id"
	acp_validate_atom thread-id "$thread_id"
	[[ "$sequence" =~ ^[1-9][0-9]*$ ]] || die 'ACP sequence must be a positive integer'
	acp_validate_type "$type"
	[[ "$type" != CONTEXT ]] || acp_validate_context_kind "$kind"
	acp_validate_atom kind "$kind"
	acp_validate_atom identifier "$identifier"
	acp_validate_atom reason "$reason"
	[[ -f "$assignment" ]] || die "ACP assignment is missing: $assignment"
	ensure_acp_state
	workspace="$(acp_workspace_fingerprint "$assignment")"
	initial_scope="$(metadata_value "$assignment" Allowed-Scope)"
	initial_context="$(metadata_value "$assignment" Context-Paths)"
	scope_fingerprint="$(printf '%s' "$initial_scope" | sha256sum | awk '{print "sha256:" $1}')"
	context_fingerprint="$(printf '%s' "$initial_context" | sha256sum | awk '{print "sha256:" $1}')"
	leaf_type="$(metadata_value "$assignment" Leaf-Type)"; [[ -n "$leaf_type" ]] || leaf_type=-
	planner="$(metadata_value "$assignment" Decomposition-Planner-Model)"; [[ -n "$planner" ]] || planner=-
	fingerprint="$(acp_request_fingerprint "$task_id" "$thread_id" "$type" "$kind" "$identifier" "$workspace")"
	duplicates="$(acp_duplicate_count "$fingerprint")"
	if (( duplicates >= HARNESS_ACP_MAX_DUPLICATE_REQUESTS )); then
		acp_event_append - "$task_id" "$thread_id" "$sequence" DUPLICATE_REJECTED "$type" "$kind" "$fingerprint" "identifier=$identifier duplicates=$duplicates"
		mark_project_integrity_anomaly ACP_DUPLICATE_LOOP "$task_id" \
			'repeated materially identical ACP requests exceeded the investigation fuse' \
			"fingerprint=$fingerprint duplicates=$duplicates limit=$HARNESS_ACP_MAX_DUPLICATE_REQUESTS" >/dev/null
		return 2
	fi
	if [[ "$evidence_source" != - ]]; then evidence="$(acp_artifact_install "$evidence_source")"; fi
	request_id="acp-$(printf '%s' "$fingerprint" | cut -d: -f2 | cut -c1-16)-$(printf '%04d' "$sequence")"
	request="$(acp_pending_dir)/$request_id.request.md"
	[[ ! -e "$request" ]] || die "ACP request already exists: $request_id"
	if compgen -G "$(acp_archive_dir)/$request_id.*.md" >/dev/null; then
		die "ACP request identifier was already archived: $request_id"
	fi
	tmp="$request.tmp.$$"
	{
		printf '# Agent Coordination Protocol Request\n\n'
		printf 'ACP-Version: %s\nRequest-ID: %s\nProject: %s\nTask-ID: %s\n' \
			"$ACP_PROTOCOL_VERSION" "$request_id" "$PROJECT" "$task_id"
		printf 'Thread-ID: %s\nSequence: %s\nRequest-Type: %s\nRequest-Kind: %s\n' \
			"$thread_id" "$sequence" "$type" "$kind"
		printf 'Identifier: %s\nReason: %s\nWorkspace-Fingerprint: %s\n' \
			"$identifier" "$reason" "$workspace"
		printf 'Request-Fingerprint: %s\nEvidence-Artifact: %s\nAssignment: %s\nRequested-At: %s\n' \
			"$fingerprint" "$evidence" "$assignment" "$(timestamp_utc)"
		printf 'Initial-Scope-Fingerprint: %s\nInitial-Context-Fingerprint: %s\nLeaf-Type: %s\nPlanner: %s\n' \
			"$scope_fingerprint" "$context_fingerprint" "$leaf_type" "$planner"
		printf '\nThe request is an untrusted worker claim. Only deterministic broker evidence or manager policy may grant authority.\n'
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$request"
	acp_event_append "$request_id" "$task_id" "$thread_id" "$sequence" REQUESTED "$type" "$kind" "$fingerprint" \
		"identifier=$identifier evidence=$evidence scope_before=$scope_fingerprint context_before=$context_fingerprint leaf_type=$leaf_type planner=$planner"
	if [[ "$type" == PREREQUISITE || "$type" == SPLIT ]]; then
		acp_discovered_graph_append "$request_id" "$task_id" "$type" "$identifier" "$fingerprint" CLAIMED
	fi
	printf '%s\n' "$request"
}

acp_resolve_request()
{
	local request="$1" decision="$2" decided_by="$3" artifact="${4:--}" detail="${5:--}"
	local request_id task_id thread_id sequence type kind fingerprint destination identifier
	[[ -f "$request" ]] || die "ACP request is missing: $request"
	case "$decision" in GRANTED|DENIED|DEFERRED|SUPERSEDED) ;; *) die "invalid ACP decision: $decision" ;; esac
	request_id="$(metadata_value "$request" Request-ID)"
	task_id="$(metadata_value "$request" Task-ID)"
	thread_id="$(metadata_value "$request" Thread-ID)"
	sequence="$(metadata_value "$request" Sequence)"
	type="$(metadata_value "$request" Request-Type)"
	kind="$(metadata_value "$request" Request-Kind)"
	fingerprint="$(metadata_value "$request" Request-Fingerprint)"
	identifier="$(metadata_value "$request" Identifier)"
	destination="$(acp_archive_dir)/$request_id.$(tr '[:upper:]' '[:lower:]' <<< "$decision").md"
	[[ ! -e "$destination" ]] || die "ACP decision is already archived: $destination"
	{
		cat "$request"
		printf '\nDecision: %s\nDecided-By: %s\nDecision-Artifact: %s\nDecision-Detail: %s\nDecided-At: %s\n' \
			"$decision" "$decided_by" "$artifact" "$detail" "$(timestamp_utc)"
	} > "$destination.tmp.$$"
	chmod 600 "$destination.tmp.$$"
	mv "$destination.tmp.$$" "$destination"
	rm -f "$request"
	acp_event_append "$request_id" "$task_id" "$thread_id" "$sequence" "$decision" "$type" "$kind" "$fingerprint" "by=$decided_by artifact=$artifact detail=$detail"
	if [[ "$type" == PREREQUISITE || "$type" == SPLIT ]]; then
		acp_discovered_graph_append "$request_id" "$task_id" "$type" "$identifier" "$fingerprint" "$decision"
	fi
	printf '%s\n' "$destination"
}

acp_write_metrics()
{
	local events metrics tmp transactions graph planned_edges discovered_edges surface_tmp artifact
	local requested_paths repository_files requested_surface_percent
	ensure_acp_state
	events="$(acp_events_file)"
	metrics="$(acp_metrics_file)"
	tmp="$metrics.tmp.$$"
	awk -F '\t' '
		BEGIN {requests=grants=denials=deferrals=context_requests=context_grants=duplicates=structural=manager_dispositions=0; added=initial=authority=suspended=resumed=integrated=capability_deferrals=discovery_calls=0}
		!/^#/ {
			if ($7 == "REQUESTED") {requests++; if ($8 == "CONTEXT") context_requests++; else structural++}
			else if ($7 == "GRANTED") {grants++; if ($8 == "CONTEXT") {context_grants++; if (match($11, /added_bytes=[0-9]+/)) {v=substr($11,RSTART+12,RLENGTH-12); added+=v}}}
			else if ($7 == "DENIED") denials++
			else if ($7 == "DEFERRED") deferrals++
			else if ($7 == "DUPLICATE_REJECTED") duplicates++
			else if ($7 ~ /^MANAGER_/) manager_dispositions++
			if ($7 == "BROKER_STARTED" && match($11, /initial_context_bytes=[0-9]+/)) {v=substr($11,RSTART+22,RLENGTH-22); initial+=v}
			if ($7 ~ /^(GRANT_SCOPE|CREATE_PREREQUISITE|SPLIT_TASK|REPLAN_TASK|DENY_REQUEST|CANCEL_TASK|ARCHITECTURE_REASSESSMENT|SPECIFICATION_CLARIFICATION)$/) authority++
			if ($7 == "SUSPENDED") suspended++
			if ($7 == "RESUMED") resumed++
			if ($7 == "INTEGRATED") integrated++
			if ($7 == "CAPABILITY_DEFERRED") capability_deferrals++
			if ($7 == "WORKER_DISCOVERY_OBSERVED" && match($11, /tool_calls=[0-9]+/)) {v=substr($11,RSTART+11,RLENGTH-11); discovery_calls+=v}
		}
		END {
			printf "requests=%d\ngrants=%d\ndenials=%d\ndeferrals=%d\n", requests, grants, denials, deferrals
			printf "context_requests=%d\ncontext_grants=%d\nduplicate_rejections=%d\n", context_requests, context_grants, duplicates
			printf "structural_requests=%d\n", structural
			printf "manager_dispositions=%d\n", manager_dispositions
			printf "broker_hit_rate_percent=%d\n", context_requests ? int(100 * context_grants / context_requests) : 0
			printf "initial_context_bytes=%d\nadded_context_bytes=%d\n", initial, added
			printf "context_amplification_percent=%d\n", initial ? int(100 * added / initial) : 0
			# Four bytes/token plus a conservative fixed discovery-turn envelope is
			# an explicit proxy, not provider billing. Broker processing is local.
			estimated_model_discovery_tokens=int((added + 3) / 4) + context_grants * 256
			printf "estimated_model_discovery_tokens=%d\nbroker_model_tokens=0\nestimated_tokens_saved=%d\n", estimated_model_discovery_tokens, estimated_model_discovery_tokens
			printf "authority_decisions=%d\nsuspensions=%d\nresumptions=%d\nintegrations=%d\ncapability_deferrals=%d\n", authority, suspended, resumed, integrated, capability_deferrals
			printf "repository_discovery_tool_calls=%d\n", discovery_calls
		}
	' "$events" > "$tmp"
	graph="$(acp_discovered_graph_file)"
	discovered_edges="$(awk -F '\t' '!/^#/ && ($4 == "DISCOVERED_EDGE" || $4 == "PREREQUISITE" || $4 == "SPLIT") {seen[$2 SUBSEP $5]=1} END {for (x in seen) count++; print count + 0}' "$graph")"
	planned_edges=0
	if project_plan_uses_dag; then
		planned_edges="$(awk -F '\t' 'NR == 1 {for(i=1;i<=NF;i++) if($i=="depends_on") c=i; next} c && $c!="-" && $c!="" {n=split($c,a,","); total+=n} END {print total + 0}' "$(project_decomposition_plan_file)")"
	fi
	printf 'planned_edges=%s\ndiscovered_edges=%s\ndiscovered_to_planned_edge_percent=%s\n' \
		"$planned_edges" "$discovered_edges" \
		"$(awk -v d="$discovered_edges" -v p="$planned_edges" 'BEGIN {print p ? int(100*d/p) : 0}')" >> "$tmp"
	surface_tmp="$(acp_control_dir)/surface-paths.tmp.$$"
	: > "$surface_tmp"
	while IFS= read -r artifact; do
		[[ -f "$artifact" ]] || continue
		sed -n 's/^## [^:]*: `\([^`:]*\):[0-9][0-9]*`.*/\1/p' "$artifact" >> "$surface_tmp"
	done < <(awk -F '\t' '!/^#/ && $7=="GRANTED" && $8=="CONTEXT" {if (match($11,/artifact=[^ ]+/)) print substr($11,RSTART+9,RLENGTH-9)}' "$events")
	requested_paths="$(LC_ALL=C sort -u "$surface_tmp" | awk 'NF {n++} END {print n+0}')"
	repository_files="$(git -C "$REPOSITORY" ls-files -z 2>/dev/null | awk 'BEGIN {RS="\0"} NF {n++} END {print n+0}')"
	requested_surface_percent="$(awk -v r="$requested_paths" -v n="$repository_files" 'BEGIN {print n ? int(100*r/n) : 0}')"
	rm -f "$surface_tmp"
	printf 'requested_repository_paths=%s\nrepository_tracked_files=%s\nrequested_repository_surface_percent=%s\n' \
		"$requested_paths" "$repository_files" "$requested_surface_percent" >> "$tmp"
	if [[ "${HARNESS_CONTEXT_CLOSURE_MODE:-off}" == patch_only &&
		"$(kv_file_value "$tmp" repository_discovery_tool_calls)" == 0 ]]; then
		printf 'repository_discovery_tokens=0\nrepository_discovery_tokens_status=ZERO_BY_NO_TOOLS_POLICY\n' >> "$tmp"
	else
		printf 'repository_discovery_tokens=-1\nrepository_discovery_tokens_status=UNATTRIBUTED\n' >> "$tmp"
	fi
	printf 'updated_at=%s\n' "$(timestamp_utc)" >> "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$metrics"
	transactions="$(acp_transactions_file)"
	awk -F '\t' 'BEGIN {OFS="\t"; print "request_id","task_id","thread_id","type","kind","fingerprint","requested_at","leaf_type","planner","scope_before","scope_after","context_before","context_after","broker_decision","manager_decision","event_count","eventual_state"}
		!/^#/ && $2 != "-" {
			id=$2; task[id]=$4; thread[id]=$5; type[id]=$8; kind[id]=$9; fp[id]=$10; count[id]++
			if ($7=="REQUESTED" && !(id in requested)) {
				requested[id]=$1
				if (match($11,/leaf_type=[^ ]+/)) leaf[id]=substr($11,RSTART+10,RLENGTH-10)
				if (match($11,/planner=[^ ]+/)) planner[id]=substr($11,RSTART+8,RLENGTH-8)
				if (match($11,/scope_before=sha256:[0-9a-f]+/)) sb[id]=substr($11,RSTART+13,RLENGTH-13)
				if (match($11,/context_before=sha256:[0-9a-f]+/)) cb[id]=substr($11,RSTART+15,RLENGTH-15)
			}
			if ($7 ~ /^(GRANTED|DENIED|DEFERRED|SUPERSEDED)$/) broker[id]=$7
			if ($7 ~ /^(GRANT_SCOPE|CREATE_PREREQUISITE|SPLIT_TASK|REPLAN_TASK|DENY_REQUEST|CANCEL_TASK|ARCHITECTURE_REASSESSMENT|SPECIFICATION_CLARIFICATION)$/) manager[id]=$7
			if ($7=="RESUMED") {
				if (match($11,/scope_after=sha256:[0-9a-f]+/)) sa[id]=substr($11,RSTART+12,RLENGTH-12)
				if (match($11,/context_after=sha256:[0-9a-f]+/)) ca[id]=substr($11,RSTART+14,RLENGTH-14)
			}
			if ($7=="RESUMED" || $7=="MANAGER_ACCEPT" || $7=="MANAGER_BLOCK") final[id]=$7
		}
		END {for(id in requested) print id,task[id],thread[id],type[id],kind[id],fp[id],requested[id],leaf[id],planner[id],sb[id],sa[id],cb[id],ca[id],broker[id],manager[id],count[id],final[id]}
	' "$events" | { IFS= read -r header; printf '%s\n' "$header"; LC_ALL=C sort; } > "$transactions.tmp.$$"
	chmod 600 "$transactions.tmp.$$"
	mv "$transactions.tmp.$$" "$transactions"
}

acp_record_manager_disposition()
{
	local result="$1" disposition="$2" artifact="${3:--}" request_id row
	local task_id thread_id sequence type kind fingerprint identifier
	[[ -f "$result" ]] || return 0
	request_id="$(metadata_value "$result" ACP-Request-ID 2>/dev/null || true)"
	[[ -n "$request_id" ]] || return 0
	case "$disposition" in MANAGER_ACCEPT|MANAGER_CHECKPOINT|MANAGER_REPLAN|MANAGER_BLOCK) ;;
		*) die "invalid ACP manager disposition: $disposition" ;;
	esac
	ensure_acp_state
	if awk -F '\t' -v id="$request_id" -v disposition="$disposition" \
		'!/^#/ && $2 == id && $7 == disposition {found=1} END {exit !found}' "$(acp_events_file)"; then
		return 0
	fi
	row="$(awk -F '\t' -v id="$request_id" '!/^#/ && $2 == id && $7 == "REQUESTED" {print; exit}' "$(acp_events_file)")"
	if [[ -z "$row" ]]; then
		mark_project_integrity_anomaly ACP_ACCOUNTING_INCONSISTENCY - \
			'manager reviewed a typed ACP result whose durable request event is missing' \
			"request_id=$request_id result=$result disposition=$disposition" >/dev/null
		return 1
	fi
	IFS=$'\t' read -r _ _ _ task_id thread_id sequence _ type kind fingerprint _ <<< "$row"
	identifier="$(metadata_value "$result" ACP-Request-Identifier 2>/dev/null || printf -)"
	acp_event_append "$request_id" "$task_id" "$thread_id" "$sequence" "$disposition" "$type" "$kind" "$fingerprint" \
		"artifact=$artifact result=$result"
	acp_record_authority_decision "$request_id" "$task_id" "$thread_id" "$sequence" \
		"$type" "$kind" "$fingerprint" "$disposition" "$artifact"
	if [[ "$type" == PREREQUISITE || "$type" == SPLIT ]]; then
		acp_discovered_graph_append "$request_id" "$task_id" "$type" "$identifier" "$fingerprint" "$disposition"
	fi
	acp_write_metrics
}

acp_suspension_file()
{
	printf '%s/%s.suspended.env\n' "$(acp_suspension_dir)" "$(task_root_id "$1")"
}

acp_register_suspension()
{
	local request_id="$1" task_id="$2" thread_id="$3" type="$4" kind="$5" identifier="$6"
	local file tmp
	ensure_acp_state
	file="$(acp_suspension_file "$task_id")"
	tmp="$file.tmp.$$"
	{
		printf 'request_id=%s\n' "$request_id"
		printf 'task_id=%s\n' "$task_id"
		printf 'task_root=%s\n' "$(task_root_id "$task_id")"
		printf 'thread_id=%s\n' "$thread_id"
		printf 'request_type=%s\n' "$type"
		printf 'request_kind=%s\n' "$kind"
		printf 'identifier=%s\n' "$identifier"
		printf 'state=AWAITING_MANAGER\n'
		printf 'suspended_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
	acp_event_append "$request_id" "$task_id" "$thread_id" 0 SUSPENDED "$type" "$kind" - \
		"identifier=$identifier inference_process=exited"
}

acp_root_is_suspended()
{
	[[ -f "$(acp_suspension_file "$1")" ]]
}

acp_record_authority_decision()
{
	local request_id="$1" task_id="$2" thread_id="$3" sequence="$4" type="$5"
	local kind="$6" fingerprint="$7" disposition="$8" artifact="${9:--}"
	local decision file tmp state
	case "$disposition:$type" in
		MANAGER_ACCEPT:*) decision=DENY_REQUEST; state=CLOSED_ALREADY_SATISFIED ;;
		*:CANCEL) decision=CANCEL_TASK; state=CANCELLED ;;
		MANAGER_REPLAN:CHALLENGE|MANAGER_CHECKPOINT:CHALLENGE) decision=REPLAN_TASK; state=AWAITING_REASSESSMENT ;;
		MANAGER_BLOCK:*) decision=SPECIFICATION_CLARIFICATION; state=AWAITING_CLARIFICATION ;;
		MANAGER_REPLAN:SCOPE|MANAGER_CHECKPOINT:SCOPE) decision=GRANT_SCOPE; state=AWAITING_RESUME ;;
		MANAGER_REPLAN:PREREQUISITE|MANAGER_CHECKPOINT:PREREQUISITE) decision=CREATE_PREREQUISITE; state=AWAITING_PREREQUISITE ;;
		MANAGER_REPLAN:SPLIT|MANAGER_CHECKPOINT:SPLIT) decision=SPLIT_TASK; state=AWAITING_SPLIT ;;
		*) decision=DENY_REQUEST; state=CLOSED_DENIED ;;
	esac
	acp_event_append "$request_id" "$task_id" "$thread_id" "$sequence" "$decision" \
		"$type" "$kind" "$fingerprint" "manager_disposition=$disposition artifact=$artifact"
	file="$(acp_suspension_file "$task_id")"
	[[ -f "$file" ]] || return 0
	tmp="$file.tmp.$$"
	awk -F= -v state="$state" -v decision="$decision" -v artifact="$artifact" '
		$1 == "state" || $1 == "manager_decision" || $1 == "decision_artifact" || $1 == "decided_at" {next}
		{print}
		END {
			print "state=" state
			print "manager_decision=" decision
			print "decision_artifact=" artifact
		}
	' "$file" > "$tmp"
	printf 'decided_at=%s\n' "$(timestamp_utc)" >> "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
}

acp_record_task_publication()
{
	local task_id="$1" assignment="$2" manager_remediation="${3:-0}"
	local file request_id source_task thread_id type kind identifier decision state tmp archive
	local resume_scope resume_context resume_scope_fingerprint resume_context_fingerprint
	file="$(acp_suspension_file "$task_id")"
	[[ -f "$file" ]] || return 0
	request_id="$(kv_file_value "$file" request_id)"
	source_task="$(kv_file_value "$file" task_id)"
	thread_id="$(kv_file_value "$file" thread_id)"
	type="$(kv_file_value "$file" request_type)"
	kind="$(kv_file_value "$file" request_kind)"
	identifier="$(kv_file_value "$file" identifier)"
	decision="$(kv_file_value "$file" manager_decision 2>/dev/null || true)"
	state="$(kv_file_value "$file" state)"
	case "$decision:$manager_remediation" in
		CREATE_PREREQUISITE:1)
			acp_event_append "$request_id" "$source_task" "$thread_id" 0 PREREQUISITE_CREATED \
				"$type" "$kind" - "prerequisite_task=$task_id identifier=$identifier"
			acp_discovered_graph_append "$request_id" "$source_task" DISCOVERED_NODE "$task_id" - CREATED
			acp_discovered_graph_append "$request_id" "$source_task" DISCOVERED_EDGE "$task_id->$source_task" - ACTIVE
			tmp="$file.tmp.$$"
			awk -F= '$1 != "state" && $1 != "prerequisite_task" {print}' "$file" > "$tmp"
			printf 'state=WAITING_PREREQUISITE\nprerequisite_task=%s\n' "$task_id" >> "$tmp"
			chmod 600 "$tmp"; mv "$tmp" "$file"
			return 0
			;;
		SPLIT_TASK:*)
			acp_event_append "$request_id" "$source_task" "$thread_id" 0 SPLIT_CHILD_CREATED \
				"$type" "$kind" - "child_task=$task_id identifier=$identifier"
			acp_discovered_graph_append "$request_id" "$source_task" DISCOVERED_NODE "$task_id" - CREATED
			;;
		GRANT_SCOPE:*|CREATE_PREREQUISITE:0) ;;
		*) return 0 ;;
	esac
	resume_scope="$(metadata_value "$assignment" Allowed-Scope)"
	resume_context="$(metadata_value "$assignment" Context-Paths)"
	resume_scope_fingerprint="$(printf '%s' "$resume_scope" | sha256sum | awk '{print "sha256:" $1}')"
	resume_context_fingerprint="$(printf '%s' "$resume_context" | sha256sum | awk '{print "sha256:" $1}')"
	acp_event_append "$request_id" "$source_task" "$thread_id" 0 RESUMED "$type" "$kind" - \
		"resume_task=$task_id saved_session=$thread_id previous_state=$state scope_after=$resume_scope_fingerprint context_after=$resume_context_fingerprint"
	acp_discovered_graph_append "$request_id" "$source_task" RESUME "$task_id" - ACTIVE
	archive="$(acp_archive_dir)/$request_id.suspension-complete.env"
	{
		cat "$file"
		printf 'state=RESUMED\nresume_task=%s\nresumed_at=%s\n' "$task_id" "$(timestamp_utc)"
	} > "$archive.tmp.$$"
	chmod 600 "$archive.tmp.$$"
	mv "$archive.tmp.$$" "$archive"
	rm -f "$file"
}

acp_scheduler_capacity()
{
	local capacity
	if (( HARNESS_WORKER_PARALLELISM == 0 )); then
		capacity="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 1)"
		[[ "$capacity" =~ ^[1-9][0-9]*$ ]] || capacity=1
		(( capacity <= HARNESS_WORKER_PARALLELISM_HARD_MAX )) || capacity="$HARNESS_WORKER_PARALLELISM_HARD_MAX"
	else
		capacity="$HARNESS_WORKER_PARALLELISM"
	fi
	printf '%s\n' "$capacity"
}

acp_normalize_capability_paths()
{
	local assignment="$1" value path
	local -a capability_paths=()
	value="$(metadata_value "$assignment" Allowed-Scope)"
	IFS=',' read -r -a capability_paths <<< "$value"
	for path in "${capability_paths[@]}"; do
		path="${path#"${path%%[![:space:]]*}"}"
		path="${path%"${path##*[![:space:]]}"}"
		[[ -n "$path" && "$path" != - && "$path" != NONE ]] || continue
		[[ "$path" != /* && "$path" != .. && "$path" != ../* && "$path" != */../* ]] || return 2
		printf '%s\n' "${path%/}"
	done | LC_ALL=C sort -u
}

acp_capability_paths_conflict()
{
	local left="$1" right="$2" a b
	while IFS= read -r a; do
		[[ -n "$a" ]] || continue
		while IFS= read -r b; do
			[[ -n "$b" ]] || continue
			if [[ "$a" == . || "$b" == . || "$a" == "$b" || "$a" == "$b/"* || "$b" == "$a/"* ]]; then return 0; fi
		done < "$right"
	done < "$left"
	return 1
}
