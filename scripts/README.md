# Scripts

## Agent / developer iteration (read first)

Coding agents and humans should use the **narrowest** gate. Full details and path→gate matrix: **`Agents.md` → Verification gates**.

| Goal | Command |
|------|---------|
| Fastest Zig compile signal | `./scripts/compile-fast.sh` or `./scripts/compile-fast.sh check` |
| Compile lib / test-fast artifacts (no run) | `./scripts/compile-fast.sh test-lib` / `test-fast` |
| Run lib tests only | `./scripts/compile-fast.sh test-lib-run` or `./scripts/zig build test-lib` |
| Units only (no quick-install) | `./scripts/test-fast.sh units` |
| Default local product gate | `./scripts/test-fast.sh` (or `full`) |
| Compile-only product gate | `./scripts/test-fast.sh compile` |
| Policy / init DX matrix only | `./scripts/quick-install-dx-verify.sh` (needs built `zig-out/bin/orca`) |
| Full Zig suite | `./scripts/zig build test` |
| Pre-merge kitchen sink | `./scripts/verify-pre-merge.sh` |
| Rust daemon units | `(cd orca-rs && cargo test --lib)` |
| Pinned Zig wrapper | `./scripts/zig …` (always prefer over bare `zig`) |

### Modes and flags

- **`compile-fast.sh`**: compile-only modes use incremental + default `-j`; run modes use `-j1` (serial tests; avoids host hangs).
- **`test-fast.sh`**: `compile` | `units` | `full` (default). Env override: `ORCA_TEST_FAST=units`.
- **`compile-test-fast`** (build.zig) matches **`test-fast`** membership (not the full suite).

### Pitfalls

- Do **not** use `build-all.sh` for iteration (`cargo build --release` for the daemon).
- Do **not** default mid-task work to `verify-pre-merge.sh` or full `zig build test`.
- Zig L1 units are often **multi-minute** (large monopath lib test binary). Prefer L0 compile first.
- Avoid clearing `.zig-cache` / `orca-rs/target` unless necessary.

---

## Phase 19 release helpers

- `install.sh`: macOS/Linux installer with OS/arch detection, checksum verification, PATH/resource profile wiring, and a step-based TTY UI (banner, phases, activation hero). Set `ORCA_INSTALL_QUIET=1` for non-error silence; honors `NO_COLOR`.
- `install.ps1`: Windows installer with the shared core contracts (checksum, binaries, runtime assets, quiet mode, activation handoff). Subset of the Unix surface — no PATH management or dashboard soft-warn.
- `install-orca-plugin.sh`: one-command bootstrap for `orca` + plugin install + plugin doctor (`opencode`, `openclaw`, or `hermes`).
- `install-orca-plugin.ps1`: Windows one-command bootstrap for `orca` + plugin install + plugin doctor (`opencode`, `openclaw`, or `hermes`).
- `update-homebrew-formula.sh`: updates `packaging/homebrew/Formula/orca.rb` from `dist/checksums.txt`.
- `render-package-manifests.sh`: renders publishable Homebrew, npm, Scoop, and WinGet manifests under `dist/package-manifests/` from `dist/checksums.txt`.
- `build-release.sh`: builds cross-platform release archives into `dist/`.
- `build-release.ps1`: PowerShell archive smoke-test helper; pass `-ArchiveOnly`. Production release verification must use `build-release.sh` because the PowerShell helper does not emit `release-manifest.json` or rendered package manifests.
- `generate-checksums.sh`: writes `dist/checksums.txt`.
- `generate-sbom.sh`: writes the Phase 19 `dist/sbom.json` hook output.

Signing is optional and controlled by `ORCA_SIGNING_ENABLED=1` plus `ORCA_SIGNING_COMMAND`.
