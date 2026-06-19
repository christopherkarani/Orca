import { spawn as nodeSpawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

type UnavailableMode = "auto" | "ask" | "noninteractive-block" | "strict" | "allow-with-warning";
type EffectiveUnavailableMode = "ask" | "noninteractive-block" | "strict" | "allow-with-warning";

type ToolCallBlock = { block: true; reason?: string };
type ToolCallResult = ToolCallBlock | undefined;

type PiToolCallEvent = {
  toolName: string;
  input?: Record<string, unknown>;
};

type PiUI = {
  select?: (title: string, options: string[], opts?: { timeout?: number; signal?: AbortSignal }) => Promise<string | undefined>;
  notify?: (message: string, type?: "info" | "warning" | "error") => void;
  setStatus?: (key: string, text: string | undefined) => void;
};

type PiContext = {
  ui?: PiUI;
  cwd?: string;
  mode?: string;
  hasUI?: boolean;
  signal?: AbortSignal;
  sessionManager?: {
    getSessionId?: () => string;
  };
};

type PiAPI = {
  on: (event: string, handler: (event: any, ctx: PiContext) => Promise<any> | any) => void;
  registerCommand: (name: string, options: { description?: string; handler: (args: string | undefined, ctx: PiContext) => Promise<void> | void }) => void;
};

type SpawnOptions = {
  stdio: ["pipe" | "ignore", "pipe" | "ignore", "pipe" | "ignore"];
  shell: false;
  signal?: AbortSignal;
};

type ChildLike = {
  stdin?: { write: (data: string) => void; end: () => void };
  stdout?: { on: (event: "data", handler: (chunk: Buffer | string) => void) => void };
  stderr?: { on: (event: "data", handler: (chunk: Buffer | string) => void) => void };
  on: (event: "error" | "close", handler: ((error: Error) => void) | ((code: number | null) => void)) => void;
};

type SpawnLike = (file: string, args: string[], options: SpawnOptions) => ChildLike;

export type OrcaEvaluateRequest = {
  schema_version: 1;
  request_id: string;
  kind: "shell_command";
  command: string;
  cwd: string;
  source: {
    host: "pi";
    tool_name: "bash";
    mode?: string;
  };
};

export type OrcaDecision =
  | { kind: "allow"; response: unknown }
  | { kind: "deny"; reason: string; response: unknown }
  | { kind: "error"; reason: string; response?: unknown; error?: Error };

type RunProcessResult = {
  code: number | null;
  stdout: string;
  stderr: string;
  error?: Error;
  timedOut?: boolean;
};

export type OrcaExtensionOptions = {
  orcaBin?: string;
  spawn?: SpawnLike;
  timeoutMs?: number;
};

const STATUS_KEY = "orca";
const DEFAULT_TIMEOUT_MS = 10_000;
const MAX_CHILD_OUTPUT_BYTES = 1024 * 1024;
const ASK_OPTIONS = [
  "Block",
  "Run once anyway",
  "Disable Orca for this Pi session",
  "Show repair instructions / run doctor",
] as const;

export function buildEvaluateRequest(command: string, ctx: PiContext): OrcaEvaluateRequest {
  return {
    schema_version: 1,
    request_id: `pi-${randomUUID()}`,
    kind: "shell_command",
    command,
    cwd: resolveCwd(ctx.cwd),
    source: {
      host: "pi",
      tool_name: "bash",
      mode: ctx.mode,
    },
  };
}

export async function runOrcaEvaluate(
  request: OrcaEvaluateRequest,
  options: Required<Pick<OrcaExtensionOptions, "orcaBin" | "spawn" | "timeoutMs">>,
): Promise<OrcaDecision> {
  const result = await runProcess(
    options.orcaBin,
    ["evaluate", "--json", "--stdin"],
    JSON.stringify(request),
    options.spawn,
    options.timeoutMs,
  );

  if (result.timedOut) {
    return { kind: "error", reason: "Orca evaluation timed out." };
  }

  if (result.error) {
    const reason =
      result.error.message === "Orca output exceeded maximum size"
        ? "Orca output exceeded maximum size."
        : "Orca is unavailable.";
    return { kind: "error", reason, error: result.error };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(result.stdout);
  } catch {
    return { kind: "error", reason: "Orca returned malformed JSON." };
  }

  const decision = getStringField(parsed, "decision");
  if (decision === "allow" && result.code === 0) {
    return { kind: "allow", response: parsed };
  }
  if (decision === "deny") {
    return { kind: "deny", reason: safeOrcaReason(parsed), response: parsed };
  }
  if (decision === "error") {
    return { kind: "error", reason: safeOrcaReason(parsed), response: parsed };
  }

  return { kind: "error", reason: `Orca returned an unexpected evaluation result (exit ${result.code ?? "unknown"}).`, response: parsed };
}

export async function runOrcaCommand(
  args: string[],
  options: Required<Pick<OrcaExtensionOptions, "orcaBin" | "spawn" | "timeoutMs">>,
): Promise<RunProcessResult> {
  return runProcess(options.orcaBin, args, undefined, options.spawn, options.timeoutMs);
}

export function resolveUnavailableMode(configured: UnavailableMode, ctx: PiContext): EffectiveUnavailableMode {
  if (configured === "auto") return isNoninteractiveSession(ctx) ? "noninteractive-block" : "ask";
  if (configured === "ask" && isNoninteractiveSession(ctx)) return "noninteractive-block";
  return configured;
}

function isNoninteractiveSession(ctx: PiContext): boolean {
  return ctx.hasUI !== true || isNoninteractiveMode(ctx.mode);
}

function isNoninteractiveMode(mode: string | undefined): boolean {
  return mode === "print" || mode === "json" || mode === "noninteractive";
}

export function safeOrcaReason(response: unknown): string {
  const reason = getStringField(response, "reason") ?? getNestedStringField(response, ["error", "message"]);
  const rule = getStringField(response, "rule_id");
  const cleanReason = sanitizeVisibleText(reason ?? "Orca blocked this bash command.");
  const cleanRule = rule ? sanitizeVisibleText(rule) : undefined;
  return cleanRule ? `${cleanReason} [${cleanRule}]` : cleanReason;
}

export function installOrcaExtension(pi: PiAPI, extensionOptions: OrcaExtensionOptions = {}): void {
  const runtime = {
    orcaBin: extensionOptions.orcaBin ?? process.env.ORCA_BIN ?? "orca",
    spawn: extensionOptions.spawn ?? (nodeSpawn as unknown as SpawnLike),
    timeoutMs: extensionOptions.timeoutMs ?? Number(process.env.ORCA_PI_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS),
  };

  let unavailableMode: UnavailableMode = parseMode(process.env.ORCA_PI_MODE) ?? "auto";
  const sessionState = new Map<string, { bypass: boolean }>();

  const stateFor = (ctx: PiContext): { bypass: boolean } => {
    const key = sessionKey(ctx);
    const current = sessionState.get(key);
    if (current) return current;
    const next = { bypass: false };
    sessionState.set(key, next);
    return next;
  };

  const updateStatus = (ctx: PiContext): void => {
    if (stateFor(ctx).bypass) {
      ctx.ui?.setStatus?.(STATUS_KEY, "orca bypass");
      return;
    }
    ctx.ui?.setStatus?.(STATUS_KEY, unavailableMode === "auto" ? "orca auto" : `orca ${unavailableMode}`);
  };

  pi.on("session_start", (_event, ctx) => {
    stateFor(ctx).bypass = false;
    updateStatus(ctx);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    stateFor(ctx).bypass = false;
    ctx.ui?.setStatus?.(STATUS_KEY, undefined);
  });

  pi.on("tool_call", async (event: PiToolCallEvent, ctx: PiContext): Promise<ToolCallResult> => {
    if (event.toolName !== "bash") return undefined;

    if (typeof event.input?.command !== "string" || event.input.command.trim().length === 0) {
      return block("Blocked by Orca: malformed Pi bash tool call; missing non-empty command.");
    }
    const command = event.input.command;

    if (stateFor(ctx).bypass) {
      ctx.ui?.notify?.("Orca protection is disabled for this Pi session; bash command allowed without Orca evaluation.", "warning");
      updateStatus(ctx);
      return undefined;
    }

    const decision = await runOrcaEvaluate(buildEvaluateRequest(command, ctx), runtime);
    if (decision.kind === "allow") return undefined;
    if (decision.kind === "deny") return block(`Blocked by Orca: ${decision.reason}`);
    return handleUnavailable(decision.reason, ctx, resolveUnavailableMode(unavailableMode, ctx), {
      disableSession: () => {
        stateFor(ctx).bypass = true;
        updateStatus(ctx);
      },
    });
  });

  pi.registerCommand("orca-start", {
    description: "Start Orca's local daemon or show installation instructions.",
    handler: async (_args, ctx) => {
      const version = await runOrcaCommand(["--version"], runtime);
      if (version.error) {
        notify(ctx, orcaInstallMessage(), "error");
        return;
      }

      const result = await runOrcaCommand(["start"], runtime);
      if (result.error) {
        notify(ctx, `Unable to run Orca start: ${sanitizeVisibleText(result.error.message)}\n\nRun: orca start`, "error");
        return;
      }
      if (result.code === 0) {
        notify(ctx, "Orca start completed. Run /orca-doctor to verify daemon health.", "info");
        return;
      }
      notify(ctx, `orca start exited with ${result.code ?? "unknown"}.\n\n${summarizeCommandOutput(result)}`, "warning");
    },
  });

  pi.registerCommand("orca-doctor", {
    description: "Run Orca doctor and show setup or daemon health diagnostics.",
    handler: async (_args, ctx) => {
      const jsonDoctor = await runOrcaCommand(["doctor", "--json"], runtime);
      if (jsonDoctor.error) {
        notify(ctx, orcaInstallMessage(), "error");
        return;
      }
      const result = jsonDoctor.code === 0 ? jsonDoctor : await runOrcaCommand(["doctor"], runtime);
      if (result.error) {
        notify(ctx, `Unable to run Orca doctor: ${sanitizeVisibleText(result.error.message)}`, "error");
        return;
      }
      notify(ctx, summarizeCommandOutput(result) || `orca doctor exited with ${result.code ?? "unknown"}`, result.code === 0 ? "info" : "warning");
    },
  });

  pi.registerCommand("orca-mode", {
    description: "View or change Orca Pi unavailable-mode and session bypass.",
    handler: async (args, ctx) => {
      const requested = args?.trim().toLowerCase();
      if (!requested) {
        notify(ctx, modeSummary(unavailableMode, stateFor(ctx).bypass), "info");
        return;
      }

      if (requested === "bypass on") {
        stateFor(ctx).bypass = true;
        updateStatus(ctx);
        notify(ctx, "Orca bypass enabled for this Pi session only.", "warning");
        return;
      }
      if (requested === "bypass off") {
        stateFor(ctx).bypass = false;
        updateStatus(ctx);
        notify(ctx, "Orca bypass disabled. Bash calls will be evaluated by Orca.", "info");
        return;
      }

      const nextMode = parseMode(requested);
      if (!nextMode) {
        notify(ctx, "Usage: /orca-mode [auto|ask|noninteractive-block|strict|allow-with-warning|bypass on|bypass off]", "warning");
        return;
      }
      unavailableMode = nextMode;
      updateStatus(ctx);
      notify(ctx, modeSummary(unavailableMode, stateFor(ctx).bypass), "info");
    },
  });
}

async function handleUnavailable(
  reason: string,
  ctx: PiContext,
  mode: EffectiveUnavailableMode,
  actions: { disableSession: () => void },
): Promise<ToolCallResult> {
  const repair = repairMessage(reason);
  if (mode === "allow-with-warning") {
    notify(ctx, `Orca unavailable; allowing bash command with warning.\n\n${repair}`, "warning");
    return undefined;
  }
  if (mode === "strict" || mode === "noninteractive-block") {
    return block(repair);
  }

  const choice = await ctx.ui?.select?.("Orca could not evaluate this bash command", [...ASK_OPTIONS], { timeout: 60_000, signal: ctx.signal });
  switch (choice) {
    case "Run once anyway":
      notify(ctx, "Allowed this bash command once without Orca evaluation.", "warning");
      return undefined;
    case "Disable Orca for this Pi session":
      actions.disableSession();
      notify(ctx, "Orca disabled for this Pi session only. Use /orca-mode bypass off to re-enable.", "warning");
      return undefined;
    case "Show repair instructions / run doctor":
      notify(ctx, repair, "error");
      return block(repair);
    case "Block":
    default:
      return block(repair);
  }
}

function runProcess(
  file: string,
  args: string[],
  stdin: string | undefined,
  spawn: SpawnLike,
  timeoutMs: number,
): Promise<RunProcessResult> {
  return new Promise((resolvePromise) => {
    const controller = new AbortController();
    let stdout = "";
    let stderr = "";
    let settled = false;
    let timedOut = false;
    let outputExceeded = false;
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, timeoutMs);

    const settle = (result: RunProcessResult): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolvePromise({ ...result, stdout, stderr, timedOut });
    };

    let child: ChildLike;
    try {
      child = spawn(file, args, {
        stdio: [stdin === undefined ? "ignore" : "pipe", "pipe", "pipe"],
        shell: false,
        signal: controller.signal,
      });
    } catch (error) {
      settle({ code: null, stdout, stderr, error: asError(error), timedOut });
      return;
    }

    child.stdout?.on("data", (chunk) => {
      const appended = appendBounded(stdout, String(chunk), MAX_CHILD_OUTPUT_BYTES);
      stdout = appended.text;
      if (appended.exceeded && !outputExceeded) {
        outputExceeded = true;
        settle({ code: null, stdout, stderr, error: new Error("Orca output exceeded maximum size"), timedOut });
        controller.abort();
      }
    });
    child.stderr?.on("data", (chunk) => {
      const appended = appendBounded(stderr, String(chunk), MAX_CHILD_OUTPUT_BYTES);
      stderr = appended.text;
      if (appended.exceeded && !outputExceeded) {
        outputExceeded = true;
        settle({ code: null, stdout, stderr, error: new Error("Orca output exceeded maximum size"), timedOut });
        controller.abort();
      }
    });
    child.on("error", (errorOrCode: Error | number | null) => {
      settle({ code: null, stdout, stderr, error: asError(errorOrCode), timedOut });
    });
    child.on("close", (codeOrError: Error | number | null) => {
      settle({ code: typeof codeOrError === "number" ? codeOrError : null, stdout, stderr, timedOut });
    });

    if (stdin !== undefined) {
      child.stdin?.write(stdin);
      child.stdin?.end();
    }
  });
}

function sessionKey(ctx: PiContext): string {
  try {
    const id = ctx.sessionManager?.getSessionId?.();
    if (id) return id;
  } catch {
    // Fall through to the local test fallback.
  }
  return "__default_session__";
}

function appendBounded(current: string, chunk: string, maxBytes: number): { text: string; exceeded: boolean } {
  const currentBytes = Buffer.byteLength(current);
  const chunkBytes = Buffer.byteLength(chunk);
  if (currentBytes + chunkBytes <= maxBytes) return { text: current + chunk, exceeded: false };
  const remaining = Math.max(0, maxBytes - currentBytes);
  return { text: current + chunk.slice(0, remaining), exceeded: true };
}

function resolveCwd(cwd: string | undefined): string {
  const candidate = cwd ? resolve(cwd) : process.cwd();
  return existsSync(candidate) ? candidate : process.cwd();
}

function block(reason: string): ToolCallBlock {
  return { block: true, reason: sanitizeVisibleText(reason) };
}

function notify(ctx: PiContext, message: string, type: "info" | "warning" | "error"): void {
  ctx.ui?.notify?.(truncate(sanitizeVisibleText(message), 2_000), type);
}

function repairMessage(reason: string): string {
  return `Orca could not evaluate this bash command: ${sanitizeVisibleText(reason)}\n\nRun /orca-doctor or run \`orca doctor\`. If the daemon is stopped, run /orca-start or \`orca start\`.`;
}

function orcaInstallMessage(): string {
  return "Orca CLI was not found in Pi's PATH. Install Orca, or set ORCA_BIN to the Orca executable path, then run /orca-doctor.";
}

function modeSummary(mode: UnavailableMode, sessionBypass: boolean): string {
  return [
    `Orca Pi mode: ${mode}`,
    `Session bypass: ${sessionBypass ? "on" : "off"}`,
    "Modes: auto, ask, noninteractive-block, strict, allow-with-warning.",
  ].join("\n");
}

function summarizeCommandOutput(result: RunProcessResult): string {
  const output = result.stdout.trim() || result.stderr.trim();
  return truncate(sanitizeVisibleText(output), 2_000);
}

function parseMode(value: string | undefined): UnavailableMode | undefined {
  if (
    value === "auto" ||
    value === "ask" ||
    value === "noninteractive-block" ||
    value === "strict" ||
    value === "allow-with-warning"
  ) {
    return value;
  }
  return undefined;
}

function sanitizeVisibleText(value: string): string {
  return value
    .replace(/[A-Za-z0-9_]*gh[pousr]_[A-Za-z0-9_]+/g, "[redacted-token]")
    .replace(/(password|token|secret|api[_-]?key)=\S+/gi, "$1=[redacted]")
    .replace(/\s+/g, " ")
    .trim();
}

function truncate(value: string, max: number): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max - 3)}...`;
}

function getStringField(value: unknown, key: string): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const field = (value as Record<string, unknown>)[key];
  return typeof field === "string" ? field : undefined;
}

function getNestedStringField(value: unknown, path: string[]): string | undefined {
  let current = value;
  for (const segment of path) {
    if (!current || typeof current !== "object") return undefined;
    current = (current as Record<string, unknown>)[segment];
  }
  return typeof current === "string" ? current : undefined;
}

function asError(value: unknown): Error {
  return value instanceof Error ? value : new Error(String(value));
}

export default function orcaPiExtension(pi: PiAPI): void {
  installOrcaExtension(pi);
}
