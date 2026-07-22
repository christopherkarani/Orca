# fm-steward (Phase 3)

Mac-only **Foundation Models steward** package for Orca. Classifies **risk-card-v1** JSON into:

| Verdict | Meaning |
|---------|---------|
| `continue` | Proceed under existing policy + hard fence |
| `ask` | Soft interrupt; human-readable `explain` required |
| `ask_sticky_candidate` | Ask and suggest a sticky allow scope |

Phase 3 ships:

- Normative schemas under `Schemas/`
- Fixture corpus under `Fixtures/` (§6.4 table)
- Deterministic **rules pre-pass** (works without on-device FM)
- Injectable `FoundationModelBackend` + warm `StewardSession` with **500ms** default timeout
- Demo CLI: `fm-steward classify --card <path.json>`

## Platform

| Platform | Support |
|----------|---------|
| **macOS 15+** | Supported (`Package.swift` platforms) |
| **Linux** | **Skipped** — product path does not use FM. Phase 4 wiring remains Mac-only for this package; Linux continues on policy + hard fence only. |

This package is **not** wired into production Zig hooks in Phase 3 (see [Scope / W4](#scope--not-done-w4)).

## Build

```bash
cd macos/fm-steward
swift build
```

Executable product: `.build/debug/fm-steward` (or `swift run fm-steward …`).

## Test

```bash
cd macos/fm-steward
swift test
```

Covers fixture table, backend/explain contracts, and session timeout fallback.

## CLI

```bash
cd macos/fm-steward

# Pretty JSON classify-response-v1 (default)
swift run fm-steward classify --card Fixtures/bulk_email.json

# Compact human lines
swift run fm-steward classify --card Fixtures/vip_email.json --human

# Override backend timeout (default 500ms)
swift run fm-steward classify --card Fixtures/grep_rm_rf.json --timeout-ms 200
```

### Behavior notes

- **Default timeout:** `500ms` (`StewardSession.defaultTimeoutMs`). Override with `--timeout-ms N`. Host API for the timeout race is **`StewardSession`** (not bare `Classifier`).
- **Timeout / unavailable model → `continue`** with `fallback=true` (and `timed_out=true` when the timer wins). Never ask-spam after timeout. Timeout is **cooperative**: backends must honor task cancellation; structured concurrency still joins cancelled children.
- **Broken ask* (empty explain) → `continue`** is a soft residual (anti-ask-spam), not hard-fence fail-closed. Hard fence remains Zig-only.
- **Default backend** is unavailable; the **rules pre-pass** still yields correct fixture verdicts without Apple FM hardware/SDK. Rules hits set `model_available=false` (not live FM).
- **Host-authoritative cards:** `features.*` and thresholds must be host-computed. `thresholds.vip_list_path` is **host-only metadata** in Phase 3 (steward does not open the path); set `features.vip=true` for VIP soft-ask.
- **Schema:** `features.namespace` is the shipped field (handoff drafts sometimes said `severity` — use `namespace`).
- Exit code `0` means classify succeeded (including `ask*`). Non-zero is usage/IO/decode failure (including `schema_version != 1` or card file > 1 MiB).

## Demo (§6.4 fixture table)

Copy-paste from `macos/fm-steward`:

```bash
# ask + non-empty explain
swift run fm-steward classify --card Fixtures/bulk_email.json --human
swift run fm-steward classify --card Fixtures/vip_email.json --human

# continue (safe / non-executed / test loop)
swift run fm-steward classify --card Fixtures/grep_rm_rf.json --human
swift run fm-steward classify --card Fixtures/npm_test_loop.json --human
```

| Fixture | Expected |
|---------|----------|
| `Fixtures/bulk_email.json` | `ask` + explain (`suggested_sticky_*` null) |
| `Fixtures/vip_email.json` | `ask_sticky_candidate` + explain + sticky suggestions |
| `Fixtures/grep_rm_rf.json` | `continue` |
| `Fixtures/npm_test_loop.json` | `continue` |
| `Fixtures/timeout_forced.json` | Neutral card metadata only — timeout proven via `SlowBackend` in unit tests (G3), not static rules |

Optional wrapper:

```bash
./scripts/demo.sh
# or: ./scripts/demo.sh --json
```

## Schemas & fixtures

- `Schemas/risk-card-v1.json` — request contract  
- `Schemas/classify-response-v1.json` — response contract (`continue` \| `ask` \| `ask_sticky_candidate`)  
- `Fixtures/*.json` — demo/CI cards  
- `Fixtures/validate.sh` — lightweight required-field check  

## Scope / not done (W4)

**W4 production hook wiring is NOT done.** Phase 3 deliberately does **not** call FM from:

- `src/cli/hook.zig`
- `src/cli/shell_eval.zig`
- production `decideShellWithPolicy` path

### G5 negative-scope check

```bash
# From repo root — must not show production FM symbols in hook/shell_eval
rg -n 'fm_steward|FmVerdict|classifyRiskCard' src/cli/hook.zig src/cli/shell_eval.zig || true
```

Zig shell security remains the in-process Zig `shell_engine` + policy path. WP6 UDS IPC / Phase 4 product wiring is out of scope here.

## Library surface (for dependents)

```text
StewardSession  ← preferred host API (warm + ≤500ms timeout race)
Classifier      ← pure rules + backend (no timeout; tests / composition)
RulesPrePass / ClassifyPipeline (internal demotion shared)
FoundationModelBackend + UnavailableBackend + LiveBackend (stub) + SlowBackend (tests)
RiskCard / ClassifyResponse (Codable, snake_case keys; public constructors via make/factories)
```

Default session timeout **500ms**. Rules pre-pass short-circuits before backend race.
