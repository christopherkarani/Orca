# Phase 14 Linux Sandbox Backend Plan

## Assumptions

- Phase 14 is limited to Linux backend capability detection, honest backend reporting, safe fallback launch behavior, Linux-gated tests, doctor output, and red-team capability reporting.
- Normal local development must not require root. Optional Linux kernel features may be detected and reported, but they must not be claimed active unless actually enabled for the run.
- On non-Linux hosts, builds and tests must continue to pass, and Linux-specific runtime checks must be target-gated or exposed as pure detection/reporting tests.
- Strong sandbox means meaningful OS-level restrictions are active, not just environment filtering, path staging, shims, policy decisions, or audit.

## Research Check

- [x] Read Phase 14 and the required canonical, architecture, security, and production-readiness documents.
- [x] Review project lessons and prior Aegis memory for phase boundaries, honest capability reporting, and Zig verification expectations.
- [x] Inspect existing sandbox stubs, platform capability model, run supervisor, doctor CLI, and red-team runner before implementation.
- [x] Verify current test/build behavior before and after the Phase 14 changes.
- [x] Research false positives in capability claims: namespace availability, seccomp/Landlock detection, network enforcement, path staging, and process cleanup.

## Checklist

- [x] Add tests first for explicit capability levels, Linux/non-Linux detection, backend fallback reporting, strict required-feature failure, and doctor Linux output formatting.
- [x] Formalize the backend capability interface with explicit levels: active, partial, observe-only, wrapper-only, unavailable, unsupported, and failed.
- [x] Implement Linux capability detection for wrapper controls, process supervision, user namespaces, mount namespaces, seccomp, Landlock, cgroups, network enforcement, and strong sandbox.
- [x] Add a safe fallback backend path that launches simple commands without silently claiming unavailable OS features.
- [x] Integrate backend selection/capability reporting into `aegis run` without weakening env filtering, staged writes, shell/PATH shims, audit, or policy behavior.
- [x] Add strict/ci required-feature failure behavior for explicitly requested unavailable backend features.
- [x] Improve process-tree cleanup where feasible, with non-Linux behavior preserved.
- [x] Extend `aegis doctor` with Linux-specific backend details and honest active/partial/unavailable status.
- [x] Add red-team capability reporting so unsupported Linux backend-specific checks skip or report unsupported instead of faking passes.
- [x] Add Linux-gated tests for command launch, env filtering, staged writes reporting, shell/PATH shims reporting, namespace/seccomp/Landlock detection, fallback launch, and cleanup where feasible.
- [x] Run `zig build`, `zig build test`, `./zig-out/bin/aegis doctor`, and `./zig-out/bin/aegis redteam --ci`.
- [x] Document review results, known limitations, Linux capability status, unsupported features, security notes, and acceptance criteria status.

## Review

- Baseline before Phase 14 code changes: `zig build` passed.
- Baseline before Phase 14 code changes: `zig build test` passed.
- Mid-implementation checkpoint: `zig build test` passed after backend, doctor, run, and red-team capability integration.
- Final verification: `zig build` passed.
- Final verification: `zig build test` passed.
- Final verification: `zig build -Dtarget=x86_64-linux` passed.
- Final verification: `zig test -target x86_64-linux src/root.zig -fno-emit-bin` passed.
- Final verification: `zig test -target x86_64-linux -fno-emit-bin --dep aegis -Mroot=src/main.zig -Maegis=src/root.zig` passed.
- Final smoke: `./zig-out/bin/aegis doctor` passed on macOS and reported fallback backend with Linux-only features unsupported.
- Final smoke: `./zig-out/bin/aegis redteam --ci` passed with 10/10 fixtures.
- Local non-Linux smoke: `./zig-out/bin/aegis run -- echo hello` passed.
- Local non-Linux smoke: `./zig-out/bin/aegis run --mode ci -- echo hello` passed.
- Linux manual runtime checks could not be run on this macOS host; Linux compile-only gates and Linux-gated tests were added for CI.
- Review fix: required backend features now require `active`; `partial`, `observe-only`, and `wrapper-only` no longer satisfy `--require-backend`.
- Review fix: Linux `strong_sandbox` is now `unavailable` until Aegis actually installs namespace/seccomp/Landlock restrictions.
