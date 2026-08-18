#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-architecture-rebuild.XXXXXX)"
cleanup() { result=$?; trap - EXIT; rm -rf -- "$TEST_ROOT"; exit "$result"; }
trap cleanup EXIT

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
timestamp_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
timestamp_compact_utc() { date -u '+%Y%m%dT%H%M%SZ'; }
project_dir() { printf '%s/project\n' "$TEST_ROOT"; }
log_event() { printf '%s\n' "$*" >> "$TEST_ROOT/events.log"; }

PROJECT=architecture-test
REPOSITORY="$TEST_ROOT/repository"
mkdir -p "$REPOSITORY" "$(project_dir)/control"
git -C "$REPOSITORY" init -q
printf 'baseline\n' > "$REPOSITORY/source.txt"
git -C "$REPOSITORY" add source.txt
git -C "$REPOSITORY" -c user.name=test -c user.email=test@example.invalid commit -qm baseline

# shellcheck source=../lib/harness-artifact-store.sh
source "$HARNESS_HOME/lib/harness-artifact-store.sh"
# shellcheck source=../lib/harness-rebuild.sh
source "$HARNESS_HOME/lib/harness-rebuild.sh"

artifact="$TEST_ROOT/project/control/artifact.env"
harness_artifact_write_kv "$artifact" 600 schema_version 1 status READY detail exact-path
harness_artifact_require_schema "$artifact" schema_version,status,detail
[[ "$(harness_artifact_get "$artifact" status)" == READY ]]
[[ "$(stat -c '%a' "$artifact")" == 600 ]]

if (harness_artifact_write_kv "$TEST_ROOT/bad.env" 600 Invalid value) >/dev/null 2>&1; then
	printf 'artifact store accepted an invalid key\n' >&2
	exit 1
fi
if (harness_artifact_write_kv "$TEST_ROOT/bad.env" 600 valid $'two\nlines') >/dev/null 2>&1; then
	printf 'artifact store accepted a multiline value\n' >&2
	exit 1
fi

benchmarks="$TEST_ROOT/benchmarks.tsv"
printf 'benchmark_id\tquery\texpected_paths\nb1\tstate\tlib/state.sh\n' > "$benchmarks"
rebuild_id="$(architecture_rebuild_begin core-cycles measured-scorecard "$benchmarks")"
state="$(architecture_rebuild_state_file "$rebuild_id")"
[[ "$(harness_artifact_get "$state" status)" == OBSERVE ]]
[[ "$(harness_artifact_get "$state" benchmarks_sha256)" =~ ^sha256:[0-9a-f]{64}$ ]]

evidence="$TEST_ROOT/evidence.md"
printf '# Evidence\n\nCharacterized.\n' > "$evidence"
architecture_rebuild_advance "$rebuild_id" OBSERVE DIAGNOSE "$evidence" observed
architecture_rebuild_advance "$rebuild_id" DIAGNOSE DESIGN "$evidence" diagnosed
architecture_rebuild_advance "$rebuild_id" DESIGN BASELINE "$evidence" designed
architecture_rebuild_advance "$rebuild_id" BASELINE FAILED "$evidence" baseline-failed
[[ "$(harness_artifact_get "$state" status)" == FAILED ]]
[[ "$(harness_artifact_get "$state" failed_phase)" == BASELINE ]]
architecture_rebuild_resume "$rebuild_id"
[[ "$(harness_artifact_get "$state" status)" == BASELINE ]]

if (architecture_rebuild_advance "$rebuild_id" BASELINE COMPARE "$evidence" illegal) >/dev/null 2>&1; then
	printf 'rebuild state machine accepted an illegal phase jump\n' >&2
	exit 1
fi
[[ "$(harness_artifact_get "$state" status)" == BASELINE ]]

architecture_rebuild_advance "$rebuild_id" BASELINE REFACTOR "$evidence" baseline-passed
architecture_rebuild_advance "$rebuild_id" REFACTOR RECOMPUTE "$evidence" refactor-complete
architecture_rebuild_advance "$rebuild_id" RECOMPUTE COMPARE "$evidence" recomputed
architecture_rebuild_advance "$rebuild_id" COMPARE AWAITING_APPROVAL "$evidence" comparison-passed
architecture_rebuild_advance "$rebuild_id" AWAITING_APPROVAL ACCEPTED "$evidence" operator-approved
[[ "$(harness_artifact_get "$state" status)" == ACCEPTED ]]
[[ "$(awk 'END {print NR}' "$(architecture_rebuild_dir "$rebuild_id")/transitions.tsv")" == 12 ]]
[[ -s "$(architecture_rebuild_dir "$rebuild_id")/architecture-rebuild-report.md" ]]
[[ -f "$(architecture_rebuild_dir "$rebuild_id")/remaining-debt.tsv" ]]

scorecard="$TEST_ROOT/scorecard.tsv"
proposal="$TEST_ROOT/proposal.md"
printf 'metric\tvalue\nstatus\tREBUILD_CANDIDATE\n' > "$scorecard"
printf '# Proposal\n' > "$proposal"
architecture_rebuild_record_candidate generation-1 "$scorecard" "$proposal"
candidate="$(architecture_rebuild_candidate_file)"
[[ "$(harness_artifact_get "$candidate" status)" == REBUILD_CANDIDATE ]]
grep -Fq ARCHITECTURE_REBUILD_CANDIDATE "$TEST_ROOT/events.log"

printf 'architecture rebuild state tests passed\n'
