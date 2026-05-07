# Linux Platform

Run:

```sh
./zig-out/bin/aegis doctor
```

## Capability Matrix

| Feature | Status |
|---|---|
| Process supervision | active or partial, host-dependent |
| Env filtering | active |
| Staged writes | active |
| Shell/PATH shims | wrapper-only |
| MCP stdio proxy | active |
| Network decision engine | active |
| Transparent network enforcement | partial or limited, backend-dependent |
| Transparent filesystem enforcement | partial or limited, backend-dependent |
| Strong sandbox | partial only when doctor reports active kernel features |

## Backend Features

Doctor may report user namespaces, mount namespaces, seccomp, Landlock, cgroups, network enforcement, audit/replay, and strong sandbox state.

## Fallback

If kernel features are unavailable, Aegis falls back to wrapper/proxy, staged-write, policy, and audit controls. Required backend features fail closed when requested with `--require-backend`.

## Limitations

Linux capability varies by distro, kernel, container, and sysctl configuration. Do not assume strong sandboxing without checking `doctor`.
