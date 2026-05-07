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
| Transparent network enforcement | observe-only |
| Transparent filesystem enforcement | unavailable by default; staged writes are active |
| Strong sandbox | unavailable |

## Backend Features

Doctor may report user namespaces, mount namespaces, seccomp, Landlock, cgroups, network observation, audit/replay, and strong sandbox state. Kernel feature probes are capability evidence only; v1.1.0 does not install namespace, seccomp, or Landlock restrictions as an active strong sandbox.

## Fallback

If kernel features are unavailable, Aegis falls back to wrapper/proxy, staged-write, policy, and audit controls. Required backend features fail closed when requested with `--require-backend`.

## Limitations

Linux capability varies by distro, kernel, container, and sysctl configuration. Do not assume transparent filesystem enforcement or strong sandboxing; v1.1.0 reports those as unavailable unless a future backend installs active OS restrictions.
