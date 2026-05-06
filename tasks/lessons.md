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
