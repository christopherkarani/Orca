# Lessons

## 2026-05-06 Phase 04 CLI Review

- Placeholder commands must return a non-success code until they perform the requested work. A no-op command that prints "not implemented yet" and exits `0` can mislead scripts and CI.
- Every command branch, including simple informational commands like `version`, must parse `--help` and reject unexpected extra arguments instead of ignoring them.

## 2026-05-06 Phase 05 Session Supervisor Review

- After spawning a child process, every later error path must either wait for or terminate the child before returning. Output hook failures and other parent-side errors are still supervisor lifecycle paths.
- Returned in-memory events must not borrow stack-backed slices from local model copies. If an event outlives the local frame, duplicate target strings or point them at clearly owned result storage.
