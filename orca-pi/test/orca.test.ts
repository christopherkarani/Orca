import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { resolve } from "node:path";
import test from "node:test";
import {
  buildEvaluateRequest,
  installOrcaExtension,
  resolveUnavailableMode,
  runOrcaEvaluate,
  safeOrcaReason,
  type OrcaEvaluateRequest,
} from "../extensions/orca.ts";

type Handler = (event: any, ctx: any) => Promise<any> | any;

class FakeChild {
  stdinWrites: string[] = [];
  stdout = new EventEmitter();
  stderr = new EventEmitter();
  stdin = {
    write: (data: string) => {
      this.stdinWrites.push(data);
    },
    end: () => {},
  };
  private emitter = new EventEmitter();

  on(event: "error" | "close", handler: (...args: any[]) => void): void {
    this.emitter.on(event, handler);
  }

  close(code: number): void {
    this.emitter.emit("close", code);
  }

  fail(error: Error): void {
    this.emitter.emit("error", error);
  }
}

function makeSpawn(plans: Array<{ code?: number; stdout?: string; stderr?: string; error?: Error }> = []) {
  const calls: Array<{ file: string; args: string[]; options: any; stdin: string[] }> = [];
  const spawn = (file: string, args: string[], options: any): FakeChild => {
    const child = new FakeChild();
    calls.push({ file, args, options, stdin: child.stdinWrites });
    const plan = plans.shift() ?? { code: 0, stdout: allowJson() };
    queueMicrotask(() => {
      if (plan.stdout) child.stdout.emit("data", plan.stdout);
      if (plan.stderr) child.stderr.emit("data", plan.stderr);
      if (plan.error) child.fail(plan.error);
      else child.close(plan.code ?? 0);
    });
    return child;
  };
  return { spawn, calls };
}

function makePi() {
  const handlers = new Map<string, Handler[]>();
  const commands = new Map<string, { handler: (args: string | undefined, ctx: any) => Promise<void> | void }>();
  const pi = {
    on(event: string, handler: Handler) {
      const list = handlers.get(event) ?? [];
      list.push(handler);
      handlers.set(event, list);
    },
    registerCommand(name: string, options: any) {
      commands.set(name, options);
    },
  };
  return { pi, handlers, commands };
}

function makeCtx(overrides: Record<string, unknown> = {}) {
  const notifications: Array<{ message: string; type?: string }> = [];
  const statuses: Array<{ key: string; text: string | undefined }> = [];
  const selections: string[] = [];
  const ctx = {
    cwd: process.cwd(),
    mode: "tui",
    hasUI: true,
    sessionManager: { getSessionId: () => "session-a" },
    ui: {
      notify: (message: string, type?: string) => notifications.push({ message, type }),
      setStatus: (key: string, text: string | undefined) => statuses.push({ key, text }),
      select: async () => selections.shift(),
    },
    ...overrides,
  };
  return { ctx, notifications, statuses, selections };
}

function allowJson(): string {
  return JSON.stringify({ decision: "allow", reason: "Command allowed", daemon: { status: "healthy", compatible: true } });
}

function denyJson(): string {
  return JSON.stringify({
    decision: "deny",
    reason: "destructive filesystem command",
    rule_id: "core.filesystem:destructive-rm",
    daemon: { status: "healthy", compatible: true },
  });
}

function errorJson(): string {
  return JSON.stringify({
    decision: "error",
    reason: "daemon is unavailable for shell-command evaluation",
    error: { code: "daemon_unavailable", message: "daemon unavailable" },
  });
}

async function fireToolCall(handler: Handler, ctx: any, command = "git status", toolName = "bash") {
  return handler({ toolName, input: { command } }, ctx);
}

test("non-bash tool call is ignored", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn();
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx();

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx, "hello", "read");
  assert.equal(result, undefined);
});

test("bash safe command with Orca allow returns undefined", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ code: 0, stdout: allowJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx();

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx, "git status");
  assert.equal(result, undefined);
});

test("bash dangerous command with Orca deny returns block", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ code: 2, stdout: denyJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx();

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx, "rm -rf /");
  assert.deepEqual(result, { block: true, reason: "Blocked by Orca: destructive filesystem command [core.filesystem:destructive-rm]" });
});

test("bash dangerous command with Orca deny blocks even when exit code is not 2", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ code: 0, stdout: denyJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx();

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx, "rm -rf /");
  assert.deepEqual(result, { block: true, reason: "Blocked by Orca: destructive filesystem command [core.filesystem:destructive-rm]" });
});

test("Orca error in non-interactive mode blocks", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx({ hasUI: false, mode: "print" });

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /Run \/orca-doctor/);
});

test("Orca error in interactive mode asks user", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx, selections } = makeCtx();
  selections.push("Run once anyway");

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result, undefined);
});

test("auto mode blocks print sessions even when hasUI is true", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx({ hasUI: true, mode: "print" });

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /Run \/orca-doctor/);
});

test("strict mode blocks", async () => {
  const { pi, handlers, commands } = makePi();
  const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx();
  await commands.get("orca-mode")!.handler("strict", ctx);

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result.block, true);
});

test("allow-with-warning mode allows and warns", async () => {
  const { pi, handlers, commands } = makePi();
  const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx, notifications } = makeCtx();
  await commands.get("orca-mode")!.handler("allow-with-warning", ctx);

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result, undefined);
  assert.equal(notifications.at(-1)?.type, "warning");
});

test("malformed Orca JSON follows unavailable policy", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ code: 0, stdout: "{not-json" }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx({ hasUI: false, mode: "print" });

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /malformed JSON/);
});

test("child process failure follows unavailable policy", async () => {
  const { pi, handlers } = makePi();
  const { spawn } = makeSpawn([{ error: new Error("ENOENT") }]);
  installOrcaExtension(pi, { spawn, orcaBin: "missing-orca" });
  const { ctx } = makeCtx({ hasUI: false, mode: "print" });

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /Orca is unavailable/);
});

test("session bypass allows subsequent bash calls during same session", async () => {
  const { pi, handlers } = makePi();
  const { spawn, calls } = makeSpawn([{ code: 3, stdout: errorJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx, selections } = makeCtx();
  selections.push("Disable Orca for this Pi session");

  const first = await fireToolCall(handlers.get("tool_call")![0], ctx);
  const second = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(first, undefined);
  assert.equal(second, undefined);
  assert.equal(calls.length, 1);
});

test("session bypass does not leak across Pi session ids", async () => {
  const { pi, handlers } = makePi();
  const { spawn, calls } = makeSpawn([{ code: 3, stdout: errorJson() }, { code: 0, stdout: allowJson() }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const firstSession = makeCtx();
  const secondSession = makeCtx({ sessionManager: { getSessionId: () => "session-b" } });
  firstSession.selections.push("Disable Orca for this Pi session");

  await fireToolCall(handlers.get("tool_call")![0], firstSession.ctx);
  const result = await fireToolCall(handlers.get("tool_call")![0], secondSession.ctx);
  assert.equal(result, undefined);
  assert.equal(calls.length, 2);
});

test("malformed bash tool calls fail closed", async () => {
  const { pi, handlers } = makePi();
  const { spawn, calls } = makeSpawn();
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx();

  const result = await handlers.get("tool_call")![0]({ toolName: "bash", input: { command: 123 } }, ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /malformed Pi bash tool call/);
  assert.equal(calls.length, 0);
});

test("/orca-doctor handles Orca present", async () => {
  const { pi, commands } = makePi();
  const { spawn } = makeSpawn([{ code: 0, stdout: "{\"ok\":true}" }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx, notifications } = makeCtx();

  await commands.get("orca-doctor")!.handler("", ctx);
  assert.equal(notifications.at(-1)?.type, "info");
  assert.match(notifications.at(-1)!.message, /ok/);
});

test("/orca-doctor handles Orca missing", async () => {
  const { pi, commands } = makePi();
  const { spawn } = makeSpawn([{ error: new Error("ENOENT") }]);
  installOrcaExtension(pi, { spawn, orcaBin: "missing-orca" });
  const { ctx, notifications } = makeCtx();

  await commands.get("orca-doctor")!.handler("", ctx);
  assert.equal(notifications.at(-1)?.type, "error");
  assert.match(notifications.at(-1)!.message, /not found/);
});

test("/orca-start handles Orca present and missing", async () => {
  const present = makePi();
  const presentSpawn = makeSpawn([{ code: 0, stdout: "orca 0.1.0" }, { code: 0, stdout: "started" }]);
  installOrcaExtension(present.pi, { spawn: presentSpawn.spawn, orcaBin: "orca" });
  const presentCtx = makeCtx();
  await present.commands.get("orca-start")!.handler("", presentCtx.ctx);
  assert.equal(presentCtx.notifications.at(-1)?.type, "info");

  const missing = makePi();
  const missingSpawn = makeSpawn([{ error: new Error("ENOENT") }]);
  installOrcaExtension(missing.pi, { spawn: missingSpawn.spawn, orcaBin: "missing-orca" });
  const missingCtx = makeCtx();
  await missing.commands.get("orca-start")!.handler("", missingCtx.ctx);
  assert.equal(missingCtx.notifications.at(-1)?.type, "error");
});

test("/orca-mode changes mode", async () => {
  const { pi, commands } = makePi();
  installOrcaExtension(pi, { spawn: makeSpawn().spawn, orcaBin: "orca" });
  const { ctx, notifications } = makeCtx();

  await commands.get("orca-mode")!.handler("strict", ctx);
  assert.match(notifications.at(-1)!.message, /strict/);
});

test("no shell interpolation is used when invoking Orca", async () => {
  const { spawn, calls } = makeSpawn([{ code: 0, stdout: allowJson() }]);
  await runOrcaEvaluate(buildEvaluateRequest("echo safe", { cwd: process.cwd(), mode: "print" }), {
    spawn,
    orcaBin: "orca",
    timeoutMs: 1_000,
  });

  assert.equal(calls[0].file, "orca");
  assert.deepEqual(calls[0].args, ["evaluate", "--json", "--stdin"]);
  assert.equal(calls[0].options.shell, false);
  const request = JSON.parse(calls[0].stdin[0]) as OrcaEvaluateRequest;
  assert.equal(request.command, "echo safe");
  assert.equal(request.source.host, "pi");
});

test("oversized Orca output follows unavailable policy", async () => {
  const { pi, handlers } = makePi();
  const huge = "x".repeat(1024 * 1024 + 1);
  const { spawn } = makeSpawn([{ code: 0, stdout: huge }]);
  installOrcaExtension(pi, { spawn, orcaBin: "orca" });
  const { ctx } = makeCtx({ hasUI: false, mode: "print" });

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /maximum size/);
});

test("helpers resolve modes and sanitize reasons", () => {
  assert.equal(resolveUnavailableMode("auto", { hasUI: true }), "ask");
  assert.equal(resolveUnavailableMode("auto", { hasUI: false }), "noninteractive-block");
  assert.equal(resolveUnavailableMode("auto", { hasUI: true, mode: "print" }), "noninteractive-block");
  assert.equal(resolveUnavailableMode("auto", { hasUI: true, mode: "json" }), "noninteractive-block");
  assert.equal(resolveUnavailableMode("ask", { hasUI: true, mode: "print" }), "noninteractive-block");
  assert.match(safeOrcaReason({ reason: "blocked token=abc123", rule_id: "rule" }), /token=\[redacted\]/);
});

test("buildEvaluateRequest resolves relative cwd", () => {
  const request = buildEvaluateRequest("git status", { cwd: ".", mode: "tui" });
  assert.equal(request.cwd, resolve("."));
});

test("Orca timeout follows unavailable policy", async () => {
  const { pi, handlers } = makePi();
  const spawn = (): FakeChild => {
    const child = new FakeChild();
    setTimeout(() => child.close(143), 5);
    return child;
  };
  installOrcaExtension(pi, { spawn, orcaBin: "orca", timeoutMs: 1 });
  const { ctx } = makeCtx({ hasUI: false, mode: "print" });

  const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /timed out/);
});
