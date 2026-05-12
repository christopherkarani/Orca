# Edge Release Artifacts

Phase 41 artifact names:

- `aegis-edge-v1.1.0-linux-amd64.tar.gz`
- `aegis-edge-v1.1.0-linux-arm64.tar.gz`
- shared `checksums.txt`
- `release-manifest.json`
- `sbom.json`
- `README-release.md`
- `known-limitations.md`

`linux-armv7` is unsupported unless a future release script explicitly adds and verifies it.
Every package should include `MANIFEST.yaml` and `SHA256SUMS`.

Verify:

```sh
cd dist
sha256sum -c checksums.txt
```

Required runtime assets include schemas, policies, examples, red-team fixtures, safety-case templates, customer proof docs, deployment profiles, demo scripts, runtime docs, and package manifests.

Aegis Edge artifacts are not real-flight readiness, not certification, not detect-and-avoid, and not autopilot replacement.
