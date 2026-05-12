# macOS Platform

Run:

```sh
./zig-out/bin/aegis doctor
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
| Transparent file enforcement | limited |
| Strong sandbox | unavailable |

## Protected Paths

Policies deny common secret paths such as `.env`, `~/.ssh/**`, cloud credential directories, keychains, and browser credential stores.

## Limitations

Aegis does not install a macOS Sandbox profile, Endpoint Security extension, kernel extension, or admin-only network filter by default. Wrapper-level protections are not transparent OS enforcement.
