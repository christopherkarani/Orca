# Data Exfil Deny Report

Provenance: fake_adapter
Scenario: data-exfil-deny
Decision: deny
policy_hash: sha256:example-data-policy-hash
Audit references: event-0301 data.egress_denied

## Findings

- Mission-plan data is high sensitivity.
- Webhook-like endpoint is classified as suspicious.
- Egress is denied and endpoint output is redacted.

## Limitations

This is simulation/SITL/bench-preparation evidence only. It is a non-certification example. No external network request is made.
