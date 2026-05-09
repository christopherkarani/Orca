# SITL Red-Team Fixtures

PX4 and ArduPilot red-team fixtures are opt-in SITL evidence. They are skipped
by default and are not counted as fake-adapter passes.

SITL red-team evidence is not real-flight readiness, certification,
detect-and-avoid, autopilot replacement behavior, or regulatory approval.

List SITL fixtures:

```sh
aegis-edge redteam list --environment px4_sitl
aegis-edge redteam list --environment ardupilot_sitl
```

Run a filtered view:

```sh
aegis-edge redteam --environment px4_sitl
aegis-edge redteam --environment ardupilot_sitl
```

If the local SITL environment is unavailable, the result is `skipped`, not
`passed`. Fake-PX4 and fake-ArduPilot evidence remains fake evidence; PX4 SITL
and ArduPilot SITL evidence remains SITL evidence; neither is real-flight
evidence.

SITL red-team fixtures cover waypoint/geofence denial, disable-failsafe-like
denial, LAND/RTL policy logging, unknown command fail-closed behavior, and stale
telemetry denial. They produce artifacts when run, but those artifacts are still
simulation evidence.
