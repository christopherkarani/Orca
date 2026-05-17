# Edge ARM64

Linux ARM64 companion-computer style builds are represented by the `linux-arm64` target and artifact name:

```bash
zig build -Dtarget=aarch64-linux
```

Release artifacts use:

```text
edge-vX.Y.Z-linux-arm64.tar.gz
```

The artifact is for simulation, SITL, customer evaluation, and no-actuation bench preparation only.
It is not flight readiness, a flight controller, detect-and-avoid, autopilot replacement, or certification.

Before installing from a release artifact:

```bash
sha256sum -c checksums.txt
./scripts/install-edge.sh
```

No systemd service is enabled automatically. No telemetry or real secrets are required.
