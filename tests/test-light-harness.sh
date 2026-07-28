#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

repo="$TEST_DIR/repository"
state_root="$TEST_DIR/state"
fake_state="$TEST_DIR/fake-state"
mkdir -p "$repo" "$fake_state" "$TEST_DIR/codex-home"

cat > "$TEST_DIR/specification.md" <<'EOF'
# Feature

Create feature.txt containing exactly `complete`.
EOF

cat > "$TEST_DIR/development-policy.txt" <<'EOF'
Development mode: prototype / feature-first.
Implement the requested feature with the smallest reasonable code change.
Use one happy-path smoke test. Do not build production infrastructure.
EOF

cat > "$TEST_DIR/fake-codex" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

output=""
model=""
resume_thread=""
while (( $# > 0 )); do
	case "$1" in
		--output-last-message)
			output="$2"
			shift 2
			;;
		--model)
			model="$2"
			shift 2
			;;
		--sandbox|--cd|--add-dir|-c|--config)
			shift 2
			;;
		resume)
			resume_thread="$2"
			shift 2
			;;
		-)
			shift
			break
			;;
		*)
			shift
			;;
	esac
done
prompt="$(cat)"
counter_file="$FAKE_CODEX_STATE/manager-counter"
touch "$FAKE_CODEX_STATE/invocations.log"

if [[ "$model" == gpt-5.6-terra ]]; then
	counter=0
	[[ ! -f "$counter_file" ]] || counter="$(cat "$counter_file")"
	counter=$((counter + 1))
	printf '%s\n' "$counter" > "$counter_file"
	thread="manager-$counter"
	if [[ "$prompt" == *"Terra goal author"* ]]; then
		message=$'# Persistent Worker Goal\nImplement the complete immutable specification, verify it, and continue until it works.\nGOAL_READY'
	elif [[ -f "$FAKE_REPOSITORY/feature.txt" ]] &&
		[[ "$(cat "$FAKE_REPOSITORY/feature.txt")" == complete ]]; then
		message=$'DECISION: ACCEPT\nAll specified behavior is implemented.'
	else
		message=$'DECISION: REVISE\n\nADD-001\nSpecification: feature.txt must contain exactly complete.\nEvidence: the repository contains only a partial value.\nRequired correction: replace it with the complete value.\nVerification: test \"$(cat feature.txt)\" = complete.'
	fi
	input=100
	cached=80
	output_tokens=20
else
	thread="${resume_thread:-worker-thread}"
	if [[ -n "$resume_thread" ]]; then
		printf 'complete\n' > "$FAKE_REPOSITORY/feature.txt"
		printf 'worker resume %s\n' "$resume_thread" >> "$FAKE_CODEX_STATE/invocations.log"
		message='Resolved the complete addendum and verified the specification.'
		input=2500
		cached=2000
		output_tokens=250
	else
		printf 'partial\n' > "$FAKE_REPOSITORY/feature.txt"
		printf 'worker fresh\n' >> "$FAKE_CODEX_STATE/invocations.log"
		message='Implemented the first complete pass and reached review readiness.'
		input=1000
		cached=800
		output_tokens=100
	fi
fi

printf '%s\n' "$message" > "$output"
jq -cn --arg thread "$thread" '{type:"thread.started",thread_id:$thread}'
jq -cn --arg text "$message" \
	'{type:"item.completed",item:{type:"agent_message",text:$text}}'
jq -cn --argjson input "$input" --argjson cached "$cached" \
	--argjson output "$output_tokens" \
	'{type:"turn.completed",usage:{input_tokens:$input,cached_input_tokens:$cached,cache_write_input_tokens:0,output_tokens:$output}}'
EOF
chmod +x "$TEST_DIR/fake-codex"

cat > "$TEST_DIR/project.env" <<EOF
export PROJECT="light-smoke"
export REPOSITORY="$repo"
export SPECIFICATION="$TEST_DIR/specification.md"
export DEVELOPMENT_POLICY="$TEST_DIR/development-policy.txt"
export HARNESS_HOME="$ROOT"
export HARNESS_ROOT="$state_root"
export MANAGER_CODEX_BIN="$TEST_DIR/fake-codex"
export WORKER_CODEX_BIN="$TEST_DIR/fake-codex"
export MANAGER_CODEX_HOME="$TEST_DIR/codex-home"
export WORKER_CODEX_HOME="$TEST_DIR/codex-home"
export MANAGER_MODEL="gpt-5.6-terra"
export MANAGER_REASONING_EFFORT="high"
export WORKER_MODEL="gpt-5.6-luna"
export WORKER_REASONING_EFFORT="high"
export HARNESS_PROVIDER_RETRY_SECONDS="1"
export HARNESS_QUOTA_RETRY_SECONDS="1"
export FAKE_CODEX_STATE="$fake_state"
export FAKE_REPOSITORY="$repo"
EOF
chmod 600 "$TEST_DIR/project.env"

"$ROOT/bin/harness-check-env" "$TEST_DIR/project.env" >/dev/null
"$ROOT/bin/harness-init" "$TEST_DIR/project.env" >/dev/null
"$ROOT/bin/harness-start" "$TEST_DIR/project.env" >/dev/null

project="$state_root/projects/light-smoke"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[[ -f "$project/control/state.env" ]] &&
		grep -qx 'status=COMPLETE' "$project/control/state.env" &&
		break
	sleep 1
done
for _ in 1 2 3 4 5; do
	[[ ! -f "$project/control/supervisor.pid" ]] && break
	sleep 1
done
grep -qx 'status=COMPLETE' "$project/control/state.env"
test ! -f "$project/control/supervisor.pid"
grep -qx 'phase=ACCEPTED' "$project/control/state.env"
grep -qx 'cycle=2' "$project/control/state.env"
grep -qx 'worker-thread' "$project/control/worker.thread"
grep -qx 'complete' "$repo/feature.txt"
test -f "$project/addenda/addendum-001.md"
test -f "$project/reviews/review-001.md"
test -f "$project/reviews/review-002.md"
test -f "$project/control/final-acceptance.md"
grep -q '^DECISION: REVISE$' "$project/addenda/addendum-001.md"
grep -q '^DECISION: ACCEPT$' "$project/control/final-acceptance.md"
grep -q '^worker fresh$' "$fake_state/invocations.log"
grep -q '^worker resume worker-thread$' "$fake_state/invocations.log"

status_output="$("$ROOT/bin/harness-status" "$TEST_DIR/project.env")"
grep -q 'Worker tokens: input=2500 cached=2000 output=250' <<< "$status_output"
grep -q 'Manager tokens: input=300 cached=240 output=60' <<< "$status_output"
if find "$project" -iname '*oracle*' -print -quit | grep -q .; then
	printf 'unexpected Oracle state exists\n' >&2
	exit 1
fi

printf 'PASS light harness persistent-worker smoke\n'
