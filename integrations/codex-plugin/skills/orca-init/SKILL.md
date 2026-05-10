# orca-init

Create or repair an Orca policy for the current repository.

## When to use

Use this skill when starting a new project, when `.orca/policy.yaml` is missing, or when you want to reset to a known-good policy preset.

## Commands

Initialize an Orca policy with the Codex preset:

```bash
orca init --preset codex
```

Validate the resulting policy:

```bash
orca policy check .orca/policy.yaml
```

## Preset fallback

If the `codex` preset is not available in your Orca build, use the closest plugin-safe preset:

```bash
orca init --preset generic-agent
```

Or, for stricter defaults:

```bash
orca init --preset strict-local
```

The `generic-agent` preset is a conservative starting point for local coding agents. Review the generated `.orca/policy.yaml` before trusting it.

## Safety rules

- **Do not silently overwrite** `.orca/policy.yaml`. If a policy already exists, review it first.
- If you need to recreate it, back up the old file:
  ```bash
  cp .orca/policy.yaml .orca/policy.yaml.bak
  ```
- Always run `orca policy check` after creating or editing a policy.

## Notes

- This skill modifies only `.orca/policy.yaml` in the current workspace.
- No host configuration is changed.
- No telemetry is sent.
- The generated policy does not contain real secrets.
