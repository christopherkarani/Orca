# Aegis Edge

Aegis Edge is a local policy, safety-envelope, MAVLink mediation, audit, red-team, and evidence runtime for drone autonomy evaluation in fake adapter, SITL, and bench-preparation environments.

For design-partner evaluation, see [customer_pilot/README.md](../../customer_pilot/README.md). The customer pilot package keeps the same no real-flight boundary as the Edge docs and examples.

Phase 28 adds a MAVLink gateway foundation for fake/in-memory simulation and protocol mediation. Later completed phases add PX4 SITL, ArduPilot SITL, safety enforcement, operator approval, audit/replay, safety-case evidence, red-team fixtures, data guard, deployment/bench diagnostics, and runtime health. Aegis Edge is not ready for real flight, provides no real-flight readiness, is not regulatory certification, and is not autopilot replacement behavior.

## What It Is

Aegis Edge sits between autonomous agents or companion planners and control bridges. It evaluates command requests against policy, safety envelope constraints, operator approval rules, emergency-mode policy, telemetry freshness, data guard rules, and runtime health before a command is forwarded in simulation-oriented contexts.

Use it to demonstrate:

- MAVLink command mediation through a bounded gateway.
- Safety-envelope evaluation for geofence, altitude, velocity, battery, state freshness, and mission items.
- Scoped and auditable operator approvals.
- Emergency LAND, RTH, and HOLD decisions that still pass through policy.
- Red-team and fault-injection fixtures for fake/SITL contexts.
- Replayable hash-chained audit logs and safety-case evidence.
- Telemetry/data egress classification, denial, and redaction.
- Runtime health and watchdog findings for simulation/SITL/bench-preparation evidence.

## What It Is Not

Aegis Edge is not a flight controller. Aegis Edge is not an autopilot replacement. It does not replace PX4 or ArduPilot. It is not detect-and-avoid. It is not regulatory approval, airworthiness approval, certification, BVLOS authorization, or proof that an aircraft is safe for flight.

## Supported Environments

- `fake_adapter`: deterministic local fake transport and fake vehicle state.
- `PX4 SITL`: opt-in local simulator evidence, separate from fake-PX4 fixtures.
- `ArduPilot SITL`: opt-in local simulator evidence, separate from fake-ArduPilot fixtures.
- `hardware_bench_no_actuation`: bench-preparation checks with explicit no-actuation and no-real-flight boundaries.

## Unsupported Environments

- Real flight.
- Real aircraft control.
- Certification or regulatory approval.
- Detect-and-avoid.
- Autopilot replacement behavior.
- Hosted telemetry service or external network dependency.

## Quickstart

```sh
zig build
./zig-out/bin/aegis-edge version --json
./zig-out/bin/aegis-edge doctor
./zig-out/bin/aegis-edge demo list
./zig-out/bin/aegis-edge demo run geofence-deny
./zig-out/bin/aegis-edge proof generate --demo geofence-deny
./zig-out/bin/aegis-edge pilot checklist
./zig-out/bin/aegis-edge pilot package
./zig-out/bin/aegis-edge pilot demo
./zig-out/bin/aegis-edge docs check
./zig-out/bin/aegis-edge review run
```

Release install docs: `docs/edge/install.md` and `docs/edge/release-artifacts.md`. Verify `checksums.txt` before installing any artifact.

## Demo Commands

```sh
./zig-out/bin/aegis-edge demo list
./zig-out/bin/aegis-edge demo run geofence-deny
./zig-out/bin/aegis-edge demo run all
./zig-out/bin/aegis-edge proof generate --demo geofence-deny
./zig-out/bin/aegis-edge pilot checklist
./zig-out/bin/aegis-edge pilot package
./zig-out/bin/aegis-edge pilot demo
examples/edge/demos/run-all.sh
scripts/edge-demo.sh
```

The default demo sequence shows an agent requesting a waypoint outside a geofence, a denied `disable_failsafe`, an allowed policy-controlled LAND, denied/redacted mission-data egress, stale telemetry causing conservative behavior, a generated safety-case report, and replay hash-chain verification.

## Red-Team Commands

```sh
./zig-out/bin/aegis-edge redteam validate
./zig-out/bin/aegis-edge redteam --ci
./zig-out/bin/aegis-edge redteam --category geofence
./zig-out/bin/aegis-edge redteam --category data-guard
./zig-out/bin/aegis-edge redteam --report safety-case
```

## Safety-Case And Replay Commands

```sh
./zig-out/bin/aegis-edge safety-case generate --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/geofence-deny.yaml
./zig-out/bin/aegis-edge safety-case show --session last
./zig-out/bin/aegis-edge replay --session last --verify
```

## Capability Overview

- MAVLink gateway: parses and maps a bounded subset of MAVLink messages in fake transport and opt-in SITL paths.
- PX4 SITL: local simulation evidence only; fake-PX4 is labeled separately.
- ArduPilot SITL: local simulation evidence only; fake-ArduPilot is labeled separately.
- Flight-safety enforcement: geofence, mission, altitude, velocity, battery, freshness, mode, authority, and command-risk checks for evaluation contexts.
- Operator approval: local, scoped, auditable approvals; CI mode never prompts.
- Data guard: classifies payloads/endpoints, denies suspicious egress, and redacts before persistence.
- Runtime health/watchdog: evaluates stale heartbeats, stale telemetry, audit health, queue depth, timeout, and degraded behavior.

## Limitations

Aegis Edge covers only supported command/message/policy surfaces. Unknown or unsupported results are not counted as passes. SITL evidence is not flight evidence. Bench-preparation evidence is no-actuation evidence. Customers must validate their own airframe, autopilot, hardware, operator procedures, communications links, and integration-specific safety analysis.

## Safety Boundary

All Phase 38 examples are customer-evaluation artifacts. They are deterministic, local, fake/SITL/bench-preparation only, and designed to make the current product understandable without implying flight readiness.

## Links

- [Edge docs hub](../../docs/edge/README.md)
- [Quickstart](../../docs/edge/quickstart.md)
- [Architecture](../../docs/edge/architecture.md)
- [Capability matrix](../../docs/edge/capability-matrix.md)
- [Customer proof](../../docs/edge/customer-proof/README.md)
- [Customer pilot package](../../customer_pilot/README.md)
- [Troubleshooting](../../docs/edge/troubleshooting.md)
