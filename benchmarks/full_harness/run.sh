#!/usr/bin/env bash
# Launch one single-agent and one manager/worker implementation benchmark.
set -Eeuo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$BENCHMARK_DIR/../.." && pwd)"
SHARED="$BENCHMARK_DIR/shared"
RUN_ID="${BENCHMARK_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
CODEX_BIN="${BENCHMARK_CODEX_BIN:-${CODEX_BIN:-codex}}"
CODEX_HOME_FOR_RUN="${BENCHMARK_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
SANDBOX="${BENCHMARK_SANDBOX:-workspace-write}"
RUN_DIR="$BENCHMARK_DIR/runs/$RUN_ID"

[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'invalid BENCHMARK_RUN_ID\n' >&2; exit 2; }
[[ "$SANDBOX" =~ ^(workspace-write|danger-full-access)$ ]] || { printf 'invalid BENCHMARK_SANDBOX\n' >&2; exit 2; }
[[ -x "$(command -v "$CODEX_BIN")" ]] || { printf 'Codex executable is unavailable: %s\n' "$CODEX_BIN" >&2; exit 2; }
[[ -d "$CODEX_HOME_FOR_RUN" ]] || { printf 'Codex home is unavailable: %s\n' "$CODEX_HOME_FOR_RUN" >&2; exit 2; }
[[ ! -e "$RUN_DIR" ]] || { printf 'run directory already exists: %s\n' "$RUN_DIR" >&2; exit 2; }
for required in manager-bootstrap manager-supervisor worker-supervisor; do
	[[ -x "$ROOT/bin/$required" ]] || {
		printf 'The unified harness is missing required Full command bin/%s.\n' "$required" >&2
		exit 2
	}
done

mkdir -p "$RUN_DIR"/{single,manager-worker,logs}
umask 077

init_repository()
{
	local repository="$1"
	mkdir -p "$repository"
	cp "$SHARED/SPECIFICATION.md" "$repository/SPECIFICATION.md"
	cp "$SHARED/AGENTS.md" "$repository/AGENTS.md"
	printf '# bnfc benchmark seed\n\nRead SPECIFICATION.md and AGENTS.md.\n' > "$repository/README.md"
	git -C "$repository" init -q
	git -C "$repository" add README.md SPECIFICATION.md AGENTS.md
	git -C "$repository" -c user.name=benchmark -c user.email=benchmark@example.invalid commit -qm 'benchmark seed'
}

single_repo="$RUN_DIR/single/repository"
pair_repo="$RUN_DIR/manager-worker/repository"
init_repository "$single_repo"
init_repository "$pair_repo"
cp "$SHARED/grader.sh" "$RUN_DIR/grader.sh"
chmod 700 "$RUN_DIR/grader.sh"
cp "$SHARED/grader.sh" "$RUN_DIR/single/grader.sh"
cp "$SHARED/grader.sh" "$RUN_DIR/manager-worker/grader.sh"
chmod 700 "$RUN_DIR/single/grader.sh" "$RUN_DIR/manager-worker/grader.sh"
cp "$BENCHMARK_DIR/pricing.env.example" "$RUN_DIR/pricing.env"
chmod 600 "$RUN_DIR/pricing.env"

single_prompt="$RUN_DIR/single/prompt.md"
printf '%s\n' \
  'You are the sole implementation agent for this benchmark.' \
  'Read AGENTS.md and SPECIFICATION.md completely. You own the entire repository.' \
  '' \
  'Work as a persistent goal executor even though this is one non-interactive Codex turn:' \
  '1. Inspect the repository and specification, then implement the complete project; do not stop after planning or after a partial subsystem.' \
  '2. Build with make clean all, run your own tests, then run ../grader.sh "$PWD".' \
  '3. If any build, test, or grader check fails, diagnose and repair it. Repeat that loop until every grader check passes.' \
  '4. Do not claim completion while any requirement or external grader check remains unmet.' \
  '5. Do not wait for user input, do not use other agents, do not modify files outside this repository, and do not create a git commit.' \
  '' \
  'Your final response must state the exact build/test commands run and their outcomes. The durable result is the working repository, not prose.' \
  > "$single_prompt"

pair_env="$RUN_DIR/manager-worker/harness.env"
printf 'export PROJECT=%q\n' "benchmark-$RUN_ID" > "$pair_env"
printf 'export REPOSITORY=%q\n' "$pair_repo" >> "$pair_env"
printf 'export SPECIFICATION=%q\n' "$pair_repo/SPECIFICATION.md" >> "$pair_env"
printf 'export HARNESS_MODE=full\n' >> "$pair_env"
printf 'export HARNESS_HOME=%q\nexport HARNESS_BIN=%q\n' "$ROOT" "$ROOT/bin" >> "$pair_env"
printf 'export HARNESS_ROOT=%q\nexport PROJECT_TMP_DIR=%q\n' "$RUN_DIR/manager-worker/state" "$RUN_DIR/manager-worker/tmp" >> "$pair_env"
printf 'export MANAGER_CODEX_HOME=%q\nexport WORKER_CODEX_HOME=%q\n' "$CODEX_HOME_FOR_RUN" "$CODEX_HOME_FOR_RUN" >> "$pair_env"
printf 'export MANAGER_CODEX_BIN=%q\nexport WORKER_CODEX_BIN=%q\n' "$CODEX_BIN" "$CODEX_BIN" >> "$pair_env"
printf 'export MANAGER_MODEL="gpt-5.6-terra"\nexport MANAGER_REASONING_EFFORT="high"\nexport MANAGER_SANDBOX=%q\n' "$SANDBOX" >> "$pair_env"
printf 'export WORKER_MODEL="gpt-5.6-luna"\nexport WORKER_REASONING_EFFORT="high"\nexport WORKER_SANDBOX=%q\n' "$SANDBOX" >> "$pair_env"
printf 'export LUNA_WORKER_MODEL="gpt-5.6-luna"\nexport LUNA_WORKER_REASONING_EFFORT="high"\n' >> "$pair_env"
printf 'export TERRA_WORKER_MODEL="gpt-5.6-terra"\nexport TERRA_WORKER_REASONING_EFFORT="high"\n' >> "$pair_env"
printf 'export MAX_ORACLE_RUNS=0\nexport HARNESS_POLL_SECONDS=1\nexport HARNESS_USE_INOTIFY=0\n' >> "$pair_env"
printf 'export HARNESS_WORKER_GOAL_MODE=1\nexport HARNESS_DECOMPOSITION_V2=1\nexport HARNESS_DECOMPOSITION_CRITIC_ENABLED=1\n' >> "$pair_env"
printf 'export HARNESS_MAX_LUNA_STRATEGY_FAILURES=2\nexport HARNESS_CODEX_IDLE_TIMEOUT_SECONDS=0\nexport HARNESS_CODEX_WALL_TIMEOUT_SECONDS=0\n' >> "$pair_env"
chmod 600 "$pair_env"

run_single()
{
	local start end status
	start="$(date +%s)"
	set +e
	(
		cd "$single_repo"
		env CODEX_HOME="$CODEX_HOME_FOR_RUN" "$CODEX_BIN" exec --json --model gpt-5.6-terra --sandbox "$SANDBOX" \
			-c 'approval_policy="never"' -c 'model_reasoning_effort="high"' \
			--output-last-message "$RUN_DIR/single/last-message.md" - < "$single_prompt" \
			> "$RUN_DIR/single/events.jsonl" 2> "$RUN_DIR/single/stderr.log"
	)
	status=$?
	set -e
	end="$(date +%s)"
	printf 'started=%s\nended=%s\nseconds=%s\nexit_status=%s\n' "$start" "$end" "$((end - start))" "$status" > "$RUN_DIR/single/timing.env"
	return "$status"
}

run_manager_worker()
{
	local start end status=0
	start="$(date +%s)"
	set +e
	"$ROOT/bin/harness-init" "$pair_env" > "$RUN_DIR/manager-worker/start.log" 2>&1
	status=$?
	if (( status == 0 )); then
		"$ROOT/bin/harness-start" "$pair_env" >> "$RUN_DIR/manager-worker/start.log" 2>&1
		status=$?
	fi
	set -e
	if (( status == 0 )); then
		while [[ ! -f "$RUN_DIR/manager-worker/state/projects/benchmark-$RUN_ID/control/project.complete" ]]; do
			if find "$RUN_DIR/manager-worker/state/projects/benchmark-$RUN_ID/control" -name '*.needs-human.md' -o -name '*-failed.md' | grep -q .; then
				status=4
				break
			fi
			sleep 2
		done
	fi
	"$ROOT/bin/harness-stop" "$pair_env" >> "$RUN_DIR/manager-worker/start.log" 2>&1 || true
	end="$(date +%s)"
	printf 'started=%s\nended=%s\nseconds=%s\nexit_status=%s\n' "$start" "$end" "$((end - start))" "$status" > "$RUN_DIR/manager-worker/timing.env"
	return "$status"
}

printf 'Launching benchmark %s\n' "$RUN_ID"
run_single & single_pid=$!
run_manager_worker & pair_pid=$!
set +e
wait "$single_pid"; single_status=$?
wait "$pair_pid"; pair_status=$?
set -e
printf 'single_exit_status=%s\nmanager_worker_exit_status=%s\n' "$single_status" "$pair_status" > "$RUN_DIR/runner-status.env"
"$BENCHMARK_DIR/evaluate.sh" "$RUN_DIR" || true
printf 'Benchmark artifacts: %s\n' "$RUN_DIR"
printf 'Single exit: %s; manager/worker exit: %s\n' "$single_status" "$pair_status"
