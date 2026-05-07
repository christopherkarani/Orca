# Packaging

Phase 19 package templates live under:

- `homebrew/aegis.rb`
- `scoop/aegis.json`
- `winget/aegis.yaml`
- `npm/package.json`
- `docker/Dockerfile`

Templates use release version metadata and placeholder checksums until release automation fills them from `dist/checksums.txt`. License fields remain pending until the project owner records the final license in `LICENSE`.
