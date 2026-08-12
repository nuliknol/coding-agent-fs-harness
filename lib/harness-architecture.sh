#!/usr/bin/env bash

# Architecture-health sidecars for Full-v2 projects. This file is sourced by
# harness-common.sh; functions intentionally resolve common helpers at runtime.

architecture_dir()
{
	printf '%s/control/architecture' "$(project_dir)"
}

architecture_invariants_file() { printf '%s/invariants.tsv' "$(architecture_dir)"; }
architecture_decisions_file() { printf '%s/decisions.tsv' "$(architecture_dir)"; }
architecture_edges_file() { printf '%s/edges.tsv' "$(architecture_dir)"; }
architecture_node_bindings_file() { printf '%s/node-bindings.tsv' "$(architecture_dir)"; }
architecture_health_gates_file() { printf '%s/health-gates.tsv' "$(architecture_dir)"; }
architecture_debt_file() { printf '%s/debt.tsv' "$(architecture_dir)"; }
architecture_decision_ledger_file() { printf '%s/decision-ledger.tsv' "$(architecture_dir)"; }
architecture_health_ledger_file() { printf '%s/health-ledger.tsv' "$(architecture_dir)"; }
architecture_debt_ledger_file() { printf '%s/debt-ledger.tsv' "$(architecture_dir)"; }
architecture_impact_dir() { printf '%s/impacts' "$(architecture_dir)"; }
architecture_profile_file() { printf '%s/profile.env' "$(architecture_dir)"; }

architecture_profile()
{
	local file
	file="$(architecture_profile_file)"
	[[ -f "$file" ]] || { printf 'explicit\n'; return 0; }
	awk -F= '$1 == "profile" {print substr($0, index($0, "=") + 1); found=1; exit} END {if (!found) print "unknown"}' "$file"
}

architecture_registered()
{
	[[ -f "$(architecture_invariants_file)" && -f "$(architecture_decisions_file)" &&
		-f "$(architecture_edges_file)" && -f "$(architecture_node_bindings_file)" &&
		-f "$(architecture_health_gates_file)" && -f "$(architecture_debt_file)" &&
		-f "$(architecture_decision_ledger_file)" && -f "$(architecture_health_ledger_file)" &&
		-f "$(architecture_debt_ledger_file)" ]]
}

architecture_require_registered()
{
	(( HARNESS_ARCHITECTURE_GUARDS == 0 )) || architecture_registered ||
		die 'architecture guards require initialized invariant, decision, edge, node-binding, health-gate, and debt sidecars'
}

architecture_validate_id()
{
	[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || die "invalid architecture identifier: $1"
}

architecture_parse_id_list()
{
	local list="$1" target="$2" item
	local -n output="$target"
	output=()
	[[ "$list" == - ]] && return 0
	[[ -n "$list" ]] || die 'architecture identifier list must use - when empty'
	IFS=',' read -r -a output <<< "$list"
	for item in "${output[@]}"; do
		architecture_validate_id "$item"
	done
}

architecture_list_contains()
{
	local list="$1" wanted="$2" id
	local -a ids=()
	architecture_parse_id_list "$list" ids
	for id in "${ids[@]}"; do [[ "$id" == "$wanted" ]] && return 0; done
	return 1
}

architecture_registry_has_id()
{
	local file="$1" id="$2"
	awk -F '\t' -v id="$id" 'NR > 1 && $1 == id {found=1} END {exit !found}' "$file"
}

architecture_require_id_list()
{
	local label="$1" list="$2" registry="$3" id
	local -a ids=()
	[[ -n "$list" ]] || die "$label must be '-' or a comma-separated identifier list"
	architecture_parse_id_list "$list" ids
	for id in "${ids[@]}"; do
		architecture_registry_has_id "$registry" "$id" || die "$label references unknown identifier: $id"
	done
}

architecture_validate_source_file()
{
	local kind="$1" file="$2" expected="$3" min_fields="$4" header fields first
	[[ -f "$file" ]] || die "$kind source does not exist: $file"
	IFS= read -r header < "$file" || die "$kind source is empty"
	[[ "$header" == "$expected" ]] || die "$kind header must be: $expected"
	while IFS=$'\t' read -r -a fields; do
		[[ -n "${fields[0]:-}" ]] || continue
		(( ${#fields[@]} == min_fields )) || die "$kind row ${fields[0]} must contain exactly $min_fields tab-separated fields"
		first="${fields[0]}"
		architecture_validate_id "$first"
	done < <(tail -n +2 "$file")
}

architecture_initialize()
{
	local source_dir="$1" dir file debt
	local inv_header dec_header edge_header binding_header gate_header debt_header
	[[ -d "$source_dir" ]] || die "architecture source directory does not exist: $source_dir"
	dir="$(architecture_dir)"
	[[ ! -e "$dir" ]] || die "architecture registry already exists: $dir"
	inv_header=$'invariant_id\tcategory\tauthority\tseverity\tstatement\tscope\tsource_requirement\tvalidation_kind\tvalidation_ref\taffected_nodes'
	dec_header=$'decision_id\tstatus\tproducer_node\tproblem\tchosen_contract\taffected_interfaces\tsupersedes\tevidence'
	edge_header=$'edge_id\tproducer_node\tconsumer_node\tcontract_artifact\tpublic_symbols\townership_model\trepresentation\tversioning_rule\tcompatibility_validation\tdecision_ids\tinvariant_ids'
	binding_header=$'node_id\tinvariant_ids\tconsumes_decisions\tproduces_decisions\tedge_contracts\thealth_gates'
	gate_header=$'gate_id\ttrigger_node\tdepends_on\tvalidation\tseverity\tinvariant_ids\tedge_ids'
	debt_header=$'debt_id\tintroduced_by_task\tintroduced_by_commit\tcategory\taffected_invariants\tconsequence\tremediation_node\tseverity\texpires_at\tstatus\twaiver_authority'
	architecture_validate_source_file invariants "$source_dir/invariants.tsv" "$inv_header" 10
	architecture_validate_source_file decisions "$source_dir/decisions.tsv" "$dec_header" 8
	architecture_validate_source_file edges "$source_dir/edges.tsv" "$edge_header" 11
	architecture_validate_source_file node-bindings "$source_dir/node-bindings.tsv" "$binding_header" 6
	architecture_validate_source_file health-gates "$source_dir/health-gates.tsv" "$gate_header" 7
	architecture_validate_source_file debt "$source_dir/debt.tsv" "$debt_header" 11
	mkdir -p "$dir" "$dir/impacts" "$dir/health-logs"
	chmod 700 "$dir" "$dir/impacts" "$dir/health-logs"
	for file in invariants.tsv decisions.tsv edges.tsv node-bindings.tsv health-gates.tsv debt.tsv; do
		install -m 600 "$source_dir/$file" "$dir/$file"
	done
	printf 'decision_id\tstate\tverified_by\tevidence_sha256\tupdated_at\n' > "$(architecture_decision_ledger_file)"
	printf 'gate_id\tstate\tverified_by\tevidence_sha256\tupdated_at\n' > "$(architecture_health_ledger_file)"
	printf 'debt_id\taction\tactor\tevidence_sha256\tupdated_at\n' > "$(architecture_debt_ledger_file)"
	while IFS=$'\t' read -r debt _; do
		[[ "$debt" != debt_id ]] || continue
		printf '%s\tINITIAL\tregistry\t-\t%s\n' "$debt" "$(timestamp_utc)" >> "$(architecture_debt_ledger_file)"
	done < "$(architecture_debt_file)"
	chmod 600 "$(architecture_decision_ledger_file)" "$(architecture_health_ledger_file)" "$(architecture_debt_ledger_file)"
	if ! ( architecture_validate_registries ); then
		rm -rf -- "$dir"
		die 'architecture registry validation failed; incomplete registry was rolled back'
	fi
	log_event "ARCHITECTURE_REGISTRY_INITIALIZED directory=$dir"
}

architecture_initialize_minimal_test_profile()
{
	local plan="$1" expected_header row node parent depends deliverable evidence validation
	local paths symbols leaf complexity route profile_dir invariant gate profile_file
	local -a rows=() fields=()
	expected_header=$'node_id\tparent_id\tdepends_on\tdeliverable\tacceptance_evidence\tfocused_validation\tallowed_paths\trequired_symbols\tleaf_type\tcomplexity_class\tworker_route'
	[[ -f "$plan" ]] || return 1
	[[ "$(sed -n '1p' "$plan")" == "$expected_header" ]] || return 1
	mapfile -t rows < <(tail -n +2 "$plan" | sed '/^[[:space:]]*$/d')
	(( ${#rows[@]} == 1 )) || return 1
	row="${rows[0]}"
	IFS=$'\t' read -r -a fields <<< "$row"
	(( ${#fields[@]} == 11 )) || return 1
	node="${fields[0]}"; parent="${fields[1]}"; depends="${fields[2]}"
	deliverable="${fields[3]}"; evidence="${fields[4]}"; validation="${fields[5]}"
	paths="${fields[6]}"; symbols="${fields[7]}"; leaf="${fields[8]}"
	complexity="${fields[9]}"; route="${fields[10]}"
	[[ "$node" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$parent" == - && "$depends" == - ]] || return 1
	[[ "$leaf" == TEST_IMPLEMENTATION && "$complexity" == LOW && "$route" == LUNA ]] || return 1
	[[ -n "$SPECIFICATION" && -f "$SPECIFICATION" ]] || return 1
	[[ -n "$deliverable" && -n "$evidence" && -n "$validation" && "$validation" != REVIEW ]] || return 1
	[[ -n "$paths" && "$paths" != - && "$paths" != / && "$paths" != . && "$paths" != *'*'* ]] || return 1
	(( $(awk -F',' '{print NF}' <<< "$paths") <= 5 )) || return 1
	[[ -n "$symbols" ]] || return 1

	profile_dir="$(mktemp -d "$PROJECT_TMP_DIR/minimal-test-architecture.XXXXXX")"
	chmod 700 "$profile_dir"
	invariant="INV-$node-test-obligation"
	gate="GATE-$node-test-acceptance"
	printf 'invariant_id\tcategory\tauthority\tseverity\tstatement\tscope\tsource_requirement\tvalidation_kind\tvalidation_ref\taffected_nodes\n' > "$profile_dir/invariants.tsv"
	printf '%s\tOTHER\tSPECIFIED\tCRITICAL\t%s\t%s\t%s\tCOMMAND\t%s\t%s\n' \
		"$invariant" "$deliverable; $evidence" "$paths" "$SPECIFICATION" "$validation" "$node" >> "$profile_dir/invariants.tsv"
	printf 'decision_id\tstatus\tproducer_node\tproblem\tchosen_contract\taffected_interfaces\tsupersedes\tevidence\n' > "$profile_dir/decisions.tsv"
	printf 'edge_id\tproducer_node\tconsumer_node\tcontract_artifact\tpublic_symbols\townership_model\trepresentation\tversioning_rule\tcompatibility_validation\tdecision_ids\tinvariant_ids\n' > "$profile_dir/edges.tsv"
	printf 'node_id\tinvariant_ids\tconsumes_decisions\tproduces_decisions\tedge_contracts\thealth_gates\n' > "$profile_dir/node-bindings.tsv"
	printf '%s\t%s\t-\t-\t-\t%s\n' "$node" "$invariant" "$gate" >> "$profile_dir/node-bindings.tsv"
	printf 'gate_id\ttrigger_node\tdepends_on\tvalidation\tseverity\tinvariant_ids\tedge_ids\n' > "$profile_dir/health-gates.tsv"
	printf '%s\t%s\t-\t%s\tCRITICAL\t%s\t-\n' "$gate" "$node" "$validation" "$invariant" >> "$profile_dir/health-gates.tsv"
	printf 'debt_id\tintroduced_by_task\tintroduced_by_commit\tcategory\taffected_invariants\tconsequence\tremediation_node\tseverity\texpires_at\tstatus\twaiver_authority\n' > "$profile_dir/debt.tsv"
	architecture_initialize "$profile_dir"
	profile_file="$(architecture_profile_file)"
	{
		printf 'profile=minimal-single-node-test\n'
		printf 'node_id=%s\n' "$node"
		printf 'source_plan_sha256=%s\n' "$(sha256sum "$plan" | awk '{print $1}')"
		printf 'generated_at=%s\n' "$(timestamp_utc)"
	} > "$profile_file"
	chmod 600 "$profile_file"
	rm -rf -- "$profile_dir"
	log_event "ARCHITECTURE_MINIMAL_TEST_PROFILE_GENERATED node=$node invariant=$invariant gate=$gate"
}

architecture_validate_registries()
{
	local id category authority severity statement scope source validation_kind validation_ref nodes
	local status producer problem contract interfaces supersedes evidence
	local edge producer_node consumer_node artifact symbols ownership representation versioning validation decisions invariants
	local node consumes produces edges gates gate depends debt task commit consequence remediation expires waiver invariant_authority
	local invariant_count=0 critical_gate_count=0 id
	local -a ids=()
	architecture_require_registered
	declare -A seen=()
	while IFS=$'\t' read -r id category authority severity statement scope source validation_kind validation_ref nodes; do
		[[ "$id" != invariant_id ]] || continue
		[[ -z "${seen[$id]:-}" ]] || die "duplicate invariant: $id"; seen[$id]=1
		[[ "$category" =~ ^(OWNERSHIP|CANONICAL_REPRESENTATION|LAYERING|SERIALIZATION|CONCURRENCY|ERROR_MODEL|DEVICE_AUTHORITY|PUBLIC_API|DEPENDENCY_CYCLE|SECURITY|PERFORMANCE|OTHER)$ ]] || die "invalid invariant category for $id"
		[[ "$authority" =~ ^(SPECIFIED|DERIVED|PROPOSED)$ ]] || die "invalid invariant authority for $id"
		[[ "$severity" =~ ^(INFO|WARNING|CRITICAL)$ ]] || die "invalid invariant severity for $id"
		[[ -n "$statement" && -n "$scope" && "$source" != - && "$validation_kind" =~ ^(COMMAND|REVIEW)$ && -n "$validation_ref" && -n "$nodes" ]] || die "invariant $id has empty required fields"
		[[ "$authority" == PROPOSED || "$nodes" != - ]] || die "enforceable invariant $id requires affected_nodes"
		invariant_count=$((invariant_count + 1))
	done < "$(architecture_invariants_file)"
	(( invariant_count > 0 )) || die 'architecture guards require at least one global invariant'
	seen=()
	while IFS=$'\t' read -r id status producer problem contract interfaces supersedes evidence; do
		[[ "$id" != decision_id ]] || continue
		[[ -z "${seen[$id]:-}" ]] || die "duplicate decision: $id"; seen[$id]=1
		[[ "$status" =~ ^(PROPOSED|ACCEPTED|SUPERSEDED)$ ]] || die "invalid decision status for $id"
		[[ -n "$producer" && -n "$problem" && -n "$contract" && -n "$interfaces" && -n "$supersedes" && -n "$evidence" ]] || die "decision $id has empty required fields"
		if [[ "$status" == ACCEPTED ]]; then
			[[ "$evidence" != - && -f "$REPOSITORY/$evidence" ]] || die "accepted decision $id lacks repository evidence: $evidence"
			git -C "$REPOSITORY" ls-tree -r --name-only HEAD -- "$evidence" | grep -Fqx -- "$evidence" ||
				die "accepted decision $id evidence is not committed at HEAD: $evidence"
		fi
	done < "$(architecture_decisions_file)"
	seen=()
	while IFS=$'\t' read -r edge producer_node consumer_node artifact symbols ownership representation versioning validation decisions invariants; do
		[[ "$edge" != edge_id ]] || continue
		[[ -z "${seen[$edge]:-}" ]] || die "duplicate edge contract: $edge"; seen[$edge]=1
		[[ -n "$producer_node" && -n "$consumer_node" && -n "$artifact" && -n "$symbols" && -n "$ownership" && -n "$representation" && -n "$versioning" && -n "$validation" ]] || die "edge $edge has empty required fields"
		architecture_require_id_list "edge $edge decision_ids" "$decisions" "$(architecture_decisions_file)"
		architecture_require_id_list "edge $edge invariant_ids" "$invariants" "$(architecture_invariants_file)"
	done < "$(architecture_edges_file)"
	seen=()
	while IFS=$'\t' read -r node invariants consumes produces edges gates; do
		[[ "$node" != node_id ]] || continue
		[[ -z "${seen[$node]:-}" ]] || die "duplicate architecture node binding: $node"; seen[$node]=1
		architecture_require_id_list "node $node invariant_ids" "$invariants" "$(architecture_invariants_file)"
		architecture_require_id_list "node $node consumes_decisions" "$consumes" "$(architecture_decisions_file)"
		architecture_require_id_list "node $node produces_decisions" "$produces" "$(architecture_decisions_file)"
		architecture_require_id_list "node $node edge_contracts" "$edges" "$(architecture_edges_file)"
		architecture_parse_id_list "$invariants" ids
		for id in "${ids[@]}"; do
			invariant_authority="$(awk -F '\t' -v id="$id" 'NR>1 && $1==id {print $3; exit}' "$(architecture_invariants_file)")"
			[[ "$invariant_authority" != PROPOSED ]] || die "proposed invariant $id is advisory and cannot constrain node $node"
		done
	done < "$(architecture_node_bindings_file)"
	seen=()
	while IFS=$'\t' read -r gate node depends validation severity invariants edges; do
		[[ "$gate" != gate_id ]] || continue
		[[ -z "${seen[$gate]:-}" ]] || die "duplicate health gate: $gate"; seen[$gate]=1
		[[ "$severity" =~ ^(WARNING|CRITICAL)$ && -n "$node" && -n "$depends" && -n "$validation" ]] || die "invalid health gate: $gate"
		[[ "$severity" != CRITICAL ]] || critical_gate_count=$((critical_gate_count + 1))
		architecture_require_id_list "health gate $gate invariant_ids" "$invariants" "$(architecture_invariants_file)"
		architecture_require_id_list "health gate $gate edge_ids" "$edges" "$(architecture_edges_file)"
	done < "$(architecture_health_gates_file)"
	(( critical_gate_count > 0 )) || die 'architecture guards require at least one CRITICAL cumulative health gate'
	while IFS=$'\t' read -r node invariants consumes produces edges gates; do
		[[ "$node" != node_id ]] || continue
		architecture_require_id_list "node $node health_gates" "$gates" "$(architecture_health_gates_file)"
	done < "$(architecture_node_bindings_file)"
	seen=()
	while IFS=$'\t' read -r debt task commit category invariants consequence remediation severity expires status waiver; do
		[[ "$debt" != debt_id ]] || continue
		[[ -z "${seen[$debt]:-}" ]] || die "duplicate debt ID: $debt"; seen[$debt]=1
		[[ "$severity" =~ ^(INFO|WARNING|CRITICAL)$ && "$status" =~ ^(OPEN|RESOLVED|WAIVED)$ ]] || die "invalid debt state for $debt"
		[[ "$category" =~ ^(OWNERSHIP|CANONICAL_REPRESENTATION|LAYERING|SERIALIZATION|CONCURRENCY|ERROR_MODEL|DEVICE_AUTHORITY|PUBLIC_API|DEPENDENCY_CYCLE|SECURITY|PERFORMANCE|DEPENDENCY|OTHER)$ ]] || die "invalid debt category for $debt"
		architecture_require_id_list "debt $debt affected_invariants" "$invariants" "$(architecture_invariants_file)"
		if [[ "$status" != RESOLVED ]]; then
			[[ "$remediation" != - && "$waiver" != - && "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "open/waived debt $debt requires remediation_node, expiration, and waiver_authority"
		fi
	done < "$(architecture_debt_file)"
}

architecture_validate_against_plan()
{
	local node producer consumer trigger affected decision producer_node gate edge dependencies authority invariants id depends validation severity gate_invariants gate_edges
	local -a ids=()
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	architecture_validate_registries
	while IFS=$'\t' read -r node _; do
		[[ "$node" != node_id ]] || continue
		[[ -n "$(project_plan_node_value "$node" deliverable)" ]] || die "architecture binding references unknown plan node: $node"
	done < "$(architecture_node_bindings_file)"
	while IFS=$'\t' read -r edge producer consumer _; do
		[[ "$edge" != edge_id ]] || continue
		[[ -n "$(project_plan_node_value "$producer" deliverable)" ]] || die "edge $edge has unknown producer: $producer"
		[[ -n "$(project_plan_node_value "$consumer" deliverable)" ]] || die "edge $edge has unknown consumer: $consumer"
		dependencies="$(project_plan_node_value "$consumer" depends_on)"
		architecture_list_contains "$dependencies" "$producer" || die "edge $edge consumer $consumer must directly depend on producer $producer"
		architecture_list_contains "$(architecture_node_value "$producer" edge_contracts)" "$edge" || die "edge $edge is absent from producer binding $producer"
		architecture_list_contains "$(architecture_node_value "$consumer" edge_contracts)" "$edge" || die "edge $edge is absent from consumer binding $consumer"
	done < "$(architecture_edges_file)"
	while IFS=$'\t' read -r decision _ producer_node _; do
		[[ "$decision" != decision_id ]] || continue
		[[ -n "$(project_plan_node_value "$producer_node" deliverable)" ]] || die "decision $decision has unknown producer: $producer_node"
		architecture_list_contains "$(architecture_node_value "$producer_node" produces_decisions)" "$decision" || die "decision $decision is absent from producer binding $producer_node"
	done < "$(architecture_decisions_file)"
	while IFS=$'\t' read -r gate trigger depends validation severity gate_invariants gate_edges; do
		[[ "$gate" != gate_id ]] || continue
		[[ -n "$(project_plan_node_value "$trigger" deliverable)" ]] || die "health gate $gate has unknown trigger: $trigger"
		architecture_list_contains "$(architecture_node_value "$trigger" health_gates)" "$gate" || die "health gate $gate is absent from trigger binding $trigger"
		architecture_parse_id_list "$depends" ids
		for node in "${ids[@]}"; do
			[[ -n "$(project_plan_node_value "$node" deliverable)" ]] || die "health gate $gate depends on unknown node: $node"
		done
	done < "$(architecture_health_gates_file)"
	while IFS=$'\t' read -r id _ authority _ _ _ _ _ _ affected; do
		[[ "$id" != invariant_id ]] || continue
		architecture_parse_id_list "$affected" ids
		for node in "${ids[@]}"; do
			[[ -n "$(project_plan_node_value "$node" deliverable)" ]] || die "invariant $id affects unknown node: $node"
			if [[ "$authority" != PROPOSED ]]; then
				architecture_list_contains "$(architecture_node_value "$node" invariant_ids)" "$id" || die "invariant $id is absent from affected node binding $node"
			fi
		done
	done < "$(architecture_invariants_file)"
	while IFS=$'\t' read -r debt _ _ _ _ _ remediation _ _ status _; do
		[[ "$debt" != debt_id ]] || continue
		if [[ "$status" != RESOLVED ]]; then
			[[ -n "$(project_plan_node_value "$remediation" deliverable)" ]] || die "debt $debt has unknown remediation node: $remediation"
		fi
	done < "$(architecture_debt_file)"
	# Every plan node has exactly one architecture binding.
	while IFS=$'\t' read -r node _; do
		[[ "$node" != node_id ]] || continue
		architecture_registry_has_id "$(architecture_node_bindings_file)" "$node" || die "plan node lacks architecture binding: $node"
	done < "$(project_decomposition_plan_file)"
}

architecture_node_value()
{
	local node="$1" field="$2"
	awk -F '\t' -v node="$node" -v wanted="$field" 'NR==1 {for(i=1;i<=NF;i++) c[$i]=i; next} $1==node {print $c[wanted]; exit}' "$(architecture_node_bindings_file)"
}

architecture_decision_accepted()
{
	local id="$1" static
	static="$(awk -F '\t' -v id="$id" 'NR>1 && $1==id {print $2; exit}' "$(architecture_decisions_file)")"
	[[ "$static" == ACCEPTED ]] || awk -F '\t' -v id="$id" 'NR>1 && $1==id && $2=="ACCEPTED" {ok=1} END {exit !ok}' "$(architecture_decision_ledger_file)"
}

architecture_require_node_ready()
{
	local node="$1" decisions id edge producer artifact
	local -a ids=()
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	decisions="$(architecture_node_value "$node" consumes_decisions)"
	architecture_parse_id_list "$decisions" ids
	for id in "${ids[@]}"; do architecture_decision_accepted "$id" || die "node $node consumes unresolved architecture decision: $id"; done
	while IFS=$'\t' read -r edge producer _ artifact _; do
		[[ "$edge" != edge_id ]] || continue
		architecture_list_contains "$(architecture_node_value "$node" edge_contracts)" "$edge" || continue
		[[ "$node" == "$producer" ]] && continue
		[[ "$(project_plan_item_status "$producer")" == COMPLETE ]] || die "edge $edge producer is not complete: $producer"
		[[ "$artifact" == - || -e "$REPOSITORY/$artifact" ]] || die "edge $edge contract artifact is absent: $artifact"
		if [[ "$artifact" != - ]]; then
			git -C "$REPOSITORY" ls-tree -r --name-only HEAD -- "$artifact" | grep -Fqx -- "$artifact" || die "edge $edge contract artifact is not committed at HEAD: $artifact"
		fi
	done < "$(architecture_edges_file)"
}

architecture_validate_assignment_metadata()
{
	local file="$1" node="$2" expected actual field
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	for field in Affected-Invariants Consumed-Decisions Produced-Decisions Edge-Contracts Health-Gates; do
		actual="$(require_single_metadata_value "$file" "$field" 'architecture-guarded assignment')"
		case "$field" in
			Affected-Invariants) expected="$(architecture_node_value "$node" invariant_ids)" ;;
			Consumed-Decisions) expected="$(architecture_node_value "$node" consumes_decisions)" ;;
			Produced-Decisions) expected="$(architecture_node_value "$node" produces_decisions)" ;;
			Edge-Contracts) expected="$(architecture_node_value "$node" edge_contracts)" ;;
			Health-Gates) expected="$(architecture_node_value "$node" health_gates)" ;;
		esac
		[[ "$actual" == "$expected" ]] || die "$field does not match architecture binding for node $node"
	done
	architecture_require_node_ready "$node"
}

architecture_validate_impact_result()
{
	local result="$1" assignment="$2" key value expected
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	for key in Changed-Public-Symbols Changed-Representations Changed-Ownership Changed-Serialization Changed-Dependencies Affected-Invariants Affected-Edges; do
		value="$(require_single_metadata_value "$result" "$key" 'architecture impact manifest')"
		[[ -n "$value" ]] || die "$key must use '-' when empty"
	done
	expected="$(metadata_value "$assignment" Affected-Invariants)"
	[[ "$(metadata_value "$result" Affected-Invariants)" == "$expected" ]] || die 'worker impact Affected-Invariants differs from assignment'
	expected="$(metadata_value "$assignment" Edge-Contracts)"
	[[ "$(metadata_value "$result" Affected-Edges)" == "$expected" ]] || die 'worker impact Affected-Edges differs from assignment'
}

architecture_record_impact()
{
	local task="$1" result="$2" target
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	target="$(architecture_impact_dir)/$PROJECT-task-$task.impact.md"
	install -m 600 "$result" "$target"
}

architecture_validate_manager_review()
{
	local review="$1" assignment="$2" expected debt_ids debt_id task
	local -a ids=()
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	[[ "$(require_single_metadata_value "$review" Impact-Assessment 'architecture review')" == PASS ]] || die 'architecture review requires Impact-Assessment: PASS'
	expected="$(metadata_value "$assignment" Affected-Invariants)"
	[[ "$(require_single_metadata_value "$review" Reviewed-Invariants 'architecture review')" == "$expected" ]] || die 'Reviewed-Invariants differs from assignment'
	expected="$(metadata_value "$assignment" Edge-Contracts)"
	[[ "$(require_single_metadata_value "$review" Reviewed-Edges 'architecture review')" == "$expected" ]] || die 'Reviewed-Edges differs from assignment'
	debt_ids="$(require_single_metadata_value "$review" Debt-Recorded 'architecture review')"
	[[ -n "$debt_ids" ]] || die 'Debt-Recorded must use NONE when empty'
	if [[ "$debt_ids" != NONE ]]; then
		task="$(metadata_value "$assignment" Task-ID)"
		architecture_parse_id_list "$debt_ids" ids
		for debt_id in "${ids[@]}"; do
			architecture_registry_has_id "$(architecture_debt_file)" "$debt_id" || die "Debt-Recorded references unknown debt: $debt_id"
			[[ "$(awk -F '\t' -v id="$debt_id" 'NR>1 && $1==id {print $2; exit}' "$(architecture_debt_file)")" == "$task" ]] ||
				die "debt $debt_id was not introduced by task $task"
		done
	fi
}

architecture_accept_decision()
{
	local decision="$1" task="$2" evidence="$3" expected expected_evidence expected_path actual_path sha
	architecture_registry_has_id "$(architecture_decisions_file)" "$decision" || die "unknown architecture decision: $decision"
	! architecture_decision_accepted "$decision" || die "architecture decision is already accepted: $decision"
	expected="$(awk -F '\t' -v id="$decision" 'NR>1 && $1==id {print $3; exit}' "$(architecture_decisions_file)")"
	[[ "$(project_plan_item_for_root "$(task_root_id "$task")")" == "$expected" ]] || die "decision $decision must be produced by node $expected"
	[[ -f "$(project_dir)/results/$(task_base "$task").result.md" && -f "$(project_dir)/archive/$(task_base "$task").assignment.md" ]] || die "decision $decision can be accepted only during review of task $task"
	expected_evidence="$(awk -F '\t' -v id="$decision" 'NR>1 && $1==id {print $8; exit}' "$(architecture_decisions_file)")"
	[[ "$expected_evidence" != - ]] || die "decision $decision has no registered evidence path"
	expected_path="$(realpath -m "$REPOSITORY/$expected_evidence")"
	actual_path="$(realpath "$evidence" 2>/dev/null || true)"
	[[ "$actual_path" == "$expected_path" && -f "$actual_path" ]] || die "decision evidence must be the registered repository file: $expected_evidence"
	git -C "$REPOSITORY" ls-tree -r --name-only HEAD -- "$expected_evidence" | grep -Fqx -- "$expected_evidence" || die "decision evidence is not committed at HEAD: $expected_evidence"
	awk -F '\t' -v task="$task" -v path="$expected_evidence" 'NR>1 && $2==task {n=split($5,a,","); for(i=1;i<=n;i++) if(a[i]==path) ok=1} END {exit !ok}' \
		"$(project_dir)/control/agent-commits.tsv" 2>/dev/null || die "decision evidence was not delivered by the controlled source commit for task $task: $expected_evidence"
	sha="$(sha256sum "$evidence" | awk '{print $1}')"
	printf '%s\tACCEPTED\t%s\t%s\t%s\n' "$decision" "$task" "$sha" "$(timestamp_utc)" >> "$(architecture_decision_ledger_file)"
	log_event "ARCHITECTURE_DECISION_ACCEPTED decision=$decision task=$task evidence_sha256=$sha"
}

architecture_run_command()
{
	local command="$1" log="$2"
	( cd "$REPOSITORY" && bash -o pipefail -c "$command" ) > "$log" 2>&1
}

architecture_run_acceptance_gates()
{
	local node="$1" task="$2" invariants edges gates id kind validation gate trigger depends severity gate_invariants gate_edges log sha decision dependency
	local -a ids=() dependency_ids=()
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	invariants="$(architecture_node_value "$node" invariant_ids)"
	architecture_parse_id_list "$invariants" ids
	for id in "${ids[@]}"; do
		read -r kind validation < <(awk -F '\t' -v id="$id" 'NR>1 && $1==id {print $8, $9; exit}' "$(architecture_invariants_file)")
		if [[ "$kind" == COMMAND ]]; then
			log="$(architecture_dir)/health-logs/$task-invariant-$id.log"
			architecture_run_command "$validation" "$log" || die "architecture invariant validation failed: $id (see $log)"
		fi
	done
	edges="$(architecture_node_value "$node" edge_contracts)"
	architecture_parse_id_list "$edges" ids
	for id in "${ids[@]}"; do
		validation="$(awk -F '\t' -v id="$id" 'NR>1 && $1==id {print $9; exit}' "$(architecture_edges_file)")"
		[[ "$validation" == REVIEW ]] && continue
		log="$(architecture_dir)/health-logs/$task-edge-$id.log"
		architecture_run_command "$validation" "$log" || die "edge compatibility validation failed: $id (see $log)"
	done
	gates="$(architecture_node_value "$node" health_gates)"
	architecture_parse_id_list "$gates" ids
	for id in "${ids[@]}"; do
		IFS=$'\t' read -r gate trigger depends validation severity gate_invariants gate_edges < <(awk -F '\t' -v id="$id" 'NR>1 && $1==id {print; exit}' "$(architecture_health_gates_file)")
		[[ "$trigger" == "$node" ]] || die "health gate $id is bound to $node but triggers on $trigger"
		architecture_parse_id_list "$depends" dependency_ids
		for dependency in "${dependency_ids[@]}"; do
			[[ "$(project_plan_item_status "$dependency")" == COMPLETE ]] || die "health gate $id dependency is not complete: $dependency"
		done
		log="$(architecture_dir)/health-logs/$task-health-$id.log"
		architecture_run_command "$validation" "$log" || die "cumulative architecture health gate failed: $id (see $log)"
		sha="$(sha256sum "$log" | awk '{print $1}')"
		printf '%s\tPASSED\t%s\t%s\t%s\n' "$id" "$task" "$sha" "$(timestamp_utc)" >> "$(architecture_health_ledger_file)"
	done
	architecture_parse_id_list "$(architecture_node_value "$node" produces_decisions)" ids
	for decision in "${ids[@]}"; do architecture_decision_accepted "$decision" || die "task cannot be accepted before produced decision is recorded: $decision"; done
}

architecture_open_critical_debt_count()
{
	awk -F '\t' 'NR>1 && $8=="CRITICAL" && $10!="RESOLVED" {count++} END {print count+0}' "$(architecture_debt_file)"
}

architecture_expired_debt_count()
{
	local today
	today="$(date -u +%Y-%m-%d)"
	awk -F '\t' -v today="$today" 'NR>1 && $10!="RESOLVED" && $9!="-" && $9 <= today {count++} END {print count+0}' "$(architecture_debt_file)"
}

architecture_missing_health_gate_count()
{
	local gate count=0
	while IFS=$'\t' read -r gate _; do
		[[ "$gate" != gate_id ]] || continue
		if ! awk -F '\t' -v id="$gate" 'NR>1 && $1==id && $2 ~ /PASSED$/ {ok=1} END {exit !ok}' "$(architecture_health_ledger_file)"; then
			count=$((count + 1))
		fi
	done < "$(architecture_health_gates_file)"
	printf '%s\n' "$count"
}

architecture_run_final_health_gates()
{
	local gate trigger depends validation severity invariants edges log sha
	while IFS=$'\t' read -r gate trigger depends validation severity invariants edges; do
		[[ "$gate" != gate_id ]] || continue
		log="$(architecture_dir)/health-logs/final-health-$gate.log"
		architecture_run_command "$validation" "$log" || die "final cumulative architecture health gate failed: $gate (see $log)"
		sha="$(sha256sum "$log" | awk '{print $1}')"
		printf '%s\tFINAL_PASSED\tcompletion\t%s\t%s\n' "$gate" "$sha" "$(timestamp_utc)" >> "$(architecture_health_ledger_file)"
	done < "$(architecture_health_gates_file)"
}

architecture_require_completion_ready()
{
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || return 0
	architecture_validate_against_plan
	(( $(architecture_open_critical_debt_count) == 0 )) || die 'project completion is blocked by unresolved critical architecture debt'
	(( $(architecture_expired_debt_count) == 0 )) || die 'project completion is blocked by expired architecture debt waivers'
	architecture_run_final_health_gates
	(( $(architecture_missing_health_gate_count) == 0 )) || die 'project completion lacks one or more passed architecture health gates'
}
