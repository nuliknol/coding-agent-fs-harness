#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-manager-batch.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\n" "$TEST_ROOT" >&2' EXIT
else
	trap 'rm -rf -- "$TEST_ROOT"' EXIT
fi
mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home" "$TEST_ROOT/fake-bin"
printf 'batch review fixture\n' > "$TEST_ROOT/repo/spec.md"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name test
git -C "$TEST_ROOT/repo" config user.email test@example.invalid
git -C "$TEST_ROOT/repo" add spec.md
git -C "$TEST_ROOT/repo" commit -qm baseline
cat > "$TEST_ROOT/init.env" <<ENV
export PROJECT=batchproj
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_HOME="$ROOT"
export HARNESS_BIN="$ROOT/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN=/bin/true
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN=/bin/true
export HARNESS_SPECIFICATION_REVIEW_ENABLED=0
export HARNESS_DECOMPOSITION_V2=1
export HARNESS_ARCHITECTURE_GUARDS=0
export HARNESS_MANAGER_BATCH_SIZE=4
ENV
"$ROOT/bin/harness-init" "$TEST_ROOT/init.env" >/dev/null
project="$TEST_ROOT/state/projects/batchproj"
cat > "$project/control/project-decomposition-v2.tsv" <<'TSV'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route
a	-	-	a	a	true	a.txt	-	LOCAL_IMPLEMENTATION	LOW	LUNA
b	-	-	b	b	true	b.txt	-	LOCAL_IMPLEMENTATION	LOW	LUNA
TSV
cat > "$project/control/project-plan.tsv" <<'TSV'
# coding-harness-project-plan-v2
a	a
b	b
TSV
cat > "$project/control/project-plan-state.tsv" <<'TSV'
# item_id	status	task_root	updated_at
a	ACTIVE	a	now
b	ACTIVE	b	now
TSV
cat > "$project/control/project-conflict-graph.tsv" <<'TSV'
left_node	right_node	reasons
TSV
for task in a b; do
	cat > "$project/archive/batchproj-task-$task.assignment.md" <<ASSIGNMENT
Task-ID: $task
Task-Root: $task
Allowed-Scope: $task.txt
ASSIGNMENT
	cat > "$project/results/batchproj-task-$task.result.md" <<RESULT
Task-ID: $task
Status: COMPLETED
RESULT
done

cat > "$TEST_ROOT/fake-bin/manager-invoke-result" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$1"
task="$2"
project="$HARNESS_ROOT/projects/$PROJECT"
printf '%s\t%s\n' "$task" "$(date +%s%3N)" >> "$HARNESS_ROOT/manager-starts.tsv"
sleep 1
mv "$project/results/$PROJECT-task-$task.result.md" \
	"$project/archive/$PROJECT-task-$task.accepted.md"
FAKE
chmod 700 "$TEST_ROOT/fake-bin/"*
cp "$TEST_ROOT/init.env" "$TEST_ROOT/batch.env"
cat >> "$TEST_ROOT/batch.env" <<ENV
export HARNESS_MANAGER_RESULT_PARALLEL_INVOKER="$TEST_ROOT/fake-bin/manager-invoke-result"
ENV
chmod 600 "$TEST_ROOT/batch.env"

"$ROOT/bin/manager-invoke-result-batch" "$TEST_ROOT/batch.env" a b >/dev/null
[[ ! -e "$project/results/batchproj-task-a.result.md" ]]
[[ ! -e "$project/results/batchproj-task-b.result.md" ]]
[[ "$(wc -l < "$TEST_ROOT/state/manager-starts.tsv")" == 2 ]]
start_spread="$(awk -F '\t' 'NR==1 {min=max=$2} $2<min {min=$2} $2>max {max=$2} END {print max-min}' \
	"$TEST_ROOT/state/manager-starts.tsv")"
(( start_spread < 500 ))
[[ "$(awk -F '\t' '$4=="ENQUEUED" {n++} END {print n+0}' "$project/control/manager-inbox.tsv")" == 2 ]]
[[ "$(awk -F '\t' '$4=="COMMITTED" {n++} END {print n+0}' "$project/control/manager-inbox.tsv")" == 2 ]]
grep -Fq 'MANAGER_REVIEW_COHORT_FINISHED' "$project/logs/events.log"
printf 'manager batch tests passed\n'
