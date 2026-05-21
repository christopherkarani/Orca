/**
 * Orca Sub-Agent Orchestrator
 *
 * Provides structured sub-agent delegation for the Aegis/Orca project.
 *
 * Commands:
 *   /plan [goal]       — Spawn a planning agent to break down work
 *   /explore [query]   — Spawn an exploration agent to investigate codebase
 *   /zig [task]        — Hand off to Zig specialist session
 *   /ts [task]         — Hand off to TypeScript specialist session
 *   /policy [task]     — Hand off to policy/schema specialist session
 *   /delegate [spec]   — Structured delegation with auto-specialist detection
 *
 * Tools (LLM-callable):
 *   delegate_to_specialist — Delegate a task to a specialist sub-agent
 *   report_to_parent       — Sub-agent reports findings back (used in sub-sessions)
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

interface SpecialistConfig {
  name: string;
  systemPrompt: string;
  label: string;
}

const SPECIALISTS: Record<string, SpecialistConfig> = {
  zig: {
    name: "orca-zig-specialist",
    label: "Zig Specialist",
    systemPrompt: `You are the Orca Zig Specialist. Your expertise is the Zig codebase of the Aegis/Orca security runtime.

Scope:
- src/core/, src/cli/, src/intercept/, src/mcp/, src/sandbox/, src/redteam/, src/audit/
- packages/core/, packages/cli/
- build.zig, build.zig.zon
- Zig 0.14+ idioms: GeneralPurposeAllocator, comptime, error unions, anytype interfaces

Rules:
- Use TDD: write or update tests in tests/ before implementing.
- Prefer explicit allocators. Never use std.heap.page_allocator directly in library code.
- Respect the module boundary: orca_core is the library, orca_cli is the CLI wrapper.
- When changing policy evaluation, also update schemas/ and tests/phase* files.
- Run the narrowest test first: zig build test -- <filter>`,
  },
  ts: {
    name: "orca-ts-specialist",
    label: "TypeScript Specialist",
    systemPrompt: `You are the Orca TypeScript Specialist. Your expertise is the plugin integrations and dashboard UI.

Scope:
- integrations/ (codex-plugin, claude-plugin, opencode-plugin, openclaw-plugin, hermes-plugin)
- orca-dashboard-ui/ (Next.js/Tailwind dashboard)
- src/dashboard/ (Zig backend serving the dashboard assets)
- schemas/ (JSON schemas consumed by plugins)

Rules:
- Prefer strict TypeScript. Avoid any.
- Plugin hooks must conform to the JSON-RPC/MCP transport specs in src/mcp/.
- Update fixture files in tests/plugin-fixtures/ when changing plugin protocol surfaces.
- Respect npm vs pnpm vs yarn boundaries per integration README.
- Test with playwright-qa.mjs for dashboard changes.`,
  },
  policy: {
    name: "orca-policy-specialist",
    label: "Policy Specialist",
    systemPrompt: `You are the Orca Policy Specialist. Your expertise is the declarative security policy system.

Scope:
- policies/presets/*.yaml
- schemas/policy-v1.json, schemas/event-v1.json, schemas/mcp-manifest-v1.json
- src/policy/ (compile, evaluate, explain, load, matchers, schema, validate)
- tests/fixtures/ for policy test data

Rules:
- Policy changes must be backwards-compatible or version-bumped.
- Validate against schemas/policy-v1.json before proposing changes.
- Consider the redteam implications: every policy relaxation is a potential attack vector.
- Update docs/policy.md when user-visible behavior changes.
- Run: ./zig-out/bin/orca policy validate --file <path>`,
  },
  explore: {
    name: "orca-explorer",
    label: "Explore Agent",
    systemPrompt: `You are the Orca Explore Agent. Your job is to investigate the codebase and report findings without making changes.

Method:
1. Start with src/root.zig and build.zig to understand module boundaries.
2. Use read and bash (rg, fd) to trace call graphs and find relevant files.
3. Summarize findings in a structured report: files involved, key decisions, risks, unknowns.
4. NEVER write code or edit files. Only read, search, and summarize.
5. If you discover a bug, report it with exact file:line references.`,
  },
  plan: {
    name: "orca-planner",
    label: "Planning Agent",
    systemPrompt: `You are the Orca Planning Agent. Your job is to create implementation plans before any code is written.

Method:
1. Restate requirements clearly.
2. Identify affected modules (Zig core, TS plugins, dashboard, policies, docs, tests).
3. Break into phases with explicit file-level tasks.
4. Assess risks: public/private boundary leaks, security regressions, test coverage gaps.
5. Wait for explicit user confirmation before declaring the plan final.
6. NEVER write implementation code. Output plans only.`,
  },
};

function detectSpecialist(prompt: string): string | null {
  const p = prompt.toLowerCase();
  if (p.includes("zig") || p.includes("build.zig") || p.includes("allocator") || p.includes("src/core/") || p.includes("src/cli/")) return "zig";
  if (p.includes("typescript") || p.includes("plugin") || p.includes("dashboard") || p.includes("next.js") || p.includes("integration")) return "ts";
  if (p.includes("policy") || p.includes("yaml") || p.includes("schema") || p.includes("preset")) return "policy";
  if (p.includes("explore") || p.includes("investigate") || p.includes("understand") || p.includes("find where")) return "explore";
  if (p.includes("plan") || p.includes("design") || p.includes("architecture")) return "plan";
  return null;
}

export default function (pi: ExtensionAPI) {
  let currentCtx: ExtensionContext | undefined;
  let activeSpecialist: string | null = null;

  pi.on("session_start", async (_event, ctx) => {
    currentCtx = ctx;
    activeSpecialist = null;
  });

  // Inject specialist system prompt when a specialist mode is active
  pi.on("before_agent_start", async (event, _ctx) => {
    if (!activeSpecialist) return {};
    const specialist = SPECIALISTS[activeSpecialist];
    if (!specialist) return {};
    return {
      systemPrompt: event.systemPrompt + `\n\n--- SPECIALIST MODE: ${specialist.label} ---\n${specialist.systemPrompt}\n--- END SPECIALIST MODE ---`,
    };
  });

  // Reset specialist mode after each turn so the user has to explicitly re-enter it
  pi.on("agent_end", async () => {
    activeSpecialist = null;
  });

  // Tool: delegate_to_specialist (LLM callable)
  pi.registerTool({
    name: "delegate_to_specialist",
    label: "Delegate to Specialist",
    description: "Delegate a focused task to a specialist sub-agent. Use when the current task requires deep expertise in Zig, TypeScript, policy schemas, or exploration.",
    parameters: Type.Object({
      specialist: Type.String({ description: "Specialist to delegate to: zig, ts, policy, explore, plan" }),
      task: Type.String({ description: "Clear, self-contained task description for the specialist" }),
      context: Type.String({ description: "Relevant context from the parent agent: files discussed, decisions made, constraints" }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const specialist = SPECIALISTS[params.specialist];
      if (!specialist) {
        return {
          content: [{ type: "text", text: `Unknown specialist: ${params.specialist}. Available: ${Object.keys(SPECIALISTS).join(", ")}` }],
          details: {},
        };
      }

      // For lightweight delegation, switch the current session to specialist mode for the next turn
      activeSpecialist = params.specialist;

      return {
        content: [{ type: "text", text: `Delegated to ${specialist.label}. The next response will operate in ${specialist.label} mode.\n\nTask: ${params.task}\n\nInjected specialist context. Submit your follow-up to proceed.` }],
        details: { specialist: params.specialist, mode: "injected" },
      };
    },
  });

  // Tool: spawn_isolated_specialist (creates a true sub-session via newSession)
  pi.registerTool({
    name: "spawn_isolated_specialist",
    label: "Spawn Isolated Specialist",
    description: "Spawn an isolated sub-session with a specialist. Use for complex parallel work or when you want a clean context separation.",
    parameters: Type.Object({
      specialist: Type.String({ description: "Specialist key: zig, ts, policy, explore, plan" }),
      task: Type.String({ description: "Task description" }),
      context: Type.String({ description: "Parent context to transfer" }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const specialist = SPECIALISTS[params.specialist];
      if (!specialist) {
        return { content: [{ type: "text", text: `Unknown specialist: ${params.specialist}` }], details: {} };
      }

      const handoffPrompt = `## Context from Parent Agent\n${params.context}\n\n## Task\n${params.task}\n\n## Instructions\n${specialist.systemPrompt}\n\nBegin working on the task. Report findings with file paths and specific code references.`;

      const result = await ctx.newSession({
        parentSession: ctx.sessionManager.getSessionFile(),
        withSession: async (replacementCtx) => {
          replacementCtx.ui.setEditorText(handoffPrompt);
          replacementCtx.ui.notify(`Spawned isolated ${specialist.label} session. Submit when ready.`, "info");
        },
      });

      if (result.cancelled) {
        return { content: [{ type: "text", text: "Isolated session was cancelled by user." }], details: {} };
      }

      return {
        content: [{ type: "text", text: `Spawned isolated ${specialist.label} session. Continue working there. When done, return to the parent session to integrate findings.` }],
        details: { specialist: params.specialist, mode: "isolated" },
      };
    },
  });

  // Commands for human-initiated delegation
  const registerSpecialistCommand = (key: string) => {
    pi.registerCommand(key, {
      description: `Delegate to ${SPECIALISTS[key].label} (${key === "plan" || key === "explore" ? "agent" : "specialist"})`,
      handler: async (args, ctx) => {
        if (!args.trim()) {
          ctx.ui.notify(`Usage: /${key} <task description>`, "warning");
          return;
        }
        activeSpecialist = key;
        ctx.ui.notify(`Switched to ${SPECIALISTS[key].label} mode for next turn.`, "info");
        // Pre-fill the editor with a structured prompt
        ctx.ui.setEditorText(`${args.trim()}\n\n[Operating as ${SPECIALISTS[key].label}]`);
      },
    });
  };

  Object.keys(SPECIALISTS).forEach(registerSpecialistCommand);

  // Auto-detect command: /delegate
  pi.registerCommand("delegate", {
    description: "Auto-detect specialist and delegate (usage: /delegate <task>)",
    handler: async (args, ctx) => {
      if (!args.trim()) {
        ctx.ui.notify("Usage: /delegate <task description>", "warning");
        return;
      }
      const detected = detectSpecialist(args);
      if (!detected) {
        ctx.ui.notify("Could not auto-detect specialist. Use /zig, /ts, /policy, /explore, or /plan explicitly.", "warning");
        return;
      }
      activeSpecialist = detected;
      ctx.ui.notify(`Auto-detected ${SPECIALISTS[detected].label}. Switched to specialist mode.`, "info");
      ctx.ui.setEditorText(`${args.trim()}\n\n[Auto-delegated to ${SPECIALISTS[detected].label}]`);
    },
  });
}
