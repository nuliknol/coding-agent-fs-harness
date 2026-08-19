#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-sctm.XXXXXX)"
cleanup()
{
	"$ROOT/bin/sctm-daemon-stop" "$TEST_ROOT/harness.env" >/dev/null 2>&1 || true
	git -C "$TEST_ROOT/repo" worktree prune >/dev/null 2>&1 || true
	if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
		printf 'Preserved test root: %s\n' "$TEST_ROOT" >&2
	else
		rm -rf -- "$TEST_ROOT"
	fi
}
trap cleanup EXIT

mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
cat > "$TEST_ROOT/repo/shared.txt" <<'SOURCE'
parse-old
middle
encode-old
SOURCE
printf 'SCTM fixture specification\n' > "$TEST_ROOT/repo/spec.md"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" config user.name test
git -C "$TEST_ROOT/repo" config user.email test@example.invalid
git -C "$TEST_ROOT/repo" add .
git -C "$TEST_ROOT/repo" commit -qm baseline
base="$(git -C "$TEST_ROOT/repo" rev-parse HEAD)"

cat > "$TEST_ROOT/harness.env" <<ENV
export PROJECT=sctmtest
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="\$REPOSITORY/spec.md"
export HARNESS_MODE=full
export HARNESS_HOME="$ROOT"
export HARNESS_BIN="$ROOT/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN=/bin/true
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN=/bin/true
export HARNESS_ACP_ENABLED=1
export HARNESS_DECOMPOSITION_V2=0
export HARNESS_WORKER_PARALLELISM=2
export HARNESS_WORKER_PARALLELISM_HARD_MAX=4
export HARNESS_WORKER_ISOLATION_MODE=worktree
export HARNESS_SCTM_ENABLED=1
export HARNESS_SCTM_SUBMIT_TIMEOUT_SECONDS=30
export HARNESS_SPECIFICATION_REVIEW_ENABLED=0
export HARNESS_ARCHITECTURE_GUARDS=0
export MAX_ORACLE_RUNS=0
ENV
chmod 600 "$TEST_ROOT/harness.env"
"$ROOT/bin/harness-init" "$TEST_ROOT/harness.env" >/dev/null
project="$TEST_ROOT/state/projects/sctmtest"

make_patch()
{
	local name="$1" old="$2" new="$3" worktree
	worktree="$TEST_ROOT/$name"
	git -C "$TEST_ROOT/repo" worktree add --detach "$worktree" "$4" >/dev/null
	sed -i "s/^${old}$/${new}/" "$worktree/shared.txt"
	git -C "$worktree" diff --binary --full-index > "$TEST_ROOT/$name.patch"
	git -C "$TEST_ROOT/repo" worktree remove --force "$worktree" >/dev/null
}

printf 'shared.txt\n' > "$TEST_ROOT/paths"
printf 'shared.txt\n' > "$TEST_ROOT/capability"
printf 'SCTM transaction\n' > "$TEST_ROOT/message"
make_patch tx1 parse-old parse-new "$base"
make_patch tx2 encode-old encode-new "$base"
printf "grep -Fqx 'parse-new' shared.txt\n" > "$TEST_ROOT/validate1"
printf "grep -Fqx 'encode-new' shared.txt\n" > "$TEST_ROOT/validate2"

"$ROOT/bin/sctm-submit" "$TEST_ROOT/harness.env" tx1 worker-a task-a "$base" \
	"$TEST_ROOT/tx1.patch" "$TEST_ROOT/paths" "$TEST_ROOT/capability" \
	"$TEST_ROOT/message" "$TEST_ROOT/validate1" > "$TEST_ROOT/tx1.out" &
pid1=$!
"$ROOT/bin/sctm-submit" "$TEST_ROOT/harness.env" tx2 worker-b task-b "$base" \
	"$TEST_ROOT/tx2.patch" "$TEST_ROOT/paths" "$TEST_ROOT/capability" \
	"$TEST_ROOT/message" "$TEST_ROOT/validate2" > "$TEST_ROOT/tx2.out" &
pid2=$!
wait "$pid1"
wait "$pid2"
grep -Fqx 'parse-new' "$TEST_ROOT/repo/shared.txt"
grep -Fqx 'encode-new' "$TEST_ROOT/repo/shared.txt"
grep -Fqx 'status=APPLIED' "$TEST_ROOT/tx1.out"
grep -Fqx 'status=APPLIED' "$TEST_ROOT/tx2.out"
[[ "$(git -C "$TEST_ROOT/repo" rev-list --count "$base..HEAD")" == 2 ]]

# Idempotent resubmission returns the durable result and cannot create a third
# commit for the same immutable transaction ID.
"$ROOT/bin/sctm-submit" "$TEST_ROOT/harness.env" tx1 worker-a task-a "$base" \
	"$TEST_ROOT/tx1.patch" "$TEST_ROOT/paths" "$TEST_ROOT/capability" \
	"$TEST_ROOT/message" "$TEST_ROOT/validate1" > "$TEST_ROOT/tx1-repeat.out"
cmp -s "$TEST_ROOT/tx1.out" "$TEST_ROOT/tx1-repeat.out"
[[ "$(git -C "$TEST_ROOT/repo" rev-list --count "$base..HEAD")" == 2 ]]

# Two transactions from the same later base that replace the same source line
# produce one commit and one deterministic conflict with a bounded current
# delta. No partial second mutation reaches the canonical tree.
conflict_base="$(git -C "$TEST_ROOT/repo" rev-parse HEAD)"
make_patch tx3 parse-new parse-three "$conflict_base"
make_patch tx4 parse-new parse-four "$conflict_base"
printf "grep -Fqx 'parse-three' shared.txt\n" > "$TEST_ROOT/validate3"
printf "grep -Fqx 'parse-four' shared.txt\n" > "$TEST_ROOT/validate4"
"$ROOT/bin/sctm-submit" "$TEST_ROOT/harness.env" tx3 worker-c task-c "$conflict_base" \
	"$TEST_ROOT/tx3.patch" "$TEST_ROOT/paths" "$TEST_ROOT/capability" \
	"$TEST_ROOT/message" "$TEST_ROOT/validate3" >/dev/null
set +e
"$ROOT/bin/sctm-submit" "$TEST_ROOT/harness.env" tx4 worker-d task-d "$conflict_base" \
	"$TEST_ROOT/tx4.patch" "$TEST_ROOT/paths" "$TEST_ROOT/capability" \
	"$TEST_ROOT/message" "$TEST_ROOT/validate4" > "$TEST_ROOT/tx4.out"
conflict_status=$?
set -e
[[ "$conflict_status" == 75 ]]
grep -Fqx 'status=CONFLICT' "$TEST_ROOT/tx4.out"
grep -Fqx 'parse-three' "$TEST_ROOT/repo/shared.txt"
[[ -s "$project/control/sctm/transactions/tx4/delta-since-worker-base.patch" ]]

# Mechanical scope and validation failures both leave HEAD and bytes intact.
rejected_base="$(git -C "$TEST_ROOT/repo" rev-parse HEAD)"
make_patch tx5 encode-new encode-scope-violation "$rejected_base"
printf 'other.txt\n' > "$TEST_ROOT/wrong-capability"
set +e
"$ROOT/bin/sctm-submit" "$TEST_ROOT/harness.env" tx5 worker-e task-e "$rejected_base" \
	"$TEST_ROOT/tx5.patch" "$TEST_ROOT/paths" "$TEST_ROOT/wrong-capability" \
	"$TEST_ROOT/message" "$TEST_ROOT/validate2" > "$TEST_ROOT/tx5.out"
scope_status=$?
set -e
(( scope_status != 0 ))
grep -Fqx 'status=SCOPE_VIOLATION' "$TEST_ROOT/tx5.out"
[[ "$(git -C "$TEST_ROOT/repo" rev-parse HEAD)" == "$rejected_base" ]]
grep -Fqx 'encode-new' "$TEST_ROOT/repo/shared.txt"

make_patch tx6 encode-new encode-validation-failure "$rejected_base"
printf 'false\n' > "$TEST_ROOT/validate-fail"
set +e
"$ROOT/bin/sctm-submit" "$TEST_ROOT/harness.env" tx6 worker-f task-f "$rejected_base" \
	"$TEST_ROOT/tx6.patch" "$TEST_ROOT/paths" "$TEST_ROOT/capability" \
	"$TEST_ROOT/message" "$TEST_ROOT/validate-fail" > "$TEST_ROOT/tx6.out"
validation_status=$?
set -e
(( validation_status != 0 ))
grep -Fqx 'status=VALIDATION_FAILED' "$TEST_ROOT/tx6.out"
[[ "$(git -C "$TEST_ROOT/repo" rev-parse HEAD)" == "$rejected_base" ]]
grep -Fqx 'encode-new' "$TEST_ROOT/repo/shared.txt"
git -C "$TEST_ROOT/repo" diff --quiet
git -C "$TEST_ROOT/repo" diff --cached --quiet

# Simulate a daemon crash after the canonical fast-forward but before its
# terminal response. Startup reconstructs the missing FIFO record, observes
# COMMITTING plus the candidate HEAD, restores the complete tree/index, and
# publishes APPLIED without committing the patch a second time.
"$ROOT/bin/sctm-daemon-stop" "$TEST_ROOT/harness.env" >/dev/null
recover_previous="$(git -C "$TEST_ROOT/repo" rev-parse HEAD)"
recover_worktree="$TEST_ROOT/recover-worktree"
git -C "$TEST_ROOT/repo" worktree add --detach "$recover_worktree" "$recover_previous" >/dev/null
sed -i 's/^middle$/middle-recovered/' "$recover_worktree/shared.txt"
git -C "$recover_worktree" add shared.txt
git -C "$recover_worktree" -c user.name=test -c user.email=test@example.invalid commit -qm recovery-candidate
recover_candidate="$(git -C "$recover_worktree" rev-parse HEAD)"
recover_transaction="$project/control/sctm/transactions/tx-recover"
mkdir "$recover_transaction"
git -C "$recover_worktree" diff --binary --full-index "$recover_previous..$recover_candidate" > "$recover_transaction/patch"
printf 'shared.txt\n' > "$recover_transaction/declared-paths"
printf 'shared.txt\n' > "$recover_transaction/capability-paths"
printf 'Crash recovery transaction\n' > "$recover_transaction/message"
printf ':\n' > "$recover_transaction/validation-command"
printf 'shared.txt\n' > "$recover_transaction/changed-paths"
printf 'transaction_id=tx-recover\nproject_id=sctmtest\nworker_id=worker-recover\ntask_id=task-recover\nbase_commit=%s\ninput_fingerprint=test\n' \
	"$recover_previous" > "$recover_transaction/request"
printf 'previous_commit=%s\ncandidate_commit=%s\n' "$recover_previous" "$recover_candidate" \
	> "$recover_transaction/commit-state"
printf 'COMMITTING\n' > "$recover_transaction/state"
chmod 600 "$recover_transaction"/*
git -C "$TEST_ROOT/repo" merge --ff-only "$recover_candidate" >/dev/null
git -C "$TEST_ROOT/repo" worktree remove --force "$recover_worktree" >/dev/null
"$ROOT/bin/sctm-daemon-start" "$TEST_ROOT/harness.env" >/dev/null
for _ in $(seq 1 100); do
	[[ -f "$recover_transaction/result" ]] && break
	sleep 0.05
done
grep -Fqx 'status=APPLIED' "$recover_transaction/result"
grep -Fqx 'reason=crash-recovered' "$recover_transaction/result"
grep -Fqx "commit=$recover_candidate" "$recover_transaction/result"
grep -Fqx "$recover_candidate" "$recover_transaction/resulting-commit"
grep -Fqx 'middle-recovered' "$TEST_ROOT/repo/shared.txt"
git -C "$TEST_ROOT/repo" diff --quiet
git -C "$TEST_ROOT/repo" diff --cached --quiet
for _ in $(seq 1 100); do
	grep -Fq 'SCTM_TRANSACTION_RECOVERY_APPLIED transaction=tx-recover' "$project/logs/events.log" && break
	sleep 0.05
done
grep -Fq 'SCTM_TRANSACTION_APPLIED transaction=tx1' "$project/logs/events.log"
grep -Fq 'SCTM_TRANSACTION_CONFLICT transaction=tx4' "$project/logs/events.log"
grep -Fq 'SCTM_TRANSACTION_RECOVERED transaction=tx-recover' "$project/logs/events.log"
grep -Fq 'SCTM_TRANSACTION_RECOVERY_APPLIED transaction=tx-recover' "$project/logs/events.log"

# Manager review must inspect the exact SCTM-integrated task commit even after
# later transactions have advanced HEAD and left the canonical worktree clean.
mkdir -p "$project/archive" "$project/control/acp/integration"
cat > "$project/archive/sctmtest-task-task-a.assignment.md" <<'ASSIGNMENT'
Task-ID: task-a
Allowed-Scope: shared.txt
ASSIGNMENT
tx1_previous="$(sed -n 's/^previous_commit=//p' \
	"$project/control/sctm/transactions/tx1/result")"
tx1_commit="$(sed -n 's/^commit=//p' \
	"$project/control/sctm/transactions/tx1/result")"
cat > "$project/control/acp/integration/task-a.integrated.env" <<INTEGRATION
task_id=task-a
integration_base=$tx1_previous
integrated_head=$tx1_commit
INTEGRATION
review_output="$("$ROOT/bin/harness-review-diff" "$TEST_ROOT/harness.env" task-a)"
grep -Fq 'Review-Source: SCTM_INTEGRATED_COMMIT' <<< "$review_output"
grep -Fq -- '-parse-old' <<< "$review_output"
grep -Fq -- '+parse-new' <<< "$review_output"
git -C "$TEST_ROOT/repo" diff --quiet
git -C "$TEST_ROOT/repo" diff --cached --quiet

"$ROOT/bin/sctm-status" "$TEST_ROOT/harness.env" > "$TEST_ROOT/sctm-status.out"
grep -Fqx 'Daemon: running' "$TEST_ROOT/sctm-status.out"
grep -Fqx 'Queued: 0' "$TEST_ROOT/sctm-status.out"
grep -Eq '^  APPLIED +4$' "$TEST_ROOT/sctm-status.out"
grep -Eq '^  CONFLICT +1$' "$TEST_ROOT/sctm-status.out"
printf 'SCTM transaction tests passed.\n'
