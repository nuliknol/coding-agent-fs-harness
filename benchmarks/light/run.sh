#!/usr/bin/env bash
# Run the archived pbnfc task through the light manager/worker harness.
set -Eeuo pipefail

LIGHT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LIGHT_DIR/../.." && pwd)"
SHARED="$ROOT/benchmarks/full_harness/shared"
DEFAULT_FULL_RUN="$ROOT/benchmarks/full_harness/runs/pbnfc-html8-terra-vs-harness-20260727a"
RUN_ID="${BENCHMARK_RUN_ID:-pbnfc-html8-light-$(date -u +%Y%m%dT%H%M%SZ)}"
CODEX_BIN="${BENCHMARK_CODEX_BIN:-${CODEX_BIN:-codex}}"
CODEX_HOME_FOR_RUN="${BENCHMARK_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
SANDBOX="${BENCHMARK_SANDBOX:-workspace-write}"
POLICY="${BENCHMARK_DEVELOPMENT_POLICY:-$LIGHT_DIR/development-policy.txt}"
FULL_RUN="${BENCHMARK_FULL_RUN:-$DEFAULT_FULL_RUN}"
RUN_DIR="$LIGHT_DIR/runs/$RUN_ID"
PROJECT="benchmark-light-$RUN_ID"

[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] ||
	{ printf 'invalid BENCHMARK_RUN_ID: %s\n' "$RUN_ID" >&2; exit 2; }
[[ "$SANDBOX" =~ ^(workspace-write|danger-full-access)$ ]] ||
	{ printf 'invalid BENCHMARK_SANDBOX: %s\n' "$SANDBOX" >&2; exit 2; }
CODEX_BIN="$(command -v "$CODEX_BIN" 2>/dev/null || true)"
[[ -n "$CODEX_BIN" && -x "$CODEX_BIN" ]] ||
	{ printf 'Codex executable is unavailable: %s\n' "$CODEX_BIN" >&2; exit 2; }
[[ -d "$CODEX_HOME_FOR_RUN" ]] ||
	{ printf 'Codex home is unavailable: %s\n' "$CODEX_HOME_FOR_RUN" >&2; exit 2; }
[[ -f "$POLICY" ]] ||
	{ printf 'development policy is unavailable: %s\n' "$POLICY" >&2; exit 2; }
[[ -f "$SHARED/SPECIFICATION.md" && -f "$SHARED/AGENTS.md" &&
	-x "$SHARED/grader.sh" ]] ||
	{ printf 'archived shared benchmark inputs are incomplete: %s\n' "$SHARED" >&2; exit 2; }
[[ -f "$FULL_RUN/comparison.tsv" ]] ||
	{ printf 'full-harness baseline is unavailable: %s\n' "$FULL_RUN" >&2; exit 2; }
[[ ! -e "$RUN_DIR" ]] ||
	{ printf 'run directory already exists: %s\n' "$RUN_DIR" >&2; exit 2; }

umask 077
mkdir -p "$RUN_DIR"/{repository,state}
cp "$SHARED/SPECIFICATION.md" "$RUN_DIR/repository/SPECIFICATION.md"
cp "$SHARED/AGENTS.md" "$RUN_DIR/repository/AGENTS.md"
cp "$SHARED/grader.sh" "$RUN_DIR/grader.sh"
cp "$POLICY" "$RUN_DIR/development-policy.txt"
cp "$LIGHT_DIR/pricing.env" "$RUN_DIR/pricing.env"
chmod 700 "$RUN_DIR/grader.sh"
printf '# pbnfc light-harness benchmark seed\n\nRead SPECIFICATION.md and AGENTS.md.\n' \
	> "$RUN_DIR/repository/README.md"
git -C "$RUN_DIR/repository" init -q
git -C "$RUN_DIR/repository" add README.md SPECIFICATION.md AGENTS.md
git -C "$RUN_DIR/repository" -c user.name=benchmark \
	-c user.email=benchmark@example.invalid commit -qm 'benchmark seed'

printf '%s\n' "$FULL_RUN" > "$RUN_DIR/full-baseline.path"
printf '%s\n' "$ROOT" > "$RUN_DIR/harness-source.path"
git -C "$ROOT" rev-parse HEAD > "$RUN_DIR/harness-head.txt"
git -C "$ROOT" status --short > "$RUN_DIR/harness-worktree-status.txt"
sha256sum "$RUN_DIR/repository/SPECIFICATION.md" \
	"$SHARED/SPECIFICATION.md" > "$RUN_DIR/specification-sha256.txt"

env_file="$RUN_DIR/harness.env"
{
	printf 'export PROJECT=%q\n' "$PROJECT"
	printf 'export REPOSITORY=%q\n' "$RUN_DIR/repository"
	printf 'export SPECIFICATION=%q\n' "$RUN_DIR/repository/SPECIFICATION.md"
	printf 'export HARNESS_MODE=%q\n' 'light'
	printf 'export DEVELOPMENT_POLICY=%q\n' "$RUN_DIR/development-policy.txt"
	printf 'export HARNESS_HOME=%q\n' "$ROOT"
	printf 'export HARNESS_BIN=%q\n' "$ROOT/bin"
	printf 'export HARNESS_ROOT=%q\n' "$RUN_DIR/state"
	printf 'export MANAGER_CODEX_HOME=%q\n' "$CODEX_HOME_FOR_RUN"
	printf 'export MANAGER_CODEX_BIN=%q\n' "$CODEX_BIN"
	printf 'export MANAGER_MODEL=%q\n' 'gpt-5.6-terra'
	printf 'export MANAGER_REASONING_EFFORT=%q\n' 'high'
	printf 'export MANAGER_SANDBOX=%q\n' "$SANDBOX"
	printf 'export WORKER_CODEX_HOME=%q\n' "$CODEX_HOME_FOR_RUN"
	printf 'export WORKER_CODEX_BIN=%q\n' "$CODEX_BIN"
	printf 'export WORKER_MODEL=%q\n' 'gpt-5.6-luna'
	printf 'export WORKER_REASONING_EFFORT=%q\n' 'high'
	printf 'export WORKER_SANDBOX=%q\n' "$SANDBOX"
	printf 'export HARNESS_MAX_MANAGER_REVIEWS=%q\n' '0'
	printf 'export HARNESS_PROVIDER_RETRY_SECONDS=%q\n' '60'
	printf 'export HARNESS_QUOTA_RETRY_SECONDS=%q\n' '300'
	printf 'export HARNESS_CODEX_WALL_TIMEOUT_SECONDS=%q\n' '0'
	printf 'export HARNESS_CODEX_IDLE_TIMEOUT_SECONDS=%q\n' '0'
	printf 'export HARNESS_CODEX_KILL_GRACE_SECONDS=%q\n' '15'
} > "$env_file"
chmod 600 "$env_file"

state_file="$RUN_DIR/state/projects/$PROJECT/control/state.env"
started_epoch="$(date +%s)"
started_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
status=0

cleanup()
{
	"$ROOT/bin/harness-stop" "$env_file" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

printf 'Starting light benchmark %s\n' "$RUN_ID"
printf 'Run directory: %s\n' "$RUN_DIR"
"$ROOT/bin/harness-check-env" "$env_file" > "$RUN_DIR/check-env.log" 2>&1
"$ROOT/bin/harness-init" "$env_file" > "$RUN_DIR/start.log" 2>&1
"$ROOT/bin/harness-start" "$env_file" >> "$RUN_DIR/start.log" 2>&1

while true; do
	current_status="$(awk -F= '$1 == "status" { print $2; exit }' "$state_file")"
	current_phase="$(awk -F= '$1 == "phase" { print $2; exit }' "$state_file")"
	case "$current_status:$current_phase" in
		COMPLETE:ACCEPTED)
			status=0
			break
			;;
		FAILED:*|PAUSED:*)
			status=1
			break
			;;
	esac
	sleep 2
done

ended_epoch="$(date +%s)"
ended_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
	printf 'started_epoch=%s\n' "$started_epoch"
	printf 'ended_epoch=%s\n' "$ended_epoch"
	printf 'started_utc=%s\n' "$started_utc"
	printf 'ended_utc=%s\n' "$ended_utc"
	printf 'seconds=%s\n' "$((ended_epoch - started_epoch))"
	printf 'exit_status=%s\n' "$status"
	printf 'final_status=%s\n' "$current_status"
	printf 'final_phase=%s\n' "$current_phase"
} > "$RUN_DIR/timing.env"

"$ROOT/bin/harness-status" "$env_file" > "$RUN_DIR/final-status.txt" 2>&1 || true
"$LIGHT_DIR/evaluate.sh" "$RUN_DIR" || true
printf 'Benchmark artifacts: %s\n' "$RUN_DIR"
exit "$status"
