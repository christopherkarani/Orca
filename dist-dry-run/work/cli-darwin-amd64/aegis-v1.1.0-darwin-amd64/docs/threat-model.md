# Threat Model

## Assets Protected

- Local environment variables passed to agent processes.
- Secret-like values before persistent logging.
- Protected paths such as `.env`, SSH keys, cloud credentials, and browser credential stores.
- Aegis-mediated writes before they reach the workspace.
- MCP tool calls, resource reads, prompt gets, and sampling requests that pass through the stdio proxy.
- Audit integrity for Aegis-managed sessions.

## Threat Actors

- Prompt-injected coding agents.
- Malicious repository content that instructs an agent to read or expose secrets.
- Untrusted MCP servers or tool metadata.
- Local automation scripts launched through Aegis.

## Trust Boundaries

- The user and local OS are trusted to launch Aegis intentionally.
- Child processes are untrusted.
- Policy files are trusted only after validation.
- MCP protocol messages and manifests are untrusted inputs.
- Audit artifacts are verified as untrusted local files during replay.

## Assumptions

- The protected process is launched through Aegis.
- The user does not approve unsafe actions deliberately.
- Aegis can write audit artifacts in the workspace.
- Platform backend claims are checked with `aegis doctor`.

## Non-goals

Aegis does not promise perfect sandboxing, protection outside Aegis-launched sessions, defense against root/admin/kernel compromise, or universal transparent filesystem/network interception.

## Platform Limitations

Wrapper and proxy controls are not the same as OS-level enforcement. macOS and Windows currently report transparent file and network enforcement as limited. Linux capability depends on kernel and host settings.

## Fail-closed Behavior

Strict and CI modes deny invalid policies, missing required backend features, unsupported ask prompts in CI, and malformed untrusted inputs where enforcement is required.

## Known Unsupported Cases

- Agents launched outside Aegis.
- Real network blocking when traffic bypasses Aegis and no active OS/backend enforcement exists.
- Transparent blocking of arbitrary filesystem calls on platforms where `doctor` reports limited or unavailable support.
- Privileged users who intentionally bypass wrappers, shims, or audit paths.
