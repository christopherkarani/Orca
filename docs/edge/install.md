# Edge Install

## Supported Artifacts

- `edge-v1.1.0-linux-amd64.tar.gz`
- `edge-v1.1.0-linux-arm64.tar.gz`

`linux-armv7`, macOS standalone Edge packages, Windows standalone Edge packages, real hardware services, and auto-enabled daemons are unsupported in this release.

## Build From Source

```sh
zig build
./zig-out/bin/edge version --json
./zig-out/bin/edge deployment assets
```

## Install From Artifact

```sh
./scripts/build-release.sh
cd dist
sha256sum -c checksums.txt
tar -xzf edge-v1.1.0-linux-arm64.tar.gz
```

Use `shasum -a 256 -c checksums.txt` where `sha256sum` is unavailable.

## Runtime Assets

Edge artifacts must include schemas, policies, examples, red-team fixtures, safety-case templates, customer proof docs, deployment profiles, demo scripts, runtime docs, and package manifests.

## Safety Boundary

Edge is fake/SITL/customer-evaluation and bench-preparation only. It is not real-flight readiness, not a flight controller, not detect-and-avoid, not certification, and not autopilot replacement. No telemetry is enabled by default and no real secrets are required.
