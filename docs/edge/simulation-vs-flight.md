# Simulation Vs Flight

Aegis Edge Phase 30 evidence is simulation evidence.

`fake_adapter` means deterministic fake-PX4 or fake MAVLink input. It is useful for unit tests, policy regressions, and repeatable examples.

`fake_ardupilot_adapter` means deterministic fake-ArduPilot input. It is useful for unit tests, policy regressions, and repeatable ArduPilot examples.

`sitl_px4` means a local PX4 SITL process was intentionally enabled for integration testing. It is useful for simulator evidence and command-mediation checks.

`sitl_ardupilot` means a local ArduPilot SITL process was intentionally enabled for integration testing. It is useful for simulator evidence and command-mediation checks.

None of these environments is real flight. None proves airworthiness, detect-and-avoid, operational safety, or regulatory compliance. Do not connect Phase 30 commands to real drone hardware or use these artifacts as flight approval.
