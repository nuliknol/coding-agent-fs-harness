#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/harness-common.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"; }

tmp_root="$(mktemp -d)"
trap 'rm -rf -- "$tmp_root"' EXIT
PROJECT=irregularity-test
HARNESS_IRREGULARITY_DETECTION_ENABLED=1
HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT=2
HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT=300
HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES=2
HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET=3
HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET=500
HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT=1000
HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS=100000
HARNESS_MAX_STATE_OSCILLATIONS=3
HARNESS_MAX_PATCH_CHURN_ROUNDS=2
HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS=500000
HARNESS_HOME="$ROOT"
project_dir() { printf '%s/project' "$tmp_root"; }
mkdir -p "$(project_dir)/control/progress" "$(project_dir)/logs" "$(project_dir)/tasks"
log_event() { printf '%s\n' "$*" >> "$(project_dir)/logs/events.log"; }

# Warning first, exact immutable task quarantine on the repeated occurrence.
mark_efficiency_warning RELATIVE_TOKEN_REGRESSION root-revision-1 'first regression' evidence
[[ ! -f "$(task_resource_anomaly_file root-revision-1)" ]] || fail 'first warning quarantined the task'
mark_task_resource_anomaly root-revision-1 RELATIVE_TOKEN_REGRESSION 'second regression' evidence >/dev/null
assert_file "$(task_resource_anomaly_file root-revision-1)"
[[ ! -f "$(task_resource_anomaly_file root-revision-2)" ]] || fail 'task anomaly leaked to a successor revision'

# Project-integrity anomalies are durable and globally visible.
mark_project_integrity_anomaly ACCOUNTING_INCONSISTENCY root-revision-1 'missing usage' evidence >/dev/null
project_has_integrity_anomaly || fail 'project integrity anomaly is not visible'
assert_contains "$(project_integrity_anomaly_file)" 'All agent launches are suppressed.'
rm -f "$(project_integrity_anomaly_file)"

# A successful classification without authoritative usage is an integrity fault.
classification="$tmp_root/missing.classification"
printf 'classification=success\nthread_id=\ninput_tokens=unknown\noutput_tokens=0\n' > "$classification"
record_root_agent_tokens root-revision-1 worker_luna "$classification"
assert_file "$(project_integrity_anomaly_file)"
assert_contains "$(project_integrity_anomaly_file)" 'successful agent episode has missing or malformed authoritative token usage'
rm -f "$(project_integrity_anomaly_file)"

classification="$tmp_root/mismatch.classification"
printf 'classification=success\nthread_id=thread-mismatch\ninput_tokens=100\noutput_tokens=0\ninvocation_processed_delta=99\ninvocation_delta_known=1\nestimated_processed_tokens=100\n' > "$classification"
record_root_agent_tokens root-revision-1 worker_luna "$classification"
assert_contains "$(project_integrity_anomaly_file)" 'root token-ledger delta disagrees with the invocation classifier delta'
rm -f "$(project_integrity_anomaly_file)"

# Convergence accounting establishes a lazy baseline and trips only on new paid
# episodes without a newly verified facet.
token_ledger="$(task_root_token_ledger_file root)"
printf 'recorded_at\ttask_id\trole\tthread_id\tinput_tokens\toutput_tokens\tprocessed_delta\n' > "$token_ledger"
record_root_verified_facet_boundary root
for n in 1 2 3; do
	printf 'now\troot-revision-%s\tworker_luna\tthread-%s\t0\t200\t200\n' "$n" "$n" >> "$token_ledger"
done
reassessment="$tmp_root/reassessment"
mark_root_architecture_reassessment() { printf '%s\n' "$2" > "$reassessment"; }
if evaluate_tokens_without_verified_gain root; then
	fail 'tokens-without-gain threshold did not stop the root'
fi
assert_contains "$reassessment" 'TOKENS_WITHOUT_VERIFIED_GAIN'
metrics="$(task_root_efficiency_metrics_file root)"
assert_contains "$metrics" 'tokens_since_verified_facet=600'
assert_contains "$metrics" 'episodes_since_verified_facet=3'
criteria_ledger="$(task_criterion_ledger_file root)"
printf 'item_id\tstate\tverified_by\tevidence_sha256\tupdated_at\nfacet-1\tPASSED\troot-revision-3\tsha\tnow\n' > "$criteria_ledger"
record_root_verified_facet_boundary root
facet_efficiency="$(project_verified_facet_efficiency_ledger_file)"
assert_contains "$facet_efficiency" $'root\t600\t1\t600'
assert_contains "$(project_efficiency_metrics_file)" 'tokens_per_verified_facet=600'

# State oscillation means a consecutive, materially unchanged recovery state.
# Revisiting one criterion with new strategy/blocker evidence is ordinary
# convergence and must not be counted across the root's full history.
replan_ledger="$(task_replan_ledger_file root)"
printf 'replanned_at\ttask_id\ttrigger_task\ttarget_criterion\tstrategy_id\tstrategy_change\tstrategy_fingerprint\tblocking_fingerprint\tverified_criteria\tverified_items\n' > "$replan_ledger"
printf 'now\troot-revision-1\troot\tcriterion-a\ts1\tNARROW_SCOPE\tstrategy-a\tblocker-a\t0\t1\n' >> "$replan_ledger"
printf 'now\troot-revision-2\troot-revision-1\tcriterion-a\ts2\tNEW_EVIDENCE\tstrategy-b\tblocker-b\t0\t1\n' >> "$replan_ledger"
rm -f "$reassessment"
evaluate_root_state_oscillation root-revision-3 criterion-a strategy-c blocker-c 1 ||
	fail 'materially changing recovery strategies were misclassified as state oscillation'
[[ ! -f "$reassessment" ]] || fail 'historical criterion reuse created a false state-oscillation pause'
printf 'now\troot-revision-3\troot-revision-2\tcriterion-a\ts3\tNEW_EVIDENCE\tstrategy-z\tblocker-z\t0\t1\n' >> "$replan_ledger"
printf 'now\troot-revision-4\troot-revision-3\tcriterion-a\ts4\tNEW_EVIDENCE\tstrategy-z\tblocker-z\t0\t1\n' >> "$replan_ledger"
if evaluate_root_state_oscillation root-revision-5 criterion-a strategy-z blocker-z 1; then
	fail 'three consecutive unchanged recovery states did not trip the oscillation fuse'
fi
assert_contains "$reassessment" 'STATE_OSCILLATION'

# Episode detector: declared/historical regression plus repeated context reads.
observations="$tmp_root/observations.tsv"
printf 'task_id\tmodel\tleaf_type\tclassification\tprocessed_tokens\tpredicted_p95_tokens\trepeated_source_reads\tsource_read_bytes\n' > "$observations"
printf 'old-1\tluna\tFOCUSED_BUG\tsuccess\t100\t200\t0\t10\nold-2\tluna\tFOCUSED_BUG\tsuccess\t120\t200\t0\t10\n' >> "$observations"
printf 'new\tluna\tFOCUSED_BUG\tsuccess\t1000\t200\t3\t9000\n' >> "$observations"
episode_output="$tmp_root/episode.out"
python3 "$ROOT/tools/irregularity_detector.py" episode --observations "$observations" --task new \
	--regression-percent 300 --min-samples 2 > "$episode_output"
assert_contains "$episode_output" 'RELATIVE_TOKEN_REGRESSION'
assert_contains "$episode_output" 'CONTEXT_AMPLIFICATION'
HARNESS_IRREGULARITY_DETECTION_ENABLED=0
if evaluate_worker_episode_irregularities new; then
	fail 'disabled detector reported a task anomaly'
fi
HARNESS_IRREGULARITY_DETECTION_ENABLED=1

# A renamed child which shrinks no measured boundary is rejected.
dag="$tmp_root/dag.tsv"; complexity="$tmp_root/complexity.tsv"
printf 'node_id\tparent_id\nparent\t-\nchild\tparent\n' > "$dag"
printf 'node_id\tcomplexity_score\tobligations\tallowed_paths\trequired_symbols\teffective_p95_tokens\n' > "$complexity"
printf 'parent\t10\t2\t2\t1\t100\nchild\t10\t2\t2\t1\t100\n' >> "$complexity"
if python3 "$ROOT/tools/irregularity_detector.py" decomposition --dag "$dag" --complexity "$complexity" > "$tmp_root/decomposition.out"; then
	fail 'non-shrinking decomposition was accepted'
fi
assert_contains "$tmp_root/decomposition.out" 'NON_SHRINKING_DECOMPOSITION'
sed -i 's/^child\t10\t2\t2\t1\t100$/child\t9\t2\t2\t1\t100/' "$complexity"
python3 "$ROOT/tools/irregularity_detector.py" decomposition --dag "$dag" --complexity "$complexity" >/dev/null ||
	fail 'strictly shrinking child was rejected'

# The three explicit investigation fuses remain exactly 500K.
grep -Fq 'HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION:-500000' "$ROOT/lib/harness-common.sh" || fail 'authoritative 500K fuse changed'
grep -Fq 'HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION:-500000' "$ROOT/lib/harness-common.sh" || fail 'live-estimated 500K fuse changed'
grep -Fq 'HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS:-500000' "$ROOT/lib/harness-common.sh" || fail 'cumulative worker-task 500K fuse changed'
grep -Fq 'HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION:-8' "$ROOT/lib/harness-common.sh" || fail 'manager replan exceeds its eight-action contract'
grep -Fq '((context_bytes + 3) / 4) + HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND' \
	"$ROOT/bin/codex-exec-jsonl" || fail 'live estimate omits fixed per-round context'
grep -Fq 'Luna-only policy requires every executable assignment to be a LOW/LUNA' "$ROOT/bin/manager-publish-task" || fail 'publisher lacks the Luna-only final route gate'
grep -Fq '[[ "$HARNESS_MODEL_POLICY" != luna_only && "$HARNESS_ESCALATION_POLICY" == legacy ]] || return 0' \
	"$ROOT/bin/manager-publish-task" || fail 'exhausted Luna recovery can still normalize to Terra under luna_only'
grep -Fq '[[ "$HARNESS_MODEL_POLICY" != luna_only && "$leaf_worker_route" == LUNA ]]' \
	"$ROOT/bin/manager-publish-task" || fail 'historical Luna failures still reject smaller Luna successors'
grep -Fq 'HARNESS_MODEL_POLICY=luna_only requires a LOW/LUNA child; decompose it further' \
	"$ROOT/bin/manager-publish-task" || fail 'Luna-only admission does not reject Terra executable children'
! grep -Fq 'evaluate_root_state_oscillation "$task_id" || true' \
	"$ROOT/bin/manager-publish-task" || fail 'state oscillation is still evaluated after publication as an ignored error'

printf 'Irregularity detection tests passed.\n'
