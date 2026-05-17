# Demo Call Script

## 1. State Safety Boundary

Say: "This demo is local customer-evaluation evidence only. It uses fake adapter or simulator workflows and does not operate aircraft, certify anything, provide approval, or replace your safety process."

Do not say: "This proves aircraft readiness."

## 2. Show Edge Architecture

Say: "Edge sits between the autonomy agent/planner and a supported command bridge. It evaluates policy, records decisions, supports replay, runs red-team scenarios, and generates safety-case evidence."

Artifact references:

- `docs/edge/customer-proof/edge-technical-brief.md`
- `customer_pilot/pilot-overview.md`
- `examples/edge/customer-proof/capability-matrix.md`

## 3. Run Geofence-Deny Demo

Command:

```sh
./zig-out/bin/edge demo run geofence-deny
```

Expected output: denial of a waypoint outside configured geofence.

Say: "The planner asks for movement outside the policy envelope. Aegis denies the command and records why."

Artifact paths:

- `examples/edge/demos/01-geofence-deny/sample-safety-report.md`
- `examples/edge/demos/01-geofence-deny/sample-replay-output.md`
- `.edge/sessions/<session-id>/`

Follow-up: "Do you have a similar geofence or operating-area rule independent of the planner?"

## 4. Run Disable-Failsafe-Deny Demo

Command:

```sh
./zig-out/bin/edge demo run disable-failsafe-deny
```

Expected output: denial of a safety-critical failsafe modification.

Say: "Aegis treats failsafe-disabling commands as policy-governed and auditable."

Do not say: "Aegis takes over failsafes."

Artifact paths:

- `examples/edge/demos/02-disable-failsafe-deny/sample-safety-report.md`

Follow-up: "Which mode or parameter changes are forbidden in your stack?"

## 5. Run Emergency LAND Demo

Command:

```sh
./zig-out/bin/edge demo run emergency-land
```

Expected output: emergency LAND allowed/logged according to policy.

Say: "Emergency commands are still evaluated and logged, including policy context."

Artifact paths:

- `examples/edge/demos/03-emergency-land/sample-safety-report.md`

Follow-up: "Which emergency actions must always remain available, and what state must be fresh?"

## 6. Run Stale Telemetry Deny Demo

Command:

```sh
./zig-out/bin/edge demo run stale-telemetry-deny
```

Expected output: movement denied because telemetry is stale.

Say: "Aegis fails closed when the state needed to evaluate movement is stale."

Artifact paths:

- `examples/edge/demos/04-stale-telemetry-deny/sample-safety-report.md`

Follow-up: "What freshness thresholds matter for position, battery, link, and vehicle mode?"

## 7. Run Data-Exfil Deny/Redact Demo

Command:

```sh
./zig-out/bin/edge demo run data-exfil-deny
```

Expected output: telemetry or mission data egress denied/redacted by data guard.

Say: "The data guard can evaluate unknown endpoint and sensitive telemetry egress in supported local scenarios."

Do not say: "Aegis sends telemetry to a hosted service."

Artifact paths:

- `examples/edge/demos/07-data-exfil-deny/sample-safety-report.md`
- `examples/edge/customer-proof/data-exfil-deny-report.md`

Follow-up: "Which telemetry, video, mission, or location fields are sensitive in your workflow?"

## 8. Show Replay

Command:

```sh
./zig-out/bin/edge replay --session last --verify
```

Expected output: replay verification succeeds for the latest local session when artifacts exist.

Say: "Replay gives a deterministic audit trail for evaluated scenarios."

Do not say: "Replay proves the real world matched the simulation."

## 9. Show Safety-Case Report

Command:

```sh
./zig-out/bin/edge proof generate --demo geofence-deny
```

Expected output: local safety-case evidence paths.

Say: "The report records provenance, policy decision, replay reference, and limitations."

Artifact paths:

- `.edge/sessions/<session-id>/safety-report.md`
- `.edge/sessions/<session-id>/safety-report.json`
- `.edge/sessions/<session-id>/evidence/`
- `examples/edge/customer-proof/geofence-deny-safety-report.md`

## 10. Show Red-Team Scorecard

Command:

```sh
./zig-out/bin/edge redteam --ci
```

Expected output: deterministic red-team scorecard with passed, failed, skipped, unsupported, or inconclusive results.

Say: "Skipped and unsupported results are not passes; they are scope and roadmap evidence."

Artifact paths:

- `examples/edge/customer-proof/redteam-scorecard.md`
- `examples/edge/customer-proof/redteam-scorecard.json`

## 11. Map To Their Workflow

Ask:

- Which scenario maps most closely to your current workflow?
- Which command would you most want to block or audit?
- What simulator or fake-adapter path could we use for a two-week pilot?
- Which report would be useful to your customer, operator, or internal review?
