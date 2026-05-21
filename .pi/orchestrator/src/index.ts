#!/usr/bin/env node
/**
 * Orca Sub-Agent Orchestrator CLI
 *
 * Usage:
 *   npx tsx src/index.ts                    # Run orchestrator with default tasks.yaml
 *   npx tsx src/index.ts --dry-run          # Show ready tasks without running
 *   npx tsx src/index.ts --registry path    # Use custom registry
 *   npx tsx src/index.ts --add-task         # Add a task interactively
 *   npx tsx src/index.ts --status           # Show task status summary
 */

import { resolve, join } from "node:path";
import { existsSync } from "node:fs";
import { loadRegistry, saveRegistry } from "./registry.js";
import { dispatch } from "./dispatcher.js";
import { detectSpecialist } from "./specialists.js";
import type { Task, TaskStatus } from "./types.js";

function parseArgs(argv: string[]): Record<string, string | boolean> {
  const args: Record<string, string | boolean> = {};
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith("--")) {
        args[key] = next;
        i++;
      } else {
        args[key] = true;
      }
    }
  }
  return args;
}

function printHelp(): void {
  console.log(`
Orca Sub-Agent Orchestrator

A Paperclip-style task orchestrator for the Aegis/Orca project using the Pi SDK.

USAGE:
  node dist/index.js [OPTIONS]

OPTIONS:
  --registry <path>    Path to tasks.yaml (default: .pi/orchestrator/tasks.yaml)
  --dry-run            Show ready tasks without dispatching agents
  --status             Print task status summary and exit
  --add-task           Add a new task interactively (reads from stdin)
  --model <provider/id> Override model (e.g. anthropic/claude-sonnet-4)
  --help               Show this help

EXAMPLES:
  # Run all ready tasks
  node dist/index.js

  # Preview what would run
  node dist/index.js --dry-run

  # Add a task and run
  echo 'Add landlock sandbox support' | node dist/index.js --add-task

  # Check overall progress
  node dist/index.js --status
`);
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv);

  if (args.help) {
    printHelp();
    process.exit(0);
  }

  const cwd = process.cwd();
  const defaultRegistryPath = join(cwd, ".pi", "orchestrator", "tasks.yaml");
  const registryPath = resolve(String(args.registry ?? defaultRegistryPath));

  // Ensure registry exists
  let registry = loadRegistry(registryPath);

  // --status: print and exit
  if (args["status"]) {
    console.log(`\nRegistry: ${registryPath}`);
    console.log(`Tasks: ${registry.tasks.length}`);
    const counts = new Map<TaskStatus, number>();
    for (const t of registry.tasks) {
      counts.set(t.status, (counts.get(t.status) ?? 0) + 1);
    }
    for (const [status, count] of counts) {
      console.log(`  ${status}: ${count}`);
    }
    console.log("");
    process.exit(0);
  }

  // --add-task: read from stdin
  if (args["add-task"]) {
    const input = await readStdin();
    const lines = input.split("\n").filter((l) => l.trim());
    if (lines.length === 0) {
      console.error("No input provided for --add-task.");
      process.exit(1);
    }

    for (const line of lines) {
      const id = `task-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
      const detected = detectSpecialist(line);
      const type = detected ?? "explore";
      const task: Task = {
        id,
        type,
        prompt: line.trim(),
        status: "pending",
        blockedBy: [],
        parentId: null,
        createdAt: new Date().toISOString(),
      };
      registry.tasks.push(task);
      console.log(`Added task ${id} (${type}): ${line.slice(0, 60)}...`);
    }
    saveRegistry(registryPath, registry);
    console.log("Registry saved.");
  }

  // Run dispatcher
  await dispatch({
    registry,
    registryPath,
    dryRun: !!args["dry-run"],
  });
}

function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf-8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => {
      resolve(data);
    });
    // If stdin is a TTY (no pipe), resolve empty after a tick
    if (process.stdin.isTTY) {
      setTimeout(() => resolve(""), 50);
    }
  });
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
