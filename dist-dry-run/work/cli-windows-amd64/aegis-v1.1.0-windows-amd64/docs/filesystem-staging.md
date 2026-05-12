# Filesystem Staging

Staged writes let users review Aegis-mediated file changes before applying them.

```sh
./zig-out/bin/aegis diff --session last
./zig-out/bin/aegis apply --session last --file path/to/file
./zig-out/bin/aegis discard --session last
```

## Layout

Session directories may include:

- `staged/`
- `original/`
- `staging-index.json`
- `events.jsonl`
- `summary.json`
- `summary.md`

## Protections

Aegis normalizes paths, records original hashes where feasible, verifies staged blob hashes before apply, and denies protected paths such as `.git/**`, `.aegis/**`, `.env`, SSH keys, and cloud credentials according to policy.

## Symlink And Traversal Notes

Path traversal and symlink escape attempts are treated as security-sensitive and covered by tests. Review diffs before applying staged writes.

## Current Interception Limitations

Staging applies to Aegis-mediated writes. It is not universal transparent filesystem interception unless the platform backend reports active support.

## Platform Notes

macOS and Windows currently document transparent filesystem enforcement as limited. Linux v1.1.0 reports transparent filesystem enforcement as unavailable by default; future backends may provide stronger controls when active OS restrictions are installed.
