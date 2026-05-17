# Edge Go-To-Market Package

This folder is the Phase 42 customer acquisition system for founder-led paid-pilot sales to commercial drone and autonomy teams.

Edge is positioned as a local simulation/SITL/bench-preparation safety-policy runtime for drone autonomy evaluation. It can mediate a bounded MAVLink command surface, evaluate safety envelopes, record audit/replay evidence, run deterministic red-team and fault-injection scenarios, and generate customer-readable safety-case evidence.

It is customer-evaluation material only. It does not include real flight, live aircraft control, certification, regulatory approval, detect-and-avoid, a replacement for PX4/ArduPilot or customer safety systems, or any guarantee of safety.

## Use This Package

1. Read [30-day plan](30-day-plan.md).
2. Build the first 50-account list using [targeting guidance](targeting/first-50-account-build-guide.md).
3. Score accounts with [ICP](icp.md), [qualification](qualification-framework.md), and [customer safety filter](targeting/customer-safety-filter.md).
4. Send manual founder-led outreach from [outreach](outreach/).
5. Run discovery and demo calls with [call scripts](calls/).
6. Offer tightly scoped pilots from [pilots](pilots/).
7. Track progress with [CRM](crm/) and [metrics](metrics/).
8. Keep all copy aligned with [safety claims guidance](safety/).

## Core Proof Bundle

- Demo: `./zig-out/bin/edge demo run geofence-deny`
- Demo suite: `./zig-out/bin/edge demo run all`
- Safety-case report: `./zig-out/bin/edge proof generate --demo geofence-deny`
- Red-team scorecard: `./zig-out/bin/edge redteam --ci`
- Customer pilot package: [customer_pilot](../customer_pilot/README.md)
- Customer proof package: [docs/edge/customer-proof](../docs/edge/customer-proof/README.md)

## Operating Rule

All customer work starts in fake adapter, PX4 SITL, ArduPilot SITL, or no-actuation bench-preparation contexts. Any customer asking for shortcuts around simulator-first evaluation, failsafes, certification claims, private-data collection, or live aircraft control should be disqualified or escalated before continuing.
