/**
 * Task registry I/O: read and write tasks.yaml
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import YAML from "yaml";
import type { TaskRegistry, Task, TaskStatus } from "./types.js";

const DEFAULT_REGISTRY: TaskRegistry = {
  version: 1,
  tasks: [],
  config: {
    maxConcurrency: 1,
    maxIterations: 100,
    cwd: process.cwd(),
    agentDir: "~/.pi/agent",
    resultsDir: join(process.cwd(), ".pi", "orchestrator", "results"),
    thinkingLevel: "medium",
    timeoutMs: 300_000, // 5 minutes
  },
};

export function loadRegistry(path: string): TaskRegistry {
  if (!existsSync(path)) {
    console.warn(`Registry not found at ${path}, creating default.`);
    saveRegistry(path, DEFAULT_REGISTRY);
    return DEFAULT_REGISTRY;
  }
  const raw = readFileSync(path, "utf-8");
  const parsed = YAML.parse(raw) as TaskRegistry;
  // Merge with defaults for missing fields
  return {
    ...DEFAULT_REGISTRY,
    ...parsed,
    config: { ...DEFAULT_REGISTRY.config, ...parsed.config },
  };
}

export function saveRegistry(path: string, registry: TaskRegistry): void {
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(path, YAML.stringify(registry, { indent: 2 }), "utf-8");
}

export function findTask(registry: TaskRegistry, id: string): Task | undefined {
  return registry.tasks.find((t) => t.id === id);
}

export function updateTask(registry: TaskRegistry, id: string, patch: Partial<Task>): void {
  const idx = registry.tasks.findIndex((t) => t.id === id);
  if (idx >= 0) {
    registry.tasks[idx] = { ...registry.tasks[idx], ...patch };
  }
}

export function getReadyTasks(registry: TaskRegistry): Task[] {
  return registry.tasks.filter((t) => {
    if (t.status !== "pending") return false;
    // All blockers must be done (or cancelled, which is terminal but not success)
    const blockerStatuses = t.blockedBy.map((bid) => findTask(registry, bid)?.status);
    return blockerStatuses.every((s) => s === "done");
  });
}

export function getRunningTasks(registry: TaskRegistry): Task[] {
  return registry.tasks.filter((t) => t.status === "running");
}

export function getTerminalStatuses(): TaskStatus[] {
  return ["done", "failed", "cancelled"];
}

export function isTerminal(status: TaskStatus): boolean {
  return getTerminalStatuses().includes(status);
}

export function countTasksByStatus(registry: TaskRegistry, status: TaskStatus): number {
  return registry.tasks.filter((t) => t.status === status).length;
}

export function allTasksTerminal(registry: TaskRegistry): boolean {
  return registry.tasks.every((t) => isTerminal(t.status));
}
