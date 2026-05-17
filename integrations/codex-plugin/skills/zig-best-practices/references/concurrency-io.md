# Concurrency, I/O, Processes, Files

## Version Warning

Zig 0.16 introduced major I/O and process API changes. Load `version-migration.md` before touching I/O, env, args, process spawning, current directory, or networking code in mixed-version repos.

Do not suggest Zig async/await/suspend/resume for current production code. As of Zig 0.16, those language features have been removed; use the current I/O interfaces, threads, event loops, or project-specific runtime abstractions.

## Threads And Synchronization

- Keep shared mutable state explicit and minimal.
- Prefer message passing, immutable snapshots, or caller-owned state over hidden globals.
- Use atomics only with a documented memory-order reason.
- Avoid holding locks across allocation, I/O, logging, callbacks, or child-process waits.
- Add stress or deterministic interleaving tests for cancellation, shutdown, and error paths.
- Define ownership of cancellation: who signals, who waits, who closes file descriptors, and who frees buffers.
- Do not store allocator-backed slices in shared state without a clear lock/ownership protocol.

## Process Handling

- Always clean up child processes on parent-side error paths.
- After spawn succeeds, every later error path should wait for, kill, or otherwise own child termination.
- Preserve argv tokenization. Do not collapse command arrays into shell strings unless shell behavior is explicitly required.
- Treat env and cwd as inputs. In 0.16-style code, process args/env are no longer global in the old way; prefer explicit init/context passing.
- For exact CLI behavior, run the built binary directly instead of only `zig build run`.
- Decide whether child stdio is inherited, ignored, piped, or captured. Tests should not accidentally inherit output into a harness protocol.
- Do not shell-join argv for convenience; shell quoting is a security boundary.

## I/O

- Bound reads from files, sockets, and stdin.
- Keep reader/writer abstractions version-matched with the repo's Zig pin.
- Do not persist raw sensitive payloads to logs.
- Surface partial write/read errors instead of converting them to success.
- For 0.16, review I/O interface release notes before replacing old reader/writer patterns.
- Keep maximum read sizes visible at call sites for untrusted files/stdin/network streams.
- Treat EOF, short read, and truncated framed input as separate states when protocol correctness depends on it.
- Flush writers and propagate flush errors before reporting success.

## Filesystem

- Distinguish paths from open directory handles.
- Canonicalize or sandbox paths when enforcing security boundaries, but keep user-facing errors tied to the original input.
- Avoid cwd-relative resource lookup for installed tools. Check executable-relative or configured resource roots.
- Use atomic write patterns for files that must not be left partially written.
- Reject symlink escapes when staging or applying workspace changes.
- Use open-directory handles to make relative access explicit; avoid re-resolving strings through cwd when policy enforcement depends on path roots.
- For installed tools, test from outside the source checkout.

## Networking

- Make network access explicit in policy/config.
- Preserve scheme, host, port, and resolved endpoint through evaluation.
- Use timeouts and cancellation paths.
- Treat DNS, redirects, proxies, and localhost aliases as policy-relevant.
- Never claim active egress enforcement unless the code actually installs or controls an enforcement point.
