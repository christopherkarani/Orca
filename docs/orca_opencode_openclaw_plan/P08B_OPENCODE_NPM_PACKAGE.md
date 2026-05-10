# P08B — OpenCode npm Package

## Objective

Package the existing Orca OpenCode plugin for npm distribution.

At the end of this phase, users should be able to add the Orca OpenCode plugin to `opencode.json` as:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@orca/opencode-plugin"]
}
```

This phase assumes local OpenCode plugin support already exists from P08.

---

## Recommended Effort

```text
Medium
```

Use High only if the existing OpenCode plugin needs substantial restructuring.

---

## Scope

Implement npm packaging for:

```text
@orca/opencode-plugin
```

Expected package directory:

```text
packages/opencode-plugin/
  package.json
  README.md
  src/
    index.ts
  dist/
    index.js
    index.d.ts
  tsconfig.json
```

If your repo already uses:

```text
integrations/opencode-plugin/
```

then either:

1. keep the source there and package from there, or
2. create `packages/opencode-plugin/` and copy/adapt source.

Prefer minimal churn.

---

## Non-goals

Do not bundle the Orca Zig CLI.

Do not compile Zig during npm install.

Do not add MCP behavior.

Do not add drone plugin behavior.

Do not publish to npm automatically unless explicitly requested.

---

## Implementation Tasks

### 1. Package Metadata

Create or update `package.json`:

```json
{
  "name": "@orca/opencode-plugin",
  "version": "1.0.0",
  "description": "OpenCode plugin wrapper for Orca runtime guardrails.",
  "type": "module",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": [
    "dist",
    "README.md",
    "package.json"
  ],
  "keywords": [
    "opencode",
    "plugin",
    "orca",
    "ai-agents",
    "security",
    "guardrails"
  ],
  "license": "Apache-2.0",
  "peerDependencies": {
    "@opencode-ai/plugin": "*"
  }
}
```

Adjust license/version to match the repo.

### 2. Runtime JS Output

Ensure npm package ships built JavaScript:

```text
dist/index.js
```

Do not require users to run TypeScript compilation manually.

### 3. Plugin Behavior

The plugin should:

- export an OpenCode plugin function
- call `orca hook opencode ...`
- call `orca plugin doctor opencode` where useful
- handle missing `orca` gracefully
- avoid printing secrets
- avoid persisting raw hook payloads
- not duplicate Orca policy logic

### 4. Docs

Create or update:

```text
docs/integrations/opencode.md
packages/opencode-plugin/README.md
```

Docs should include:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@orca/opencode-plugin"]
}
```

Also include local install fallback:

```bash
mkdir -p ~/.config/opencode/plugins
cp integrations/opencode-plugin/orca.ts ~/.config/opencode/plugins/orca.ts
```

Required wording:

```text
The strongest local protection remains running OpenCode through `orca run -- opencode`; the OpenCode plugin provides native hooks and guardrails inside OpenCode.
```

Required limitation:

```text
The OpenCode plugin does not add MCP server behavior or drone-specific plugin features.
```

### 5. Packaging Script

Update or add:

```text
scripts/package-npm-plugins.sh
```

or update existing packaging scripts to produce:

```text
dist/npm/orca-opencode-plugin-vX.Y.Z.tgz
```

Use `npm pack --dry-run` or equivalent for validation.

### 6. Tests

Add tests for:

- package.json valid JSON
- package name is `@orca/opencode-plugin`
- dist output exists
- README contains install instructions
- plugin source calls `orca`
- plugin source does not duplicate policy logic
- plugin source does not include secrets
- plugin source does not include drone or MCP behavior
- npm pack includes only expected files
- existing OpenCode hook fixtures still pass

---

## Commands to Run

```bash
zig build
zig build test

./zig-out/bin/orca plugin doctor opencode
./zig-out/bin/orca plugin install opencode --dry-run

cat tests/plugin-fixtures/opencode/tool_execute_before_command_dangerous.json \
  | ./zig-out/bin/orca hook opencode tool.execute.before

npm pack --dry-run ./packages/opencode-plugin
```

If package source remains under `integrations/opencode-plugin`, adjust the npm command accordingly.

---

## Acceptance Criteria

- `@orca/opencode-plugin` package metadata exists.
- built JS output exists.
- npm dry-run pack works.
- docs explain `opencode.json` usage.
- plugin requires `orca` on PATH.
- no Zig binary bundling.
- no MCP behavior.
- no drone plugin behavior.
- no secrets.
- existing Orca tests pass.
- existing Codex and Claude plugins still work.

---

## Deliverable

Create or update:

```text
docs/integrations/p08b-opencode-npm-package.md
```

Include:

- summary
- package path
- package name
- build output status
- npm pack status
- docs updated
- tests run
- known limitations
- whether npm publication is ready

---

## Handoff

At the end, provide:

- files changed
- tests run
- npm packaging status
- package artifact status
- secret-safety result
- known limitations
- whether `@orca/opencode-plugin` is ready to publish
