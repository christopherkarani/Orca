# Local Dashboard

Orca includes a local-first web dashboard for day-to-day inspection and setup.

```sh
orca dashboard
```

By default it listens only on:

```text
http://127.0.0.1:7742
```

The dashboard is a local control surface over existing Orca behavior. It does not replace the CLI, does not evaluate policy in frontend code, and does not add hosted telemetry, accounts, cloud sync, or external services.

## What It Shows

- Orca version and workspace root
- Local license tier, report-export availability, and offline verification status
- CI readiness from the same checks as `orca ci check`
- `.orca/policy.yaml` presence, mode, and validation status
- Productized policy packs that initialize through Orca policy code
- OpenClaw and Hermes setup cards with exact local commands
- Recent `.orca/sessions` entries
- Denied actions from replay artifacts
- Event type, target, decision, policy context, rule/reason when recorded, and hash-chain verification status

## Local Actions

The browser can run only fixed Orca actions:

```sh
orca doctor
orca policy check .orca/policy.yaml
orca plugin doctor openclaw
orca plugin doctor hermes
orca replay --session last --only denied --verify
orca report --session last --format markdown
orca ci check --format markdown
orca demo blocked-action
orca license status
```

Policy edits are saved only after Orca parses and validates the submitted YAML. Preset initialization writes `.orca/policy.yaml` from the same preset text used by the CLI.

Mutation routes require a per-run browser token embedded in the dashboard page and the server rejects non-localhost bindings by default.

## Security Notes

Use `orca doctor` as the source of truth for platform capability claims. The dashboard should describe controls as active, limited, wrapper-only, observe-only, or unavailable based on Orca state; it must not imply transparent sandboxing or enforcement that Orca does not provide.
