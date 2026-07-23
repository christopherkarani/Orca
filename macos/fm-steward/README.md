# fm-steward (Phase 3)

Mac-only **on-device Apple Foundation Models steward** for Orca (`SystemLanguageModel`).

**v1 focus: dangerous shell / agent commands** (soft-interrupt nuance after policy + hard fence).  
Email bulk/VIP / pay adapters are **out of v1 product corpus** — architecture stubs only under `residual-knowledge/`.

Classifies **risk-card-v1** JSON into:

| Verdict | Meaning |
|---------|---------|
| `continue` | Proceed under existing policy + hard fence |
| `ask` | Soft interrupt; human-readable `explain` required |
| `ask_sticky_candidate` | Ask and suggest a sticky allow scope |

Phase 3 ships:

- Normative schemas under `Schemas/`
- Shell fixture corpus under `Fixtures/`
- Deterministic **rules pre-pass** (safe shapes + hard-danger ask + residual FM)
- **Live `LiveBackend`** using `import FoundationModels` + guided generation (`@Generable`)
- Warm `StewardSession` with timeout race for residual FM work
- **Residual Wax few-shot assist** (text mode): YAML packs → compiled seed → `.wax` → k≤3 neighbors
- Demo CLI: `fm-steward classify --card <path.json> [--live] [--few-shot auto|off|wax]`

## Platform

| Platform | Support |
|----------|---------|
| **macOS 26+** | Supported — requires Apple Intelligence / Foundation Models assets |
| **Linux** | **Skipped** — product path does not use FM |

This package is **not** wired into production Zig hooks in Phase 3 (see [Scope / W4](#scope--not-done-w4)).

## Security honesty

**FM + Wax are residual assist only — not sole security.**

| Layer | Role |
|-------|------|
| Zig hard fence | Catastrophe **deny** |
| Policy / YOLO / sticky | Host product |
| Rules pre-pass | Clear continue / hard-ask |
| Wax few-shots | Gray **examples** for residual FM (never deny/allow) |
| On-device FM | Soft `continue` \| `ask` \| `ask_sticky_candidate` |

Wax never unlocks hard deny. Fail-open: store/search errors → empty few-shots → normal FM/unavailable path.

## Build

```bash
cd macos/fm-steward
swift build
```

## Test

```bash
cd macos/fm-steward
python3 scripts/compile-residual-knowledge.py --check
swift test
bash Fixtures/validate.sh
```

## Residual knowledge packs

Human-authored **ambiguous coding-agent** examples live under `residual-knowledge/`:

```text
residual-knowledge/shell/*.yaml
residual-knowledge/containers/*.yaml
residual-knowledge/email|pay|social/   # stubs only (not implemented)
```

Compile to the checked-in seed artifact:

```bash
python3 scripts/compile-residual-knowledge.py          # write Fixtures/ambig-fewshot/seed.json
python3 scripts/compile-residual-knowledge.py --check  # CI / pre-commit gate
python3 scripts/compile-residual-knowledge.py --self-test
```

**Pipeline:** YAML packs → `seed.json` → text-mode `.wax` (seeded on first use or seed-hash change) → residual classify retrieves k≤3 → `LiveBackend.prompt` injects neighbors → FM decides.

See [`residual-knowledge/README.md`](residual-knowledge/README.md) for authoring rules and multi-domain employee architecture (docs/stubs only).

## CLI

```bash
cd macos/fm-steward

# Safe / rules short-circuit
swift run fm-steward classify --card Fixtures/grep_rm_rf.json --human
swift run fm-steward classify --card Fixtures/npm_test_loop.json --human

# Clear danger (deterministic hard-ask; no FM / no Wax)
swift run fm-steward classify --card Fixtures/curl_pipe_sh.json --human
swift run fm-steward classify --card Fixtures/rm_rf_workdir.json --human

# Residual gray (default --few-shot auto; live FM when available)
swift run fm-steward classify --card Fixtures/npm_test_loop.json --live --human
# pure FM residual (no few-shot):
swift run fm-steward classify --card Fixtures/npm_test_loop.json --few-shot off --live --human

# Full live prompt/output matrix
swift run fm-steward probe-matrix

# Pure-FM viability (always no few-shot)
swift run fm-steward eval-danger
```

### Behavior notes

- **v1 scope:** shell/command danger nuance only. Do not use email bulk/VIP demos as the product bar.
- **On-device model:** `SystemLanguageModel.default` + guided generation. Check `LiveBackend.isOnDeviceModelAvailable`.
- **Rules first (order):**
  1. `executed=false` → continue  
  2. `same_intent=test_loop` → continue  
  3. `CommandShape` safe shapes (echo/search/comment/print/var+echo/allowlisted dev clean) → continue  
  4. `HardDangerRules` clear catastrophe / exfil / RCE → **ask**  
  5. else residual: **Wax text few-shots (k≤3)** + **LiveBackend** FM  
- **Few-shot default:** `--few-shot auto` when seed is present; reseed if store missing or seed content hash ≠ `*.wax.seedsha`. Fail-open on auto. Use `off` for pure-FM comparisons. `eval-danger` is always pure-FM.
- **Hard fence** remains Zig (catastrophe deny). FM never unlocks hard deny; offline/timeout → continue.
- **Default timeout:** `3000ms` (raise with `--timeout-ms` for cold first token). Prefer **`StewardSession`** as host API.
- **Fresh LanguageModelSession per classify** so multi-card runs do not exceed the 4K context window.
- **Wax:** SPM pin ≥ **0.1.25**, `traits: []` (text mode; no MiniLM). See `docs/dev/dependencies.md`.

## Demo (v1 shell fixtures)

| Fixture | Expected (product path) |
|---------|-------------------------|
| `Fixtures/grep_rm_rf.json` | `continue` (rules: not executed) |
| `Fixtures/npm_test_loop.json` | `continue` (rules: test_loop) |
| `Fixtures/curl_pipe_sh.json` | `ask` (HardDangerRules: curl\|sh) |
| `Fixtures/rm_rf_workdir.json` | `ask` (HardDangerRules: home path wipe) |
| `Fixtures/timeout_forced.json` | Neutral card metadata; timeout proven via `SlowBackend` tests |

```bash
./scripts/demo.sh
```

## Scope / not done (W4)

**W4 production hook wiring is NOT done.** Phase 3 does not call FM from `hook.zig` / `shell_eval.zig`.

### G5 negative-scope check

```bash
rg -n 'fm_steward|FmVerdict|classifyRiskCard' src/cli/hook.zig src/cli/shell_eval.zig || true
```

Host sticky UI / always-allow storage / employee email·pay·social seed bodies → later phases (architecture documented under `residual-knowledge/`).

## Library surface

```text
StewardSession     ← preferred host API (warm + timeout race; residual few-shot; default 3000ms)
Classifier         ← pure rules + backend only (NO residual few-shot / RAG)
RulesPrePass       ← executed=false → test_loop → CommandShape → HardDanger → residual FM
CommandShape       ← safe skip shapes (no pipe exfil on search/echo)
HardDangerRules    ← deterministic soft-ask for clear danger
FewShotRuntime     ← product factory: makeRetriever (off / auto / wax)
FewShotStorePaths  ← App Support ambig.wax (+ ensureParentDirectory)
SeedPathResolver   ← explicit → App Support seed.json → package fixture → nil
FewShotRetriever   ← protocol + Null / Static / WaxFewShotStore (text)
FewShotSeedBootstrap ← seed SHA-256 reseed helpers (*.wax.seedsha sidecar)
LiveBackend        ← real SystemLanguageModel, shell-focused prompt + few-shot block
UnavailableBackend / SlowBackend
RiskCard / ClassifyResponse / StewardModelOutput
```

## Host attach

**Product residual path for hosts:** `StewardSession` + `FewShotRuntime.makeRetriever` only.

Do **not** use `Classifier` for residual RAG / few-shot. `Classifier` is the pure
rules + backend pipeline (tests and composition). It has no retriever, no Wax store,
and never injects neighbor examples. Residual few-shot assist is composed only on
`StewardSession` after the host builds a retriever from the library factory.

### Before you attach

Run the residual attach gate (offline hard gate; optional live soft SKIP):

```bash
# from package root (macos/fm-steward)
bash scripts/residual-stress-matrix.sh              # offline only (default)
bash scripts/residual-stress-matrix.sh --live       # offline + live residual dump

# from repo root
bash macos/fm-steward/scripts/residual-stress-matrix.sh
```

The residual-matrix / residual-stress-matrix gate asserts rules short-circuits never
consult few-shot (`few_shot_hits` / spy callCount == 0). Live residual dump soft-SKIPs
when on-device FM is unavailable (exit 0). **Run residual-stress-matrix before host
attach.** Do not enable few-shot on `eval-danger` (pure-FM only).

### Store layout (product default)

| Artifact | Path |
|----------|------|
| Wax store | `~/Library/Application Support/Orca/fm-steward/ambig.wax` |
| Seed-hash sidecar | `~/Library/Application Support/Orca/fm-steward/ambig.wax.seedsha` |
| Optional seed copy | `~/Library/Application Support/Orca/fm-steward/seed.json` |

Resolved via `FewShotStorePaths.productStoreURL()` / `storeURL(override:)`. Hosts may
override the store URL for tests or ops; product default is **not** a temp directory.

### Seed resolution order

Existence-checked (regular file only); first hit wins — `SeedPathResolver.resolve`:

1. **Explicit** seed URL (host / CLI `--seed` override)
2. **App Support** `…/Orca/fm-steward/seed.json` (`SeedPathResolver.productAppSupportSeedURL()`)
3. **Package fixture** `Fixtures/ambig-fewshot/seed.json` when package root is available
4. **`nil`** — no seed found

| Mode (`FewShotMode`) | Missing seed / load failure |
|----------------------|-----------------------------|
| `.auto` (product default) | Fail-open → `NullFewShotRetriever` (pure residual FM) |
| `.wax` | Throws (`seedNotFound` / `seedFailed`) |
| `.off` | Always null retriever |

Reseed when the store is missing **or** seed content hash ≠ sidecar `*.wax.seedsha`
(owned by `FewShotRuntime` / `FewShotSeedBootstrap`, not the host).

### Host wiring sketch

```swift
import FMSteward

// 1) Resolve seed (explicit → App Support → package fixture → nil)
let seedURL = SeedPathResolver.resolve(
    explicit: hostSeedOverride,                         // or nil
    appSupportSeed: SeedPathResolver.productAppSupportSeedURL(),
    packageSeed: packageFixtureSeedURL                  // or nil in installed hosts
)

// 2) Product store under Application Support
let storeURL = FewShotStorePaths.productStoreURL()
try? FewShotStorePaths.ensureParentDirectory(for: storeURL)

// 3) Residual retriever — ONLY via FewShotRuntime (not Classifier)
let mode: FewShotMode = .auto
let retriever: any FewShotRetriever
if let seedURL {
    retriever = try await FewShotRuntime.makeRetriever(
        mode: mode,
        seedURL: seedURL,
        storeURL: storeURL
        // searchMode defaults to .text (product path)
    )
} else if mode == .wax {
    // no seed → wax must error; auto would use Null
    throw … // host maps to fail-closed or operator message
} else {
    retriever = NullFewShotRetriever()  // auto / off without seed
}

// 4) Preferred host API — residual few-shot + timeout race
let session = StewardSession(
    backend: LiveBackend.preferredDefault(),
    fewShotRetriever: retriever
)
await session.warm()
let response = await session.classify(card)
```

### Honesty (Phase 3 attach)

- **Not production Zig hooks yet.** Phase 3 does not call FM from `hook.zig` /
  `shell_eval.zig` (see [Scope / W4](#scope--not-done-w4)). Host attach here means
  Mac demo / embed of the Swift library only.
- **Assist only.** Wax neighbors + on-device FM are residual soft-seatbelt assist —
  not sole security. Zig hard fence still owns catastrophe deny. Fail-open on
  store/search errors → empty few-shots → normal FM / unavailable path.
- Prefer sequential `StewardSession.classify` from one owner (actor single-flight).
