# Linux Platform

Run:

```sh
./zig-out/bin/orca doctor
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
| Transparent filesystem enforcement | staged writes always; Landlock session-attach when available |
| Strong sandbox | session-attach via Landlock when ABI ≥ 1 (kernel 5.13+); otherwise unavailable |

## OS filesystem sandbox (`orca run`)

`orca run --os-sandbox auto|on|off` (default `auto`) can attach a Landlock filesystem boundary to the agent child:

- **Probe ≠ session-attach.** Doctor Landlock / strong-sandbox reports are capability evidence only. Doctor never reports a live session as `active` from a probe alone.
- **Session-attach** is claimable only after apply-before-exec child attach succeeds for that run (with a profile hash). The pre-exec status handshake (`status_ok`) does not prove `execve`; an `active` session can still fail at exec (e.g. exit 127).
- **FS scope (Landlock):** workspace child RW with workspace-root RO — create/write at the workspace root is denied; Seatbelt (macOS) allows full workspace subpath RW including create-at-root.
- **`auto`** attaches when the host supports Landlock ABI ≥ 1 and degrades loudly when it does not.
- **`on`** fails closed when attach cannot complete.
- **`off`** disables OS apply.

Requirements: Linux kernel **5.13+** with Landlock **ABI ≥ 1**. Containers and host policy can still make Landlock unavailable.

## Backend Features

Doctor may report user namespaces, mount namespaces, seccomp, Landlock, cgroups, network observation, audit/replay, and strong sandbox capability. Kernel feature probes are not a live session claim. Landlock restrictions are installed only on the `orca run` child path when `--os-sandbox` allows attach and the host supports it.

## Fallback

If kernel features are unavailable, Orca falls back to wrapper/proxy, staged-write, policy, and audit controls. Required backend features fail closed when requested with `--require-backend` or `--os-sandbox on`.

## Limitations

Linux capability varies by distro, kernel, container, and sysctl configuration. Do not treat doctor probes as transparent filesystem enforcement for an arbitrary process; trust OS-enforced FS isolation only for sessions that completed child attach.

## Hardlink residual

Landlock grant expansion skips symlinks (`DT_LNK`) and install opens use `O_NOFOLLOW`. Non-directory expand leaves with `st_nlink > 1` are also skipped so a pre-planted hardlink to an outside same-FS inode does not become an RW `PATH_BENEATH` surface. Directories are never skipped on nlink (normal dir nlink ≥ 2).

**Residual after the nlink filter:** hardlinks created *after* plan build (Landlock is path-based; the expand snapshot does not re-check nlink at install), plus expand-plan → child-open path TOCTOU (workspace write between parent plan and child `O_PATH` open can still replace a grant leaf). Legitimate multi-linked files under the workspace also lose leaf RW (write via another single-link name, or parent dir grant when expand does not apply).
