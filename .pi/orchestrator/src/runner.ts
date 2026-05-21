/**
 * Pi SDK session runner for the Orca sub-agent orchestrator.
 *
 * Spawns an ephemeral Pi session with a specialist system prompt,
 * runs the task prompt, captures the transcript, and enforces safety bounds.
 */

import {
  AuthStorage,
  createAgentSession,
  DefaultResourceLoader,
  ModelRegistry,
  SessionManager,
  SettingsManager,
  type AgentSessionEvent,
} from "@earendil-works/pi-coding-agent";
import { getModel, type Model } from "@earendil-works/pi-ai";
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyModel = Model<any>;
import { type RunResult, type Task, type OrchestratorConfig } from "./types.js";
import { getSpecialistConfig } from "./specialists.js";

function resolveHome(path: string): string {
  if (path.startsWith("~/")) {
    return path.replace("~", process.env.HOME ?? process.env.USERPROFILE ?? ".");
  }
  return path;
}

function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_resolve, reject) => {
      setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms);
    }),
  ]);
}

export async function runTask(task: Task, config: OrchestratorConfig): Promise<RunResult> {
  const specialist = getSpecialistConfig(task.type);
  const maxTurns = task.maxTurns ?? specialist.defaultMaxTurns;
  const timeoutMs = config.timeoutMs ?? 300_000;
  const startTime = Date.now();

  const transcriptParts: string[] = [];
  const toolCalls: RunResult["toolCalls"] = [];
  let turnCount = 0;
  let currentToolCall: { toolName: string; args: unknown } | null = null;
  let aborted = false;

  // Build auth and model
  const agentDir = resolveHome(config.agentDir);
  const authStorage = AuthStorage.create(agentDir);
  const modelRegistry = ModelRegistry.create(authStorage);

  let model: AnyModel | undefined;
  if (config.model) {
    const [provider, id] = config.model.split("/");
    if (provider && id) {
      model = getModel(provider as any, id as any) ?? undefined;
      if (!model) {
        const available = await modelRegistry.getAvailable();
        model = available[0];
      }
    }
  }
  if (!model) {
    const available = await modelRegistry.getAvailable();
    model = available[0];
  }
  if (!model) {
    throw new Error("No model available. Configure an API key in ~/.pi/agent/auth.json or set env vars.");
  }

  // Build resource loader with specialist system prompt
  const settingsManager = SettingsManager.inMemory({
    compaction: { enabled: false }, // Keep full transcript
    retry: { enabled: true, maxRetries: 1 },
  });

  const loader = new DefaultResourceLoader({
    cwd: config.cwd,
    agentDir,
    settingsManager,
    systemPromptOverride: () => specialist.systemPrompt,
  });
  await loader.reload();

  const { session } = await createAgentSession({
    cwd: config.cwd,
    agentDir,
    model,
    thinkingLevel: (config.thinkingLevel as any) ?? "medium",
    authStorage,
    modelRegistry,
    tools: specialist.tools,
    resourceLoader: loader,
    sessionManager: SessionManager.inMemory(),
    settingsManager,
  });

  // Event subscriptions
  const unsubscribe = session.subscribe((event: AgentSessionEvent) => {
    switch (event.type) {
      case "message_update": {
        if (event.assistantMessageEvent.type === "text_delta") {
          transcriptParts.push(event.assistantMessageEvent.delta);
        }
        break;
      }
      case "turn_start": {
        turnCount++;
        if (turnCount > maxTurns && !aborted) {
          aborted = true;
          console.warn(`[Orchestrator] Task ${task.id} exceeded maxTurns (${maxTurns}). Aborting.`);
          session.abort().catch(() => {});
        }
        break;
      }
      case "tool_execution_start": {
        currentToolCall = { toolName: event.toolName, args: event.args };
        transcriptParts.push(`\n[TOOL CALL: ${event.toolName}]\n`);
        break;
      }
      case "tool_execution_end": {
        if (currentToolCall) {
          toolCalls.push({
            toolName: currentToolCall.toolName,
            args: currentToolCall.args,
            result: event.result,
            isError: event.isError,
          });
          currentToolCall = null;
        }
        transcriptParts.push(`\n[TOOL RESULT: ${event.isError ? "ERROR" : "OK"}]\n`);
        break;
      }
    }
  });

  // Run with timeout
  let promptError: Error | undefined;
  try {
    await withTimeout(session.prompt(task.prompt), timeoutMs, `Task ${task.id}`);
  } catch (err) {
    promptError = err instanceof Error ? err : new Error(String(err));
    if (!aborted) {
      aborted = true;
      try { await session.abort(); } catch { /* ignore */ }
    }
  }

  const durationMs = Date.now() - startTime;
  unsubscribe();
  session.dispose();

  const transcript = transcriptParts.join("");

  if (promptError && !transcript.trim()) {
    return {
      taskId: task.id,
      status: "failed",
      transcript: `Error: ${promptError.message}`,
      toolCalls,
      turns: turnCount,
      durationMs,
      error: promptError.message,
    };
  }

  return {
    taskId: task.id,
    status: aborted ? "aborted" : "done",
    transcript,
    toolCalls,
    turns: turnCount,
    durationMs,
    error: promptError?.message,
  };
}
