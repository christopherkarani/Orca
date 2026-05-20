# Orca Plugin Demo

## Overview

This demo shows Orca Codex and Claude Code plugin flows using checked-in synthetic fixtures and deterministic CLI behavior. It is meant for local validation, documentation, and regression checks only.

This deterministic demo uses fake hook payloads. It does not require real Codex, Claude Code, a real LLM, real secrets, external network access, MCP, or drone hardware.

See the host-specific walkthroughs in [codex-demo.md](codex-demo.md) and [claude-demo.md](claude-demo.md). The checked-in payload index is in [fake-hook-payloads/README.md](fake-hook-payloads/README.md).

## Prerequisites

- Zig 0.15.2
- A built Orca binary (`./zig-out/bin/orca`)

## Demo flow

1. Build Orca:
   ```bash
   zig build
   ```

2. Package plugins:
   ```bash
   ./scripts/package-plugins.sh
   ```

3. Verify plugin doctor for codex:
   ```bash
   ./zig-out/bin/orca plugin doctor codex
   ```

4. Verify plugin doctor for claude:
   ```bash
   ./zig-out/bin/orca plugin doctor claude
   ```

5. Trigger fake Codex hook:
   ```bash
   cat tests/plugin-fixtures/codex/pre_tool_use_command_dangerous.json | ./zig-out/bin/orca hook codex PreToolUse
   ```

6. Trigger fake Claude hook:
   ```bash
   cat tests/plugin-fixtures/claude/pre_tool_use_command_dangerous.json | ./zig-out/bin/orca hook claude PreToolUse
   ```

7. Run redteam:
   ```bash
   ./zig-out/bin/orca redteam --ci
   ```

8. Run replay:
   ```bash
   ./zig-out/bin/orca replay --session last --verify
   ```

   This step may need a prior Orca run session.

9. Explain limitations:
   - The demo proves deterministic local policy evaluation and replay formatting.
   - It does not claim host-side enforcement beyond what the plugin hooks and Orca can actually do.
   - It does not require or use real Codex/Claude sessions, secrets, network access, MCP, or hardware integrations.

## Security note

Use only the checked-in fake payloads under `tests/plugin-fixtures/`. Do not substitute real secrets, external services, or production host data.
