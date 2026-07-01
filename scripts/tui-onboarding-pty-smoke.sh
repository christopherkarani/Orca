#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_SOCKET="orca-tui-smoke-$$"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/orca-tui-smoke.XXXXXX")"

cleanup() {
    tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

fail() {
    echo "tui onboarding PTY smoke: $*" >&2
    exit 1
}

command -v tmux >/dev/null 2>&1 || fail "tmux is required"

ORCA="$ROOT/zig-out/bin/orca"
[[ -x "$ORCA" ]] || fail "build Orca first with ./scripts/zig build"

capture_pane() {
    tmux -L "$TMUX_SOCKET" capture-pane -p -S -200 2>/dev/null
}

wait_for() {
    local needle="$1"
    local attempts=0
    while ((attempts < 80)); do
        if capture_pane | grep -Fq "$needle"; then
            return 0
        fi
        sleep 0.05
        attempts=$((attempts + 1))
    done
    capture_pane >&2
    fail "timed out waiting for: $needle"
}

mkdir -p "$SMOKE_ROOT/start-workspace" "$SMOKE_ROOT/home"
tmux -L "$TMUX_SOCKET" new-session -d -x 100 -y 30 \
    -c "$SMOKE_ROOT/start-workspace" \
    "before=\$(stty -g); env HOME='$SMOKE_ROOT/home' PATH='/usr/bin:/bin' ORCA_RESOURCE_ROOT='$ROOT' '$ORCA' start --skip-verify; code=\$?; after=\$(stty -g); if [ \"\$before\" = \"\$after\" ]; then echo __ORCA_TERMIOS_RESTORED__; else echo __ORCA_TERMIOS_CHANGED__; fi; exit \$code"
tmux -L "$TMUX_SOCKET" set-option remain-on-exit on

wait_for "Choose your protection mode"
# The original failure appears after the 100 ms raw-input timeout.
sleep 0.3

start_screen="$(capture_pane)"
prompt_count="$(grep -Fc "Choose your protection mode" <<<"$start_screen")"
[[ "$prompt_count" == "1" ]] || fail "expected one protection prompt, found $prompt_count"

if grep -Eq '^ {12,}(🛡  )?Orca' <<<"$start_screen"; then
    fail "banner drifted horizontally after buffered output flushed in raw mode"
fi

tmux -L "$TMUX_SOCKET" send-keys Up
tmux -L "$TMUX_SOCKET" send-keys Enter
wait_for "Protection mode: Firewall"
wait_for "__ORCA_TERMIOS_RESTORED__"

echo "orca start PTY smoke passed"

tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
mkdir -p "$SMOKE_ROOT/quickstart-workspace" "$SMOKE_ROOT/quickstart-home" "$SMOKE_ROOT/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$SMOKE_ROOT/bin/codex"
chmod +x "$SMOKE_ROOT/bin/codex"

tmux -L "$TMUX_SOCKET" new-session -d -x 100 -y 40 \
    -c "$SMOKE_ROOT/quickstart-workspace" \
    "before=\$(stty -g); env HOME='$SMOKE_ROOT/quickstart-home' PATH='$SMOKE_ROOT/bin:/usr/bin:/bin' ORCA_RESOURCE_ROOT='$ROOT' '$ORCA' quickstart; code=\$?; after=\$(stty -g); if [ \"\$before\" = \"\$after\" ]; then echo __ORCA_TERMIOS_RESTORED__; else echo __ORCA_TERMIOS_CHANGED__; fi; exit \$code"
tmux -L "$TMUX_SOCKET" set-option remain-on-exit on

wait_for "Select agent hosts to integrate"
sleep 0.3

quickstart_screen="$(capture_pane)"
host_prompt_count="$(grep -Fc "Select agent hosts to integrate" <<<"$quickstart_screen")"
[[ "$host_prompt_count" == "1" ]] || fail "expected one host prompt, found $host_prompt_count"

if grep -Eq '^ {12,}(Orca Doctor|Summary:|Select agent hosts)' <<<"$quickstart_screen"; then
    fail "quickstart output drifted horizontally at the raw prompt boundary"
fi

tmux -L "$TMUX_SOCKET" send-keys Enter
wait_for "Core protection is ready"
wait_for "__ORCA_TERMIOS_RESTORED__"

echo "orca quickstart PTY smoke passed"
