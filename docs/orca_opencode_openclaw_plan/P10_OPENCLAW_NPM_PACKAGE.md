# P10 — OpenClaw npm Package

## Objective

Package the Orca OpenClaw plugin for npm distribution.

At the end of this phase, users should be able to install with:

```bash
openclaw plugins install npm:@orca/openclaw-plugin
```

or, if bare npm fallback is supported:

```bash
openclaw plugins install @orca/openclaw-plugin
```

---

## Recommended Effort

```text
Medium-High
```

Use High if OpenClaw package metadata validation is complex.

---

## Scope

Package:

```text
@orca/openclaw-plugin
```

from:

```text
integrations/openclaw-plugin/
```

or:

```text
packages/openclaw-plugin/
```

Choose the path that minimizes churn.

---

## Non-goals

Do not publish to ClawHub yet.

Do not bundle Orca Zig binary.

Do not add MCP behavior.

Do not add drone plugin behavior.

Do not auto-publish to npm unless explicitly requested.

---

## Required npm Package Contents

Package must include:

```text
package.json
openclaw.plugin.json
dist/index.js
dist/index.d.ts
README.md
```

Package must not include:

```text
src/ only without dist
node_modules
planning files
drone files
.mcp.json
real secrets
temporary files
```

---

## Package Metadata

`package.json` should include:

```json
{
  "name": "@orca/openclaw-plugin",
  "version": "1.0.0",
  "type": "module",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": [
    "dist",
    "openclaw.plugin.json",
    "README.md",
    "package.json"
  ],
  "openclaw": {
    "extensions": ["./src/index.ts"],
    "runtimeExtensions": ["./dist/index.js"]
  }
}
```

If the package is published from a location where `src/` is not shipped, adjust `openclaw.extensions` and `runtimeExtensions` according to OpenClaw’s current requirements.

---

## Build

Add or update build scripts to produce runtime JS:

```bash
npm run build
```

or:

```bash
pnpm build
```

Do not rely on TypeScript source only for npm installs.

---

## Docs

Update:

```text
docs/integrations/openclaw.md
```

Add npm install:

```bash
openclaw plugins install npm:@orca/openclaw-plugin
```

Also include:

```bash
openclaw plugins list --json
openclaw plugins doctor
```

Do not claim ClawHub install until P11.

---

## Tests

Add tests for:

- package.json valid
- npm package name correct
- openclaw field present
- runtime dist exists
- openclaw.plugin.json included
- npm pack dry-run succeeds
- tarball does not include forbidden files
- package README has install instructions
- no secrets
- no MCP behavior
- no drone behavior

---

## Commands to Run

```bash
zig build
zig build test

npm pack --dry-run ./integrations/openclaw-plugin
```

or package path used by implementation.

If OpenClaw is installed:

```bash
openclaw plugins install npm:@orca/openclaw-plugin --dry-run
```

If no dry-run exists, do not install globally without explicit confirmation.

---

## Acceptance Criteria

- npm package metadata is ready.
- runtime JS exists.
- npm pack dry-run succeeds.
- docs include npm install path.
- no ClawHub claim yet.
- no secrets.
- no MCP behavior.
- no drone plugin behavior.
- existing plugin tests pass.

---

## Deliverable

Create or update:

```text
docs/integrations/p10-openclaw-npm-package.md
```

Include:

- summary
- package path
- build status
- npm pack status
- artifact contents
- tests run
- known limitations
- whether npm publish is ready

---

## Handoff

At the end, provide:

- files changed
- tests run
- package status
- npm pack status
- docs status
- known limitations
- whether npm publishing is ready
