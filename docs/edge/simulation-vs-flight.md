# Simulation Vs Flight

Aegis Edge Phase 29 evidence is simulation evidence.

`fake_adapter` means deterministic fake-PX4 or fake MAVLink input. It is useful for unit tests, policy regressions, and repeatable examples.

`sitl_px4` means a local PX4 SITL process was intentionally enabled for integration testing. It is useful for simulator evidence and command-mediation checks.

Neither environment is real flight. Neither environment proves airworthiness, detect-and-avoid, operational safety, or regulatory compliance. Do not connect Phase 29 commands to real drone hardware or use these artifacts as flight approval.
