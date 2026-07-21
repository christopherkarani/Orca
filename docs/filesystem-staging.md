# Filesystem Staging

Staged writes let users review Orca-mediated file changes before applying them.

```sh
./zig-out/bin/orca diff --session last
./zig-out/bin/orca apply --session last --file path/to/file
./zig-out/bin/orca discard --session last
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

Orca normalizes paths, records original hashes where feasible, verifies staged blob hashes before apply, and denies protected paths such as `.git/**`, `.orca/**`, `.env`, SSH keys, and cloud credentials according to policy.

## Symlink And Traversal Notes

Path traversal and symlink escape attempts are treated as security-sensitive and covered by tests. Review diffs before applying staged writes.

## Current Interception Limitations

Staging applies to Orca-mediated writes. It is not universal transparent filesystem interception. OS FS isolation is **session-attach** only: claimable after `orca run --os-sandbox` child apply succeeds for that run — doctor capability probes alone are not a live session claim.

## Platform Notes

- **Linux:** staged writes always; Landlock session-attach when ABI ≥ 1 (kernel 5.13+) via `orca run --os-sandbox auto|on|off` (default `auto`). CI attach evidence: linux amd64.
- **macOS:** staged writes always; Seatbelt session-attach on product majors 14–26 (capability gate) via the same `--os-sandbox` flag. CI attach evidence: macos-14; other majors local until freeze jobs cover them.
- **Windows:** transparent filesystem enforcement remains limited; no Landlock/Seatbelt-equivalent attach path yet.

See [platform-linux.md](platform-linux.md), [platform-macos.md](platform-macos.md), and [compatibility.md](compatibility.md#protection-grades-canonical).
