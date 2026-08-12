#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/harness-autostart-test.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/config" "$TEST_ROOT/runtime"
cat > "$TEST_ROOT/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
[[ "$*" != *is-enabled* ]] || printf 'enabled\n'
SYSTEMCTL
chmod 755 "$TEST_ROOT/bin/systemctl"
export SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
export PATH="$TEST_ROOT/bin:$PATH"

cat > "$TEST_ROOT/full.env" <<ENV
export HARNESS_MODE="full"
export PROJECT="full-autostart-test"
export REPOSITORY="$TEST_ROOT"
export HARNESS_HOME="$HARNESS_HOME"
ENV
cat > "$TEST_ROOT/light.env" <<ENV
export HARNESS_MODE="light"
export PROJECT="light-autostart-test"
export REPOSITORY="$TEST_ROOT"
export HARNESS_HOME="$HARNESS_HOME"
ENV
chmod 600 "$TEST_ROOT/full.env" "$TEST_ROOT/light.env"

"$HARNESS_HOME/bin/harness-autostart" enable "$TEST_ROOT/full.env" "$TEST_ROOT/light.env" \
	> "$TEST_ROOT/enable.out"
grep -Fq 'daemon-reload' "$SYSTEMCTL_LOG"
grep -Fq 'enable coding-agent-fs-harness-autostart.service' "$SYSTEMCTL_LOG"
unit="$XDG_CONFIG_HOME/systemd/user/coding-agent-fs-harness-autostart.service"
grep -Fq "ExecStart=\"$HARNESS_HOME/bin/harness-autostart\" run" "$unit"
grep -Fq 'WantedBy=default.target' "$unit"

"$HARNESS_HOME/bin/harness-autostart" status > "$TEST_ROOT/status.out"
grep -Fqx 'Registered: 2' "$TEST_ROOT/status.out"
grep -Fq $'full\t'"$(realpath "$TEST_ROOT/full.env")" "$TEST_ROOT/status.out"
grep -Fq $'light\t'"$(realpath "$TEST_ROOT/light.env")" "$TEST_ROOT/status.out"

"$HARNESS_HOME/bin/harness-autostart" disable "$TEST_ROOT/full.env" >/dev/null
"$HARNESS_HOME/bin/harness-autostart" status > "$TEST_ROOT/status-after.out"
grep -Fqx 'Registered: 1' "$TEST_ROOT/status-after.out"
! grep -Fq "$(realpath "$TEST_ROOT/full.env")" "$TEST_ROOT/status-after.out"

printf 'autostart tests passed\n'
