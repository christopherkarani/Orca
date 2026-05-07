# Phase 15 macOS Backend Plan

## Assumptions

- Phase 15 is limited to macOS backend support and honest capability reporting; Windows and future sandbox hardening phases stay untouched.
- macOS v1.0 support is wrapper/partial protection for local development: env filtering, staged writes, PATH/shell shims, command guard, MCP proxy compatibility, audit/redaction, process launch, and best-effort cleanup.
- Transparent filesystem enforcement, transparent network enforcement, and strong sandboxing are not active on macOS in this phase unless real OS-level enforcement is implemented and tested.
- Tests must use temporary directories that simulate sensitive macOS paths and must never inspect real user secrets, browser profiles, keychains, or cloud credentials.

## Research Check

- [x] Read Phase 15 and the required canonical, architecture, security, and production-readiness documents.
- [x] Review project lessons and prior Aegis memory for phase boundaries, honest capability reporting, and Zig verification expectations.
- [x] Inspect existing sandbox backend, Linux phase implementation, run integration, doctor CLI, env filtering, command shims, and filesystem staging before implementation.
- [x] Validate false positives before coding: macOS backend claims, path matching on case-insensitive filesystems, symlink escape behavior, shell shim coverage, process cleanup behavior, redaction persistence, and non-macOS build impact.

## Checklist

- [x] Add macOS-gated and pure unit tests first for platform detection, backend capability detection, honest unsupported feature reporting, path normalization/protected matching, case-insensitive simulated paths, symlink escapes, env filtering, staging, PATH shim insertion, shell wrappers, process launch, and process cleanup where feasible.
- [x] Implement `src/sandbox/macos.zig` using the Phase 14 backend interface and honest wrapper/partial capability levels.
- [x] Wire backend selection so macOS uses the macOS backend while non-macOS fallback/Linux behavior stays intact.
- [x] Add macOS process launch support with environment integration, PATH shim/shell wrapper compatibility, and best-effort child cleanup without admin/root requirements.
- [x] Add macOS path helpers for home expansion, Library/Application Support/Keychains/browser/GitHub/SSH/cloud credential protected patterns, case-insensitive matching, relative traversal, and symlink escape detection using temporary test roots.
- [x] Improve `aegis doctor` macOS output to show env filtering, path staging, shell shims, process supervision, transparent file/network enforcement, strong sandbox, MCP stdio proxy, and audit/replay with active/partial/limited/unavailable status.
- [x] Verify strict/ci mode fails closed when an explicitly required backend feature is unavailable, while normal local wrapper/partial mode remains usable and visibly reported.
- [x] Confirm audit/redaction compatibility: fake secrets do not persist to `events.jsonl` or replay output.
- [x] Run required verification: `zig build`, `zig build test`, `./zig-out/bin/aegis doctor`, `./zig-out/bin/aegis redteam --ci`.
- [x] On macOS, run smoke checks: `aegis run -- echo hello`, `aegis run --mode ci -- echo hello`, `aegis init --preset generic-agent --force`, `aegis policy check .aegis/policy.yaml`, and fake-secret audit/replay inspection.
- [x] Document review results, known limitations, macOS capability status, unsupported features, security notes, and acceptance criteria status.

## Review

- Baseline before Phase 15 code changes: `zig build` passed.
- Baseline before Phase 15 code changes: `zig build test` passed.
- Final verification: `zig build` passed.
- Final verification: `zig build test` passed.
- Final verification: `zig build -Dtarget=x86_64-linux` passed.
- Final verification: `zig build -Dtarget=aarch64-linux` passed.
- Final verification: `zig build -Dtarget=x86_64-windows` passed after compile-only guards for existing POSIX-only code paths.
- Final smoke: `./zig-out/bin/aegis doctor` passed on macOS and reported `selected: macos`.
- Final smoke: `./zig-out/bin/aegis redteam --ci` passed with 10/10 fixtures.
- macOS smoke: `./zig-out/bin/aegis run -- echo hello` passed.
- macOS smoke: `./zig-out/bin/aegis run --mode ci -- echo hello` passed.
- macOS smoke in a temporary workspace: `aegis init --preset generic-agent --force` passed.
- macOS smoke in the same temporary workspace: `aegis policy check .aegis/policy.yaml` passed.
- Security smoke in a temporary workspace: `aegis run --mode ci -- echo fake_secret_value` produced redaction markers, and `fake_secret_value` was absent from `events.jsonl` and `aegis replay --verify` output.
- Required backend failure smoke: `aegis run --mode ci --require-backend strong_sandbox -- echo hello` failed closed with exit code 4.
- macOS capability status: env filtering active, path staging active, shell/PATH shims wrapper-only, process supervision active, transparent file enforcement limited, transparent network enforcement limited, strong sandbox unavailable, MCP stdio proxy active, audit/replay active.
- Known limitations: macOS does not install transparent filesystem enforcement, transparent network enforcement, Endpoint Security controls, kernel extensions, Sandbox.app profiles, or admin/root-only containment by default.
- Security notes: unsupported protections are not reported active; explicit required backend features still require `active`; tests use simulated macOS sensitive paths in temp directories; no raw fake secret persisted in audit or replay smoke output.
