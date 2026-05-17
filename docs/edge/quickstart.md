# Edge Quickstart

This quickstart uses local fake/SITL/bench-preparation artifacts only. Do not connect real aircraft or real control links.

## Build From Source

```sh
zig build
```

## Check The Runtime

```sh
./zig-out/bin/edge doctor
./zig-out/bin/edge docs check
```

## Run The Fake Geofence Demo

```sh
./zig-out/bin/edge demo run geofence-deny
```

Expected result: A waypoint outside the configured geofence is denied and the output points to sample safety-report and replay artifacts.

## Run The Red-Team Suite

```sh
./zig-out/bin/edge redteam --ci
```

Required fake/simulation fixtures must pass. Optional SITL fixtures skip when local SITL is not explicitly enabled.

## Generate A Safety-Case Report

```sh
./zig-out/bin/edge proof generate --demo geofence-deny
```

The generated safety-case report includes provenance, limitations, policy hash, command decisions, findings, and hash-chain verification status.

## Inspect Replay

```sh
./zig-out/bin/edge replay --session last --verify
```

Replay verifies the local hash chain for the most recent Edge session.

## Optional PX4 SITL

PX4 SITL is opt-in local simulation evidence. Fake-PX4 fixtures are not PX4 SITL evidence.

```sh
./zig-out/bin/edge px4 doctor
```

## Optional ArduPilot SITL

ArduPilot SITL is opt-in local simulation evidence. Fake-ArduPilot fixtures are not ArduPilot SITL evidence.

```sh
./zig-out/bin/edge ardupilot doctor
```

## Next Docs

- [Customer proof](customer-proof/README.md)
- [Capability matrix](capability-matrix.md)
- [Troubleshooting](troubleshooting.md)
