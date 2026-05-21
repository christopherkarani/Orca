# Orca Sub-Agent Orchestrator

A **Paperclip-style task orchestrator** for the Aegis/Orca project using the [Pi SDK](https://github.com/earendil-works/pi-coding-agent). Spawns specialist sub-agents (Zig, TypeScript, Policy, Explore, Plan) with dependency-aware dispatch, automatic status tracking, and structured result capture.

---

## Quick Start

```bash
# From project root
cd .pi/orchestrator
npm install       # One-time setup
npm run build     # Compile TypeScript

# Check task status
node dist/index.js --status

# Preview what would run
node dist/index.js --dry-run

# Run all ready tasks
node dist/index.js
```

---

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   tasks.yaml    │────▶│   Orchestrator   │────▶│  Pi SDK Session │
│  (task queue)   │     │  (dispatch loop) │     │ (specialist agent)
└─────────────────┘     └──────────────────┘     └─────────────────┘
         ▲                                              │
         │                                              ▼
         │                                       ┌──────────────┐
         └───────────────────────────────────────│  results/    │
            updates status + resultFile          │  {id}.md     │
                                                 └──────────────┘
```

1. **Define tasks** in `tasks.yaml` with types (`zig`, `ts`, `policy`, `explore`, `plan`), prompts, and `blockedBy` dependencies.
2. **Orchestrator loop** finds tasks whose blockers are `done`, marks them `running`, and spawns a Pi SDK session.
3. **Specialist session** receives a tailored system prompt (loaded from `.pi/skills/orca-{type}-specialist/SKILL.md`).
4. **Results** are saved to `.pi/orchestrator/results/{taskId}.md` with full transcript + tool calls.
5. **Status updates** flow back to `tasks.yaml`, unblocking dependent tasks automatically.

---

## Task YAML Format

```yaml
version: 1
config:
  maxConcurrency: 1          # Sequential (1) or parallel (2+)
  maxIterations: 100         # Safety bound on dispatch loops
  cwd: "."                   # Working directory for Pi
  agentDir: "~/.pi/agent"    # Global Pi config directory
  model: "anthropic/claude-sonnet-4"  # Optional model override
  thinkingLevel: "medium"    # off | minimal | low | medium | high | xhigh
  timeoutMs: 300000          # Per-task timeout (5 min default)
  resultsDir: ".pi/orchestrator/results"

tasks:
  - id: explore-sandbox
    type: explore
    prompt: "Investigate src/sandbox/linux.zig..."
    status: pending
    blockedBy: []            # No blockers = ready immediately
    parentId: null
    maxTurns: 20             # Safety: abort after N LLM turns

  - id: plan-landlock
    type: plan
    prompt: "Create implementation plan for landlock..."
    status: pending
    blockedBy:
      - explore-sandbox       # Won't start until explore-sandbox is done
    parentId: null
    maxTurns: 15

  - id: implement-landlock-zig
    type: zig
    prompt: "Implement landlock in src/sandbox/linux.zig..."
    status: pending
    blockedBy:
      - plan-landlock
    parentId: plan-landlock
    maxTurns: 30
```

### Specialist Types

| Type | Description | Default Tools | Default Max Turns |
|------|-------------|---------------|-------------------|
| `zig` | Zig core, CLI, intercept, MCP, sandbox, audit | read, bash, edit, write | 30 |
| `ts` | TypeScript plugins, dashboard, schemas | read, bash, edit, write | 25 |
| `policy` | YAML policies, JSON schemas, redteam | read, bash, edit, write | 20 |
| `explore` | Read-only codebase investigation | read, bash, grep, find, ls | 20 |
| `plan` | Implementation planning (no code) | read, bash, grep, find, ls | 15 |

---

## CLI Commands

| Command | Description |
|---------|-------------|
| `node dist/index.js` | Run all ready tasks |
| `node dist/index.js --dry-run` | Show ready tasks without dispatching |
| `node dist/index.js --status` | Print task status summary |
| `node dist/index.js --add-task` | Add task(s) from stdin |
| `node dist/index.js --registry path/to/tasks.yaml` | Use custom registry |

### Adding Tasks from CLI

```bash
# Add a single task (auto-detects specialist)
echo "Fix memory leak in src/audit/writer.zig" | node dist/index.js --add-task

# Add multiple tasks
cat <<'EOF' | node dist/index.js --add-task
Fix memory leak in src/audit/writer.zig
Update codex-plugin for new stop reasons
Add landlock policy preset
EOF
```

---

## Architecture

```
.pi/orchestrator/
├── src/
│   ├── index.ts         # CLI entry point
│   ├── registry.ts      # Task registry I/O (YAML)
│   ├── types.ts         # Task, Status, SpecialistKey types
│   ├── dispatcher.ts    # Ready-task detection + Pi session spawning
│   ├── runner.ts        # Pi SDK wrapper (system prompt, transcript capture)
│   └── specialists.ts   # Specialist prompt loading from SKILL.md files
├── dist/                # Compiled JS (after npm run build)
├── results/             # Per-task markdown transcripts
├── tasks.yaml           # Your task queue
└── package.json
```

### Key Design Decisions

1. **Sequential by default** (`maxConcurrency: 1`). Pi SDK sessions share global state; parallel execution is experimental.
2. **Ephemeral sessions**. Each task gets a fresh `SessionManager.inMemory()` — no persistence, no conversation history.
3. **Compaction disabled**. Full transcripts are captured for auditability.
4. **Max turns enforced**. The orchestrator counts `turn_start` events and calls `session.abort()` if a task goes too deep.
5. **Specialist prompts loaded from skills**. DRY: the same `SKILL.md` files power both the interactive Pi extension and the orchestrator.

---

## Integration with Interactive Pi

The orchestrator **coexists** with the interactive Pi extension (`.pi/extensions/orca-subagent-orchestrator.ts`):

- **Interactive mode**: Use `/plan`, `/zig`, `/explore` for quick ad-hoc specialist sessions.
- **Orchestrator mode**: Use `tasks.yaml` for structured, dependency-aware, multi-agent workflows.

Both load specialist prompts from the same `.pi/skills/` directory.

---

## Safety Limits

| Limit | Default | Behavior |
|-------|---------|----------|
| `maxTurns` | 15–30 (per specialist) | Abort session, mark failed |
| `timeoutMs` | 300,000 (5 min) | Abort session, mark failed |
| `maxIterations` | 100 | Stop dispatcher loop |
| `maxConcurrency` | 1 | Sequential execution |

---

## Troubleshooting

### "No model available"
Configure an API key in `~/.pi/agent/auth.json` or set env vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.).

### Task stuck in `running`
If the orchestrator crashes while a task is running, manually edit `tasks.yaml` to set the task status back to `pending`.

### Results are empty
Check that the model produced output. Some models may error silently. Inspect `results/{taskId}.md` for error details.
