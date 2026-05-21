/**
 * Specialist definitions for the Orca sub-agent orchestrator.
 *
 * Prompts are loaded from the project skill files for DRYness.
 * Falls back to inline prompts if skill files are missing.
 */

import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import type { SpecialistKey } from "./types.js";

const SKILL_DIR = join(process.cwd(), ".pi", "skills");

function loadSkillMarkdown(name: string): string | null {
  const path = join(SKILL_DIR, name, "SKILL.md");
  if (!existsSync(path)) return null;
  try {
    const content = readFileSync(path, "utf-8");
    // Strip frontmatter (everything between first --- pair)
    const match = content.match(/^---\s*\n[\s\S]*?\n---\s*\n([\s\S]*)$/);
    return match ? match[1].trim() : content.trim();
  } catch {
    return null;
  }
}

export interface SpecialistConfig {
  key: SpecialistKey;
  label: string;
  systemPrompt: string;
  defaultMaxTurns: number;
  /** Which built-in tools this specialist needs */
  tools: string[];
}

const INLINE_PROMPTS: Record<SpecialistKey, string> = {
  zig: `You are the Orca Zig Specialist. Your expertise is the Zig codebase of the Aegis/Orca security runtime.

Scope: src/core/, src/cli/, src/intercept/, src/mcp/, src/sandbox/, src/redteam/, src/audit/, packages/core/, packages/cli/, build.zig
Rules: explicit allocators, error unions, comptime where readable, TDD mandatory, narrowest test first.
Before calling work complete, run the verification checklist from the orca-zig-specialist skill.`,

  ts: `You are the Orca TypeScript Specialist. Your expertise is the plugin integrations and dashboard UI.

Scope: integrations/, orca-dashboard-ui/, src/dashboard/, schemas/
Rules: strict TypeScript, no any, plugin fixtures synchronized, dashboard QA with playwright.
Before calling work complete, run the verification checklist from the orca-ts-specialist skill.`,

  policy: `You are the Orca Policy Specialist. Your expertise is the declarative security policy system.

Scope: policies/presets/, schemas/policy-v1.json, schemas/event-v1.json, src/policy/
Rules: backwards-compatible changes, validate against schema, redteam parity for relaxations.
Before calling work complete, run the verification checklist from the orca-policy-specialist skill.`,

  explore: `You are the Orca Explore Agent. Your job is to investigate the codebase and report findings without making changes.

Method: Start with src/root.zig and build.zig. Use read and bash (rg, fd) to trace call graphs. Summarize findings in a structured report.
CRITICAL: NEVER write, edit, or delete files. Only read, search, and summarize.`,

  plan: `You are the Orca Planning Agent. Your job is to create implementation plans before any code is written.

Method: Restate requirements, identify affected modules, break into phases with file-level tasks, assess risks, wait for explicit user confirmation.
CRITICAL: NEVER write implementation code. Output plans only.`,
};

export function getSpecialistConfig(key: SpecialistKey): SpecialistConfig {
  const loaded = loadSkillMarkdown(`orca-${key}-specialist`);
  const prompt = loaded ?? INLINE_PROMPTS[key];

  const defaults: Record<SpecialistKey, Omit<SpecialistConfig, "key" | "systemPrompt">> = {
    zig: { label: "Zig Specialist", defaultMaxTurns: 30, tools: ["read", "bash", "edit", "write"] },
    ts: { label: "TypeScript Specialist", defaultMaxTurns: 25, tools: ["read", "bash", "edit", "write"] },
    policy: { label: "Policy Specialist", defaultMaxTurns: 20, tools: ["read", "bash", "edit", "write"] },
    explore: { label: "Explore Agent", defaultMaxTurns: 20, tools: ["read", "bash", "grep", "find", "ls"] },
    plan: { label: "Planning Agent", defaultMaxTurns: 15, tools: ["read", "bash", "grep", "find", "ls"] },
  };

  return {
    key,
    systemPrompt: prompt,
    ...defaults[key],
  };
}

export function detectSpecialist(prompt: string): SpecialistKey | null {
  const p = prompt.toLowerCase();
  if (p.includes("zig") || p.includes("build.zig") || p.includes("allocator") || p.includes("src/core/") || p.includes("src/cli/")) return "zig";
  if (p.includes("typescript") || p.includes("plugin") || p.includes("dashboard") || p.includes("next.js") || p.includes("integration")) return "ts";
  if (p.includes("policy") || p.includes("yaml") || p.includes("schema") || p.includes("preset")) return "policy";
  if (p.includes("explore") || p.includes("investigate") || p.includes("understand") || p.includes("find where")) return "explore";
  if (p.includes("plan") || p.includes("design") || p.includes("architecture")) return "plan";
  return null;
}
