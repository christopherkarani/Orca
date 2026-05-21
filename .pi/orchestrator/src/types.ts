/**
 * Core types for the Orca sub-agent orchestrator.
 */

export type TaskStatus = "pending" | "running" | "done" | "failed" | "cancelled";

export type SpecialistKey = "zig" | "ts" | "policy" | "explore" | "plan";

export interface Task {
  /** Unique task identifier (kebab-case) */
  id: string;
  /** Specialist type that determines system prompt and allowed tools */
  type: SpecialistKey;
  /** The prompt sent to the sub-agent */
  prompt: string;
  /** Current execution status */
  status: TaskStatus;
  /** Task IDs that must complete before this task can start */
  blockedBy: string[];
  /** Parent task ID for tree structure */
  parentId: string | null;
  /** Maximum LLM turns before auto-abort (safety bound) */
  maxTurns?: number;
  /** Path to saved result file (auto-populated) */
  resultFile?: string;
  /** ISO timestamp when task was created */
  createdAt: string;
  /** ISO timestamp when task started running */
  startedAt?: string;
  /** ISO timestamp when task finished */
  finishedAt?: string;
  /** Error message if status is failed */
  error?: string;
}

export interface OrchestratorConfig {
  /** Max concurrent Pi sessions (start with 1) */
  maxConcurrency: number;
  /** Max dispatch loops before exit (safety bound) */
  maxIterations: number;
  /** Working directory for Pi discovery (project root) */
  cwd: string;
  /** Global Pi agent directory */
  agentDir: string;
  /** Optional model override (provider/id, e.g. "anthropic/claude-sonnet-4") */
  model?: string;
  /** Optional thinking level override */
  thinkingLevel?: "off" | "minimal" | "low" | "medium" | "high" | "xhigh";
  /** Per-task timeout in milliseconds */
  timeoutMs?: number;
  /** Directory to write result files */
  resultsDir: string;
  /** Whether to include the orchestrator extension in sub-sessions (default false) */
  includeOrchestratorExtension?: boolean;
}

export interface TaskRegistry {
  /** Schema version */
  version: number;
  /** All tasks in the queue */
  tasks: Task[];
  /** Orchestrator configuration */
  config: OrchestratorConfig;
}

export interface RunResult {
  taskId: string;
  status: "done" | "failed" | "aborted";
  transcript: string;
  toolCalls: ToolCallRecord[];
  turns: number;
  durationMs: number;
  error?: string;
}

export interface ToolCallRecord {
  toolName: string;
  args: unknown;
  result?: unknown;
  isError: boolean;
}
