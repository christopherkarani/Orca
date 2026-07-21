# Compatibility Matrix

Use `orca doctor` for the authoritative report on a specific machine. This matrix uses Orca capability vocabulary: `active`, `partial`, `wrapper-only`, `observe-only`, `limited`, `unavailable`, and `unsupported`.

## Protection grades (canonical)

Orca is **graded mediation**, not a universal OS sandbox. Public product language uses these grades:

| Grade | Meaning | Typical Orca surface |
| --- | --- | --- |
| `hook` | Host invokes Orca and honors veto | Native plugin / host hook that actually fires |
| `wrapper` | PATH shims / `orca run` mediation | Finite executable list; absolute paths may bypass |
| `proxy` | Traffic must traverse an Orca proxy | MCP / optional network proxies |
| `OS-enforced` | Kernel/sandbox backend actually enforcing for that session | Only after `orca run` child session-attach succeeds; doctor probes alone are not enough |

**Default `orca run` posture:** typically **`wrapper`**, plus optional OS filesystem session-attach under `--os-sandbox auto|on|off` (default `auto`). Host **`hook`** applies only when hooks fire and honor veto. **`proxy`** applies only to traffic that traverses an Orca proxy. **`OS-enforced`** FS isolation requires a successful Landlock (Linux) or Seatbelt (macOS) attach for that child — not a doctor capability probe.

**What can still bypass `wrapper` mediation:** absolute-path binaries outside the shim list, non-shimmed tools, agents started outside `orca run`/hooks, non-proxy HTTP clients, non-firing host hooks, and direct syscalls.

### Vocabulary map

Doctor / platform reports and `orca start --protection` labels are **not** a second taxonomy. Map them to grades:

| Other surface | Maps to grade(s) | Notes |
| --- | --- | --- |
| doctor `wrapper-only` (command guard / PATH shims) | `wrapper` | Not transparent OS enforcement |
| doctor sandbox / strong sandbox `partial` (API present) | probe only | Capability evidence; **not** a live session claim |
| doctor sandbox / transparent FS or network `active` | `OS-enforced` | Rare; doctor never marks session active from probe alone |
| `orca run --os-sandbox` auto/on + successful child attach | `OS-enforced` (FS, that session) | Landlock ABI ≥ 1 (kernel 5.13+) or Seatbelt majors 14–26 (capability gate; CI attach evidence: linux amd64 + macos-14) |
| doctor `observe-only` / `limited` / `unavailable` | no enforcement claim | Decision or partial path only |
| MCP stdio proxy `active` | `proxy` (MCP path) | Only for mediated MCP traffic |
| `orca start --protection command-guard` | primarily `hook` (+ daemon for shell eval) | Host hooks only if they fire and honor veto |
| `orca start --protection firewall` | primarily `wrapper` (`orca run` / shims) | CLI label only — not kernel firewall |
| `orca start --protection maximum` | multi-grade aspirational (`hook` + `wrapper`) | Not `OS-enforced` from doctor probes; OS FS needs `orca run --os-sandbox` session-attach |

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
| Transparent filesystem enforcement | staged writes; Landlock attach when available | limited; Seatbelt attach when available | limited |
| Strong sandbox (session-attach) | Landlock when ABI ≥ 1 (kernel 5.13+); else unavailable | Seatbelt capability majors 14–26; else unavailable | unavailable |
| `orca run --os-sandbox` | auto \| on \| off (default auto) | auto \| on \| off (default auto) | off / unavailable |
| Process cleanup | active or partial | active | partial |
| Red-team suite | active | active | active |

`wrapper-only` means Orca-mediated command paths are protected by shims or wrappers (grade **`wrapper`**). It is not transparent OS enforcement.

**Probe vs session-attach:** Doctor and platform matrices may report sandbox **capability** (`partial` / API present). That is not a live session `active` claim. Trust **`OS-enforced`** filesystem isolation only for an `orca run` session that completed child apply-before-exec attach (profile hash present). Use `--os-sandbox on` to fail closed when attach cannot complete.

**Capability matrix vs CI attach evidence:** Landlock/Seatbelt version gates (Linux ABI ≥ 1; macOS product majors 14–26) describe **where attach may run**. Continuous **CI attach evidence** today is **linux amd64** and **macos-14** only; other OS/arch/major cells are local until freeze jobs exist — do not treat every gated major as CI-proven.
