# macOS Platform

Run:

```sh
./zig-out/bin/orca doctor
```

Current macOS local output reports process supervision, env filtering, staged writes, MCP stdio proxy, network decision engine, and audit/replay as active.

## Capability Matrix

| Feature | Status |
|---|---|
| Process supervision | active |
| Env filtering | active |
| Staged writes | active |
| Shell/PATH shims | wrapper-only |
| MCP stdio proxy | active |
| Network decision engine | active |
| Network observation | observe-only |
| Transparent network enforcement | limited |
| Transparent file enforcement | limited; Seatbelt session-attach when available |
| Strong sandbox | session-attach via Seatbelt on product majors 14–26; otherwise unavailable |

## OS filesystem sandbox (`orca run`)

`orca run --os-sandbox auto|on|off` (default `auto`) can attach a custom Seatbelt (SBPL) filesystem boundary to the agent child:

- **Probe ≠ session-attach.** Doctor strong-sandbox / API-presence reports are capability evidence only. Doctor never reports a live session as `active` from a probe alone.
- **Session-attach** is claimable only after apply-before-exec child attach succeeds for that run (with a profile hash).
- **FS scope (Seatbelt):** full workspace subpath RW minus control-root carve-outs (create-at-root allowed); Landlock (Linux) keeps workspace-root RO with child RW only.
- **`auto`** attaches when the running product major is in the advertised matrix and the sandbox apply symbol resolves; otherwise degrades loudly.
- **`on`** fails closed when attach cannot complete.
- **`off`** disables OS apply.

Advertised matrix: macOS product majors **14 through 26** inclusive (version-gated). Outside the matrix → unavailable. Nested re-apply is not supported; children inherit the first successful apply.

## Protected Paths

Policies deny common secret paths such as `.env`, `~/.ssh/**`, cloud credential directories, keychains, and browser credential stores.

## Limitations

Orca does not install an Endpoint Security extension, kernel extension, or admin-only network filter by default. Seatbelt attach is limited to the `orca run` child path under `--os-sandbox` and the version matrix above. Wrapper-level protections alone are not transparent OS enforcement.
