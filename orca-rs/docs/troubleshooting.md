# Troubleshooting Guide

Common issues and how to resolve them.

## orca is not blocking anything

1. Confirm the hook is installed correctly.
2. Ensure the orca binary is on PATH.
3. Verify config loading (project/user/system) and pack enablement.

If available, run:
- `orca doctor` for a structured diagnostics report.

## Packs are not enabled

Check your config files in order:
- `.orca.toml` (project)
- `~/.config/orca/config.toml` (user)
- `/etc/orca/config.toml` (system)

Also verify environment overrides:
- `ORCA_PACKS`
- `ORCA_DISABLE`

## False positives (safe command blocked)

1. Add a safe allowlist entry (project or user).
2. If recurring, file a bug report with the exact command.
3. Add a test case to prevent regressions.

## False negatives (dangerous command allowed)

1. File a bug report with the exact command and context.
2. Add a destructive pattern + test case.
3. Update the pack’s safe pattern list to avoid over-broad allow rules.

## Hook errors or timeouts

For heredoc or large script parsing:
- Lower `max_body_bytes` or `max_body_lines`.
- Increase `timeout_ms` if needed.
- Ensure `fallback_on_parse_error` is true for hook mode.

## Performance concerns

If hook latency is high:
- Reduce enabled pack count.
- Disable expensive packs temporarily.
- Capture performance logs and open an issue.

## Reporting issues

When filing a report, include:
- The exact command
- Expected vs actual decision
- Your enabled packs list
- Relevant config snippets (redact secrets)
