# Security Review Response Template

This is a draft technical-response template. Customer security and legal teams should review the final answers before sharing.

## Does Aegis Edge require cloud connectivity?

No. Normal customer pilot evaluation is local and offline.

## Does it send telemetry externally?

No hosted telemetry is required for the pilot. Data guard examples evaluate local payload and endpoint fixtures.

## Where are logs stored?

Local run artifacts are written under the configured local output path, commonly `.aegis-edge/`. The pilot report should list the exact path used.

## How are secrets redacted?

Pilot materials instruct customers not to provide real secrets. Redaction examples use synthetic placeholders and local data guard checks.

## What data does it persist?

Local audit events, replay summaries, safety reports, red-team scorecards, policy hashes, scenario hashes, and limitations.

## Does it require real secrets?

No. Use placeholders only.

## Does it require privileged access?

Normal pilot package review and fake adapter evaluation do not require privileged access. Any local simulator setup should be reviewed separately by the customer.

## What platforms are supported?

The pilot package targets local development and evaluation workflows already supported by the Aegis Edge build and CLI. Deployment targets should be confirmed with the current Edge deployment docs.

## What are the limitations?

No real flight, no live aircraft control, no certification, no regulatory approval, no detect-and-avoid, no autopilot replacement, and bounded MAVLink coverage.

## How does audit verification work?

Audit events are written locally and replay verifies hash-chain continuity. The evidence bundle records the final hash and replay status.

## How are vulnerability reports handled?

Use the agreed customer pilot contact path and include reproduction steps, affected version, local artifact paths, and whether any sensitive data was involved. Do not send real secrets in the report.
