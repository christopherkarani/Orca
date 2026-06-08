#!/usr/bin/env bash
#
# orca uninstaller
#
# One-liner uninstall:
#   curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/uninstall.sh | bash
#
# Options:
#   --yes            Skip confirmation prompt
#   --keep-config    Keep configuration files (~/.config/orca/)
#   --keep-history   Keep history database (~/.local/share/orca/)
#   --purge          Remove everything (overrides keep flags)
#   --quiet          Suppress non-error output
#
set -euo pipefail

# Defaults
YES=0
KEEP_CONFIG=0
KEEP_HISTORY=0
PURGE=0
QUIET=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Logging functions
log() { [ "$QUIET" -eq 1 ] && return 0; echo -e "$@"; }
ok() { [ "$QUIET" -eq 1 ] && return 0; echo -e "${GREEN}✓${NC} $*"; }
warn() { [ "$QUIET" -eq 1 ] && return 0; echo -e "${YELLOW}⚠${NC} $*"; }
err() { echo -e "${RED}✗${NC} $*" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            YES=1
            shift
            ;;
        --keep-config)
            KEEP_CONFIG=1
            shift
            ;;
        --keep-history)
            KEEP_HISTORY=1
            shift
            ;;
        --purge)
            PURGE=1
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        *)
            err "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Purge overrides keep flags
if [ "$PURGE" -eq 1 ]; then
    KEEP_CONFIG=0
    KEEP_HISTORY=0
fi

# Find orca binary location
find_guard_binary() {
    # Check common locations (orca first, then legacy orca)
    local locations=(
        "$HOME/.local/bin/orca"
        "/usr/local/bin/orca"
        "/usr/bin/orca"
        "$HOME/.local/bin/orca"
        "/usr/local/bin/orca"
        "/usr/bin/orca"
    )

    for loc in "${locations[@]}"; do
        if [ -x "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done

    # Fall back to which (orca, then legacy orca)
    command -v orca 2>/dev/null || command -v orca 2>/dev/null || true
}

json_settings_has_guard_command_hook() {
    local settings="$1"
    local event_name="$2"
    local matcher="${3:-}"

    if [ ! -f "$settings" ]; then
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        grep -qE '"command".*(orca|orca)' "$settings" 2>/dev/null
        return $?
    fi

    python3 - "$settings" "$event_name" "$matcher" <<'PYEOF'
import json
import os
import shlex
import sys

settings_file = sys.argv[1]
event_name = sys.argv[2]
matcher = sys.argv[3]

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(command):
    if not isinstance(command, str) or not command:
        return False
    try:
        parts = shlex.split(command)
    except ValueError:
        return False
    if not parts:
        return False
    name = os.path.basename(parts[0])
    if name.endswith(".exe"):
        name = name[:-4]
    return name in GUARD_BIN_NAMES

try:
    with open(settings_file, "r", encoding="utf-8") as f:
        settings = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(1)

if not isinstance(settings, dict):
    sys.exit(1)
hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(1)
entries = hooks.get(event_name)
if not isinstance(entries, list):
    sys.exit(1)

for entry in entries:
    if not isinstance(entry, dict):
        continue
    if matcher and entry.get("matcher") != matcher:
        continue
    inner_hooks = entry.get("hooks")
    if not isinstance(inner_hooks, list):
        continue
    if any(isinstance(hook, dict) and is_guard_command(hook.get("command")) for hook in inner_hooks):
        sys.exit(0)

sys.exit(1)
PYEOF
}

json_copilot_has_guard_hook() {
    local hook_file="$1"

    if [ ! -f "$hook_file" ]; then
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        grep -qE '(orca|orca)' "$hook_file" 2>/dev/null
        return $?
    fi

    python3 - "$hook_file" <<'PYEOF'
import json
import os
import shlex
import sys

hook_file = sys.argv[1]

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(command):
    if not isinstance(command, str) or not command:
        return False
    try:
        parts = shlex.split(command)
    except ValueError:
        return False
    if not parts:
        return False
    name = os.path.basename(parts[0])
    if name.endswith(".exe"):
        name = name[:-4]
    return name in GUARD_BIN_NAMES

try:
    with open(hook_file, "r", encoding="utf-8") as f:
        settings = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(1)

if not isinstance(settings, dict):
    sys.exit(1)
hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(1)
pre_tool = hooks.get("preToolUse")
if not isinstance(pre_tool, list):
    sys.exit(1)

for entry in pre_tool:
    if not isinstance(entry, dict):
        continue
    if is_guard_command(entry.get("bash")) or is_guard_command(entry.get("powershell")):
        sys.exit(0)

sys.exit(1)
PYEOF
}

json_cursor_has_guard_hook() {
    local hooks_json="$1"
    local hook_script="${2:-$HOME/.cursor/hooks/orca-pre-shell.py}"  # legacy: orca-pre-shell.py also checked in unconfigure_cursor

    if [ ! -f "$hooks_json" ]; then
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        grep -qE '(orca|orca)' "$hooks_json" 2>/dev/null
        return $?
    fi

    python3 - "$hooks_json" "$hook_script" <<'PYEOF'
import json
import shlex
import sys

hooks_file = sys.argv[1]
expected_hook = sys.argv[2]

CURSOR_HOOK_PATHS = {
    os.path.expanduser("~/.cursor/hooks/orca-pre-shell.py"),
    os.path.expanduser("~/.cursor/hooks/orca-pre-shell.py"),
}

def is_guard_cursor_command(command):
    if not isinstance(command, str) or not command:
        return False
    try:
        parts = shlex.split(command)
    except ValueError:
        return False
    if not parts:
        return False
    cmd_path = parts[0]
    return cmd_path in CURSOR_HOOK_PATHS or cmd_path == expected_hook

try:
    with open(hooks_file, "r", encoding="utf-8") as f:
        settings = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(1)

if not isinstance(settings, dict):
    sys.exit(1)
hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(1)
entries = hooks.get("beforeShellExecution")
if not isinstance(entries, list):
    sys.exit(1)

for entry in entries:
    if isinstance(entry, dict) and is_guard_cursor_command(entry.get("command")):
        sys.exit(0)

sys.exit(1)
PYEOF
}

yaml_hermes_has_guard_hook() {
    local cfg_file="$1"

    if [ ! -f "$cfg_file" ]; then
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        # Best-effort: a literal "orca" mention in the pre_tool_call section
        # is at least suggestive. We avoid claiming a hit without python3.
        grep -q 'pre_tool_call' "$cfg_file" 2>/dev/null && grep -qE '(orca|orca)' "$cfg_file" 2>/dev/null
        return $?
    fi

    python3 - "$cfg_file" <<'PYEOF'
import os
import shlex
import sys
try:
    import yaml
except ImportError:
    sys.exit(1)

cfg_file = sys.argv[1]

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(cmd):
    if not isinstance(cmd, str) or not cmd:
        return False
    try:
        parts = shlex.split(cmd)
    except ValueError:
        return False
    if not parts:
        return False
    name = os.path.basename(parts[0])
    if name.endswith(".exe"):
        name = name[:-4]
    return name in GUARD_BIN_NAMES

try:
    with open(cfg_file, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
except (IOError, yaml.YAMLError):
    sys.exit(1)

if not isinstance(cfg, dict):
    sys.exit(1)
hooks = cfg.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(1)
pre_tool_call = hooks.get("pre_tool_call")
if not isinstance(pre_tool_call, list):
    sys.exit(1)
for entry in pre_tool_call:
    if isinstance(entry, dict) and is_guard_command(entry.get("command")):
        sys.exit(0)
sys.exit(1)
PYEOF
}

# Remove orca hook from Claude Code settings
unconfigure_claude_code() {
    local settings="$HOME/.claude/settings.json"

    if [ ! -f "$settings" ]; then
        return 0
    fi

    # Check if orca is configured
    if ! json_settings_has_guard_command_hook "$settings" "PreToolUse" "Bash"; then
        return 0
    fi

    # Use python3 to remove the hook safely
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$settings" <<'PYEOF'
import json
import os
import shlex
import sys

settings_file = sys.argv[1]

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(cmd):
    """True iff `cmd` invokes the orca binary (basename match, not substring).

    Uninstall correctness is critical here: a substring check would
    drop hooks for unrelated tools whose path or name happens to
    contain "orca" (e.g. /opt/orcagrep/bin/scan, ~/.local/bin/orcaworkflow,
    custom-orca-helper.sh). Since this code can DELETE entries, false
    positives correspond to data loss for the user's other tooling.
    """
    if not isinstance(cmd, str) or not cmd:
        return False
    try:
        tokens = shlex.split(cmd)
    except ValueError:
        return False
    if not tokens:
        return False
    name = os.path.basename(tokens[0])
    if name.endswith('.exe'):
        name = name[:-4]
    return name in GUARD_BIN_NAMES

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(0)

if not isinstance(settings, dict):
    sys.exit(0)
if 'hooks' not in settings:
    sys.exit(0)
if not isinstance(settings['hooks'], dict):
    sys.exit(0)
if 'PreToolUse' not in settings['hooks']:
    sys.exit(0)

pre_tool_use = settings['hooks']['PreToolUse']
if not isinstance(pre_tool_use, list):
    sys.exit(0)

# Filter out ONLY orca hooks (basename match)
new_hooks = []
removed = False
for entry in pre_tool_use:
    if isinstance(entry, dict) and entry.get('matcher') == 'Bash':
        hooks = entry.get('hooks', [])
        if not isinstance(hooks, list):
            new_hooks.append(entry)
            continue
        filtered = [
            h for h in hooks
            if not (isinstance(h, dict) and is_guard_command(h.get('command', '')))
        ]
        if len(filtered) != len(hooks):
            removed = True
        if filtered:
            entry['hooks'] = filtered
            new_hooks.append(entry)
    else:
        new_hooks.append(entry)

if not removed:
    sys.exit(0)

settings['hooks']['PreToolUse'] = new_hooks

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print("removed", file=sys.stderr)
PYEOF
        return $?
    else
        warn "python3 not available - cannot safely edit Claude Code settings"
        warn "Please manually remove orca from $settings"
        return 1
    fi
}

# Remove orca hook from Gemini CLI settings
unconfigure_gemini() {
    local settings="$HOME/.gemini/settings.json"

    if [ ! -f "$settings" ]; then
        return 0
    fi

    # Check if orca is configured
    if ! json_settings_has_guard_command_hook "$settings" "BeforeTool"; then
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$settings" <<'PYEOF'
import json
import os
import shlex
import sys

settings_file = sys.argv[1]

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(cmd):
    """True iff `cmd` invokes the orca binary (basename match, not substring)."""
    if not isinstance(cmd, str) or not cmd:
        return False
    try:
        tokens = shlex.split(cmd)
    except ValueError:
        return False
    if not tokens:
        return False
    name = os.path.basename(tokens[0])
    if name.endswith('.exe'):
        name = name[:-4]
    return name in GUARD_BIN_NAMES

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(0)

if not isinstance(settings, dict):
    sys.exit(0)
if 'hooks' not in settings:
    sys.exit(0)
if not isinstance(settings['hooks'], dict):
    sys.exit(0)
if 'BeforeTool' not in settings['hooks']:
    sys.exit(0)

before_tool = settings['hooks']['BeforeTool']
if not isinstance(before_tool, list):
    sys.exit(0)

# Filter out ONLY orca hooks (basename match)
new_hooks = []
removed = False
for entry in before_tool:
    if isinstance(entry, dict):
        hooks = entry.get('hooks', [])
        if not isinstance(hooks, list):
            new_hooks.append(entry)
            continue
        filtered = [
            h for h in hooks
            if not (isinstance(h, dict) and is_guard_command(h.get('command', '')))
        ]
        if len(filtered) != len(hooks):
            removed = True
        if filtered:
            entry['hooks'] = filtered
            new_hooks.append(entry)
    else:
        new_hooks.append(entry)

if not removed:
    sys.exit(0)

settings['hooks']['BeforeTool'] = new_hooks

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print("removed", file=sys.stderr)
PYEOF
        return $?
    else
        warn "python3 not available - cannot safely edit Gemini CLI settings"
        return 1
    fi
}

# Remove orca hook from GitHub Copilot CLI repo-local hook file
unconfigure_copilot() {
    if ! command -v git >/dev/null 2>&1; then
        return 0
    fi

    local repo_root=""
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -z "$repo_root" ]; then
        return 0
    fi

    local hook_file="$repo_root/.github/hooks/orca.json"
    local legacy_hook_file="$repo_root/.github/hooks/orca.json"
    if [ ! -f "$hook_file" ] && [ ! -f "$legacy_hook_file" ]; then
        return 0
    fi

    if [ -f "$hook_file" ] && json_copilot_has_guard_hook "$hook_file"; then
        :
    elif [ -f "$legacy_hook_file" ] && json_copilot_has_guard_hook "$legacy_hook_file"; then
        hook_file="$legacy_hook_file"
    else
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$hook_file" <<'PYEOF'
import json
import os
import shlex
import sys

hook_file = sys.argv[1]

try:
    with open(hook_file, "r", encoding="utf-8") as f:
        settings = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(0)

if not isinstance(settings, dict):
    sys.exit(0)

hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(0)

pre_tool = hooks.get("preToolUse")
if not isinstance(pre_tool, list):
    sys.exit(0)

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(command):
    if not isinstance(command, str) or not command:
        return False
    try:
        parts = shlex.split(command)
    except ValueError:
        return False
    if not parts:
        return False
    name = os.path.basename(parts[0])
    if name.endswith(".exe"):
        name = name[:-4]
    return name in GUARD_BIN_NAMES

def strip_orca_platform_fields(entry):
    if not isinstance(entry, dict):
        return False, [entry]

    cleaned = dict(entry)
    removed = False
    for key in ("bash", "powershell"):
        if is_guard_command(cleaned.get(key)):
            removed = True
            cleaned.pop(key, None)

    if not removed:
        return False, [entry]
    if cleaned.get("bash") or cleaned.get("powershell"):
        return True, [cleaned]
    return True, []

removed = False
new_pre = []
for entry in pre_tool:
    entry_removed, residual_entries = strip_orca_platform_fields(entry)
    if entry_removed:
        removed = True
    new_pre.extend(residual_entries)

if not removed:
    sys.exit(0)

if new_pre:
    hooks["preToolUse"] = new_pre
else:
    hooks.pop("preToolUse", None)

for key in list(hooks.keys()):
    if hooks.get(key) == []:
        hooks.pop(key, None)

if not hooks:
    settings.pop("hooks", None)

if not settings or settings == {"version": 1}:
    os.remove(hook_file)
else:
    with open(hook_file, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)

print("removed", file=sys.stderr)
PYEOF
        return $?
    else
        warn "python3 not available - cannot safely edit GitHub Copilot hook file"
        warn "Please manually remove orca from $hook_file"
        return 1
    fi
}

# Remove orca settings from Aider config
unconfigure_aider() {
    local config="$HOME/.aider.conf.yml"

    if [ ! -f "$config" ]; then
        return 0
    fi

    # Check if our settings exist
    if ! grep -qE 'Added by (orca|orca) installer' "$config" 2>/dev/null; then
        return 0
    fi

    # Create backup
    cp "$config" "${config}.bak.$(date +%Y%m%d%H%M%S)"

    # Remove lines added by orca installer
    local tmp="${config}.tmp"
    awk '
        /Added by (orca|orca) installer/ { skip=1; next }
        skip && /git-commit-verify:/ { skip=0; next }
        { skip=0; print }
    ' "$config" > "$tmp"

    # Check if file is now empty (just whitespace)
    if [ ! -s "$tmp" ] || ! grep -q '[^[:space:]]' "$tmp"; then
        rm -f "$tmp" "$config"
    else
        mv "$tmp" "$config"
    fi

    return 0
}

# Remove orca hook from Codex CLI (~/.codex/hooks.json).
#
# install.sh writes a Claude-shaped PreToolUse Bash matcher block into
# ~/.codex/hooks.json. Now that Codex 0.125.0 has stable hooks and orca
# emits its protocol-specific exit-2 deny path for Codex, leaving the
# hook entry behind after `orca uninstall` removes the binary would cause
# every Bash invocation to log "PreToolUse Failed" because codex would
# spawn a path that no longer exists.
unconfigure_codex() {
    local hooks_json="$HOME/.codex/hooks.json"

    if [ ! -f "$hooks_json" ]; then
        return 0
    fi

    if ! json_settings_has_guard_command_hook "$hooks_json" "PreToolUse" "Bash"; then
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$hooks_json" <<'PYEOF'
import json
import os
import shlex
import sys

hooks_file = sys.argv[1]

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(command):
    if not isinstance(command, str):
        return False
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()
    if not parts:
        return False
    return os.path.basename(parts[0]).removesuffix(".exe") in GUARD_BIN_NAMES

try:
    with open(hooks_file, 'r') as f:
        config = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(0)

if not isinstance(config, dict):
    sys.exit(0)

hooks = config.get('hooks')
if not isinstance(hooks, dict):
    sys.exit(0)

pre_tool_use = hooks.get('PreToolUse')
if not isinstance(pre_tool_use, list):
    sys.exit(0)

new_pre_tool_use = []
removed = False
for entry in pre_tool_use:
    if not isinstance(entry, dict):
        new_pre_tool_use.append(entry)
        continue
    if entry.get('matcher') != 'Bash':
        new_pre_tool_use.append(entry)
        continue
    inner = entry.get('hooks', [])
    if not isinstance(inner, list):
        new_pre_tool_use.append(entry)
        continue
    filtered = [
        h for h in inner
        if not (isinstance(h, dict) and is_guard_command(h.get('command', '')))
    ]
    if len(filtered) != len(inner):
        removed = True
    if filtered:
        entry['hooks'] = filtered
        new_pre_tool_use.append(entry)
    # else: drop the matcher entry entirely (it had only orca hooks)

if not removed:
    sys.exit(0)

if new_pre_tool_use:
    hooks['PreToolUse'] = new_pre_tool_use
else:
    hooks.pop('PreToolUse', None)

if not hooks:
    config.pop('hooks', None)

# If the file is now effectively empty, remove it so codex doesn't keep
# parsing a stub. install.sh creates this file dedicated for orca, so
# leaving it as an empty {} is just litter.
try:
    if not config:
        os.remove(hooks_file)
    else:
        with open(hooks_file, 'w') as f:
            json.dump(config, f, indent=2)
except OSError as exc:
    print(f"warning: failed to update {hooks_file}: {exc}", file=sys.stderr)
    sys.exit(1)

print("removed", file=sys.stderr)
PYEOF
        return $?
    else
        warn "python3 not available - cannot safely edit Codex hooks.json"
        warn "Please manually remove orca from $hooks_json"
        return 1
    fi
}

# Remove orca hook from Cursor IDE
unconfigure_cursor() {
    local hooks_json="$HOME/.cursor/hooks.json"
    local orca_hook_script="$HOME/.cursor/hooks/orca-pre-shell.py"
    local legacy_hook_script="$HOME/.cursor/hooks/orca-pre-shell.py"

    local removed=0

    # Remove hook scripts (orca and legacy orca)
    for hook_script in "$orca_hook_script" "$legacy_hook_script"; do
        if [ -f "$hook_script" ] && grep -qE 'orca-cursor-hook|orca-cursor-hook' "$hook_script" 2>/dev/null; then
            rm -f "$hook_script" 2>/dev/null && removed=1
        fi
    done

    # Remove entry from hooks.json (orca or legacy cursor hook path)
    if [ -f "$hooks_json" ] && { json_cursor_has_guard_hook "$hooks_json" "$orca_hook_script" ||         json_cursor_has_guard_hook "$hooks_json" "$legacy_hook_script"; }; then
        if command -v python3 >/dev/null 2>&1; then
            python3 - "$hooks_json" "$hook_script" <<'PYEOF'
import json
import os
import shlex
import sys

hooks_file = sys.argv[1]
expected_hook = sys.argv[2]

try:
    with open(hooks_file, "r") as f:
        settings = json.load(f)
except (IOError, ValueError, json.JSONDecodeError):
    sys.exit(0)

if not isinstance(settings, dict):
    sys.exit(0)

hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(0)

entries = hooks.get("beforeShellExecution")
if not isinstance(entries, list):
    sys.exit(0)

CURSOR_HOOK_PATHS = {
    os.path.expanduser("~/.cursor/hooks/orca-pre-shell.py"),
    os.path.expanduser("~/.cursor/hooks/orca-pre-shell.py"),
}

def is_guard_cursor_command(command):
    if not isinstance(command, str) or not command:
        return False
    try:
        parts = shlex.split(command)
    except ValueError:
        return False
    if not parts:
        return False
    cmd_path = parts[0]
    return cmd_path in CURSOR_HOOK_PATHS or cmd_path == expected_hook

new_entries = [
    entry for entry in entries
    if not (isinstance(entry, dict) and is_guard_cursor_command(entry.get("command")))
]
if len(new_entries) == len(entries):
    sys.exit(0)

if new_entries:
    hooks["beforeShellExecution"] = new_entries
else:
    hooks.pop("beforeShellExecution", None)

if not hooks:
    settings.pop("hooks", None)

if not settings or settings == {"version": 1}:
    os.remove(hooks_file)
else:
    with open(hooks_file, "w") as f:
        json.dump(settings, f, indent=2)

print("removed", file=sys.stderr)
PYEOF
            removed=1
        else
            warn "python3 not available - cannot safely edit Cursor hooks.json"
            warn "Please manually remove orca from $hooks_json"
            return 1
        fi
    fi

    [ "$removed" -eq 1 ] && return 0
    return 0
}

# Remove orca hook from Hermes Agent (~/.hermes/config.yaml)
unconfigure_hermes() {
    local cfg_file="$HOME/.hermes/config.yaml"

    if [ ! -f "$cfg_file" ]; then
        return 0
    fi

    if ! yaml_hermes_has_guard_hook "$cfg_file"; then
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not available - cannot safely edit Hermes config.yaml"
        warn "Please manually remove orca from $cfg_file"
        return 1
    fi
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        warn "python3 PyYAML not available - cannot safely edit Hermes config.yaml"
        warn "Please manually remove orca from $cfg_file"
        return 1
    fi

    python3 - "$cfg_file" <<'PYEOF'
import os
import shlex
import sys
import yaml

cfg_file = sys.argv[1]

GUARD_BIN_NAMES = frozenset({"orca", "orca"})

def is_guard_command(cmd):
    if not isinstance(cmd, str):
        return False
    try:
        parts = shlex.split(cmd)
    except ValueError:
        parts = cmd.split()
    if not parts:
        return False
    name = os.path.basename(parts[0])
    if name.endswith(".exe"):
        name = name[:-4]
    return name in GUARD_BIN_NAMES

try:
    with open(cfg_file, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
except (IOError, yaml.YAMLError):
    sys.exit(0)

if not isinstance(cfg, dict):
    sys.exit(0)
hooks = cfg.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(0)
pre_tool_call = hooks.get("pre_tool_call")
if not isinstance(pre_tool_call, list):
    sys.exit(0)

filtered = []
removed = False
for entry in pre_tool_call:
    if isinstance(entry, dict) and is_guard_command(entry.get("command")):
        removed = True
        continue
    filtered.append(entry)

if not removed:
    sys.exit(0)

if filtered:
    hooks["pre_tool_call"] = filtered
else:
    hooks.pop("pre_tool_call", None)
    if not hooks:
        cfg.pop("hooks", None)

# We do NOT touch `hooks_auto_accept` on uninstall: the user may have other
# hooks declared in this same file (per Hermes' shared config layout) that
# rely on auto-accept for non-TTY runs. Removing it would silently break
# their other integrations.

try:
    if not cfg:
        os.remove(cfg_file)
    else:
        with open(cfg_file, "w", encoding="utf-8") as f:
            yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
except OSError as exc:
    print(f"warning: failed to update {cfg_file}: {exc}", file=sys.stderr)
    sys.exit(1)

print("removed", file=sys.stderr)
PYEOF
    return $?
}

# Main uninstall function
main() {
    log "${BOLD}orca uninstaller${NC}"
    log ""

    # Find binary
    local binary
    binary=$(find_guard_binary)

    # Determine paths
    local config_dir="$HOME/.config/orca"
    local legacy_config_dir="$HOME/.config/orca"
    local data_dir="$HOME/.local/share/orca"
    local legacy_data_dir="$HOME/.local/share/orca"
    local claude_settings="$HOME/.claude/settings.json"
    local gemini_settings="$HOME/.gemini/settings.json"
    local aider_config="$HOME/.aider.conf.yml"
    local copilot_hook_file=""

    if command -v git >/dev/null 2>&1; then
        local repo_root=""
        repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
        if [ -n "$repo_root" ]; then
            copilot_hook_file="$repo_root/.github/hooks/orca.json"
            copilot_legacy_hook_file="$repo_root/.github/hooks/orca.json"
        fi
    fi

    # Show what will be removed
    log "The following will be removed:"
    log ""

    local found_anything=0
    local aider_configured=0

    # Agent hooks
    if json_settings_has_guard_command_hook "$claude_settings" "PreToolUse" "Bash"; then
        log "  • Claude Code hook ($claude_settings)"
        found_anything=1
    fi
    if json_settings_has_guard_command_hook "$gemini_settings" "BeforeTool"; then
        log "  • Gemini CLI hook ($gemini_settings)"
        found_anything=1
    fi
    if [ -f "$aider_config" ] && grep -qE 'Added by (orca|orca) installer' "$aider_config" 2>/dev/null; then
        log "  • Aider configuration ($aider_config)"
        found_anything=1
        aider_configured=1
    fi
    if { [ -n "$copilot_hook_file" ] && json_copilot_has_guard_hook "$copilot_hook_file"; } || \
       { [ -n "${copilot_legacy_hook_file:-}" ] && json_copilot_has_guard_hook "$copilot_legacy_hook_file"; }; then
        log "  • GitHub Copilot CLI hook ($copilot_hook_file)"
        found_anything=1
    fi
    local cursor_hooks_json="$HOME/.cursor/hooks.json"
    local cursor_orca_script="$HOME/.cursor/hooks/orca-pre-shell.py"
    local cursor_legacy_script="$HOME/.cursor/hooks/orca-pre-shell.py"
    if { [ -f "$cursor_orca_script" ] && grep -qE 'orca-cursor-hook|orca-cursor-hook' "$cursor_orca_script" 2>/dev/null; } || \
       { [ -f "$cursor_legacy_script" ] && grep -qE 'orca-cursor-hook|orca-cursor-hook' "$cursor_legacy_script" 2>/dev/null; } || \
       json_cursor_has_guard_hook "$cursor_hooks_json" "$cursor_orca_script" || \
       json_cursor_has_guard_hook "$cursor_hooks_json" "$cursor_legacy_script"; then
        log "  • Cursor IDE hook ($cursor_hooks_json)"
        found_anything=1
    fi
    local codex_hooks_json="$HOME/.codex/hooks.json"
    if json_settings_has_guard_command_hook "$codex_hooks_json" "PreToolUse" "Bash"; then
        log "  • Codex CLI hook ($codex_hooks_json)"
        found_anything=1
    fi
    local hermes_config="$HOME/.hermes/config.yaml"
    if yaml_hermes_has_guard_hook "$hermes_config"; then
        log "  • Hermes Agent hook ($hermes_config)"
        found_anything=1
    fi

    # Config
    if [ "$KEEP_CONFIG" -eq 0 ]; then
        for cfg in "$config_dir" "$legacy_config_dir"; do
            if [ -d "$cfg" ]; then
                log "  • Configuration directory ($cfg)"
                found_anything=1
            fi
        done
    fi

    # History
    if [ "$KEEP_HISTORY" -eq 0 ]; then
        for data in "$data_dir" "$legacy_data_dir"; do
            if [ -d "$data" ]; then
                log "  • History data ($data)"
                found_anything=1
            fi
        done
    fi

    # Binary
    if [ -n "$binary" ] && [ -f "$binary" ]; then
        log "  • Binary ($binary)"
        found_anything=1
    fi

    if [ "$found_anything" -eq 0 ]; then
        log "  ${DIM}Nothing to remove - orca/orca does not appear to be installed${NC}"
        return 0
    fi

    log ""

    # Confirmation
    if [ "$YES" -eq 0 ]; then
        # When invoked via `curl … | bash`, stdin is the pipe from curl, not
        # the user's terminal — `read` returns immediately with empty input
        # and the default "N" answer silently cancels the uninstall. Read
        # from /dev/tty instead so the curl-pipe-bash one-liner works.
        # If /dev/tty isn't available (e.g. CI), refuse with a clear message
        # rather than silently cancelling.
        printf "%bProceed with uninstall? [y/N]%b " "$YELLOW" "$NC"
        response=""
        if [ -r /dev/tty ]; then
            # `|| true` so Ctrl-D/EOF doesn't kill the script under `set -e`;
            # an empty response falls through the case below and cancels cleanly.
            read -r response < /dev/tty || true
        elif [ -t 0 ]; then
            read -r response || true
        else
            echo
            log "${YELLOW}Cannot read confirmation (no TTY available).${NC}"
            log "${YELLOW}Re-run with --yes to skip the prompt, e.g.:${NC}"
            log "    curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/uninstall.sh | bash -s -- --yes"
            return 1
        fi
        case "$response" in
            [yY]|[yY][eE][sS])
                ;;
            *)
                log "${YELLOW}Uninstall cancelled.${NC}"
                return 0
                ;;
        esac
    fi

    log ""

    # Remove Claude Code hook
    if unconfigure_claude_code 2>&1 | grep -q "removed"; then
        ok "Removed Claude Code hook"
    fi

    # Remove Gemini CLI hook
    if unconfigure_gemini 2>&1 | grep -q "removed"; then
        ok "Removed Gemini CLI hook"
    fi

    # Remove GitHub Copilot CLI hook (repo-local .github/hooks/orca.json)
    if unconfigure_copilot 2>&1 | grep -q "removed"; then
        ok "Removed GitHub Copilot CLI hook"
    fi

    # Remove Cursor IDE hook
    if unconfigure_cursor 2>&1 | grep -q "removed"; then
        ok "Removed Cursor IDE hook"
    fi

    # Remove Codex CLI hook
    if unconfigure_codex 2>&1 | grep -q "removed"; then
        ok "Removed Codex CLI hook"
    fi

    # Remove Hermes Agent hook
    if unconfigure_hermes 2>&1 | grep -q "removed"; then
        ok "Removed Hermes Agent hook"
    fi

    # Remove Aider config
    if [ "$aider_configured" -eq 1 ] && unconfigure_aider; then
        if [ ! -f "$aider_config" ] || ! grep -qE 'Added by (orca|orca) installer' "$aider_config" 2>/dev/null; then
            ok "Removed Aider configuration"
        fi
    fi

    # Remove config directory
    if [ "$KEEP_CONFIG" -eq 0 ]; then
        for cfg in "$config_dir" "$legacy_config_dir"; do
            if [ -d "$cfg" ]; then
                if rm -rf "$cfg" 2>/dev/null; then
                    ok "Removed configuration directory ($cfg)"
                else
                    warn "Failed to remove configuration directory ($cfg)"
                fi
            fi
        done
    fi

    # Remove data directory
    if [ "$KEEP_HISTORY" -eq 0 ]; then
        for data in "$data_dir" "$legacy_data_dir"; do
            if [ -d "$data" ]; then
                if rm -rf "$data" 2>/dev/null; then
                    ok "Removed history data ($data)"
                else
                    warn "Failed to remove history data ($data)"
                fi
            fi
        done
    fi

    # Remove binary
    if [ -n "$binary" ] && [ -f "$binary" ]; then
        if rm -f "$binary" 2>/dev/null; then
            ok "Removed binary"
        else
            warn "Failed to remove binary - you may need sudo"
            warn "  Run: sudo rm -f $binary"
        fi
    fi

    log ""
    log "${GREEN}${BOLD}Uninstall complete!${NC}"
    log "${DIM}Restart any AI coding agents for changes to take effect.${NC}"
}

main "$@"
