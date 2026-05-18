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
- Secretless runtime availability, broker-reference mode, service-policy templates, verification commands, guarantees, and limitations
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

## Secretless View

The Secretless tab is an operator surface for the optional Secretless Agent Runtime.

It includes:

- Active broker status and whether raw secrets are stored or injected
- Credential reference rows derived from policy without raw values
- Broker check cards for configured brokers
- Proxy backend status, bind behavior, and HTTPS host/port-only limitation
- A generated `orca run --secretless --network-backend proxy -- <agent-command>` command
- A GitHub service-policy template covering hosts, methods, allowed paths, denied paths, credential references, and `unmatched: deny`
- Fixed verification actions for credential checks, proxy smoke, policy check/explain, and replay verification
- A capability matrix for env replacement, broker checks, service policy, proxy backend, and transparent-interception status
- Broker extension-point cards for local dummy, Infisical / Agent Vault, 1Password CLI, macOS Keychain, and env-file development brokers
- Recent secret redaction and proxy request-level audit events from `.orca/sessions`
- Guarantees and limitations so the UI does not imply vault behavior or transparent network interception

The generated command is copied or shown for terminal use. The dashboard does not execute arbitrary agent commands from the browser. The service-policy template can be inserted into the policy editor, but it is not persisted until the user clicks **Validate and save** and Orca accepts the YAML.

The dashboard’s fixed actions are allowlisted server-side: `credentials-check`, `credentials-check-github`, `proxy-smoke`, `policy-check`, `policy-explain-github`, `replay-last`, and the existing operational checks. `proxy-smoke` starts a local Orca proxy instance and forwards a fixed localhost request through it to verify forwarding plus request-level decision capture. Unsupported action IDs are rejected.

Mutation routes require a per-run browser token embedded in the dashboard page and the server rejects non-localhost bindings by default.

## Security Notes

Use `orca doctor` as the source of truth for platform capability claims. The dashboard should describe controls as active, limited, wrapper-only, observe-only, or unavailable based on Orca state; it must not imply transparent sandboxing or enforcement that Orca does not provide.
