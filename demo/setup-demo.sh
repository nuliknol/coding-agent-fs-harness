#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PACKAGE_DIR/bin"
DEMO_REPO="${HARNESS_DEMO_REPO:-/tmp/coding-harness-demo-repo-${UID}}"
DEMO_STATE="${HARNESS_DEMO_STATE:-/tmp/coding-harness-demo-state-${UID}}"
ENV_FILE="${HARNESS_DEMO_ENV:-/tmp/demo-calc-harness-${UID}.env}"
CODEX_PATH="${HARNESS_DEMO_CODEX_BIN:-$(command -v codex || true)}"
MANAGER_HOME="${HARNESS_DEMO_MANAGER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
WORKER_HOME="${HARNESS_DEMO_WORKER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"

[[ -n "$CODEX_PATH" ]] || {
	printf 'Set HARNESS_DEMO_CODEX_BIN to the Codex executable.\n' >&2
	exit 1
}

rm -rf "$DEMO_REPO" "$DEMO_STATE"
mkdir -p "$DEMO_REPO"
cp -a "$SCRIPT_DIR/repo/." "$DEMO_REPO/"
cat > "$DEMO_REPO/specification.md" <<'SPEC'
# Demo specification

Implement `calc_add()` so it returns the arithmetic sum of its two integer arguments. Preserve the existing public interface and make the supplied test pass.
SPEC

cat > "$ENV_FILE" <<ENV
export PROJECT="demo-calc"
export REPOSITORY="$DEMO_REPO"
export SPECIFICATION="\$REPOSITORY/specification.md"
export HARNESS_HOME="$PACKAGE_DIR"
export HARNESS_BIN="\$HARNESS_HOME/bin"
export HARNESS_ROOT="$DEMO_STATE"
export MANAGER_CODEX_HOME="$MANAGER_HOME"
export MANAGER_CODEX_BIN="$CODEX_PATH"
export MANAGER_MODEL="gpt-5.5"
export MANAGER_REASONING_EFFORT="high"
export MANAGER_SANDBOX="workspace-write"
export WORKER_CODEX_HOME="$WORKER_HOME"
export WORKER_CODEX_BIN="$CODEX_PATH"
export WORKER_MODEL="gpt-5.4-mini"
export WORKER_REASONING_EFFORT="high"
export WORKER_SANDBOX="workspace-write"
export HARNESS_POLL_SECONDS="1"
export HARNESS_WAIT_SECONDS="30"
export HARNESS_STALE_SECONDS="900"
export HARNESS_USE_INOTIFY="1"
export WORKER_HEARTBEAT_SECONDS="60"
ENV
chmod 600 "$ENV_FILE"

"$BIN/harness-init" "$ENV_FILE"
printf '\nDemo environment file: %s\n' "$ENV_FILE"
printf 'Demo repository: %s\n' "$DEMO_REPO"
printf '\nStart the complete manager/worker loop with:\n'
printf '%s %s\n' "$BIN/harness-start" "$ENV_FILE"
