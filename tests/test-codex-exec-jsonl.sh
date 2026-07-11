#!/usr/bin/env bash
# Focused tests for the non-interactive Codex JSONL runner.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/codex-jsonl-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/home"
printf 'base\n' > "$TMP/repo/tracked.txt"
git -C "$TMP/repo" init -q
git -C "$TMP/repo" add tracked.txt
git -C "$TMP/repo" -c user.email=test@example.invalid -c user.name=test commit -qm initial

cat > "$TMP/mock-codex" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
last=""; next=0
for a in "$@"; do
 if (( next )); then last="$a"; next=0; continue; fi
 [[ "$a" == --output-last-message ]] && next=1
done
case "${MOCK_MODE:?}" in
 success) printf 'done\n' > "$last"; printf '{"type":"turn.completed"}\n' ;;
 failed) printf '{"type":"turn.failed","error":{"message":"simulated"}}\n'; exit 1 ;;
 error) printf '{"type":"error","message":"simulated"}\n'; exit 1 ;;
 invalid) printf 'not json\n' ;;
 empty) : ;;
 nonzero) exit 7 ;;
 stderr_progress) printf 'progress\n' >&2; printf 'done\n' > "$last"; printf '{"type":"turn.completed"}\n' ;;
 benign_blocked_text) printf 'done\n' > "$last"; printf '{"type":"item.completed","item":{"type":"agent_message","text":"The blocked queue is now fixed."}}\n{"type":"turn.completed"}\n' ;;
 refusal) printf '{"type":"error","message":"Request refused by an additional safety check"}\n'; exit 1 ;;
 idle) sleep 5 ;;
 wall) while true; do printf 'progress\n' >&2; sleep 1; done ;;
 partial) printf 'partial\n' >> "$REPOSITORY/tracked.txt"; exit 7 ;;
esac
MOCK
chmod +x "$TMP/mock-codex"
cat > "$TMP/env" <<ENV
export PROJECT="jsonltest"
export REPOSITORY="$TMP/repo"
export HARNESS_HOME="$ROOT"
export HARNESS_BIN="$ROOT/bin"
export HARNESS_ROOT="$TMP/state"
export MANAGER_CODEX_HOME="$TMP/home"
export MANAGER_CODEX_BIN="$TMP/mock-codex"
export WORKER_CODEX_HOME="$TMP/home"
export WORKER_CODEX_BIN="$TMP/mock-codex"
export HARNESS_CODEX_WALL_TIMEOUT_SECONDS="2"
export HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="1"
export HARNESS_CODEX_KILL_GRACE_SECONDS="1"
ENV
chmod 600 "$TMP/env"
prompt="$TMP/prompt"; printf 'test\n' > "$prompt"

run_case() {
 local mode="$1" want="$2" status=0 base
 base="$TMP/$mode"
 set +e
 MOCK_MODE="$mode" "$ROOT/bin/codex-exec-jsonl" "$TMP/env" worker gpt-5.5 "$prompt" "$base.jsonl" "$base.stderr" "$base.last"
 status=$?
 set -e
 [[ "$(awk -F= '$1 == "classification" {print $2}' "$base.classification")" == "$want" ]]
}
run_case success success
run_case failed turn_failed
run_case error error_event
run_case invalid json_event_parse_failure
run_case empty empty_final_output
run_case nonzero process_nonzero_exit
run_case stderr_progress success
grep -q progress "$TMP/stderr_progress.stderr"
run_case benign_blocked_text success
run_case refusal model_refusal_or_blocked_content
run_case idle idle_timeout
run_case wall wall_clock_timeout
run_case partial partial_edit_failure
! git -C "$TMP/repo" diff --quiet --
printf 'Codex JSONL runner tests passed.\n'
