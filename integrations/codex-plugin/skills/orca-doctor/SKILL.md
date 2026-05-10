# orca-doctor

Check Orca installation, policy status, host integration status, and plugin readiness.

## When to use

Use this skill when you want to verify that Orca is properly installed, that a policy exists for the current repository, and that the Codex plugin integration is ready.

## Commands

Run the Orca plugin doctor for Codex:

```bash
orca plugin doctor codex
```

Run the general Orca doctor for platform capabilities:

```bash
orca doctor
```

## Interpreting results

### Missing Orca binary

If `orca` is not found in PATH, install Orca first. Build from source with Zig 0.15.2:

```bash
zig build
```

The binary will be at `./zig-out/bin/orca`.

### Missing policy

If `.orca/policy.yaml` is missing, initialize one:

```bash
orca init --preset codex
```

Then validate it:

```bash
orca policy check .orca/policy.yaml
```

### Missing Codex plugin install

If the plugin directory is not detected, ensure the Orca repository includes `integrations/codex-plugin/` and that you are running from the workspace root.

### Follow-up diagnostics

If the doctor reports warnings:

1. Read the warning message carefully.
2. Fix missing policies or binaries.
3. Re-run `orca plugin doctor codex` to confirm.
4. If issues persist, run `orca doctor` for platform-specific capability notes.

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- The doctor output goes to stdout; errors go to stderr.
