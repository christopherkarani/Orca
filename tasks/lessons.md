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
