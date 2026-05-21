/**
 * Task dispatcher: finds ready tasks, runs them via Pi SDK sessions,
 * captures results, and updates the registry.
 */

import { writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import type { TaskRegistry, RunResult, Task } from "./types.js";
import { getReadyTasks, updateTask, saveRegistry, countTasksByStatus } from "./registry.js";
import { runTask } from "./runner.js";

export interface DispatchOptions {
  registry: TaskRegistry;
  registryPath: string;
  dryRun?: boolean;
}

export async function dispatch(options: DispatchOptions): Promise<void> {
  const { registry, registryPath, dryRun = false } = options;
  const config = registry.config;

  // Ensure results directory exists
  if (!existsSync(config.resultsDir)) {
    mkdirSync(config.resultsDir, { recursive: true });
  }

  console.log(`\n=== Orca Sub-Agent Orchestrator ===`);
  console.log(`Total tasks: ${registry.tasks.length}`);
  console.log(`Pending: ${countTasksByStatus(registry, "pending")}`);
  console.log(`Running: ${countTasksByStatus(registry, "running")}`);
  console.log(`Done: ${countTasksByStatus(registry, "done")}`);
  console.log(`Failed: ${countTasksByStatus(registry, "failed")}`);
  console.log(`Max concurrency: ${config.maxConcurrency}`);
  console.log(`Max iterations: ${config.maxIterations}`);
  console.log(`Model: ${config.model ?? "auto"}`);
  console.log("");

  if (dryRun) {
    const ready = getReadyTasks(registry);
    console.log(`[DRY RUN] Ready tasks (${ready.length}):`);
    for (const t of ready) {
      console.log(`  - ${t.id} (${t.type}): ${t.prompt.slice(0, 80)}...`);
    }
    return;
  }

  let iterations = 0;

  while (iterations < config.maxIterations) {
    iterations++;
    const ready = getReadyTasks(registry);

    if (ready.length === 0) {
      const running = registry.tasks.filter((t) => t.status === "running");
      if (running.length === 0) {
        console.log(`\n[Iteration ${iterations}] No ready or running tasks. Orchestrator idle.`);
        break;
      }
      console.log(`\n[Iteration ${iterations}] No ready tasks. Waiting for ${running.length} running task(s)...`);
      // In sequential mode, this shouldn't happen because we await each run.
      break;
    }

    // Pick tasks up to maxConcurrency
    const batch = ready.slice(0, config.maxConcurrency);
    console.log(`\n[Iteration ${iterations}] Dispatching ${batch.length} task(s): ${batch.map((t) => t.id).join(", ")}`);

    // Mark as running and save
    for (const task of batch) {
      updateTask(registry, task.id, { status: "running", startedAt: new Date().toISOString() });
    }
    saveRegistry(registryPath, registry);

    // Run tasks (sequential for now to avoid Pi global state issues)
    for (const task of batch) {
      console.log(`\n>>> Starting task: ${task.id} (${task.type})`);
      console.log(`    Prompt: ${task.prompt.slice(0, 120)}${task.prompt.length > 120 ? "..." : ""}`);

      let result: RunResult;
      try {
        result = await runTask(task, config);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error(`    ERROR: ${message}`);
        result = {
          taskId: task.id,
          status: "failed",
          transcript: `Fatal error: ${message}`,
          toolCalls: [],
          turns: 0,
          durationMs: 0,
          error: message,
        };
      }

      // Save result file
      const resultPath = join(config.resultsDir, `${task.id}.md`);
      const resultContent = buildResultMarkdown(task, result);
      writeFileSync(resultPath, resultContent, "utf-8");

      // Update registry
      const finalStatus = result.status === "done" ? "done" : "failed";
      updateTask(registry, task.id, {
        status: finalStatus,
        finishedAt: new Date().toISOString(),
        resultFile: resultPath,
        error: result.error,
      });
      saveRegistry(registryPath, registry);

      // Print summary
      console.log(`    Status: ${result.status} | Turns: ${result.turns} | Duration: ${(result.durationMs / 1000).toFixed(1)}s`);
      console.log(`    Tools used: ${result.toolCalls.length} | Result: ${resultPath}`);
      if (result.error) {
        console.log(`    Error: ${result.error}`);
      }
    }
  }

  // Final summary
  console.log(`\n=== Orchestrator Complete ===`);
  console.log(`Iterations run: ${iterations}`);
  for (const status of ["pending", "running", "done", "failed", "cancelled"] as const) {
    const count = countTasksByStatus(registry, status);
    if (count > 0) console.log(`  ${status}: ${count}`);
  }
  console.log("");
}

function buildResultMarkdown(task: Task, result: RunResult): string {
  const lines: string[] = [
    `# Task Result: ${task.id}`,
    "",
    `**Type:** ${task.type}`,
    `**Status:** ${result.status}`,
    `**Turns:** ${result.turns}`,
    `**Duration:** ${(result.durationMs / 1000).toFixed(1)}s`,
    `**Started:** ${task.startedAt ?? "unknown"}`,
    `**Finished:** ${new Date().toISOString()}`,
    "",
    "## Prompt",
    "",
    task.prompt,
    "",
    "## Transcript",
    "",
    result.transcript || "_(No transcript captured)_",
    "",
  ];

  if (result.toolCalls.length > 0) {
    lines.push("## Tool Calls", "");
    for (const tc of result.toolCalls) {
      lines.push(`### ${tc.toolName}`);
      lines.push("");
      lines.push("```json");
      lines.push(JSON.stringify(tc.args, null, 2));
      lines.push("```");
      lines.push("");
      lines.push(`Result: ${tc.isError ? "ERROR" : "OK"}`);
      if (tc.result) {
        lines.push("");
        lines.push("```json");
        lines.push(JSON.stringify(tc.result, null, 2).slice(0, 2000));
        lines.push("```");
      }
      lines.push("");
    }
  }

  if (result.error) {
    lines.push("## Error", "", result.error, "");
  }

  return lines.join("\n");
}
