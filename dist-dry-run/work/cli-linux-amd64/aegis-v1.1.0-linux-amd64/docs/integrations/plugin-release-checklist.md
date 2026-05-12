# Plugin Release Checklist

Use this checklist before publishing any plugin release artifact.

## Build and tests

- [ ] zig build passes
- [ ] zig build test passes
- [ ] plugin security tests pass

## Packaging and artifact verification

- [ ] package plugins (`./scripts/package-plugins.sh`)
- [ ] verify checksums
- [ ] verify Codex plugin artifact contents
- [ ] verify Claude plugin artifact contents
- [ ] verify no secrets in artifacts
- [ ] verify no MCP config in artifacts
- [ ] verify no drone plugin files in artifacts

## Docs and release materials

- [ ] verify docs links work
- [ ] verify issue templates exist
- [ ] verify release notes exist
- [ ] verify launch demo exists
- [ ] verify known limitations are clear in docs
- [ ] verify README plugin section is present
- [ ] verify no overclaiming in docs

## Runtime smoke tests

- [ ] verify plugin doctor works for both hosts
- [ ] verify fake hook payloads work

## Practical verification notes

- Verify checksums against the generated plugin checksum file before publishing.
- Inspect the Codex and Claude zip contents to confirm only the expected manifest, skills, hooks, and README are present.
- Confirm the release artifact does not contain `.mcp.json`, drone-related plugin files, secrets, or other build leftovers.
- Run the host-specific doctor and hook smoke tests from the local build before tagging the release.
