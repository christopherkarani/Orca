# Allow-Once: Temporary Exception Flow

This guide explains how to use the allow-once feature to temporarily override orca's blocking behavior for specific commands.

---

## Overview

When orca blocks a command, it prints a 6-digit numeric code that can be used to temporarily allow that exact command. This provides an escape hatch for false positives without permanently weakening your security policy.

**Key properties:**
- Exceptions are scoped to the exact command + directory (project root in git repos, cwd otherwise)
- Exceptions expire after 24 hours
- By default, exceptions are reusable until expiry
- All exceptions are logged for audit

---

## Example: Blocked Command Output

When orca blocks a command, you'll see output like this:

```
ALLOW-24H CODE: [123456] | run: orca allow-once 123456
Tip: orca explain "git reset --hard HEAD"

╭─────────────────────── COMMAND BLOCKED ────────────────────────╮
│                                                                 │
│  🛑 BLOCKED: Destructive command detected                      │
│                                                                 │
│  Pack: core.git                                                 │
│  Rule: reset-hard                                               │
│                                                                 │
│  Reason: git reset --hard discards uncommitted changes          │
│          and can cause irreversible data loss                   │
│                                                                 │
│  Command: git reset --hard HEAD                                 │
│                                                                 │
╰─────────────────────────────────────────────────────────────────╯
```

The first line contains the allow-once code (`123456` in this example).

---

## Allowing a Blocked Command

To allow the blocked command, run:

```bash
orca allow-once 123456
```

This creates a temporary exception that:
- Allows the exact command that was blocked
- Is scoped to the project root (if in a git repo) or current directory (otherwise)
- Expires after 24 hours
- Can be used multiple times until expiry

### Single-Use Exceptions

For a one-time exception that's consumed after the first use:

```bash
orca allow-once 123456 --single-use
```

This is more restrictive and recommended when you only need to run the command once.

---

## Expiry and Scope

### Time Limit

All allow-once exceptions expire after **24 hours** from creation. This cannot be changed.

### Directory Scope

Exceptions are scoped based on whether the command was blocked inside a git repository:

- **project scope** (automatic in git repos): If the blocked command was inside a git repository, the exception applies anywhere within that repository (root and all subdirectories).
- **cwd scope** (outside git repos): If blocked outside a git repository, the exception only applies in the exact directory where the command was blocked.

The scope is automatically determined—you cannot override it. This ensures exceptions are appropriately scoped: broad enough to be useful within a project, but not so broad that they leak across unrelated directories.

### Exact Command Match

The exception only applies to the **exact command text** that was blocked. Even minor differences (extra spaces, different arguments) will not match.

---

## Redaction and Security

### Default Behavior

By default, orca redacts potentially sensitive information from commands when displaying them:

```bash
orca allow-once list
# Shows: git clone https://***@github.com/...
```

### Viewing Raw Commands

To see the actual command text (useful for debugging), use `--show-raw`:

```bash
orca allow-once list --show-raw
# Shows: git clone https://token@github.com/...
```

**Security note:** Only use `--show-raw` in trusted environments. The raw command may contain tokens, passwords, or other sensitive data.

---

## Precedence and Force Override

### Normal Allow-Once

A standard allow-once exception overrides pack-based denials but does **not** override explicit blocklist entries in your config file (`.orca.toml` or `~/.config/orca/config.toml`).

### Force Override

If you've explicitly blocked a command in your config and need to override it, use `--force`:

```bash
orca allow-once 123456 --force
```

This requires additional confirmation because:
1. You explicitly added the block to your config
2. Overriding it may indicate a mistake or policy conflict
3. The action is logged for audit purposes

---

## Managing Exceptions

### List Active Exceptions

To see pending codes and active allow-once entries:

```bash
orca allow-once list
```

Add `--show-raw` to see unredacted commands:

```bash
orca allow-once list --show-raw
```

### Revoke an Exception

To revoke a pending code or active exception:

```bash
orca allow-once revoke 123456
```

You can also revoke by full hash (useful when multiple codes collide):

```bash
orca allow-once revoke 0123abcd...
```

### Clear All Exceptions

To clear expired entries:

```bash
orca allow-once clear
```

To wipe all pending codes:

```bash
orca allow-once clear --pending
```

To wipe all active allow-once entries:

```bash
orca allow-once clear --allow-once
```

To wipe everything:

```bash
orca allow-once clear --all
```

---

## Command Reference

### Basic Usage

```bash
orca allow-once <CODE>              # Apply an allow-once code
orca allow-once <CODE> --single-use # Apply as one-time exception
orca allow-once <CODE> --force      # Override config blocklist
orca allow-once <CODE> --dry-run    # Preview without applying
```

### Management Commands

```bash
orca allow-once list                # List pending and active entries
orca allow-once list --show-raw     # List with unredacted commands
orca allow-once revoke <CODE>       # Revoke a specific exception
orca allow-once clear               # Clear expired entries
orca allow-once clear --all         # Wipe all entries
```

### Collision Handling

When multiple blocked commands share the same short code, you must disambiguate:

```bash
orca allow-once 123456 --pick 1       # Select by index (1-based)
orca allow-once 123456 --hash 0123... # Select by full hash
```

Without disambiguation, the CLI will show a list of matching entries to choose from.

### Additional Flags

| Flag | Description |
|------|-------------|
| `--yes`, `-y` | Auto-confirm (non-interactive) |
| `--json` | Output JSON for automation |
| `--show-raw` | Show unredacted command text |
| `--dry-run` | Preview without applying |
| `--single-use` | Consumed after first allow |
| `--force` | Override config blocklist |
| `--pick <N>` | Select by index when codes collide |
| `--hash <HASH>` | Select by full hash when codes collide |

---

## Logging and Audit

All allow-once actions are logged:

- **Pending code creation**: Logged when a command is blocked
- **Exception application**: Logged when `orca allow-once` is run
- **Exception consumption**: Logged when a single-use exception is used
- **Exception expiry**: Logged when entries are pruned

Enable verbose logging for detailed audit trails:

```bash
ORCA_VERBOSE=1 orca allow-once 123456
```

Log files are stored in `~/.config/orca/orca.log` by default (configurable).

---

## Storage Locations

| File | Purpose |
|------|---------|
| `~/.config/orca/pending_exceptions.jsonl` | Pending codes from blocked commands |
| `~/.config/orca/allow_once.jsonl` | Active allow-once entries |

These can be overridden with environment variables:
- `ORCA_PENDING_EXCEPTIONS_PATH`
- `ORCA_ALLOW_ONCE_PATH`

---

## Optional HMAC Hardening

Set `ORCA_ALLOW_ONCE_SECRET` to harden short-code generation with HMAC-SHA256.
This prevents attackers (or tooling) from forging valid short codes without the secret.

Trade-offs:
- **Security**: stronger, tamper-resistant short codes.
- **Recoverability**: if the secret changes or is lost, previously issued codes will no longer resolve.
  Re-run the blocked command to generate a new code under the new secret.

Keep the secret stable within the environment where you expect to resolve codes.

---

## Best Practices

1. **Use `--single-use` for one-off operations** - Prefer single-use exceptions when you only need to run a command once.

2. **Review before applying** - Use `orca explain "<command>"` to understand why the command was blocked before allowing it.

3. **Use `--force` sparingly** - If you find yourself frequently needing `--force`, consider updating your config blocklist instead.

4. **Monitor logs** - Periodically review allow-once activity for security auditing.

5. **Clear old entries** - Run `orca allow-once clear` periodically to remove expired entries.

---

## Troubleshooting

### "Code not found or expired"

The short code may have expired (24-hour limit) or been revoked. Re-run the blocked command to generate a new code.

### "Code matches multiple entries"

Use `--pick <N>` or `--hash <HASH>` to disambiguate:

```bash
orca allow-once 123456 --pick 1
```

### "Cannot override config blocklist without --force"

The blocked command is in your config blocklist. Add `--force` if you're certain:

```bash
orca allow-once 123456 --force
```

### Permissions Error

Ensure you have write access to `~/.config/orca/`. The allow-once stores are user-scoped by default.
