# aegis-init

Create or repair an Aegis policy for the current repository.

## When to use

Use this skill when starting a new project, when `.aegis/policy.yaml` is missing, or when you want to reset to a known-good policy preset.

## Commands

Initialize an Aegis policy with the Codex preset:

```bash
aegis init --preset codex
```

Validate the resulting policy:

```bash
aegis policy check .aegis/policy.yaml
```

## Preset fallback

If the `codex` preset is not available in your Aegis build, use the closest plugin-safe preset:

```bash
aegis init --preset generic-agent
```

Or, for stricter defaults:

```bash
aegis init --preset strict-local
```

The `generic-agent` preset is a conservative starting point for local coding agents. Review the generated `.aegis/policy.yaml` before trusting it.

## Safety rules

- **Do not silently overwrite** `.aegis/policy.yaml`. If a policy already exists, review it first.
- If you need to recreate it, back up the old file:
  ```bash
  cp .aegis/policy.yaml .aegis/policy.yaml.bak
  ```
- Always run `aegis policy check` after creating or editing a policy.

## Notes

- This skill modifies only `.aegis/policy.yaml` in the current workspace.
- No host configuration is changed.
- No telemetry is sent.
- The generated policy does not contain real secrets.
