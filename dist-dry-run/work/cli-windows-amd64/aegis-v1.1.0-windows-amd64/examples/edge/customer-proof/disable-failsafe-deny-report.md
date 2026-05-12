# Disable Failsafe Deny Report

Provenance: fake_adapter
Scenario: disable-failsafe-deny
Decision: deny
policy_hash: sha256:example-disable-failsafe-policy-hash
Audit references: event-0101 safety.command_denied

## Findings

- `disable_failsafe` is a denied command.
- Deny beats allow.

## Limitations

This is simulation/SITL/bench-preparation evidence only. It is a non-certification example and does not validate all vehicle modes.
