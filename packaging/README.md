# Packaging

Production package templates live under:

- `homebrew/Formula/orca.rb`
- `scoop/orca.json`
- `winget/orca.yaml`
- `npm/package.json`
- `docker/Dockerfile`
- `edge/Dockerfile`
- `systemd/edge.service`
- `systemd/edge-bench.example.service`
- `systemd/edge-sitl.service`

Templates use release version metadata and remain fail-closed while they contain placeholder checksums. Release automation renders publishable Homebrew, npm, Scoop, and WinGet manifests into `dist/package-manifests/` from `dist/checksums.txt`; `scripts/verify-release.sh` fails if rendered manifests are missing or still contain placeholders. The project license is Apache-2.0.

Edge packaging is for local simulation/SITL/bench-preparation evaluation only. Package templates must not add credentials, hosted telemetry, privileged container defaults, real hardware endpoint defaults, real-flight deployment, certification claims, detect-and-avoid claims, or autopilot replacement behavior.
