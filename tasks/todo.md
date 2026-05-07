# Phase 16 Windows Backend Plan

## Assumptions

- Phase 16 is limited to Windows backend support and honest capability reporting; future MCP/installer/hardening phases stay untouched.
- Windows v1.0 support should be useful wrapper-mediated local protection: process launch, env filtering, staging, PATH shims, cmd/PowerShell command guard coverage, protected path matching, MCP stdio compatibility, audit/replay compatibility, and clear doctor output.
- Normal local development must not require administrator privileges, WFP drivers, kernel hooks, or transparent filesystem/network enforcement.
- Unsupported or wrapper-only protections must not satisfy explicit required-backend checks unless they are reported `active`.
- Tests must use simulated Windows sensitive paths and fake secrets only; no test may inspect real user profile credentials.

## Research Check

- [x] Read Phase 16 and required canonical, architecture, security, and production-readiness documents.
- [x] Review project lessons and Aegis memory for phase boundaries, honest capability reporting, and Zig verification expectations.
- [x] Inspect existing Linux/macOS backend interface, fallback prepare path, doctor output, run required-backend checks, env filtering, command shims, command classifier, filesystem staging, and red-team runner.
- [x] Validate assumptions and false-positive risks before coding: Windows cannot claim full transparent file/network enforcement, `cmd.exe`/PowerShell executable interception is partial through PATH shims, Job Object cleanup is optional unless implemented and tested, and non-Windows builds must remain unaffected.

## Checklist

- [x] Capture baseline verification before code edits.
- [x] Implement explicit `src/sandbox/windows.zig` backend detection using the established backend interface.
- [x] Wire Windows backend selection into `src/sandbox/backend.zig`.
- [x] Add honest Windows capability states for env filtering, path staging, PATH shims, cmd/PowerShell wrappers, process cleanup, transparent file/network enforcement, strong sandbox, MCP stdio proxy, and audit/replay.
- [x] Add Windows-specific `aegis doctor` output without changing macOS/Linux claims.
- [x] Add Windows path normalization helpers covering drive letters, UNC paths, slash normalization, case-insensitive comparisons, `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%`, traversal, spaces, and PowerShell escaping where feasible.
- [x] Add Windows protected path matching for SSH/cloud/browser/GitHub CLI/PSReadLine/common credential files using simulated paths.
- [x] Integrate Windows protected path matching with filesystem guard raw-path decisions without reading real secrets.
- [x] Add Windows-compatible PATH shim files and PATH/PATHEXT environment handling where feasible.
- [x] Expand command classification for Windows cmd/PowerShell risky patterns.
- [x] Add Windows-gated and pure deterministic tests for backend detection, path handling, protected matching, env filtering, staging, PATH shims, command classification, process launch, process cleanup status, and honest unsupported feature reporting.
- [x] Run required verification: `zig build`, `zig build test`, `./zig-out/bin/aegis doctor`, `./zig-out/bin/aegis redteam --ci`.
- [x] Document review results, known limitations, Windows capability status, unsupported features, security notes, and acceptance criteria status.

## Review

- Baseline before Phase 16 code changes: `zig build` passed.
- Baseline before Phase 16 code changes: `zig build test` passed.
- Interim verification: `zig build` passed after implementation.
- Interim verification: `zig build test` initially failed on UNC path normalization producing three leading slashes; fixed and reran successfully.
- Interim verification: `zig build check-windows` passed as a compile-only Windows target gate.
- Final verification: `zig build` passed.
- Final verification: `zig build test` passed.
- Final verification: `zig build check-windows` passed.
- Final verification: `zig build -Dtarget=x86_64-windows` passed.
- Final smoke: `./zig-out/bin/aegis doctor` passed on macOS and reported `selected: macos`; Windows doctor rendering is covered by an injected-report unit test.
- Final smoke: `./zig-out/bin/aegis redteam --ci` passed with 10/10 fixtures.
- Local process smoke: `./zig-out/bin/aegis run -- echo hello` passed on macOS.
- Required backend failure smoke: `./zig-out/bin/aegis run --mode ci --require-backend strong_sandbox -- echo hello` failed closed with exit code 4.
- Windows capability status: env filtering active, path staging active, PATH shims wrapper-only, cmd wrapper partial, PowerShell wrapper partial, process cleanup partial, transparent file enforcement limited, transparent network enforcement limited, strong sandbox unavailable, MCP stdio proxy active, audit/replay active.
- Unsupported features: no Windows Filtering Platform driver, no AppContainer profile, no transparent filesystem enforcement, no transparent network enforcement, no admin-required sandbox path, and no Job Object process-tree cleanup implementation in this phase.
- Security notes: unsupported protections are not reported active; explicit required backend features still require `active`; Windows path tests use simulated profile roots; tests do not read real Windows user secrets; fake-secret redaction remains covered by existing audit/red-team tests.
- Manual Windows checks not run on this macOS host: `aegis doctor` on Windows, `aegis run -- cmd /c echo hello`, `aegis run -- powershell -NoProfile -Command "Write-Output hello"`, `aegis run --mode ci -- cmd /c echo hello`, `aegis init --preset generic-agent --force`, `aegis policy check .aegis/policy.yaml`, encoded-command denial, and Windows audit/replay fake-secret inspection.
- Review fix: replaced Windows `.cmd` batch shims with copied executable aliases so extension-qualified calls like `cmd.exe`, `powershell.exe`, `pwsh.exe`, and `git.exe` route through `aegis shim exec` by argv0.
- Review fix: removed `%*` batch forwarding from the Windows shim path, eliminating cmd metacharacter re-parsing at the wrapper boundary.
- Review fix: command classification now analyzes all argv tokens after `cmd /c`, `cmd /k`, `powershell -Command`, and `pwsh -Command`, with regression tests for split destructive/elevation/download-pipe forms.
- Review fix verification: `zig build`, `zig build test`, `zig build check-windows`, `zig build -Dtarget=x86_64-windows`, `./zig-out/bin/aegis doctor`, `./zig-out/bin/aegis redteam --ci`, and required-backend fail-closed smoke all passed.
