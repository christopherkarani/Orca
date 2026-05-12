# Simulation Vs Flight

Aegis Edge Phase 31 evidence is fake-adapter, PX4 SITL, ArduPilot SITL, or bench-preparation evidence only.

`fake_adapter` means deterministic fake-PX4 or fake MAVLink input. It is useful for unit tests, policy regressions, and repeatable examples.

`fake_ardupilot_adapter` means deterministic fake-ArduPilot input. It is useful for unit tests, policy regressions, and repeatable ArduPilot examples.

`sitl_px4` means a local PX4 SITL process was intentionally enabled for integration testing. It is useful for simulator evidence and command-mediation checks.

`sitl_ardupilot` means a local ArduPilot SITL process was intentionally enabled for integration testing. It is useful for simulator evidence and command-mediation checks.

Phase 32 operator approval and emergency-mode behavior remains simulation/SITL/bench-preparation evidence only. Operator approval does not make unsafe commands safe, and emergency mode does not bypass policy, autopilot failsafes, human authority, detect-and-avoid requirements, or regulatory obligations.

None of these environments is real flight. None proves airworthiness, detect-and-avoid, operational safety, or regulatory compliance. Do not connect Phase 31 commands to real drone hardware or use these artifacts as flight approval.

Aegis Edge is not a flight controller and does not replace autopilot failsafes. SITL evidence is useful for deterministic regression testing, not real-flight validation.
Aegis Edge Phase 33 safety-case reports preserve the same boundary: fake adapter evidence, PX4 SITL evidence, ArduPilot SITL evidence, and bench-preparation evidence are reported separately and never as real-flight validation.

Missing SITL is reported as skipped or unsupported, not passed. Generated reports and bundles include a non-certification disclaimer and a `Real flight: Not performed` evidence row.

Phase 36 deployment profiles and bench-readiness reports preserve the same boundary. `hardware_bench_no_actuation` is not flight mode, not SITL, not real-flight readiness, and not certification.

Phase 34 red-team evidence preserves the same boundary. Red-team fixtures are
synthetic and deterministic. They test safety-control behavior in fake adapter
and optional SITL contexts, but they do not prove real-world operational safety,
airworthiness, certification, detect-and-avoid, or autopilot replacement
behavior.
## Phase 37 Health Boundary

Runtime health and watchdog checks are bounded to fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation/customer-evaluation contexts. They provide local evidence about stale state, missing heartbeats, audit failures, and degraded modes.

They are not real-flight readiness, not an autopilot replacement, not detect-and-avoid, and not regulatory certification.
