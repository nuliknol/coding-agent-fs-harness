#!/usr/bin/env bash

architecture_rebuild_root()
{
	# Keep this module independently sourceable by transition tests; it shares
	# the architecture namespace without requiring harness-architecture.sh.
	printf '%s/control/architecture/rebuild\n' "$(project_dir)"
}

architecture_rebuild_candidate_file()
{
	printf '%s/control/architecture/rebuild-candidate.env\n' "$(project_dir)"
}

architecture_rebuild_validate_id()
{
	[[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}$ ]] || die "invalid architecture rebuild ID: $1"
}

architecture_rebuild_dir()
{
	architecture_rebuild_validate_id "$1"
	printf '%s/%s\n' "$(architecture_rebuild_root)" "$1"
}

architecture_rebuild_state_file()
{
	printf '%s/state.env\n' "$(architecture_rebuild_dir "$1")"
}

architecture_rebuild_latest_file()
{
	printf '%s/latest.env\n' "$(architecture_rebuild_root)"
}

architecture_rebuild_phase_is_known()
{
	[[ "$1" =~ ^(OBSERVE|DIAGNOSE|DESIGN|BASELINE|REFACTOR|RECOMPUTE|COMPARE|AWAITING_APPROVAL|ACCEPTED|FAILED)$ ]]
}

architecture_rebuild_transition_is_legal()
{
	case "$1:$2" in
		OBSERVE:DIAGNOSE|DIAGNOSE:DESIGN|DESIGN:BASELINE|BASELINE:REFACTOR|\
		REFACTOR:RECOMPUTE|RECOMPUTE:COMPARE|COMPARE:AWAITING_APPROVAL|\
		AWAITING_APPROVAL:ACCEPTED) return 0 ;;
		OBSERVE:FAILED|DIAGNOSE:FAILED|DESIGN:FAILED|BASELINE:FAILED|REFACTOR:FAILED|\
		RECOMPUTE:FAILED|COMPARE:FAILED|AWAITING_APPROVAL:FAILED) return 0 ;;
		FAILED:OBSERVE|FAILED:DIAGNOSE|FAILED:DESIGN|FAILED:BASELINE|FAILED:REFACTOR|\
		FAILED:RECOMPUTE|FAILED:COMPARE|FAILED:AWAITING_APPROVAL) return 0 ;;
		*) return 1 ;;
	esac
}

architecture_rebuild_state_value()
{
	harness_artifact_get "$(architecture_rebuild_state_file "$1")" "$2"
}

architecture_rebuild_write_state()
{
	local rebuild_id="$1" status="$2" last_completed="$3" failed_phase="$4" expected="${5:-}"
	local state scope trigger source_revision benchmark_sha created before_generation after_generation
	state="$(architecture_rebuild_state_file "$rebuild_id")"
	scope="$(harness_artifact_get "$state" scope 2>/dev/null || true)"
	trigger="$(harness_artifact_get "$state" trigger 2>/dev/null || true)"
	source_revision="$(harness_artifact_get "$state" source_revision 2>/dev/null || true)"
	benchmark_sha="$(harness_artifact_get "$state" benchmarks_sha256 2>/dev/null || printf '-')"
	created="$(harness_artifact_get "$state" created_at 2>/dev/null || timestamp_utc)"
	before_generation="$(harness_artifact_get "$state" before_generation 2>/dev/null || printf '-')"
	after_generation="$(harness_artifact_get "$state" after_generation 2>/dev/null || printf '-')"
	local -a record=(schema_version 1 rebuild_id "$rebuild_id" project "$PROJECT" status "$status"
		last_completed_phase "$last_completed" failed_phase "$failed_phase" scope "$scope"
		trigger "$trigger" source_revision "$source_revision" benchmarks_sha256 "$benchmark_sha"
		before_generation "$before_generation" after_generation "$after_generation"
		created_at "$created" updated_at "$(timestamp_utc)")
	if [[ -n "$expected" ]]; then
		harness_artifact_compare_and_swap_kv "$state" status "$expected" 600 "${record[@]}"
	else
		harness_artifact_write_kv "$state" 600 "${record[@]}"
	fi
}

architecture_rebuild_begin()
{
	local scope="$1" trigger="$2" benchmarks="${3:--}" rebuild_id run_dir state source_revision benchmark_sha=-
	[[ -n "$scope" && "$scope" != *$'\n'* && "$trigger" != *$'\n'* ]] || die 'rebuild scope and trigger must be nonempty single lines'
	if [[ "$benchmarks" != - ]]; then
		[[ -f "$benchmarks" ]] || die "architecture benchmark file does not exist: $benchmarks"
		benchmark_sha="sha256:$(sha256sum "$benchmarks" | awk '{print $1}')"
	fi
	source_revision="$(git -C "$REPOSITORY" rev-parse HEAD)"
	rebuild_id="$(timestamp_compact_utc)-$(printf '%s\0%s\0%s\0%s' "$PROJECT" "$scope" "$trigger" "$RANDOM" | sha256sum | cut -c1-12)"
	run_dir="$(architecture_rebuild_dir "$rebuild_id")"
	mkdir -p "$run_dir/artifacts"
	chmod 700 "$run_dir" "$run_dir/artifacts"
	state="$run_dir/state.env"
	harness_artifact_write_kv "$state" 600 \
		schema_version 1 rebuild_id "$rebuild_id" project "$PROJECT" status OBSERVE \
		last_completed_phase NONE failed_phase - scope "$scope" trigger "$trigger" \
		source_revision "$source_revision" benchmarks_sha256 "$benchmark_sha" \
		before_generation - after_generation - created_at "$(timestamp_utc)" updated_at "$(timestamp_utc)"
	if [[ "$benchmarks" != - ]]; then
		harness_artifact_install_file "$benchmarks" "$run_dir/artifacts/benchmarks.tsv"
	fi
	harness_artifact_write_kv "$(architecture_rebuild_latest_file)" 600 rebuild_id "$rebuild_id" updated_at "$(timestamp_utc)"
	harness_artifact_append_tsv "$run_dir/transitions.tsv" \
		$'recorded_at\tfrom_phase\tto_phase\tevidence_sha256\tnote' \
		"$(timestamp_utc)" NONE OBSERVE - "$trigger"
	printf '%s\n' "$rebuild_id"
}

architecture_rebuild_advance()
{
	local rebuild_id="$1" expected="$2" next="$3" evidence="$4" note="${5:--}"
	local state current run_dir evidence_target evidence_sha last_completed failed_phase=-
	architecture_rebuild_phase_is_known "$expected" || die "unknown rebuild phase: $expected"
	architecture_rebuild_phase_is_known "$next" || die "unknown rebuild phase: $next"
	architecture_rebuild_transition_is_legal "$expected" "$next" || die "illegal architecture rebuild transition: $expected -> $next"
	state="$(architecture_rebuild_state_file "$rebuild_id")"
	harness_artifact_require_schema "$state" 'schema_version,rebuild_id,project,status,last_completed_phase,scope,trigger,source_revision,created_at,updated_at'
	current="$(harness_artifact_get "$state" status)"
	[[ "$current" == "$expected" ]] || die "architecture rebuild $rebuild_id is $current, expected $expected"
	run_dir="$(architecture_rebuild_dir "$rebuild_id")"
	evidence_sha=-
	if [[ "$evidence" != - ]]; then
		[[ -f "$evidence" ]] || die "architecture rebuild evidence does not exist: $evidence"
		evidence_target="$run_dir/artifacts/${next,,}.evidence"
		harness_artifact_install_file "$evidence" "$evidence_target"
		evidence_sha="sha256:$(sha256sum "$evidence_target" | awk '{print $1}')"
	fi
	last_completed="$expected"
	if [[ "$next" == FAILED ]]; then
		failed_phase="$expected"
	elif [[ "$expected" == FAILED ]]; then
		last_completed="$(harness_artifact_get "$state" last_completed_phase)"
	fi
	# Required acceptance artifacts must exist before the authoritative state is
	# committed. A report failure therefore leaves the run resumable at
	# AWAITING_APPROVAL instead of creating a partially accepted transaction.
	if [[ "$next" == ACCEPTED ]]; then
		architecture_rebuild_generate_report "$rebuild_id" ACCEPTED
	fi
	architecture_rebuild_write_state "$rebuild_id" "$next" "$last_completed" "$failed_phase" "$expected"
	harness_artifact_append_tsv "$run_dir/transitions.tsv" \
		$'recorded_at\tfrom_phase\tto_phase\tevidence_sha256\tnote' \
		"$(timestamp_utc)" "$expected" "$next" "$evidence_sha" "$note"
}

architecture_rebuild_generate_report()
{
	local rebuild_id="$1" status_override="${2:-}" run_dir
	run_dir="$(architecture_rebuild_dir "$rebuild_id")"
	local -a status_args=()
	[[ -z "$status_override" ]] || status_args=(--status "$status_override")
	python3 "$HARNESS_HOME/tools/generate_architecture_rebuild_report.py" \
		--run-dir "$run_dir" --repository "$REPOSITORY" "${status_args[@]}" >/dev/null
	[[ -s "$run_dir/architecture-rebuild-report.md" && -f "$run_dir/remaining-debt.tsv" ]] ||
		die "architecture rebuild report generation failed: $rebuild_id"
}

architecture_rebuild_resume()
{
	local rebuild_id="$1" state failed_phase
	state="$(architecture_rebuild_state_file "$rebuild_id")"
	[[ "$(harness_artifact_get "$state" status)" == FAILED ]] || die "architecture rebuild is not failed: $rebuild_id"
	failed_phase="$(harness_artifact_get "$state" failed_phase)"
	[[ "$failed_phase" != - ]] || die "architecture rebuild has no resumable failed phase: $rebuild_id"
	architecture_rebuild_advance "$rebuild_id" FAILED "$failed_phase" - resume
}

architecture_rebuild_record_candidate()
{
	local generation="$1" scorecard="$2" proposal="$3" status
	[[ -f "$scorecard" && -f "$proposal" ]] || return 0
	status="$(awk -F '\t' '$1=="status" {print $2; exit}' "$scorecard")"
	[[ "$status" == REBUILD_CANDIDATE ]] || return 0
	harness_artifact_write_kv "$(architecture_rebuild_candidate_file)" 600 \
		schema_version 1 project "$PROJECT" status REBUILD_CANDIDATE generation "$generation" \
		scorecard "$scorecard" proposal "$proposal" recorded_at "$(timestamp_utc)"
	log_event "ARCHITECTURE_REBUILD_CANDIDATE generation=$generation scorecard=$scorecard proposal=$proposal"
}

architecture_rebuild_require_clean_source()
{
	git -C "$REPOSITORY" diff --quiet --ignore-submodules -- ||
		die 'architecture rebuild evidence requires a clean tracked worktree'
	git -C "$REPOSITORY" diff --cached --quiet --ignore-submodules -- ||
		die 'architecture rebuild evidence requires an empty Git index'
}

architecture_rebuild_prepare()
{
	local rebuild_id="$1" run_dir state index_output generation maps benchmarks scorecard proposal
	local -a benchmark_args=()
	run_dir="$(architecture_rebuild_dir "$rebuild_id")"
	state="$(architecture_rebuild_state_file "$rebuild_id")"
	[[ "$(harness_artifact_get "$state" status)" == OBSERVE ]] || die "architecture rebuild is not at OBSERVE: $rebuild_id"
	architecture_rebuild_require_clean_source
	maps="$run_dir/before/maps"
	index_output="$("$HARNESS_BIN/harness-architecture-source-index" "$HARNESS_ENV_FILE" "$maps")"
	generation="$(sed -n 's/^SOURCE_ARCHITECTURE_READY generation=\([^ ]*\) path=.*/\1/p' <<< "$index_output")"
	[[ -n "$generation" ]] || die 'source architecture index did not report a generation'
	harness_artifact_update_kv "$state" before_generation "$generation"
	benchmarks="$run_dir/artifacts/benchmarks.tsv"
	if [[ -s "$benchmarks" ]]; then
		python3 "$HARNESS_HOME/tools/architecture_benchmarks.py" --maps-dir "$maps" \
			--generation "$generation" --repository "$REPOSITORY" --queries "$benchmarks" \
			--output "$run_dir/before/benchmarks.tsv"
	fi
	scorecard="$run_dir/before/scorecard.tsv"
	proposal="$run_dir/before/rebuild-proposal.md"
	[[ ! -s "$run_dir/before/benchmarks.tsv" ]] || benchmark_args=(--benchmarks "$run_dir/before/benchmarks.tsv")
	python3 "$HARNESS_HOME/tools/architecture_scorecard.py" --maps-dir "$maps" \
		--generation "$generation" --output "$scorecard" --proposal "$proposal" "${benchmark_args[@]}"
	architecture_rebuild_advance "$rebuild_id" OBSERVE DIAGNOSE "$maps/summary.json" source-evidence-captured
	architecture_rebuild_advance "$rebuild_id" DIAGNOSE DESIGN "$proposal" advisory-findings-classified
}

architecture_rebuild_recompute()
{
	local rebuild_id="$1" run_dir state index_output generation maps benchmarks scorecard proposal comparison status
	local -a benchmark_args=()
	run_dir="$(architecture_rebuild_dir "$rebuild_id")"
	state="$(architecture_rebuild_state_file "$rebuild_id")"
	[[ "$(harness_artifact_get "$state" status)" == RECOMPUTE ]] || die "architecture rebuild is not at RECOMPUTE: $rebuild_id"
	architecture_rebuild_require_clean_source
	maps="$run_dir/after/maps"
	index_output="$("$HARNESS_BIN/harness-architecture-source-index" "$HARNESS_ENV_FILE" "$maps")"
	generation="$(sed -n 's/^SOURCE_ARCHITECTURE_READY generation=\([^ ]*\) path=.*/\1/p' <<< "$index_output")"
	[[ -n "$generation" ]] || die 'source architecture index did not report a generation'
	harness_artifact_update_kv "$state" after_generation "$generation"
	benchmarks="$run_dir/artifacts/benchmarks.tsv"
	if [[ -s "$benchmarks" ]]; then
		python3 "$HARNESS_HOME/tools/architecture_benchmarks.py" --maps-dir "$maps" \
			--generation "$generation" --repository "$REPOSITORY" --queries "$benchmarks" \
			--output "$run_dir/after/benchmarks.tsv"
	fi
	scorecard="$run_dir/after/scorecard.tsv"
	proposal="$run_dir/after/rebuild-proposal.md"
	[[ ! -s "$run_dir/after/benchmarks.tsv" ]] || benchmark_args=(--benchmarks "$run_dir/after/benchmarks.tsv")
	python3 "$HARNESS_HOME/tools/architecture_scorecard.py" --maps-dir "$maps" \
		--generation "$generation" --output "$scorecard" --proposal "$proposal" "${benchmark_args[@]}"
	architecture_rebuild_advance "$rebuild_id" RECOMPUTE COMPARE "$scorecard" after-evidence-captured
	comparison="$run_dir/comparison.tsv"
	set +e
	"$HARNESS_BIN/harness-compare-architecture-scorecards" "$run_dir/before/scorecard.tsv" "$scorecard" > "$comparison"
	status=$?
	set -e
	if (( status == 0 )); then
		architecture_rebuild_advance "$rebuild_id" COMPARE AWAITING_APPROVAL "$comparison" comparison-passed
	else
		architecture_rebuild_advance "$rebuild_id" COMPARE FAILED "$comparison" "comparison-exit-$status"
		return "$status"
	fi
}
