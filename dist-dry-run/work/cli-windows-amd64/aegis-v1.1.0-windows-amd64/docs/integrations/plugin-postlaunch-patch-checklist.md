# Plugin Post-Launch Patch Checklist

Use this checklist for hotfixes after a plugin release ships. Keep the patch local-first, narrow, and verifiable.

## First 24-hour triage process

- Confirm the report with host, plugin version, Aegis version, OS, architecture, and install method.
- Reproduce the issue against the released artifact and, if needed, the repo checkout.
- Decide whether the issue is security, install, host compatibility, docs, or release packaging.
- Ask for a minimal, redacted bug report before requesting any broader logs.
- If the issue is P0 or P1, stop normal release work and route the fix immediately.

## First 72-hour triage process

- Land the smallest fix that addresses the bug.
- Add or update deterministic tests, fixtures, or release checks.
- Run build, test, packaging, and smoke verification locally.
- Update docs if the failure came from unclear install or compatibility guidance.
- Decide whether to cut `vX.Y.1` or hold for a broader release only if the fix is not yet verified.

## When to cut vX.Y.1 criteria

- The shipped release is broken in a user-facing way.
- The fix is narrow, backward-compatible, and locally verifiable.
- The patch does not add new features or widen scope.
- The patch closes a security issue, install failure, hook failure, or host compatibility regression.
- The artifact, checksum, and notes can all be updated together.

## Security patch criteria

- Secret leakage or redaction failure.
- Unsafe decision downgrade.
- Hook output corrupts host protocol.
- A false security claim is present in docs or release materials.
- Any fix must preserve local-first behavior and no telemetry by default.

## Install bug patch criteria

- Plugin install fails or extracts to the wrong path.
- Hooks do not fire after install.
- `plugin doctor` and real install state disagree.
- Marketplace install or local-path install is broken.
- The fix can be validated with the same host and artifact path that failed.

## Docs patch criteria

- The install or verification steps are confusing.
- Compatibility notes are stale or incomplete.
- Known limitations are not stated clearly enough.
- The docs overstate what the plugin can do.
- The patch only needs documentation changes, not artifact changes.

## Host compatibility patch criteria

- A host version changes hook names, event payloads, install paths, or plugin loading behavior.
- Codex and Claude behavior diverge in a way the docs do not explain.
- The issue is a host integration mismatch, not an Aegis policy bug.
- The patch can be described with a version note or a host-specific workaround.

## Release rollback notes

- If a released artifact is wrong, mark it superseded and publish a corrected patch release.
- Update checksums and release notes together.
- Tell users how to uninstall and reinstall from a local artifact or source checkout.
- Do not keep a broken or unsafe artifact available just because the docs are already published.

## What data to collect without telemetry

- Aegis version and plugin version.
- Host name, host version, OS, and architecture.
- Install method and install path.
- Exact command or hook event.
- Expected behavior and actual behavior.
- Redacted stdout and stderr.
- Artifact name or checksum if a release zip was used.
- Minimal reproduction steps or fixture data.

## How to ask users for bug reports safely

Ask for the smallest redacted report that still reproduces the issue. Use a template like this:

```text
Host:
Host version:
Aegis version:
Plugin version or artifact name:
Install method:
Steps to reproduce:
Expected result:
Actual result:
Redacted stdout/stderr:
Relevant environment details:
```

Tell users not to include tokens, API keys, private prompts, private file contents, or full logs that contain secrets.

## No telemetry by default

Aegis plugins are local-first and do not collect telemetry by default. Support and patch triage should rely on user-provided bug reports and local environment details only.
