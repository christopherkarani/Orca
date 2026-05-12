# Aegis v1.1.0

## Summary

This release prepares Aegis CLI and Aegis Edge artifacts for local production distribution. Aegis Edge is limited to simulation/SITL/customer-evaluation and bench-preparation evidence.

## Highlights

- Aegis CLI v1.1.0 local policy, redaction, audit/replay, and red-team workflow.
- Aegis Edge MAVLink gateway, PX4 SITL, ArduPilot SITL, safety enforcement, operator approvals, emergency modes, data guard, runtime health, audit/replay, red-team, and safety-case evidence.
- Release manifest, `checksums.txt`, SBOM inventory hook, package templates, install instructions, known limitations, and customer pilot materials.

## Install

Download the matching archive and `checksums.txt`, then verify before installing:

```sh
sha256sum -c checksums.txt
```

CLI examples:

```sh
aegis version --json
aegis doctor
```

Edge examples:

```sh
aegis-edge version --json
aegis-edge deployment assets
aegis-edge docs check
```

## Aegis Edge safety boundary

Aegis Edge is not a flight controller. It is not real-flight readiness, certification, detect-and-avoid, autopilot replacement, regulatory approval, or a guarantee that every unsafe action is blocked. PX4 and ArduPilot support is local simulation/SITL only unless a future phase explicitly changes that boundary.

## Known limitations

See `known-limitations.md` and `docs/edge/known-limitations.md`.

## Security disclosure

Do not file public issues containing secrets. Use the process in `SECURITY.md` for sensitive reports.

## Customer pilot note

The included customer pilot package is a local evaluation bundle with legal templates marked for review. It contains no real customer names, secrets, pricing commitments, or real-flight instructions.
