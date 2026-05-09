# aegis-doctor

Check Aegis installation, policy status, host integration status, and plugin readiness.

## When to use

Use this skill when you want to verify that Aegis is properly installed, that a policy exists for the current repository, and that the Codex plugin integration is ready.

## Commands

Run the Aegis plugin doctor for Codex:

```bash
aegis plugin doctor codex
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
aegis init --preset codex
```

Then validate it:

```bash
aegis policy check .aegis/policy.yaml
```

### Missing Codex plugin install

If the plugin directory is not detected, ensure the Aegis repository includes `integrations/codex-plugin/` and that you are running from the workspace root.

### Follow-up diagnostics

If the doctor reports warnings:

1. Read the warning message carefully.
2. Fix missing policies or binaries.
3. Re-run `aegis plugin doctor codex` to confirm.
4. If issues persist, run `aegis doctor` for platform-specific capability notes.

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- The doctor output goes to stdout; errors go to stderr.
