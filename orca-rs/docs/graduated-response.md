# Design: Graduated Response System

## Status: DRAFT
**Author:** ChartreuseStone
**Date:** 2026-01-19
**Bead:** git_safety_guard-2at5
**Epic:** E10 (git_safety_guard-yejh)
**Reviewed:** Pending

---

## 1. Executive Summary

This design specifies a graduated response system that replaces the current
binary allow/deny behavior with context-aware escalation levels. The system
tracks command occurrences within sessions and across session history, enabling
more nuanced responses based on pattern frequency and user behavior.

Key features:
- Three response levels: WARNING, SOFT_BLOCK, HARD_BLOCK
- Four graduation modes: paranoid, strict, standard, lenient
- Session-scoped occurrence tracking (resets on new shell)
- Cross-session history tracking (persisted, time-windowed)
- Severity-based overrides (critical patterns always hard block)

---

## 2. Response Levels

### 2.1 WARNING

**Behavior:**
- Command is **allowed to proceed**
- Warning message displayed to stderr
- Event logged to history
- Designed for first occurrence in a session

**Output format (stderr):**
```
⚠️  orca WARNING: This command matches a destructive pattern

Pattern:  core.git:reset-hard
Severity: high
Command:  git reset --hard HEAD~1

This is occurrence 1/2 in this session. Command will proceed.
Use --quiet to suppress warnings.
```

**JSON output (stdout):**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "responseLevel": "warning",
    "sessionOccurrence": 1,
    "sessionThreshold": 2,
    "ruleId": "core.git:reset-hard",
    "warningMessage": "Command matches destructive pattern"
  }
}
```

### 2.2 SOFT_BLOCK

**Behavior:**
- Command is **blocked initially**
- User can confirm to proceed (interactive mode)
- Requires explicit "yes" confirmation, no auto-bypass
- Triggered after session threshold exceeded

**Output format (stderr):**
```
🛑 orca SOFT BLOCK: Command requires confirmation

Pattern:  core.git:reset-hard
Severity: high
Command:  git reset --hard HEAD~1

This is occurrence 3 in this session (threshold: 2).
History: 2 occurrences in last 24h (threshold: 5).

To proceed, use: orca confirm <code>
Code: 7f3a
```

**JSON output (stdout):**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "responseLevel": "soft_block",
    "sessionOccurrence": 3,
    "sessionThreshold": 2,
    "historyOccurrence": 2,
    "historyThreshold": 5,
    "confirmCode": "7f3a",
    "ruleId": "core.git:reset-hard",
    "remediation": {
      "confirmCommand": "orca confirm 7f3a",
      "safeAlternative": "git stash"
    }
  }
}
```

### 2.3 HARD_BLOCK

**Behavior:**
- Command is **blocked with no override**
- User must add pattern to allowlist or use `orca allow-once`
- Triggered when history threshold exceeded
- Always used in "paranoid" mode
- Always used for critical severity patterns (configurable)

**Output format (stderr):**
```
🚫 orca HARD BLOCK: Command blocked (threshold exceeded)

Pattern:  core.git:reset-hard
Severity: high
Command:  git reset --hard HEAD~1

This command has been blocked 6 times in the last 24h (threshold: 5).
Direct confirmation is not available for this command.

Options:
  1. Add to allowlist: orca allowlist add core.git:reset-hard --project
  2. Allow once:       orca allow-once <code>
  3. Review history:   orca history core.git:reset-hard

Code: 9b2e
```

**JSON output (stdout):**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "responseLevel": "hard_block",
    "sessionOccurrence": 4,
    "historyOccurrence": 6,
    "historyThreshold": 5,
    "allowOnceCode": "9b2e",
    "ruleId": "core.git:reset-hard",
    "remediation": {
      "allowOnceCommand": "orca allow-once 9b2e",
      "allowlistCommand": "orca allowlist add core.git:reset-hard --project"
    }
  }
}
```

---

## 3. Graduation Modes

Graduation modes define how quickly responses escalate from WARNING to HARD_BLOCK.

### 3.1 Mode Definitions

| Mode | Behavior | Use Case |
|------|----------|----------|
| `paranoid` | Always HARD_BLOCK | Current behavior, maximum safety |
| `strict` | WARNING → SOFT_BLOCK → HARD_BLOCK | High-security environments |
| `standard` | WARNING → WARNING → SOFT_BLOCK → HARD_BLOCK | Balanced default |
| `lenient` | WARNING (repeating) → SOFT_BLOCK (never hard) | Development/experimentation |

### 3.2 Graduation Curves

```
Occurrence:     1       2       3       4       5       6+
─────────────────────────────────────────────────────────────
paranoid:      HARD    HARD    HARD    HARD    HARD    HARD
strict:        WARN    SOFT    HARD    HARD    HARD    HARD
standard:      WARN    WARN    SOFT    SOFT    HARD    HARD
lenient:       WARN    WARN    WARN    SOFT    WARN    WARN...
```

### 3.3 Mode Selection Logic

```rust
fn select_response_level(
    mode: GraduationMode,
    session_count: u32,
    history_count: u32,
    session_threshold: u32,
    history_threshold: u32,
    severity: Severity,
    critical_always_hard: bool,
) -> ResponseLevel {
    // Critical severity override
    if severity == Severity::Critical && critical_always_hard {
        return ResponseLevel::HardBlock;
    }

    match mode {
        GraduationMode::Paranoid => ResponseLevel::HardBlock,

        GraduationMode::Strict => {
            if history_count >= history_threshold {
                ResponseLevel::HardBlock
            } else if session_count >= session_threshold {
                ResponseLevel::SoftBlock
            } else {
                ResponseLevel::Warning
            }
        }

        GraduationMode::Standard => {
            if history_count >= history_threshold {
                ResponseLevel::HardBlock
            } else if session_count >= session_threshold {
                ResponseLevel::SoftBlock
            } else {
                ResponseLevel::Warning
            }
        }

        GraduationMode::Lenient => {
            // Lenient never hard blocks (except critical override above)
            if session_count >= session_threshold {
                ResponseLevel::SoftBlock
            } else {
                ResponseLevel::Warning
            }
        }
    }
}
```

---

## 4. Configuration Schema

### 4.1 Configuration File

Location: `~/.config/orca/config.toml` (user) or `.orca/config.toml` (project)

```toml
[response]
# Graduation mode: paranoid, strict, standard, lenient
mode = "standard"

# Session tracking (resets on new shell)
session_threshold = 2  # Soft block after this many in session

# History tracking (cross-session persistence)
history_threshold = 5  # Hard block after this many in history window
history_window = "24h" # Lookback period for history (e.g., "1h", "24h", "7d")

# Severity overrides
critical_always_hard = true  # Critical severity bypasses graduation
high_minimum_level = "warning"  # Minimum level for high severity

# Behavior flags
show_warnings = true           # Display warning messages
quiet_after_threshold = false  # Suppress repeated warnings
log_warnings = true            # Log warnings to history
```

### 4.2 Environment Variable Overrides

```bash
ORCA_RESPONSE_MODE=strict       # Override mode
ORCA_SESSION_THRESHOLD=3        # Override session threshold
ORCA_HISTORY_THRESHOLD=10       # Override history threshold
ORCA_CRITICAL_ALWAYS_HARD=false # Disable critical override
```

### 4.3 CLI Flags

```bash
orca --mode=paranoid            # Temporary mode override
orca --no-warnings              # Suppress warning output
orca --session-threshold=1      # Override for this invocation
```

### 4.4 Configuration Merge Order

Priority (highest to lowest):
1. CLI flags
2. Environment variables
3. Project config (`.orca/config.toml`)
4. User config (`~/.config/orca/config.toml`)
5. System config (`/etc/orca/config.toml`)
6. Built-in defaults

---

## 5. State Machine

### 5.1 Decision Flow

```
                                    ┌─────────────────────┐
                                    │   Command Input     │
                                    └──────────┬──────────┘
                                               │
                                               ▼
                                    ┌─────────────────────┐
                                    │  Pattern Matching   │
                                    └──────────┬──────────┘
                                               │
                              ┌────────────────┼────────────────┐
                              │                │                │
                              ▼                ▼                ▼
                        ┌───────────┐   ┌───────────┐   ┌───────────┐
                        │   Safe    │   │ Unmatched │   │Destructive│
                        │  Pattern  │   │  Pattern  │   │  Pattern  │
                        └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
                              │               │               │
                              ▼               ▼               ▼
                           ALLOW           ALLOW     ┌────────────────┐
                                                     │ Load Session   │
                                                     │ & History      │
                                                     └───────┬────────┘
                                                             │
                                                             ▼
                                                     ┌────────────────┐
                                                     │ Check Critical │
                                                     │ Override       │
                                                     └───────┬────────┘
                                                             │
                              ┌───────────────yes────────────┤
                              │                              │no
                              ▼                              ▼
                         HARD_BLOCK              ┌────────────────────┐
                                                 │ Apply Graduation   │
                                                 │ Mode Logic         │
                                                 └──────────┬─────────┘
                                                            │
                              ┌──────────────┬──────────────┼──────────────┐
                              │              │              │              │
                              ▼              ▼              ▼              ▼
                           WARNING      SOFT_BLOCK     HARD_BLOCK      ALLOW
                              │              │              │        (lenient)
                              ▼              ▼              ▼
                        ┌───────────┐  ┌───────────┐  ┌───────────┐
                        │ Increment │  │ Increment │  │ Increment │
                        │ Counters  │  │ Counters  │  │ Counters  │
                        │ Log Event │  │ Log Event │  │ Log Event │
                        └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
                              │              │              │
                              ▼              ▼              ▼
                           PROCEED        PROMPT         BLOCK
                                         CONFIRM
```

### 5.2 State Transitions

```
┌─────────┐      session_count < session_threshold      ┌─────────┐
│  NEW    │ ──────────────────────────────────────────► │ WARNING │
│ COMMAND │                                             │  STATE  │
└────┬────┘                                             └────┬────┘
     │                                                       │
     │  session_count >= session_threshold AND               │ command
     │  history_count < history_threshold                    │ allowed
     │                                                       ▼
     │                                                  ┌─────────┐
     └──────────────────────────────────────────────►  │SOFT_BLOCK│
     │                                                  │  STATE  │
     │                                                  └────┬────┘
     │                                                       │
     │  history_count >= history_threshold                   │ user
     │                                                       │ confirms
     │                                                       ▼
     │                                                  ┌─────────┐
     └──────────────────────────────────────────────►  │HARD_BLOCK│
                                                       │  STATE  │
                                                       └─────────┘
```

---

## 6. Session Tracking

### 6.1 Session Identification

Sessions are identified by a combination of:
- Shell process ID (PPID of orca process)
- Terminal device (TTY)
- Session start timestamp

```rust
struct SessionId {
    ppid: u32,
    tty: Option<String>,
    start_ts: DateTime<Utc>,
}
```

### 6.2 Session Store

Location: `/tmp/orca-sessions/<session_hash>.json`

Format:
```json
{
  "session_id": "abc123...",
  "ppid": 12345,
  "tty": "/dev/pts/1",
  "start_ts": "2026-01-19T10:00:00Z",
  "last_active": "2026-01-19T10:30:00Z",
  "occurrences": {
    "core.git:reset-hard": 2,
    "core.filesystem:rm-rf-general": 1
  }
}
```

### 6.3 Session Lifecycle

- **Creation:** First destructive command in a new shell
- **Update:** Increment pattern counters on each match
- **Expiry:** Sessions auto-expire after 24h of inactivity
- **Cleanup:** Prune expired sessions on startup

---

## 7. History Tracking

### 7.1 History Store

Location: `~/.config/orca/history.jsonl`

Each line represents a single event:
```json
{
  "schema_version": 1,
  "timestamp": "2026-01-19T10:30:00Z",
  "rule_id": "core.git:reset-hard",
  "pack_id": "core.git",
  "severity": "high",
  "response_level": "warning",
  "session_id": "abc123...",
  "cwd": "/home/user/project",
  "command_hash": "sha256:...",
  "allowed": true
}
```

### 7.2 History Queries

```rust
fn count_history(
    rule_id: &str,
    window: Duration,
    cwd: Option<&Path>,  // Optional scope to directory
) -> u32
```

### 7.3 History Maintenance

- Auto-prune entries older than `max_history_age` (default: 30d)
- Configurable max history size (default: 10000 entries)
- Prune on startup and periodically during long sessions

---

## 8. Soft Block Confirmation Flow

### 8.1 Confirmation Code

Generated same as allow-once codes (see design-allow-once-short-code.md):
```
short_code = sha256("<timestamp> | <cwd> | <command_raw>")[-4:]
```

### 8.2 Confirmation Command

```bash
orca confirm <code>
```

Behavior:
- Valid for 5 minutes (short-lived)
- Scope: exact command + cwd
- Single-use (consumed on use)
- Stores in pending_confirmations.jsonl

### 8.3 Confirmation Store

Location: `~/.config/orca/pending_confirmations.jsonl`

```json
{
  "schema_version": 1,
  "short_code": "7f3a",
  "full_hash": "sha256:...",
  "created_at": "2026-01-19T10:30:00Z",
  "expires_at": "2026-01-19T10:35:00Z",
  "cwd": "/home/user/project",
  "command_hash": "sha256:...",
  "rule_id": "core.git:reset-hard",
  "consumed_at": null
}
```

---

## 9. Integration with Existing Features

### 9.1 Allow-Once Codes

Allow-once bypasses graduation entirely:
- If command has a valid allow-once exception, skip graduation checks
- Response level is implicitly ALLOW
- Still logged to history (with `allowed: true, via: "allow-once"`)

### 9.2 Allowlist

Allowlisted patterns bypass graduation entirely:
- Check allowlist before graduation
- Response level is implicitly ALLOW
- Not logged to history (no tracking needed)

### 9.3 Explain Command

`orca explain` shows graduation status:
```
$ orca explain "git reset --hard HEAD~1"

Pattern:    core.git:reset-hard
Pack:       core.git
Severity:   high
Status:     Would be blocked (SOFT_BLOCK)

Graduation info:
  Mode:              standard
  Session count:     3
  Session threshold: 2
  History count:     2
  History threshold: 5
  History window:    24h

Recommendation: This command has been used 3 times this session.
                Consider adding to allowlist if this is expected workflow.
```

---

## 10. CLI Commands

### 10.1 New Commands

```bash
# View response configuration
orca config response

# View session state
orca session [--json]

# View history for a pattern
orca history <rule_id> [--window=24h] [--json]

# Clear session state (restart graduation)
orca session clear

# Confirm a soft-blocked command
orca confirm <code>
```

### 10.2 Modified Commands

```bash
# Stats includes graduation info
orca stats [--graduation]

# Explain shows graduation state
orca explain "<command>"
```

---

## 11. Backward Compatibility

### 11.1 Default Behavior

Default mode is `standard`, which differs from current `paranoid` behavior.
To preserve existing behavior:

```toml
[response]
mode = "paranoid"
```

### 11.2 Migration

On first run with new version:
1. Check if config exists
2. If no `[response]` section, add with `mode = "paranoid"` comment
3. Log message about new graduation feature

---

## 12. Security Considerations

### 12.1 Session Hijacking

Mitigations:
- Session ID includes TTY and PPID
- Session files have 0600 permissions
- Session directory in /tmp with restricted access

### 12.2 History Tampering

Mitigations:
- History file has 0600 permissions
- JSONL append-only for concurrent writes
- Fail-open on corruption (safety over tracking)

### 12.3 Confirmation Code Prediction

Mitigations:
- Codes include high-entropy timestamp
- 5-minute expiry limits attack window
- Single-use prevents replay

---

## 13. Testing Plan

### 13.1 Unit Tests

- Response level selection logic for all modes
- Session counter increment/decrement
- History query with time windows
- Configuration merge order
- Confirmation code generation and validation

### 13.2 Integration Tests

- Full graduation flow (WARNING → SOFT_BLOCK → HARD_BLOCK)
- Session persistence across orca invocations
- History accumulation and pruning
- Allow-once/allowlist bypass
- Critical severity override

### 13.3 E2E Tests

Add to `scripts/e2e_test.sh`:
```bash
# Graduation mode tests
test_graduation_warning_first_occurrence
test_graduation_soft_block_session_threshold
test_graduation_hard_block_history_threshold
test_graduation_paranoid_always_hard
test_graduation_lenient_never_hard
test_graduation_critical_override
```

---

## 14. Implementation Tasks

See dependent beads:
- **git_safety_guard-4kcu**: [E10-T2] Implement occurrence tracking (session state)
- **git_safety_guard-8sjj**: [E10-T3] Implement cross-session tracking via history
- **git_safety_guard-tmob**: [E10-T5] Add graduation config options

---

## 15. Open Questions

1. **Session expiry behavior**: Should sessions expire after shell exit or time-based only?
2. **Project-scoped graduation**: Should graduation counters be per-project or global?
3. **Pack-level configuration**: Should modes be configurable per-pack?
4. **Confirmation TTY requirement**: Should soft block confirmation require TTY?

---

## Appendix A: Default Configuration

```toml
[response]
mode = "standard"
session_threshold = 2
history_threshold = 5
history_window = "24h"
critical_always_hard = true
high_minimum_level = "warning"
show_warnings = true
quiet_after_threshold = false
log_warnings = true

[history]
max_age = "30d"
max_entries = 10000
prune_on_startup = true
```

---

## Appendix B: Response Level Enum

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResponseLevel {
    /// Command allowed with warning message
    Warning,
    /// Command blocked, user can confirm to proceed
    SoftBlock,
    /// Command blocked, no direct override available
    HardBlock,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GraduationMode {
    Paranoid,
    Strict,
    Standard,
    Lenient,
}
```

---

## Appendix C: JSON Schema

See `docs/json-schema/hook-output.json` for the complete JSON schema including
new graduation-related fields.
