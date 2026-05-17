# Technical FAQ

## What MAVLink messages are supported?

A bounded subset including heartbeat/state, `COMMAND_LONG`, `COMMAND_INT`, `SET_MODE`, parameter safety toggles, setpoint targets, and generic mission upload messages.

## How are unknown MAVLink commands handled?

Unknown or unsupported high-risk commands fail conservatively and are not counted as successful coverage.

## How are sysid/compid policies handled?

Mapped MAVLink metadata is preserved for policy and audit context where the gateway supports it.

## How are coordinate frames handled?

Known frames are normalized for safety evaluation. Unknown frames are rejected or treated conservatively.

## How are altitude references handled?

Policies declare altitude references. Mismatched or missing references are findings.

## How is stale telemetry handled?

State freshness and watchdog policies can deny movement or high-risk commands.

## How does operator approval work?

Approvals are local, scoped, auditable, and time-bounded. CI mode never prompts.

## How are emergency modes prevented from bypassing policy?

Emergency LAND, RTH, and HOLD are evaluated by emergency policy and safety constraints.

## How are audit logs hashed?

Edge sessions use hash-chained event logs and replay verification under `.edge/sessions/`.

## How is redaction performed?

Sensitive payloads and endpoint query values are classified and redacted before persistence.

## How are safety-case reports generated?

`edge safety-case generate` or `edge proof generate --demo <id>` collects scenario evidence, replay status, policy hash, findings, and limitations.

## How are PX4 SITL tests gated?

PX4 SITL is opt-in. Missing SITL skips; fake-PX4 does not count as PX4 SITL success.

## How are ArduPilot SITL tests gated?

ArduPilot SITL is opt-in. Missing SITL skips; fake-ArduPilot does not count as ArduPilot SITL success.

## What runs in normal CI?

Fake/simulation fixtures, docs checks, policy validation, safety-case generation, replay verification, and red-team CI fixtures.

## What is opt-in?

PX4 SITL and ArduPilot SITL local simulator paths.

## What is unsupported?

Real flight, certification, detect-and-avoid, autopilot replacement, hosted telemetry, and real aircraft control.
