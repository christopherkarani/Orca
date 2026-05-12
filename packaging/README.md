# Packaging

Phase 19 root package templates and Phase 36+ Edge package templates live under:

- `homebrew/aegis.rb`
- `scoop/aegis.json`
- `winget/aegis.yaml`
- `npm/package.json`
- `docker/Dockerfile`
- `aegis-edge/Dockerfile`
- `systemd/aegis-edge.service`
- `systemd/aegis-edge-bench.example.service`
- `systemd/aegis-edge-sitl.service`

Templates use release version metadata and placeholder checksums until release automation fills them from `dist/checksums.txt`. License fields remain pending until the project owner records the final license in `LICENSE`.

Aegis Edge packaging is for local simulation/SITL/bench-preparation evaluation only. Package templates must not add credentials, hosted telemetry, privileged container defaults, real hardware endpoint defaults, real-flight deployment, certification claims, detect-and-avoid claims, or autopilot replacement behavior.
