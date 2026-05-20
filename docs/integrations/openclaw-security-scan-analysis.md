# OpenClaw Plugin Security Scan — Deep Analysis

## Problem

The Orca OpenClaw plugin is blocked by OpenClaw's security scanner because it uses `child_process.execSync` to call the `orca` binary. This is legitimate and necessary — the plugin is a thin wrapper around the Orca CLI.

## Root Cause

OpenClaw's `skill-scanner-ChU7r8Ij.js` has a blanket rule:

```javascript
{
    ruleId: "dangerous-exec",
    severity: "critical",
    message: "Shell command execution detected (child_process)",
    pattern: /\b(exec|execSync|spawn|spawnSync|execFile|execFileSync)\s*\(/,
    requiresContext: /child_process/
}
```

Any plugin importing `child_process` and calling `execSync`/`spawn` gets blocked with critical severity. There is no way to declare legitimate use.

## Scanner Bypass Options (from OpenClaw source)

1. **`--dangerously-force-unsafe-install`**
   - User explicitly overrides the scan
   - Shows warnings but allows install
   - **Current workaround**

2. **`trustedSourceLinkedOfficialInstall`**
   - Only for `channel: "official"`, `isOfficial: true`, `verification.tier: "source-linked"`, `sourceRepo: "openclaw/openclaw"`
   - Only official OpenClaw org packages bypass the scan
   - Third-party plugins cannot meet this criteria

3. **Bundled plugins**
   - OpenClaw's own `/dist/extensions/` are not scanned
   - External plugins are always scanned

## Plugin Manifest Gap

The `PluginManifest` type (`manifest.d.ts`) has no permissions/capabilities field. Unlike:
- VS Code extensions: `capabilities` in manifest
- Browser extensions: `permissions` array
- Chrome apps: Explicit permission model

OpenClaw's manifest only has activation hints, model support, and config contracts. No security capability declarations.

## Fix Options

### Option 1: OpenClaw adds permissions model (Best long-term)

Add to `openclaw.plugin.json`:
```json
{
  "id": "orca",
  "permissions": ["child_process"],
  "permissionJustifications": {
    "child_process": "Required to call local Orca CLI binary for policy enforcement"
  }
}
```

Scanner would check: "Does plugin declare this permission? If yes, skip the rule."

**Requires OpenClaw framework change.**

### Option 2: OpenClaw adds trusted third-party list

```javascript
const TRUSTED_THIRD_PARTY_PLUGINS = [
  'christopherkarani/orca-openclaw-plugin',
  // other vetted plugins
];
```

**Requires OpenClaw framework change.**

### Option 3: Orca exposes HTTP API for hooks

If `orca --http` exposed endpoints like `POST /hook/openclaw/tool.before`, the plugin could use `fetch()` which the scanner allows. Plugin would try HTTP first, fall back to child_process.

**Requires Orca change + OpenClaw plugin refactor.**

### Option 4: OpenClaw exposes blessed spawn API

```typescript
api.runtime.spawnExternal('orca', ['hook', 'openclaw', event], { input: payloadJson })
```

The framework handles spawning, not the plugin. The scanner would trust framework calls.

**Requires OpenClaw framework change.**

### Option 5: Status quo with better UX

- Document `--dangerously-force-unsafe-install` clearly
- Rename flag to something less scary like `--allow-process-spawn`
- Add config option to permanently trust specific plugins

**Requires OpenClaw UX change.**

## Recommended Path

**Immediate:** Document `--dangerously-force-unsafe-install` in README (done).

**Short-term:** Open an issue with OpenClaw requesting a permissions model in plugin manifests. Reference this analysis.

**Medium-term:** If OpenClaw team is receptive, implement Option 1 or 4.

**Fallback:** If no framework change is possible, explore Option 3 (HTTP API) as an alternative architecture.

## Files Analyzed

- `/Users/chriskarani/.nvm/versions/node/v24.13.0/lib/node_modules/openclaw/dist/skill-scanner-ChU7r8Ij.js`
- `/Users/chriskarani/.nvm/versions/node/v24.13.0/lib/node_modules/openclaw/dist/install-security-scan.runtime-CVPdJBEm.js`
- `/Users/chriskarani/.nvm/versions/node/v24.13.0/lib/node_modules/openclaw/dist/plugin-sdk/src/plugins/manifest.d.ts`
- `/Users/chriskarani/.nvm/versions/node/v24.13.0/lib/node_modules/openclaw/dist/clawhub-BJcyN7a2.js`

## Date

2026-05-20
