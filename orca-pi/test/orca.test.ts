import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import {
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import test from "node:test";
import {
	buildEvaluateRequest,
	installOrcaExtension,
	resolveOrcaBin,
	resolveUnavailableMode,
	runOrcaEvaluate,
	safeOrcaReason,
	type OrcaEvaluateRequest,
} from "../extensions/orca.ts";

type Handler = (event: any, ctx: any) => Promise<any> | any;

const packageJson = JSON.parse(
	readFileSync(new URL("../package.json", import.meta.url), "utf8"),
) as {
	dependencies: Record<string, string>;
};
const requiredRuntimeVersion = packageJson.dependencies["@orca-sec/orca"];

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

function makeSpawn(
	plans: Array<{
		code?: number;
		stdout?: string;
		stderr?: string;
		error?: Error;
		run?: (call: {
			file: string;
			args: string[];
			options: any;
			stdin: string[];
		}) => void;
	}> = [],
) {
	const calls: Array<{
		file: string;
		args: string[];
		options: any;
		stdin: string[];
	}> = [];
	const spawn = (file: string, args: string[], options: any): FakeChild => {
		const child = new FakeChild();
		const call = { file, args, options, stdin: child.stdinWrites };
		calls.push(call);
		const plan = plans.shift() ?? { code: 0, stdout: allowJson() };
		queueMicrotask(() => {
			plan.run?.(call);
			if (plan.stdout) child.stdout.emit("data", plan.stdout);
			if (plan.stderr) child.stderr.emit("data", plan.stderr);
			if (plan.error) child.fail(plan.error);
			else child.close(plan.code ?? 0);
		});
		return child;
	};
	return { spawn, calls };
}

async function flushAsyncWork(): Promise<void> {
	await new Promise<void>((resolvePromise) => setImmediate(resolvePromise));
	await new Promise<void>((resolvePromise) => setImmediate(resolvePromise));
}

function makePi() {
	const handlers = new Map<string, Handler[]>();
	const commands = new Map<
		string,
		{ handler: (args: string | undefined, ctx: any) => Promise<void> | void }
	>();
	const messages: Array<{
		message: {
			customType: string;
			content: string;
			display: boolean;
			details?: unknown;
		};
		options?: { triggerTurn?: boolean; deliverAs?: string };
	}> = [];
	const pi = {
		on(event: string, handler: Handler) {
			const list = handlers.get(event) ?? [];
			list.push(handler);
			handlers.set(event, list);
		},
		registerCommand(name: string, options: any) {
			commands.set(name, options);
		},
		sendMessage(message: any, options?: any) {
			messages.push({ message, options });
		},
	};
	return { pi, handlers, commands, messages };
}

function makeCtx(overrides: Record<string, unknown> = {}) {
	const notifications: Array<{ message: string; type?: string }> = [];
	const statuses: Array<{ key: string; text: string | undefined }> = [];
	const widgets: Array<{
		key: string;
		value: string[] | undefined;
		opts?: { placement?: "aboveEditor" | "belowEditor" };
	}> = [];
	const selections: string[] = [];
	const ctx = {
		cwd: process.cwd(),
		mode: "tui",
		hasUI: true,
		sessionManager: { getSessionId: () => "session-a" },
		ui: {
			notify: (message: string, type?: string) =>
				notifications.push({ message, type }),
			setStatus: (key: string, text: string | undefined) =>
				statuses.push({ key, text }),
			setWidget: (
				key: string,
				value: undefined | string[],
				opts?: { placement?: "aboveEditor" | "belowEditor" },
			) => widgets.push({ key, value, opts }),
			select: async () => selections.shift(),
		},
		...overrides,
	};
	return { ctx, notifications, statuses, widgets, selections };
}

function allowJson(): string {
	return JSON.stringify({
		decision: "allow",
		reason: "Command allowed",
		daemon: { status: "healthy", compatible: true },
	});
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

test("resolveOrcaBin honors executable ORCA_BIN before other candidates", () => {
	const result = resolveOrcaBin({
		env: { ORCA_BIN: "/trusted/orca" },
		bundledPackageRoot: "/package",
		isExecutable: (path) => path === "/trusted/orca",
		isCompatiblePathOrca: () => true,
	});

	assert.deepEqual(result, { orcaBin: "/trusted/orca", source: "explicit" });
});

test("resolveOrcaBin prefers the bundled runtime and requires opt-in for PATH", () => {
	const defaults = {
		bundledPackageRoot: "/package",
		isExecutable: () => true,
		isCompatiblePathOrca: () => true,
	};

	assert.deepEqual(resolveOrcaBin({ ...defaults, env: {} }), {
		orcaBin: resolve("/package/vendor/orca"),
		daemonBin: resolve("/package/vendor/orca-daemon"),
		source: "bundled",
	});
	assert.deepEqual(
		resolveOrcaBin({
			...defaults,
			bundledPackageRoot: "/missing-package",
			isExecutable: () => false,
			env: { ORCA_PI_USE_PATH: "true" },
		}),
		{
			orcaBin: "orca",
			source: "path",
		},
	);
});

test("resolveOrcaBin uses bundled Orca when PATH is incompatible", () => {
	const result = resolveOrcaBin({
		env: {},
		bundledPackageRoot: "/package",
		isExecutable: () => true,
		isCompatiblePathOrca: () => false,
	});

	assert.equal(result.orcaBin, resolve("/package/vendor/orca"));
	assert.equal(result.daemonBin, resolve("/package/vendor/orca-daemon"));
	assert.equal(result.source, "bundled");
});

test("resolveOrcaBin validates opted-in PATH version output", () => {
	const compatible = resolveOrcaBin({
		env: { ORCA_PI_USE_PATH: "true" },
		bundledPackageRoot: "/missing-package",
		isExecutable: () => false,
		spawnSync: () => ({
			status: 0,
			stdout: `orca ${requiredRuntimeVersion}\n`,
		}),
	});
	assert.equal(compatible.source, "path");

	for (const result of [
		{ status: 0, stdout: "orca 0.0.0\n" },
		{ status: 0, stdout: "not-orca\n" },
		{ status: 1, stdout: `orca ${requiredRuntimeVersion}\n` },
		{ status: null, stdout: "", error: new Error("timeout") },
	]) {
		assert.equal(
			resolveOrcaBin({
				env: { ORCA_PI_USE_PATH: "true" },
				bundledPackageRoot: "/missing-package",
				isExecutable: () => false,
				spawnSync: () => result,
			}).source,
			"missing",
		);
	}
});

test("bundled Orca evaluation receives its companion daemon path", async () => {
	const { pi, handlers } = makePi();
	const { spawn, calls } = makeSpawn([{ code: 0, stdout: allowJson() }]);
	installOrcaExtension(pi, {
		spawn,
		resolveBin: () => ({
			orcaBin: "/package/vendor/orca",
			daemonBin: "/package/vendor/orca-daemon",
			source: "bundled",
		}),
	});

	await fireToolCall(handlers.get("tool_call")![0], makeCtx().ctx);

	assert.equal(calls[0].options.env.ORCA_DAEMON, "/package/vendor/orca-daemon");
});

test("session start quietly initializes a missing policy and probes health", async () => {
	const cwd = mkdtempSync(resolve(tmpdir(), "orca-pi-"));
	const { pi, handlers } = makePi();
	const { spawn, calls } = makeSpawn([
		{
			code: 0,
			run: (call) => {
				mkdirSync(resolve(call.options.cwd, ".orca"));
				writeFileSync(
					resolve(call.options.cwd, ".orca/policy.yaml"),
					"version: 1\n",
				);
			},
		},
		{ code: 0, stdout: "healthy" },
	]);
	const context = makeCtx({ cwd });
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });

	const returned = handlers.get("session_start")![0]({}, context.ctx);
	assert.equal(returned, undefined);
	await flushAsyncWork();

	assert.deepEqual(
		calls.map((call) => call.args),
		[["init", "--preset", "generic-agent"], ["doctor"]],
	);
	assert.deepEqual(
		calls.map((call) => call.options.cwd),
		[cwd, cwd],
	);
	assert.equal(context.notifications.length, 0);
	assert.equal(context.statuses.at(-1)?.text, "orca ready");
	assert.ok(
		context.statuses.every(
			(entry) =>
				entry.text === undefined ||
				entry.text === "orca degraded" ||
				entry.text === "orca ready" ||
				entry.text === "orca bypass",
		),
		"expected footer status to contain Orca state only",
	);
	rmSync(cwd, { recursive: true, force: true });
});

test("first bash evaluation waits for non-blocking session bootstrap", async () => {
	const cwd = mkdtempSync(resolve(tmpdir(), "orca-pi-"));
	const { pi, handlers } = makePi();
	const { spawn, calls } = makeSpawn([
		{
			code: 0,
			run: (call) => {
				mkdirSync(resolve(call.options.cwd, ".orca"));
				writeFileSync(
					resolve(call.options.cwd, ".orca/policy.yaml"),
					"version: 1\n",
				);
			},
		},
		{ code: 0, stdout: "healthy" },
		{ code: 0, stdout: allowJson() },
	]);
	const context = makeCtx({ cwd });
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });

	assert.equal(handlers.get("session_start")![0]({}, context.ctx), undefined);
	const decision = await fireToolCall(
		handlers.get("tool_call")![0],
		context.ctx,
	);

	assert.equal(decision, undefined);
	assert.deepEqual(
		calls.map((call) => call.args),
		[
			["init", "--preset", "generic-agent"],
			["doctor"],
			["evaluate", "--json", "--stdin"],
		],
	);
	assert.deepEqual(
		calls.map((call) => call.options.cwd),
		[cwd, cwd, cwd],
	);
	rmSync(cwd, { recursive: true, force: true });
});

test("/orca-setup ensures policy and probes health without invoking start", async () => {
	const cwd = mkdtempSync(resolve(tmpdir(), "orca-pi-"));
	const { pi, commands } = makePi();
	const { spawn, calls } = makeSpawn([
		{
			code: 0,
			run: (call) => {
				mkdirSync(resolve(call.options.cwd, ".orca"));
				writeFileSync(
					resolve(call.options.cwd, ".orca/policy.yaml"),
					"version: 1\n",
				);
			},
		},
		{ code: 0, stdout: "healthy" },
	]);
	const context = makeCtx({ cwd });
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });

	await commands.get("orca-setup")!.handler("", context.ctx);

	assert.deepEqual(
		calls.map((call) => call.args),
		[["init", "--preset", "generic-agent"], ["doctor"]],
	);
	assert.deepEqual(
		calls.map((call) => call.options.cwd),
		[cwd, cwd],
	);
	assert.equal(
		calls.some((call) => call.args.includes("start")),
		false,
	);
	assert.equal(context.notifications.at(-1)?.type, "info");
	rmSync(cwd, { recursive: true, force: true });
});

async function fireToolCall(
	handler: Handler,
	ctx: any,
	command = "git status",
	toolName = "bash",
) {
	return handler({ toolName, input: { command } }, ctx);
}

test("non-bash tool call is ignored", async () => {
	const { pi, handlers } = makePi();
	const { spawn } = makeSpawn();
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx } = makeCtx();

	const result = await fireToolCall(
		handlers.get("tool_call")![0],
		ctx,
		"hello",
		"read",
	);
	assert.equal(result, undefined);
});

test("bash safe command with Orca allow returns undefined", async () => {
	const { pi, handlers } = makePi();
	const { spawn } = makeSpawn([{ code: 0, stdout: allowJson() }]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx } = makeCtx();

	const result = await fireToolCall(
		handlers.get("tool_call")![0],
		ctx,
		"git status",
	);
	assert.equal(result, undefined);
});

test("bash dangerous command with Orca deny returns block", async () => {
	const { pi, handlers, messages } = makePi();
	const { spawn } = makeSpawn([{ code: 2, stdout: denyJson() }]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx, widgets } = makeCtx();

	const result = await fireToolCall(
		handlers.get("tool_call")![0],
		ctx,
		"rm -rf /",
	);
	assert.deepEqual(result, {
		block: true,
		reason:
			"Orca blocked this bash command: destructive filesystem command • rule core.filesystem:destructive-rm",
	});
	assert.equal(messages.length, 1);
	assert.equal(messages[0].message.customType, "orca-decision");
	assert.equal(messages[0].message.display, true);
	assert.deepEqual(messages[0].options, { triggerTurn: false });
	assert.equal(
		widgets.some((entry) => entry.key === "orca-block" && entry.value !== undefined),
		false,
		"expected deny output to avoid the docked widget surface",
	);
	const inlineDecision = messages[0].message.content;
	assert.match(inlineDecision, /┏━+/);
	assert.match(inlineDecision, /ORCA \/\/ BLOCKED/);
	assert.match(
		inlineDecision,
		/COMMAND STOPPED BEFORE EXECUTION/,
	);
	assert.match(inlineDecision, /destructive filesystem command/);
	assert.match(inlineDecision, /Why: destructive filesystem command/);
	assert.match(
		inlineDecision,
		/Rule: core\.filesystem:destructive-rm/,
	);
	assert.ok(
		inlineDecision.split("\n").every((line) => line.length === 56),
		"expected a compact, aligned 56-column Orca card",
	);
});

test("Orca inline decision keeps long reasons inside the compact frame", async () => {
	const longReason = `unsafe-${"x".repeat(120)} command escaped policy`;
	const { pi, handlers, messages } = makePi();
	const { spawn } = makeSpawn([
		{
			code: 2,
			stdout: JSON.stringify({
				decision: "deny",
				reason: longReason,
				rule_id: "custom.long-reason",
			}),
		},
	]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx } = makeCtx();

	await fireToolCall(handlers.get("tool_call")![0], ctx, "dangerous-command");

	const inlineDecision = messages[0]?.message.content;
	assert.ok(inlineDecision, "expected inline Orca decision content");
	assert.ok(
		inlineDecision.split("\n").every((line) => line.length === 56),
		"expected every long-reason card line to stay inside the frame",
	);
	assert.match(inlineDecision, /Why: unsafe-/);
	assert.match(inlineDecision, /command escaped policy/);
});

test("bash dangerous command with Orca deny blocks even when exit code is not 2", async () => {
	const { pi, handlers } = makePi();
	const { spawn } = makeSpawn([{ code: 0, stdout: denyJson() }]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx } = makeCtx();

	const result = await fireToolCall(
		handlers.get("tool_call")![0],
		ctx,
		"rm -rf /",
	);
	assert.deepEqual(result, {
		block: true,
		reason:
			"Orca blocked this bash command: destructive filesystem command • rule core.filesystem:destructive-rm",
	});
});

test("Orca error in non-interactive mode blocks", async () => {
	const { pi, handlers } = makePi();
	const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx } = makeCtx({ hasUI: false, mode: "print" });

	const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
	assert.equal(result.block, true);
	assert.match(result.reason, /Run \/orca-setup/);
});

test("Orca error in interactive mode waits for the user's decision", async () => {
	const { pi, handlers } = makePi();
	const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx, widgets } = makeCtx();
	let resolveSelection: (choice: string) => void = () => {};
	ctx.ui.select = () =>
		new Promise<string>((resolvePromise) => {
			resolveSelection = resolvePromise;
		});

	let settled = false;
	const pendingResult = fireToolCall(handlers.get("tool_call")![0], ctx).then(
		(result) => {
			settled = true;
			return result;
		},
	);
	await flushAsyncWork();
	assert.equal(settled, false, "expected bash tool call to wait for select()");
	const askWidget = widgets.find((entry) => entry.key === "orca-block");
	assert.ok(askWidget, "expected Orca ask widget");
	assert.deepEqual(askWidget.opts, { placement: "aboveEditor" });
	assert.match(askWidget.value?.join("\n") ?? "", /ORCA \/\/ YOUR CALL/);
	assert.match(
		askWidget.value?.join("\n") ?? "",
		/ORCA PAUSED THIS COMMAND/,
	);
	assert.match(
		askWidget.value?.join("\n") ?? "",
		/Choose: Run once, repair Orca, or keep it blocked\./,
	);
	assert.ok(
		askWidget.value?.every((line) => line.length === 56),
		"expected a compact, aligned 56-column Orca ask card",
	);

	resolveSelection("Run once anyway");
	const result = await pendingResult;
	assert.equal(result, undefined);
	assert.equal(settled, true);
	assert.equal(widgets.at(-1)?.value, undefined);
});

test("auto mode blocks print sessions even when hasUI is true", async () => {
	const { pi, handlers } = makePi();
	const { spawn } = makeSpawn([{ code: 3, stdout: errorJson() }]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx } = makeCtx({ hasUI: true, mode: "print" });

	const result = await fireToolCall(handlers.get("tool_call")![0], ctx);
	assert.equal(result.block, true);
	assert.match(result.reason, /Run \/orca-setup/);
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
	const { spawn, calls } = makeSpawn([
		{ code: 3, stdout: errorJson() },
		{ code: 0, stdout: allowJson() },
	]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const firstSession = makeCtx();
	const secondSession = makeCtx({
		sessionManager: { getSessionId: () => "session-b" },
	});
	firstSession.selections.push("Disable Orca for this Pi session");

	await fireToolCall(handlers.get("tool_call")![0], firstSession.ctx);
	const result = await fireToolCall(
		handlers.get("tool_call")![0],
		secondSession.ctx,
	);
	assert.equal(result, undefined);
	assert.equal(calls.length, 2);
});

test("malformed bash tool calls fail closed", async () => {
	const { pi, handlers } = makePi();
	const { spawn, calls } = makeSpawn();
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx } = makeCtx();

	const result = await handlers.get("tool_call")![0](
		{ toolName: "bash", input: { command: 123 } },
		ctx,
	);
	assert.equal(result.block, true);
	assert.match(result.reason, /malformed Pi bash tool call/);
	assert.equal(calls.length, 0);
});

test("/orca-doctor handles Orca present", async () => {
	const { pi, commands } = makePi();
	const { spawn } = makeSpawn([{ code: 0, stdout: '{"ok":true}' }]);
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

test("/orca-stop disables Pi bash protection until /orca-start re-enables it", async () => {
	const cwd = mkdtempSync(resolve(tmpdir(), "orca-pi-"));
	mkdirSync(resolve(cwd, ".orca"));
	writeFileSync(resolve(cwd, ".orca/policy.yaml"), "version: 1\n");
	const { pi, commands, handlers } = makePi();
	const { spawn, calls } = makeSpawn([
		{ code: 0, stdout: "healthy" },
		{ code: 0, stdout: allowJson() },
	]);
	installOrcaExtension(pi, { spawn, orcaBin: "orca" });
	const { ctx, notifications, statuses } = makeCtx({ cwd });

	await commands.get("orca-stop")!.handler("", ctx);
	const stopped = await fireToolCall(
		handlers.get("tool_call")![0],
		ctx,
		"git status",
	);
	await commands.get("orca-start")!.handler("", ctx);
	const restarted = await fireToolCall(
		handlers.get("tool_call")![0],
		ctx,
		"git status",
	);

	assert.equal(stopped, undefined);
	assert.equal(restarted, undefined);
	assert.deepEqual(
		calls.map((call) => call.args),
		[["doctor"], ["evaluate", "--json", "--stdin"]],
	);
	assert.equal(
		notifications.some((entry) =>
			entry.message.includes("disabled for this Pi session"),
		),
		true,
	);
	assert.equal(
		notifications.some((entry) => entry.message.includes("enabled")),
		true,
	);
	assert.equal(
		statuses.some((entry) => entry.text === "orca bypass"),
		true,
	);
	assert.equal(statuses.at(-1)?.text, "orca ready");
	rmSync(cwd, { recursive: true, force: true });
});

test("/orca-start re-enables without invoking the CLI start command", async () => {
	const cwd = mkdtempSync(resolve(tmpdir(), "orca-pi-"));
	mkdirSync(resolve(cwd, ".orca"));
	writeFileSync(resolve(cwd, ".orca/policy.yaml"), "version: 1\n");
	const present = makePi();
	const presentSpawn = makeSpawn([{ code: 0, stdout: "healthy" }]);
	installOrcaExtension(present.pi, {
		spawn: presentSpawn.spawn,
		orcaBin: "orca",
	});
	const presentCtx = makeCtx({ cwd });
	await present.commands.get("orca-start")!.handler("", presentCtx.ctx);
	assert.deepEqual(
		presentSpawn.calls.map((call) => call.args),
		[["doctor"]],
	);
	assert.equal(presentCtx.notifications.at(-1)?.type, "info");

	const missing = makePi();
	const missingSpawn = makeSpawn([{ error: new Error("ENOENT") }]);
	installOrcaExtension(missing.pi, {
		spawn: missingSpawn.spawn,
		orcaBin: "missing-orca",
	});
	const missingCtx = makeCtx();
	await missing.commands.get("orca-start")!.handler("", missingCtx.ctx);
	assert.equal(missingCtx.notifications.at(-1)?.type, "error");
	assert.equal(
		missingSpawn.calls.some((call) => call.args.includes("start")),
		false,
	);
	rmSync(cwd, { recursive: true, force: true });
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
	await runOrcaEvaluate(
		buildEvaluateRequest("echo safe", { cwd: process.cwd(), mode: "print" }),
		{
			spawn,
			orcaBin: "orca",
			timeoutMs: 1_000,
		},
	);

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
	assert.equal(
		resolveUnavailableMode("auto", { hasUI: false }),
		"noninteractive-block",
	);
	assert.equal(
		resolveUnavailableMode("auto", { hasUI: true, mode: "print" }),
		"noninteractive-block",
	);
	assert.equal(
		resolveUnavailableMode("auto", { hasUI: true, mode: "json" }),
		"noninteractive-block",
	);
	assert.equal(
		resolveUnavailableMode("ask", { hasUI: true, mode: "print" }),
		"noninteractive-block",
	);
	assert.match(
		safeOrcaReason({ reason: "blocked token=abc123", rule_id: "rule" }),
		/Orca blocked this bash command: blocked token=\[redacted\] • rule rule/,
	);
});

test("buildEvaluateRequest resolves relative cwd", () => {
	const request = buildEvaluateRequest("git status", { cwd: ".", mode: "tui" });
	assert.equal(request.cwd, resolve("."));
});

test("buildEvaluateRequest includes the stable Pi session id", () => {
	const request = buildEvaluateRequest("git status", {
		cwd: process.cwd(),
		mode: "tui",
		sessionManager: { getSessionId: () => "pi-session-42" },
	});
	assert.equal(request.source.session_id, "pi-session-42");
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
