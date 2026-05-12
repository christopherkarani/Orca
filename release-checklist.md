# Aegis v1.1.0 Release Checklist

- [ ] `zig build`
- [ ] `zig build test`
- [ ] `aegis redteam --ci`
- [ ] `aegis-edge redteam --ci`
- [ ] `aegis-edge docs check`
- [ ] demo and proof commands pass
- [ ] safety-case report generation passes
- [ ] audit/replay verification passes
- [ ] release artifacts generated
- [ ] `checksums.txt` generated and verified
- [ ] `sbom.json` generated with hook-only status or replaced by complete SBOM
- [ ] signing status recorded honestly
- [ ] package manifests reviewed
- [ ] runtime assets included
- [ ] known limitations included
- [ ] safety boundary prominent
- [ ] customer pilot materials reviewed
- [ ] docs overclaim scan reviewed
- [ ] risk register reviewed
- [ ] release blockers resolved or documented
- [ ] approval to tag

Boundary: Aegis Edge is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement.
