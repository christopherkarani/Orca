# Compatibility Matrix

Use `orca doctor` for the authoritative report on a specific machine. This matrix uses Orca capability vocabulary: `active`, `partial`, `wrapper-only`, `observe-only`, `limited`, `unavailable`, and `unsupported`.

## Protection grades (canonical)

Orca is **graded mediation**, not a universal OS sandbox. Public product language uses these grades:

| Grade | Meaning | Typical Orca surface |
| --- | --- | --- |
| `hook` | Host invokes Orca and honors veto | Native plugin / host hook that actually fires |
| `wrapper` | PATH shims / `orca run` mediation | Finite executable list; absolute paths may bypass |
| `proxy` | Traffic must traverse an Orca proxy | MCP / optional network proxies |
| `OS-enforced` | Kernel/sandbox backend actually enforcing | Only when `orca doctor` reports the backend active |

**Default `orca run` posture:** typically **`wrapper`**. Host **`hook`** applies only when hooks fire and honor veto. **`proxy`** applies only to traffic that traverses an Orca proxy. **`OS-enforced`** is uncommon; trust it only when doctor reports the backend active.

**What can still bypass `wrapper` mediation:** absolute-path binaries outside the shim list, non-shimmed tools, agents started outside `orca run`/hooks, non-proxy HTTP clients, non-firing host hooks, and direct syscalls.

### Vocabulary map

Doctor / platform reports and `orca start --protection` labels are **not** a second taxonomy. Map them to grades:

| Other surface | Maps to grade(s) | Notes |
| --- | --- | --- |
| doctor `wrapper-only` (command guard / PATH shims) | `wrapper` | Not transparent OS enforcement |
| doctor sandbox / transparent FS or network `active` | `OS-enforced` | Rare; verify per feature |
| doctor `observe-only` / `limited` / `unavailable` | no enforcement claim | Decision or partial path only |
| MCP stdio proxy `active` | `proxy` (MCP path) | Only for mediated MCP traffic |
| `orca start --protection command-guard` | primarily `hook` (+ daemon for shell eval) | Host hooks only if they fire and honor veto |
| `orca start --protection firewall` | primarily `wrapper` (`orca run` / shims) | CLI label only — not kernel firewall |
| `orca start --protection maximum` | multi-grade aspirational (`hook` + `wrapper`) | Not `OS-enforced` unless doctor confirms |

Reserve marketing “firewall” / “maximum protection” for a **verified** multi-grade or **`OS-enforced`** posture. See also [threat-model.md](threat-model.md).

---

## Platform feature matrix

| Feature | Linux | macOS | Windows |
|---|---|---|---|
| Launch arbitrary command | active | active | active |
| Env filtering | active | active | active |
| Secret redaction | active | active | active |
| Audit/replay | active | active | active |
| Staged writes | active | active | active |
| Command guard | wrapper-only | wrapper-only | wrapper-only |
| Shell/PATH shims | wrapper-only | wrapper-only | wrapper-only |
| MCP stdio proxy | active | active | active |
| MCP manifests | active | active | active |
| MCP sampling controls | active | active | active |
| Network decision engine | active | active | active |
| Proxy-mediated network enforcement | unavailable | unavailable | unavailable |
| Transparent network enforcement | observe-only | limited | limited |
| Transparent filesystem enforcement | unavailable; staged writes active | limited | limited |
| Strong sandbox | unavailable | unavailable | unavailable |
| Process cleanup | active or partial | active | partial |
| Red-team suite | active | active | active |

`wrapper-only` means Orca-mediated command paths are protected by shims or wrappers (grade **`wrapper`**). It is not transparent OS enforcement.
