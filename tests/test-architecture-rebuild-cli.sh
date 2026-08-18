#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-architecture-rebuild-cli.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

repository="$TEST_ROOT/repository"
mkdir -p "$repository/lib" "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
printf 'Architecture fixture specification.\n' > "$repository/spec.md"
printf '#!/usr/bin/env bash\nfixture_state() { printf "ready\\n"; }\n' > "$repository/lib/fixture.sh"
printf 'def fixture_value():\n    return 1\n' > "$repository/fixture.py"
git -C "$repository" init -q
git -C "$repository" add .
git -C "$repository" -c user.name=test -c user.email=test@example.invalid commit -qm seed

env_file="$TEST_ROOT/project.env"
cat > "$env_file" <<ENV
export PROJECT="architecture-cli"
export REPOSITORY="$repository"
export SPECIFICATION="$repository/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$ROOT"
export HARNESS_BIN="$ROOT/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export HARNESS_DECOMPOSITION_V2="0"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$env_file"
"$ROOT/bin/harness-init" "$env_file" >/dev/null

begin_output="$($ROOT/bin/harness-architecture-rebuild "$env_file" begin fixture periodic-test)"
rebuild_id="$(awk -F= '$1=="rebuild_id" {print $2; exit}' <<< "$begin_output")"
[[ "$rebuild_id" =~ ^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}$ ]]
grep -Fqx status=DESIGN <<< "$begin_output"

printf 'Interrupted design evidence.\n' > "$TEST_ROOT/interrupted.md"
"$ROOT/bin/harness-architecture-rebuild" "$env_file" fail "$rebuild_id" DESIGN \
	"$TEST_ROOT/interrupted.md" interrupted-test >/dev/null
grep -Fqx status=FAILED < <("$ROOT/bin/harness-architecture-rebuild" "$env_file" status "$rebuild_id")
"$ROOT/bin/harness-architecture-rebuild" "$env_file" resume "$rebuild_id" >/dev/null
grep -Fqx status=DESIGN < <("$ROOT/bin/harness-architecture-rebuild" "$env_file" status "$rebuild_id")

printf '# Target Architecture\n\nSeparate fixture ownership.\n' > "$TEST_ROOT/target.md"
printf '# Behavioral Baseline\n\nfixture_state prints ready.\n' > "$TEST_ROOT/baseline.md"
printf 'step\tstatus\nevidence-provider-extraction\tCOMPLETE\n' > "$TEST_ROOT/migration.tsv"
printf '# Operator Approval\n\nApproved after comparison.\n' > "$TEST_ROOT/approval.md"
"$ROOT/bin/harness-architecture-rebuild" "$env_file" design "$rebuild_id" "$TEST_ROOT/target.md" >/dev/null
"$ROOT/bin/harness-architecture-rebuild" "$env_file" baseline "$rebuild_id" "$TEST_ROOT/baseline.md" >/dev/null
"$ROOT/bin/harness-architecture-rebuild" "$env_file" refactor-complete "$rebuild_id" "$TEST_ROOT/migration.tsv" >/dev/null
"$ROOT/bin/harness-architecture-rebuild" "$env_file" recompute "$rebuild_id" >/dev/null
grep -Fqx status=AWAITING_APPROVAL < <("$ROOT/bin/harness-architecture-rebuild" "$env_file" status "$rebuild_id")
"$ROOT/bin/harness-architecture-rebuild" "$env_file" accept "$rebuild_id" "$TEST_ROOT/approval.md" >/dev/null

run_dir="$TEST_ROOT/state/projects/architecture-cli/control/architecture/rebuild/$rebuild_id"
grep -Fqx status=ACCEPTED "$run_dir/state.env"
for artifact in target-architecture.md behavioral-baseline.md migration-ledger.tsv approval.md \
	architecture-rebuild-report.md remaining-debt.tsv comparison.tsv; do
	test -f "$run_dir/$artifact"
done
grep -Fq '# Architecture Rebuild Report' "$run_dir/architecture-rebuild-report.md"
grep -Fq $'debt_id\tfinding_kind\tpriority' "$run_dir/remaining-debt.tsv"
grep -Fq $'comparison_status\tPASS' "$run_dir/comparison.tsv"

printf 'architecture rebuild CLI tests passed\n'

