# Noninteractive CI Mode

CI and red-team modes never prompt. Any `ask` or operator-approval-required decision is converted to `deny`, and Edge records `operator.ask_denied_noninteractive`.

This fail-closed behavior prevents headless jobs from silently approving flight-affecting commands. Use deterministic pre-seeded approval data only in simulation tests that explicitly validate expiry, scope, policy hash, state hash, command hash, and provenance.

No external network, cloud approval service, SaaS workflow, mobile app, or real hardware is required.
