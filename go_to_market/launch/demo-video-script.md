# Demo Video Script

## Title

Aegis Edge: unsafe drone-agent command denied with replayable safety evidence

## Opening

"This is Aegis Edge, a local safety-policy and audit runtime for autonomous drone agent evaluation in simulation, SITL, and bench-preparation workflows."

## Boundary

"This demo is not aircraft operation, certification, approval, detect-and-avoid, or replacement of the customer's safety process."

## Scene 1: Architecture

Show the agent/planner, Aegis Edge policy runtime, MAVLink-style bridge, audit/replay store, red-team harness, and safety-case report.

## Scene 2: Unsafe Command

Run:

```sh
./zig-out/bin/aegis-edge demo run geofence-deny
```

Say: "The agent attempts a command outside the allowed geofence. Aegis denies it."

## Scene 3: Proof

Run:

```sh
./zig-out/bin/aegis-edge proof generate --demo geofence-deny
```

Say: "The report shows provenance, policy decision, replay reference, and limitations."

## Scene 4: Red-Team

Run:

```sh
./zig-out/bin/aegis-edge redteam --ci
```

Say: "The red-team scorecard makes passed, failed, skipped, unsupported, and inconclusive outcomes explicit."

## CTA

"I am looking for 3 drone/autonomy design partners with simulation or SITL workflows. If this maps to your stack, book a 20-minute technical call."
