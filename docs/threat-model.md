# Threat Model

## Assets Protected

- Local environment variables passed to agent processes.
- Secret-like values before persistent logging.
- Protected paths such as `.env`, SSH keys, cloud credentials, and browser credential stores.
- Orca-mediated writes before they reach the workspace.
- MCP tool calls, resource reads, prompt gets, and sampling requests that pass through the stdio proxy.
- Host and MCP tool calls classified into effect classes (e.g. `comms.message`) when policy includes an `effects:` section — by tool name catalog, structural argument shapes, network host tags, and Zig-side shell bypass patterns (e.g. `open mailto:`). Host shell PreToolUse uses the Zig `shell_engine` (MVP core/git/system packs). Residual gap: full shell effect-class parity with Zig `shell_bypass` / effect packs is not claimed for every compound shell form; cloud/k8s pack parity beyond MVP is deferred.
- Audit integrity for Orca-managed sessions.

## Threat Actors

- Prompt-injected coding agents.
- Malicious repository content that instructs an agent to read or expose secrets.
- Untrusted MCP servers or tool metadata.
- Local automation scripts launched through Orca.

## Trust Boundaries

- The user and local OS are trusted to launch Orca intentionally.
- Child processes are untrusted.
- Policy files are trusted only after validation.
- MCP protocol messages and manifests are untrusted inputs.
- Audit artifacts are verified as untrusted local files during replay.

## Assumptions

- The protected process is launched through Orca.
- The user does not approve unsafe actions deliberately.
- Orca can write audit artifacts in the workspace.
- Platform backend claims are checked with `orca doctor`.

## Non-goals

Orca does not promise perfect sandboxing, protection outside Orca-launched sessions, defense against root/admin/kernel compromise, or universal transparent filesystem/network interception.

## Platform Limitations

Wrapper and proxy controls are not the same as OS-level enforcement. macOS and Windows currently report transparent file and network enforcement as limited. Linux capability depends on kernel and host settings.

Protection is **graded** (`hook` | `wrapper` | `proxy` | `OS-enforced`). Canonical definitions and the map from doctor / platform reports (and the public `orca start` **Ask on risk** default) live in [compatibility.md](compatibility.md#protection-grades-canonical).

## Fail-closed Behavior

Strict and CI modes deny invalid policies, missing required backend features, unsupported ask prompts in CI, and malformed untrusted inputs where enforcement is required.

## Known Unsupported Cases

- Agents launched outside Orca.
- Real network blocking when traffic bypasses Orca and no active OS/backend enforcement exists.
- Transparent blocking of arbitrary filesystem calls on platforms where `doctor` reports limited or unavailable support.
- Privileged users who intentionally bypass wrappers, shims, or audit paths.
