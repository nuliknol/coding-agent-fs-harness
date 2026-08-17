#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_BIN="$HARNESS_HOME/bin"
TEST_ROOT="$(mktemp -d /tmp/harness-repository-index.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\n" "$TEST_ROOT" >&2' EXIT
else
	cleanup_test_root() { result=$?; trap - EXIT; rm -rf -- "$TEST_ROOT"; exit "$result"; }
	trap cleanup_test_root EXIT
fi

cp -a "$SCRIPT_DIR/fixtures/context-index-c" "$TEST_ROOT/repo"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" add .
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
cat > "$TEST_ROOT/bin/scip-clang" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == --version ]]; then
	printf 'fixture-scip-clang 1.0\n'
	exit 0
fi
compdb=
output=
while (( $# > 0 )); do
	case "$1" in
		--compdb-path) compdb="$2"; shift 2 ;;
		--index-output-path) output="$2"; shift 2 ;;
		--jobs) shift 2 ;;
		--no-progress-report) shift ;;
		*) printf 'unexpected scip-clang argument: %s\n' "$1" >&2; exit 2 ;;
	esac
done
[[ -s "$compdb" && -n "$output" ]]
printf 'fixture-index %s\n' "$(sha256sum "$compdb" | awk '{print $1}')" > "$output"
SH
cat > "$TEST_ROOT/bin/scip" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == --version ]]; then
	printf 'fixture-scip 1.0\n'
	exit 0
fi
case "${1:-}" in
	lint) [[ -s "$2" ]]; printf 'fixture lint ok\n' ;;
	stats)
		[[ "$2" == --from && -s "$3" ]]
		printf 'Documents: 3\nOccurrences: 4\n'
		;;
	*) printf 'unexpected scip command: %s\n' "$*" >&2; exit 2 ;;
esac
SH
cat > "$TEST_ROOT/bin/scip-clang-fail" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf 'fixture-scip-clang-fail 1.0\n'; exit 0; fi
printf 'intentional indexing failure\n' >&2
exit 9
SH
cat > "$TEST_ROOT/bin/hanging-version-tool" <<'SH'
#!/usr/bin/env bash
printf 'Warning: Unknown option --version\n'
printf 'dynamic timestamp %s\n' "$(date +%s%N)"
printf 'startup diagnostic three\n'
printf 'startup diagnostic four\n'
# Joern can exit successfully after emitting this unsupported-option banner.
exit 0
SH
chmod +x "$TEST_ROOT/bin/scip-clang" "$TEST_ROOT/bin/scip" "$TEST_ROOT/bin/scip-clang-fail" \
	"$TEST_ROOT/bin/hanging-version-tool"

# A provider whose --version action enters a REPL must not stall immutable
# identity construction.  Keep this assertion outside a harness invocation so
# it directly exercises the shared fingerprint helper.
probe_started="$(date +%s)"
# shellcheck source=../lib/harness-repository-index.sh
source "$HARNESS_HOME/lib/harness-repository-index.sh"
probe_fingerprint="$(repository_index_tool_fingerprint "$TEST_ROOT/bin/hanging-version-tool")"
probe_fingerprint_repeat="$(repository_index_tool_fingerprint "$TEST_ROOT/bin/hanging-version-tool")"
joern_fingerprint="$(repository_index_joern_fingerprint 1 "$TEST_ROOT/bin/hanging-version-tool")"
joern_fingerprint_repeat="$(repository_index_joern_fingerprint 1 "$TEST_ROOT/bin/hanging-version-tool")"
probe_elapsed="$(( $(date +%s) - probe_started ))"
[[ "$probe_fingerprint" =~ ^[0-9a-f]{64}$ ]]
[[ "$probe_fingerprint_repeat" == "$probe_fingerprint" ]]
[[ "$joern_fingerprint" == "$probe_fingerprint" ]]
[[ "$joern_fingerprint_repeat" == "$joern_fingerprint" ]]
(( probe_elapsed < 15 ))
cpu_affinity="$(repository_index_cpu_affinity_list 2)"
[[ "$cpu_affinity" =~ ^[0-9]+,[0-9]+$ ]]
[[ "$(taskset --cpu-list "$cpu_affinity" sh -c "awk '\$1 == \"Cpus_allowed_list:\" {print \$2}' /proc/self/status")" == "$cpu_affinity" ]]

write_env()
{
	local project="$1" compdb="$2" scip_clang="$3" env_file="$4"
	cat > "$env_file" <<ENV
export PROJECT="$project"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="$TEST_ROOT/repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_BIN"
export HARNESS_ROOT="$TEST_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export MANAGER_MODEL="gpt-5.6-terra"
export WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export DECOMPOSITION_MODEL="gpt-5.6-sol"
export HARNESS_WORKER_GOAL_MODE="1"
export HARNESS_DECOMPOSITION_V2="0"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_REPOSITORY_INDEX_MODE="advisory"
export HARNESS_CONTEXT_CLOSURE_MODE="off"
export HARNESS_REPOSITORY_INDEX_ROOT="$TEST_ROOT/state/repository-indexes"
export HARNESS_COMPILE_COMMANDS="$compdb"
export HARNESS_SCIP_CLANG_BIN="$scip_clang"
export HARNESS_SCIP_BIN="$TEST_ROOT/bin/scip"
export HARNESS_SCIP_IMPORTER_BIN="/bin/true"
export HARNESS_SCIP_CLANG_JOBS="1"
export MAX_ORACLE_RUNS="0"
ENV
	chmod 600 "$env_file"
}

cmake -S "$TEST_ROOT/repo" -B "$TEST_ROOT/build-a" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null
env_a="$TEST_ROOT/index-a.env"
write_env indexa "$TEST_ROOT/build-a/compile_commands.json" "$TEST_ROOT/bin/scip-clang" "$env_a"
"$HARNESS_BIN/harness-init" "$env_a" >/dev/null

missing_status="$($HARNESS_BIN/harness-index-status "$env_a")"
grep -Fqx $'status\tMISSING' <<< "$missing_status"

first_output="$($HARNESS_BIN/harness-index-repository "$env_a")"
grep -Fq 'INDEX_READY generation=' <<< "$first_output"
pointer_a="$TEST_ROOT/state/projects/indexa/control/repository-index.env"
generation_a="$(awk -F= '$1=="generation" {print $2}' "$pointer_a")"
generation_dir_a="$(awk -F= '$1=="generation_dir" {print $2}' "$pointer_a")"
test -s "$generation_dir_a/index.scip"
test -s "$generation_dir_a/architecture.sqlite"
test -s "$generation_dir_a/integrity.env"
test "$(sqlite3 "$generation_dir_a/architecture.sqlite" 'PRAGMA user_version;')" = 5
test "$(sqlite3 "$generation_dir_a/architecture.sqlite" 'SELECT count(*) FROM index_generations;')" = 1
test "$(sqlite3 "$generation_dir_a/architecture.sqlite" "SELECT count(*) FROM sqlite_master WHERE name='lexical_documents';")" = 1

ready_status="$($HARNESS_BIN/harness-index-status "$env_a" --details)"
grep -Fqx $'status\tREADY' <<< "$ready_status"
grep -Fqx $'schema_version\t5' <<< "$ready_status"

# Existing installations acquire the publication marker lazily. Their READY
# manifest inherits the integrity_check that gated atomic publication, so
# enrollment opens only the schema header; later calls use immutable artifact
# metadata and do not reopen the database.
mkdir -p "$TEST_ROOT/sqlite-probe"
cat > "$TEST_ROOT/sqlite-probe/sqlite3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${*: -1}" >> "${SQLITE_PROBE_LOG:?}"
exec /usr/bin/sqlite3 "$@"
SH
chmod +x "$TEST_ROOT/sqlite-probe/sqlite3"
rm -f "$generation_dir_a/integrity.env" "$generation_dir_a/.integrity.lock"
sqlite_probe_log="$TEST_ROOT/sqlite-probe.log"
PATH="$TEST_ROOT/sqlite-probe:$PATH" SQLITE_PROBE_LOG="$sqlite_probe_log" \
	"$HARNESS_BIN/harness-index-status" "$env_a" >/dev/null
test "$(wc -l < "$sqlite_probe_log")" = 1
grep -Fqx 'PRAGMA user_version;' "$sqlite_probe_log"
! grep -Fqx 'PRAGMA quick_check;' "$sqlite_probe_log"
PATH="$TEST_ROOT/sqlite-probe:$PATH" SQLITE_PROBE_LOG="$sqlite_probe_log" \
	"$HARNESS_BIN/harness-index-status" "$env_a" >/dev/null
test "$(wc -l < "$sqlite_probe_log")" = 1
test -s "$generation_dir_a/integrity.env"

# If an enrolled marker no longer matches the artifacts, the cheap path is not
# trusted: verification must re-open the schema and run quick_check before
# recording the changed metadata.
sed -i 's/^artifact_fingerprint=.*/artifact_fingerprint=changed/' \
	"$generation_dir_a/integrity.env"
PATH="$TEST_ROOT/sqlite-probe:$PATH" SQLITE_PROBE_LOG="$sqlite_probe_log" \
	"$HARNESS_BIN/harness-index-status" "$env_a" >/dev/null
test "$(wc -l < "$sqlite_probe_log")" = 3
test "$(grep -Fxc 'PRAGMA quick_check;' "$sqlite_probe_log")" = 1

# Every Joern input that affects the immutable graph/import must participate in
# live freshness, not only generation construction. This also upgrades older
# manifests that did not persist the selected analysis-class set.
cp "$env_a" "$TEST_ROOT/index-joern-config-changed.env"
printf 'export HARNESS_JOERN_TIMEOUT_SECONDS="901"\n' >> \
	"$TEST_ROOT/index-joern-config-changed.env"
chmod 600 "$TEST_ROOT/index-joern-config-changed.env"
joern_config_stale_status="$($HARNESS_BIN/harness-index-status \
	"$TEST_ROOT/index-joern-config-changed.env")"
grep -Fqx $'status\tSTALE' <<< "$joern_config_stale_status"
grep -Fqx $'reason\tjoern-configuration-changed' <<< "$joern_config_stale_status"

# Importer semantics participate in both immutable identity and live freshness.
sed 's#HARNESS_SCIP_IMPORTER_BIN="/bin/true"#HARNESS_SCIP_IMPORTER_BIN="/bin/false"#' \
	"$env_a" > "$TEST_ROOT/index-importer-changed.env"
chmod 600 "$TEST_ROOT/index-importer-changed.env"
importer_stale_status="$($HARNESS_BIN/harness-index-status "$TEST_ROOT/index-importer-changed.env")"
grep -Fqx $'status\tSTALE' <<< "$importer_stale_status"
grep -Fqx $'reason\tscip-importer-changed' <<< "$importer_stale_status"

second_output="$($HARNESS_BIN/harness-index-repository "$env_a")"
grep -Fq "INDEX_REUSED generation=$generation_a" <<< "$second_output"

"$HARNESS_BIN/harness-index-invalidate" "$env_a" --reason 'fixture invalidation' >/dev/null
invalidated_status="$($HARNESS_BIN/harness-index-status "$env_a")"
grep -Fqx $'status\tINVALIDATED' <<< "$invalidated_status"
grep -Fqx $'reason\tfixture invalidation' <<< "$invalidated_status"
revalidated_output="$($HARNESS_BIN/harness-index-repository "$env_a")"
grep -Fq "INDEX_REUSED generation=$generation_a" <<< "$revalidated_output"
grep -Fqx $'status\tREADY' < <("$HARNESS_BIN/harness-index-status" "$env_a")

# A second harness project using the same repository and configuration reuses
# the immutable generation.
env_shared="$TEST_ROOT/index-shared.env"
write_env indexshared "$TEST_ROOT/build-a/compile_commands.json" "$TEST_ROOT/bin/scip-clang" "$env_shared"
"$HARNESS_BIN/harness-init" "$env_shared" >/dev/null
shared_output="$($HARNESS_BIN/harness-index-repository "$env_shared")"
grep -Fq "INDEX_REUSED generation=$generation_a" <<< "$shared_output"
shared_pointer="$TEST_ROOT/state/projects/indexshared/control/repository-index.env"
grep -Fqx "generation=$generation_a" "$shared_pointer"

# A distinct compiler configuration creates a distinct generation even at the
# same source revision.
cmake -S "$TEST_ROOT/repo" -B "$TEST_ROOT/build-b" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	-DCMAKE_C_FLAGS=-DINDEX_VARIANT=1 >/dev/null
write_env indexa "$TEST_ROOT/build-b/compile_commands.json" "$TEST_ROOT/bin/scip-clang" "$env_a"
variant_output="$($HARNESS_BIN/harness-index-repository "$env_a")"
grep -Fq 'INDEX_READY generation=' <<< "$variant_output"
generation_b="$(awk -F= '$1=="generation" {print $2}' "$pointer_a")"
[[ "$generation_b" != "$generation_a" ]]

# A failed new generation cannot replace the last valid project pointer.
cp "$pointer_a" "$TEST_ROOT/pointer-before-failure"
cmake -S "$TEST_ROOT/repo" -B "$TEST_ROOT/build-c" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	-DCMAKE_C_FLAGS=-DINDEX_VARIANT=2 >/dev/null
write_env indexa "$TEST_ROOT/build-c/compile_commands.json" "$TEST_ROOT/bin/scip-clang-fail" "$env_a"
if "$HARNESS_BIN/harness-index-repository" "$env_a" > "$TEST_ROOT/failure.out" 2>&1; then
	printf 'failing scip-clang unexpectedly published an index\n' >&2
	exit 1
fi
cmp -s "$pointer_a" "$TEST_ROOT/pointer-before-failure"

# Historical context cost is summarized without replaying transcript contents.
project_dir="$TEST_ROOT/state/projects/indexa"
mkdir -p "$project_dir/control/context-capsules" "$project_dir/logs"
printf 'bounded context\n' > "$project_dir/control/context-capsules/indexa-task-001.md"
cat > "$project_dir/logs/complexity-observations.tsv" <<'TSV'
recorded_at	project	plan_node	task_id	role	model	worker_route	complexity_score	predicted_actions	predicted_p95_tokens	processed_tokens	usage_source	items	commands	output_bytes	max_output_bytes	source_read_bytes	repeated_source_reads	changed_files	duration_seconds	classification	changed_lines	planner_model	planner_effort	leaf_type
now	indexa	n1	001	worker_luna	gpt-5.6-luna	LUNA	10	6	100000	120000	actual	7	4	8000	4000	3000	2	1	20	success	4
TSV
cat > "$project_dir/logs/complexity-outcomes.tsv" <<'TSV'
recorded_at	project	plan_node	task_id	outcome	root_replans	planner_model	planner_effort
now	indexa	n1	001	ACCEPTED	0	gpt-5.6-sol	high
TSV
baseline="$($HARNESS_BIN/harness-context-baseline "$env_a")"
grep -Fqx $'worker_episodes\t1' <<< "$baseline"
grep -Fqx $'processed_tokens\t120000' <<< "$baseline"
grep -Fqx $'repeated_source_reads\t2' <<< "$baseline"
grep -Fqx $'accepted_outcomes\t1' <<< "$baseline"

# Configuration validation prevents required closure from running without an
# enabled repository index.
sed -e 's/HARNESS_REPOSITORY_INDEX_MODE="advisory"/HARNESS_REPOSITORY_INDEX_MODE="off"/' \
	-e 's/HARNESS_CONTEXT_CLOSURE_MODE="off"/HARNESS_CONTEXT_CLOSURE_MODE="required"/' \
	"$env_a" > "$TEST_ROOT/invalid-mode.env"
chmod 600 "$TEST_ROOT/invalid-mode.env"
if "$HARNESS_BIN/harness-index-status" "$TEST_ROOT/invalid-mode.env" > "$TEST_ROOT/invalid-mode.out" 2>&1; then
	printf 'required context closure accepted disabled repository index\n' >&2
	exit 1
fi
grep -Fq 'HARNESS_CONTEXT_CLOSURE_MODE requires HARNESS_REPOSITORY_INDEX_MODE=advisory or required' \
	"$TEST_ROOT/invalid-mode.out"

# Safe-boundary refresh is supervisor-owned. A manager terminal command only
# records the durable request; the persistent supervisor rebuilds and publishes
# the new required generation before any later planning turn.
env_refresh_advisory="$TEST_ROOT/index-refresh-advisory.env"
env_refresh="$TEST_ROOT/index-refresh.env"
write_env indexrefresh "$TEST_ROOT/build-a/compile_commands.json" "$TEST_ROOT/bin/scip-clang" \
	"$env_refresh_advisory"
sed -e 's/HARNESS_REPOSITORY_INDEX_MODE="advisory"/HARNESS_REPOSITORY_INDEX_MODE="required"/' \
	-e 's/HARNESS_CONTEXT_CLOSURE_MODE="off"/HARNESS_CONTEXT_CLOSURE_MODE="patch_only"/' \
	"$env_refresh_advisory" > "$env_refresh"
printf 'export HARNESS_POLL_SECONDS="1"\nexport HARNESS_USE_INOTIFY="0"\n' >> "$env_refresh"
chmod 600 "$env_refresh"
"$HARNESS_BIN/harness-init" "$env_refresh" >/dev/null
"$HARNESS_BIN/harness-index-repository" "$env_refresh" >/dev/null
printf '\n/* supervisor refresh boundary */\n' >> "$TEST_ROOT/repo/src/calc.c"
git -C "$TEST_ROOT/repo" add src/calc.c
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid \
	commit -qm 'advance refresh fixture'
(
	source "$env_refresh"
	source "$HARNESS_HOME/lib/harness-common.sh"
	source "$HARNESS_HOME/lib/harness-repository-index.sh"
	export HARNESS_ENV_FILE="$env_refresh"
	repository_index_refresh_at_safe_boundary fixture-task ACCEPTED
)
refresh_project="$TEST_ROOT/state/projects/indexrefresh"
test -f "$refresh_project/control/repository-index-refresh.pending.env"
grep -q 'REPOSITORY_INDEX_REFRESH_SCHEDULED task=fixture-task outcome=ACCEPTED' \
	"$refresh_project/logs/events.log"
"$HARNESS_BIN/harness-supervisor-start" "$env_refresh" >/dev/null
for _ in $(seq 1 200); do
	grep -Fqx $'status\tREADY' < <("$HARNESS_BIN/harness-index-status" "$env_refresh") &&
		[[ ! -f "$refresh_project/control/repository-index-refresh.pending.env" ]] && break
	sleep 0.05
done
"$HARNESS_BIN/harness-supervisor-stop" "$env_refresh" >/dev/null
grep -Fqx $'status\tREADY' < <("$HARNESS_BIN/harness-index-status" "$env_refresh")
test ! -f "$refresh_project/control/repository-index-refresh.pending.env"
grep -q 'REPOSITORY_INDEX_REFRESHED task=fixture-task outcome=ACCEPTED.*owner=supervisor' \
	"$refresh_project/logs/events.log"

# Required mode must also discover a committed source increment when a blocked
# terminal review preserved it without invoking an outcome-specific scheduler.
printf '\n/* unscheduled blocked-result increment */\n' >> "$TEST_ROOT/repo/src/calc.c"
git -C "$TEST_ROOT/repo" add src/calc.c
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid \
	commit -qm 'advance unscheduled refresh fixture'
test ! -f "$refresh_project/control/repository-index-refresh.pending.env"
"$HARNESS_BIN/harness-supervisor-start" "$env_refresh" >/dev/null
for _ in $(seq 1 200); do
	grep -Fqx $'status\tREADY' < <("$HARNESS_BIN/harness-index-status" "$env_refresh") &&
		grep -q 'REPOSITORY_INDEX_REFRESHED task=supervisor outcome=REQUIRED_BARRIER.*owner=supervisor' \
			"$refresh_project/logs/events.log" && break
	sleep 0.05
done
"$HARNESS_BIN/harness-supervisor-stop" "$env_refresh" >/dev/null
grep -q 'REPOSITORY_INDEX_REFRESH_SCHEDULED task=supervisor outcome=REQUIRED_BARRIER' \
	"$refresh_project/logs/events.log"
grep -q 'REPOSITORY_INDEX_REFRESHED task=supervisor outcome=REQUIRED_BARRIER.*owner=supervisor' \
	"$refresh_project/logs/events.log"
grep -Fqx $'status\tREADY' < <("$HARNESS_BIN/harness-index-status" "$env_refresh")

# A review can create the refresh marker after the loop's initial refresh
# check. The supervisor must cross the barrier again before either recovery or
# ordinary planning can publish the next task in that same iteration.
python3 - "$HARNESS_BIN/manager-supervisor" <<'PY'
from pathlib import Path
import sys

loop = Path(sys.argv[1]).read_text(encoding="utf-8").split("while true; do", 1)[1]
first_refresh = loop.index("process_repository_index_refresh")
results = loop.index("process_results", first_refresh)
second_refresh = loop.index("process_repository_index_refresh", results)
replans = loop.index("process_auto_replans", second_refresh)
planning = loop.index("process_planning_gap", replans)
assert first_refresh < results < second_refresh < replans < planning
PY

printf 'repository index tests passed\n'
