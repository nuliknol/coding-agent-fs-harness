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

acp_discovered_graph_file()
{
	printf '%s/discovered-graph.tsv\n' "$(acp_control_dir)"
}

ensure_acp_state()
{
	local dir events init_lock
	dir="$(acp_control_dir)"
	mkdir -p "$(acp_pending_dir)" "$(acp_archive_dir)" "$(acp_artifact_dir)"
	chmod 700 "$dir" "$(acp_pending_dir)" "$(acp_archive_dir)" "$(acp_artifact_dir)"
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
		CONTEXT|SCOPE|PREREQUISITE|SPLIT) ;;
		*) die "unsupported ACP request type: $1" ;;
	esac
}

acp_validate_context_kind()
{
	case "$1" in
		TYPE_DEFINITION|SYMBOL_DEFINITION|CALLER_CONTRACT|CALLEE_CONTRACT|\
		FAILING_ASSERTION|TEST_OWNER|BUILD_OWNER|OWNER|PRODUCER|CONSUMER|\
		REPRESENTATION_WRITER) ;;
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
		printf '\nThe request is an untrusted worker claim. Only deterministic broker evidence or manager policy may grant authority.\n'
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$request"
	acp_event_append "$request_id" "$task_id" "$thread_id" "$sequence" REQUESTED "$type" "$kind" "$fingerprint" "identifier=$identifier evidence=$evidence"
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
	local events metrics tmp
	ensure_acp_state
	events="$(acp_events_file)"
	metrics="$(acp_metrics_file)"
	tmp="$metrics.tmp.$$"
	awk -F '\t' '
		BEGIN {requests=grants=denials=deferrals=context_requests=context_grants=duplicates=structural=manager_dispositions=0}
		!/^#/ {
			if ($7 == "REQUESTED") {requests++; if ($8 == "CONTEXT") context_requests++; else structural++}
			else if ($7 == "GRANTED") {grants++; if ($8 == "CONTEXT") context_grants++}
			else if ($7 == "DENIED") denials++
			else if ($7 == "DEFERRED") deferrals++
			else if ($7 == "DUPLICATE_REJECTED") duplicates++
			else if ($7 ~ /^MANAGER_/) manager_dispositions++
		}
		END {
			printf "requests=%d\ngrants=%d\ndenials=%d\ndeferrals=%d\n", requests, grants, denials, deferrals
			printf "context_requests=%d\ncontext_grants=%d\nduplicate_rejections=%d\n", context_requests, context_grants, duplicates
			printf "structural_requests=%d\n", structural
			printf "manager_dispositions=%d\n", manager_dispositions
			printf "broker_hit_rate_percent=%d\n", context_requests ? int(100 * context_grants / context_requests) : 0
		}
	' "$events" > "$tmp"
	printf 'updated_at=%s\n' "$(timestamp_utc)" >> "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$metrics"
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
	if [[ "$type" == PREREQUISITE || "$type" == SPLIT ]]; then
		acp_discovered_graph_append "$request_id" "$task_id" "$type" "$identifier" "$fingerprint" "$disposition"
	fi
	acp_write_metrics
}
