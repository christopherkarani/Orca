# Lessons

## 2026-05-06 Phase 04 CLI Review

- Placeholder commands must return a non-success code until they perform the requested work. A no-op command that prints "not implemented yet" and exits `0` can mislead scripts and CI.
- Every command branch, including simple informational commands like `version`, must parse `--help` and reject unexpected extra arguments instead of ignoring them.

## 2026-05-06 Phase 05 Session Supervisor Review

- After spawning a child process, every later error path must either wait for or terminate the child before returning. Output hook failures and other parent-side errors are still supervisor lifecycle paths.
- Returned in-memory events must not borrow stack-backed slices from local model copies. If an event outlives the local frame, duplicate target strings or point them at clearly owned result storage.

## 2026-05-06 Phase 06 Audit Review

- Workspace fallback tests must exercise a real non-Git temporary directory, not the filesystem root. Default workspace detection should preserve the original start directory when no parent `.git` marker exists.
- Audit replay verification must treat local audit artifacts as untrusted input. Missing or wrong-shaped JSON fields should return a verification failure reason, never panic through unchecked optional or union unwraps.

## 2026-05-06 Phase 07 Policy Review

- Policy discovery must fail closed when a configured policy path exists but cannot be loaded or parsed. Only a genuinely missing optional discovery location may fall through to the next source.
- Policy parsers must reject unknown schema keys in every supported format. A misspelled deny/default key changes security meaning and should be an invalid policy, not ignored configuration.
- Runtime audit artifacts under `.aegis/last` and `.aegis/sessions/` are local state from smoke tests. Keep them out of commits and ignore them explicitly.

## 2026-05-06 Phase 08 Secret Protection Review

- Redaction tests must include embedded secret-bearing arguments inside larger event strings, not only standalone `NAME=value` strings. Joined command targets can otherwise persist raw synthetic secrets even when summary argument redaction passes.
- Environment filtering must separate policy inheritance from effective mode. A `--mode observe` override cannot turn `env.inherit: false` into inherited unmatched variables; minimal environments should admit only explicit `env.allow` matches.

## 2026-05-06 Phase 09 Filesystem Staging Review

- Filesystem security tests must cover protected home-directory paths when the workspace itself is `$HOME`; matching only normalized `./...` workspace paths can bypass `~/...` deny rules.
- Staging apply must authenticate both sides of the review contract: verify the original workspace hash and the staged blob hash before writing.
- Diff must render the captured original from the staging session, not the live workspace file, so review output remains stable after workspace drift.

## 2026-05-07 Phase 10 Command Guard Review

- New CLI modules must be included in the actual patch, not only referenced by imports; untracked source files make clean-checkout builds fail.
- Approval state must survive the wrapper boundary. If a parent approves an ask-class command that is also shimmed, pass a bounded approval token to the shim or the shim will re-deny the command.
- Shim coverage must match classifier coverage for risky executable aliases. If `pip3`, `python3`, `ssh`, `scp`, or `nc` are classified, they need corresponding shims in the initial wrapper set.

## 2026-05-07 Phase 11 MCP Stdio Proxy Review

- MCP metadata scanning must feed enforcement state, not just audit output. If a tool is flagged critical during `tools/list`, later `tools/call` must fail closed even when the tool name matches a broad allow rule.
- JSON-RPC notifications are one-way. A stdio proxy must forward notifications without waiting for a response, or compliant MCP clients can deadlock after `notifications/initialized`.
- MCP inspect clients must complete the initialize lifecycle by sending `notifications/initialized` before normal requests like `tools/list`.
- CLI command parsing for subprocess launchers must preserve multi-token argv; `--command node -- server.js` and similar shapes are common for MCP servers.

## 2026-05-07 Phase 12 Network Guard Review

- Network capability reporting must distinguish decision-only controls from active egress enforcement. Do not report proxy-mediated enforcement as partial unless Aegis actually starts or configures a managed proxy path.
- Policy action adapters must preserve all structured action fields. For network decisions, build evaluator input from host, port, and scheme instead of dropping port/scheme context.
- Long-lived trackers must own string keys. Never store borrowed slices from temporary parser buffers in maps that outlive the evaluated input.

## 2026-05-07 Phase 14 Linux Backend Review

- Explicit backend requirements must be satisfied only by `active` capabilities. `partial`, `observe-only`, and `wrapper-only` are honest reports, but they are not enough to proceed when the user asks for a required backend feature.
- Do not report `strong_sandbox` as partial merely because process supervision or kernel feature probes exist. It is unavailable until Aegis actually installs OS-level restrictions such as namespaces, seccomp filters, or Landlock rules.

## 2026-05-07 Phase 15 macOS Backend Review

- User-facing capability labels can also be CLI compatibility surface when parsers accept labels. If doctor wording changes, preserve older spellings as explicit aliases and add parser regression tests.

## 2026-05-07 Phase 16 Windows Backend Review

- Windows PATH shims cannot rely on `.cmd` batch forwarding as a security boundary. Batch `%*` re-parses metacharacters; use executable aliases or another argv-preserving mechanism.
- If doctor says `cmd.exe` or `powershell.exe` are wrapper-guarded, generated shims must cover extension-qualified invocations such as `cmd.exe`, `powershell.exe`, `pwsh.exe`, and `git.exe`.
- Shell command classifiers must analyze all argv tokens after `/c`, `/k`, `-Command`, or `-c`; checking only the first token misses split destructive flags like `rmdir /s /q` and `Remove-Item -Recurse -Force`.

## 2026-05-07 Phase 17 MCP Review

- MCP sampling is normally server-originated. A stdio proxy must inspect server-to-client JSON-RPC requests as well as client-to-server requests, and default-deny sampling before forwarding it to the client.
- MCP manifests are a trust boundary, not just metadata. Manifest defaults must only apply when the launched command/args, expected binary hash, and environment allowlist binding have been checked.

## 2026-05-07 Phase 19 Release Pipeline Review

- New modules and package/template files must be staged or otherwise included in the actual patch before declaring merge readiness. Local tests can pass with untracked files that clean checkout CI will never see.
- GitHub Actions inputs are shell input until proven otherwise. Do not interpolate `${{ inputs.* }}` directly into `run:` commands; pass them through environment variables and keep any dynamic command text inside the Aegis-mediated child process.

## 2026-05-07 Phase 20 Security Hardening Review

- Shell-control detection must not bypass argv-level mandatory deny checks. When command text contains redirects, chains, or substitutions, classify both the tokenized argv and whole shell string, then keep the stricter result.
- Policy pattern validation must match matcher semantics. If `[`/`]`/`{`/`}` are literals to the matcher, validation must allow real paths that contain them and reject only actually unsafe or unsupported input.

## 2026-05-07 Phase 23 Product Split Review

- New package roots and contract tests must be visible to `git diff` before build wiring lands. A clean-checkout build cannot rely on untracked files, even when local `zig build test` passes.
- Public JSON schemas must be checked against runtime parser tests. If the parser supports nested shapes such as `files.write.mode` or `mcp.servers.<server>.tools`, the schema must accept that exact shape and reject parser-invalid alternatives.

## 2026-05-07 Phase 25 CLI Hardening Review

- When release version defaults change, update or remove checked-in `dist/` artifacts in the same patch. Stale artifact names and checksums can make the documented local install path fail even when source builds and tests pass.
- Do not leave binary execution packs under Markdown names. Use `file` or equivalent when a newly reviewed `.md` file renders as binary garbage, then remove it unless it is intentionally versioned in the correct artifact location.

## 2026-05-07 Phase 26 Edge Domain Review

- Before declaring a phase complete, compare `git diff --name-only <base>` with `git ls-files --others --exclude-standard`. If build wiring imports new modules or tests, those files must be tracked/staged so a clean-checkout patch can build.

## 2026-05-07 Phase 27 Edge Policy Review

- Edge command evaluation must bind every request to the exact vehicle state being used. Separate request/state files are a safety boundary; mismatched vehicle IDs must fail before constraint evaluation.
- Parameterized Edge commands must require the parameter variant their safety checks depend on. Missing or mismatched target data must be invalid, not treated as a command with no constraints.
- Public schemas and release artifacts are part of the runtime contract. Required policy sections, JSON output escaping, and installed binaries must match what docs and schemas advertise.

## 2026-05-08 Phase 29 PX4 SITL Review

- Environment-derived endpoint slices returned from helpers must own their storage or keep the env buffer alive with an explicit deinit path. Never return slices into freed env-var buffers.
- `requires_px4_sitl` is an enforcement gate, not advisory metadata. Reject inconsistent scenario metadata before any fake-PX4 execution can produce a pass.
- Public Edge policy schemas must match parser-required fields and supported blocks. Schema drift around geofence and altitude policy shape misleads policy authors and schema-driven tooling.

## 2026-05-08 Phase 30 ArduPilot SITL Review

- New Phase sources, docs, examples, and tests must be visible to `git diff` before review handoff. `build.zig` wiring plus untracked files is a clean-checkout build failure even when local tests pass.
- A configured SITL gate is not proof of live SITL. Until a real transport exchange is implemented, SITL-labeled scenarios must skip when unavailable and fail closed when merely configured, never run fake adapters as SITL evidence.
- Release archives are part of the reviewed contract. Regenerate checked-in archives and checksums whenever new binaries such as `aegis-edge` or package resources are added.
- Built-in CLI schema printing must not depend on the caller's cwd. Use build-embedded schema documents or an executable/resource-prefix lookup, and regress arbitrary-cwd invocation.
- Runtime schema descriptors, checked-in JSON schemas, and emitted audit event names must be tested together so persisted events like `mavlink.command_denied` validate.
- If a public schema already advertises a domain-supported field such as `safety.geofence.home_position`, prefer implementing loader support and round-trip tests over silently narrowing the contract.

## 2026-05-08 Phase 31 Flight Safety Review

- Safety exception flags need explicit fail-closed branches. Skipping a special-case allow is not enough when a later generic command allow can still permit the request.

## 2026-05-08 Phase 33 Edge Audit Review

- Before review handoff, force every new Phase source, test, doc, and example into `git diff` with tracking or intent-to-add. A clean-checkout review cannot see untracked audit/report modules even when local builds pass.
- For allocator-owned slices that are reordered in place and later passed through evaluation paths, keep one `errdefer` owner until normal success frees or transfers ownership. Duplicate `errdefer` registrations create error-path double frees.
- Generated `.aegis-edge` session state is local runtime output. Keep it ignored and untracked even when smoke commands produce useful approval or replay artifacts.
