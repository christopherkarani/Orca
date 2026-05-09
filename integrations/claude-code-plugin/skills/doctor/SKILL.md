# doctor

Check Aegis installation, policy status, host integration status, and plugin readiness.

## When to use

Use this skill when you want to verify that Aegis is properly installed, that a policy exists for the current repository, and that the Claude Code plugin integration is ready.

## Commands

Run the Aegis plugin doctor for Claude Code:

```bash
aegis plugin doctor claude
```

Run the general Aegis doctor for platform capabilities:

```bash
aegis doctor
```

## Interpreting results

### Missing Aegis binary

If `aegis` is not found in PATH, install Aegis first. Build from source with Zig 0.15.2:

```bash
zig build
```

The binary will be at `./zig-out/bin/aegis`.

### Missing policy

If `.aegis/policy.yaml` is missing, initialize one:

```bash
aegis init --preset claude-code
```

If the `claude-code` preset is not available, use the closest plugin-safe preset:

```bash
aegis init --preset generic-agent
```

Then validate it:

```bash
aegis policy check .aegis/policy.yaml
```

### Missing Claude Code plugin install

If the plugin directory is not detected, ensure the Aegis repository includes `integrations/claude-code-plugin/` and that you are running from the workspace root.

### Follow-up diagnostics

If the doctor reports warnings:

1. Read the warning message carefully.
2. Fix missing policies or binaries.
3. Re-run `aegis plugin doctor claude` to confirm.
4. If issues persist, run `aegis doctor` for platform-specific capability notes.

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- The doctor output goes to stdout; errors go to stderr.
