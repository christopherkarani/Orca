import { spawn as nodeSpawn } from "node:child_process";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { accessSync, constants, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";

type UnavailableMode =
	| "auto"
	| "ask"
	| "noninteractive-block"
	| "strict"
	| "allow-with-warning";
type EffectiveUnavailableMode =
	| "ask"
	| "noninteractive-block"
	| "strict"
	| "allow-with-warning";

type ToolCallBlock = { block: true; reason?: string };
type ToolCallResult = ToolCallBlock | undefined;

type PiToolCallEvent = {
	toolName: string;
	input?: Record<string, unknown>;
};

type PiUI = {
	select?: (
		title: string,
		options: string[],
		opts?: { timeout?: number; signal?: AbortSignal },
	) => Promise<string | undefined>;
	notify?: (message: string, type?: "info" | "warning" | "error") => void;
	setStatus?: (key: string, text: string | undefined) => void;
	setWidget?: (
		key: string,
		value: undefined | string[],
		opts?: { placement?: "aboveEditor" | "belowEditor" },
	) => void;
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
	on: (
		event: string,
		handler: (event: any, ctx: PiContext) => Promise<any> | any,
	) => void;
	registerCommand: (
		name: string,
		options: {
			description?: string;
			handler: (
				args: string | undefined,
				ctx: PiContext,
			) => Promise<void> | void;
		},
	) => void;
};

type SpawnOptions = {
	stdio: ["pipe" | "ignore", "pipe" | "ignore", "pipe" | "ignore"];
	shell: false;
	signal?: AbortSignal;
	env?: NodeJS.ProcessEnv;
	cwd?: string;
};

type SpawnSyncLike = (
	file: string,
	args: string[],
	options: {
		encoding: "utf8";
		env: NodeJS.ProcessEnv;
		shell: false;
		timeout: number;
	},
) => { error?: Error; status: number | null; stdout?: string };

type ChildLike = {
	stdin?: { write: (data: string) => void; end: () => void };
	stdout?: {
		on: (event: "data", handler: (chunk: Buffer | string) => void) => void;
	};
	stderr?: {
		on: (event: "data", handler: (chunk: Buffer | string) => void) => void;
	};
	on: (
		event: "error" | "close",
		handler: ((error: Error) => void) | ((code: number | null) => void),
	) => void;
};

type SpawnLike = (
	file: string,
	args: string[],
	options: SpawnOptions,
) => ChildLike;

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

type OrcaEvaluateResponse = {
	decision?: string;
	reason?: string;
	message?: string;
	severity?: string;
	rule_id?: string;
	ruleId?: string;
	pack_id?: string;
	packId?: string;
	pattern_name?: string;
	patternName?: string;
	remediation?: Array<{ description?: string }>;
	error?: { message?: string };
};

type OrcaDecisionCard = {
	variant: "block" | "ask";
	title: string;
	summary: string;
	rule?: string;
	pack?: string;
	severity?: string;
	nextStep?: string;
};

type RunProcessResult = {
	code: number | null;
	stdout: string;
	stderr: string;
	error?: Error;
	timedOut?: boolean;
};

type SetupResult = {
	status: "ready" | "missing" | "degraded";
	message: string;
};
type SessionState = {
	bypass: boolean;
	status: SetupResult["status"];
	bootstrap?: Promise<SetupResult>;
};

export type OrcaExtensionOptions = {
	orcaBin?: string;
	resolveBin?: () => ResolvedOrcaBin;
	spawn?: SpawnLike;
	timeoutMs?: number;
};

export type ResolvedOrcaBin = {
	orcaBin: string;
	daemonBin?: string;
	source: "explicit" | "bundled" | "path" | "missing";
};

type ResolveOrcaBinOptions = {
	env?: NodeJS.ProcessEnv;
	bundledPackageRoot?: string;
	isExecutable?: (path: string) => boolean;
	isCompatiblePathOrca?: () => boolean;
	spawnSync?: SpawnSyncLike;
};

const STATUS_KEY = "orca";
const BLOCK_WIDGET_KEY = "orca-block";
const DEFAULT_TIMEOUT_MS = 10_000;
const MAX_CHILD_OUTPUT_BYTES = 1024 * 1024;
const REQUIRED_ORCA_VERSION = (
	createRequire(import.meta.url)("../package.json") as {
		dependencies: Record<string, string>;
	}
).dependencies["@orca-sec/orca"];
const ASK_OPTIONS = [
	"Block",
	"Run once anyway",
	"Disable Orca for this Pi session",
	"Show repair instructions / run doctor",
] as const;

export function resolveOrcaBin(
	options: ResolveOrcaBinOptions = {},
): ResolvedOrcaBin {
	const env = options.env ?? process.env;
	const isExecutable = options.isExecutable ?? isExecutableFile;
	const explicit = env.ORCA_BIN?.trim();
	if (explicit && isExecutable(explicit))
		return { orcaBin: explicit, source: "explicit" };

	const packageRoot = options.bundledPackageRoot ?? resolveBundledPackageRoot();
	if (packageRoot) {
		const executableSuffix = process.platform === "win32" ? ".exe" : "";
		const orcaBin = resolve(packageRoot, "vendor", `orca${executableSuffix}`);
		const daemonBin = resolve(
			packageRoot,
			"vendor",
			`orca-daemon${executableSuffix}`,
		);
		if (isExecutable(orcaBin) && isExecutable(daemonBin)) {
			return { orcaBin, daemonBin, source: "bundled" };
		}
	}

	const allowPath = env.ORCA_PI_USE_PATH === "true";
	const pathIsCompatible =
		options.isCompatiblePathOrca ??
		(() => isCompatiblePathOrca(env, options.spawnSync ?? spawnSync));
	if (allowPath && pathIsCompatible())
		return { orcaBin: "orca", source: "path" };

	return { orcaBin: "__orca_bundled_runtime_missing__", source: "missing" };
}

export function buildEvaluateRequest(
	command: string,
	ctx: PiContext,
): OrcaEvaluateRequest {
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
	options: Required<
		Pick<OrcaExtensionOptions, "orcaBin" | "spawn" | "timeoutMs">
	> & { env?: NodeJS.ProcessEnv },
): Promise<OrcaDecision> {
	const result = await runProcess(
		options.orcaBin,
		["evaluate", "--json", "--stdin"],
		JSON.stringify(request),
		options.spawn,
		options.timeoutMs,
		options.env,
		request.cwd,
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
		return {
			kind: "error",
			reason: sanitizeVisibleText(getDecisionReason(parsed)),
			response: parsed,
		};
	}

	return {
		kind: "error",
		reason: `Orca returned an unexpected evaluation result (exit ${result.code ?? "unknown"}).`,
		response: parsed,
	};
}

export async function runOrcaCommand(
	args: string[],
	options: Required<
		Pick<OrcaExtensionOptions, "orcaBin" | "spawn" | "timeoutMs">
	> & { env?: NodeJS.ProcessEnv },
	cwd?: string,
): Promise<RunProcessResult> {
	return runProcess(
		options.orcaBin,
		args,
		undefined,
		options.spawn,
		options.timeoutMs,
		options.env,
		cwd,
	);
}

export function resolveUnavailableMode(
	configured: UnavailableMode,
	ctx: PiContext,
): EffectiveUnavailableMode {
	if (configured === "auto")
		return isNoninteractiveSession(ctx) ? "noninteractive-block" : "ask";
	if (configured === "ask" && isNoninteractiveSession(ctx))
		return "noninteractive-block";
	return configured;
}

function isNoninteractiveSession(ctx: PiContext): boolean {
	return ctx.hasUI !== true || isNoninteractiveMode(ctx.mode);
}

function isNoninteractiveMode(mode: string | undefined): boolean {
	return mode === "print" || mode === "json" || mode === "noninteractive";
}

export function safeOrcaReason(response: unknown): string {
	return formatOrcaDecisionSummary(buildOrcaDecisionCard(response, "block"));
}

export function installOrcaExtension(
	pi: PiAPI,
	extensionOptions: OrcaExtensionOptions = {},
): void {
	const resolvedBin = extensionOptions.orcaBin
		? { orcaBin: extensionOptions.orcaBin, source: "explicit" as const }
		: (extensionOptions.resolveBin ?? resolveOrcaBin)();
	const runtime = {
		orcaBin: resolvedBin.orcaBin,
		spawn: extensionOptions.spawn ?? (nodeSpawn as unknown as SpawnLike),
		timeoutMs:
			extensionOptions.timeoutMs ??
			Number(process.env.ORCA_PI_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS),
		env: resolvedBin.daemonBin
			? { ...process.env, ORCA_DAEMON: resolvedBin.daemonBin }
			: process.env,
	};

	let unavailableMode: UnavailableMode =
		parseMode(process.env.ORCA_PI_MODE) ?? "auto";
	const sessionState = new Map<string, SessionState>();

	const stateFor = (ctx: PiContext): SessionState => {
		const key = sessionKey(ctx);
		const current = sessionState.get(key);
		if (current) return current;
		const next = { bypass: false, status: "degraded" as const };
		sessionState.set(key, next);
		return next;
	};

	const updateStatus = (ctx: PiContext): void => {
		if (stateFor(ctx).bypass) {
			ctx.ui?.setStatus?.(STATUS_KEY, "orca bypass");
			return;
		}
		ctx.ui?.setStatus?.(STATUS_KEY, `orca ${stateFor(ctx).status}`);
	};

	pi.on("session_start", (_event, ctx) => {
		const state = stateFor(ctx);
		state.bypass = false;
		state.status = "degraded";
		updateStatus(ctx);
		if (process.env.ORCA_PI_AUTO_SETUP === "false") {
			state.status = "ready";
			updateStatus(ctx);
			return;
		}
		state.bootstrap = setupOrca(ctx, runtime);
		void state.bootstrap.then((result) => {
			state.status = result.status;
			updateStatus(ctx);
		});
	});

	pi.on("session_shutdown", (_event, ctx) => {
		stateFor(ctx).bypass = false;
		ctx.ui?.setStatus?.(STATUS_KEY, undefined);
		clearOrcaWidget(ctx);
	});

	pi.on(
		"tool_call",
		async (event: PiToolCallEvent, ctx: PiContext): Promise<ToolCallResult> => {
			if (event.toolName !== "bash") return undefined;

			if (
				typeof event.input?.command !== "string" ||
				event.input.command.trim().length === 0
			) {
				const details = {
					variant: "block" as const,
					title: "ORCA BLOCKED",
					summary:
						"malformed Pi bash tool call; missing non-empty command.",
				};
				showOrcaWidget(ctx, details);
				return block(formatOrcaDecisionSummary(details));
			}
			const command = event.input.command;
			await stateFor(ctx).bootstrap;

			if (stateFor(ctx).bypass) {
				clearOrcaWidget(ctx);
				ctx.ui?.notify?.(
					"Orca protection is disabled for this Pi session; bash command allowed without Orca evaluation.",
					"warning",
				);
				updateStatus(ctx);
				return undefined;
			}

			const decision = await runOrcaEvaluate(
				buildEvaluateRequest(command, ctx),
				runtime,
			);
			if (decision.kind === "allow") {
				clearOrcaWidget(ctx);
				return undefined;
			}
			if (decision.kind === "deny") {
				const card = buildOrcaDecisionCard(decision.response, "block");
				showOrcaWidget(ctx, card);
				return block(formatOrcaDecisionSummary(card));
			}
			return handleUnavailable(
				decision.reason,
				ctx,
				resolveUnavailableMode(unavailableMode, ctx),
				{
					disableSession: () => {
						stateFor(ctx).bypass = true;
						updateStatus(ctx);
					},
				},
			);
		},
	);

	const setupHandler = async (
		_args: string | undefined,
		ctx: PiContext,
	): Promise<void> => {
		const result = await setupOrca(ctx, runtime);
		stateFor(ctx).status = result.status;
		updateStatus(ctx);
		notify(
			ctx,
			result.message,
			result.status === "ready"
				? "info"
				: result.status === "missing"
					? "error"
					: "warning",
		);
	};

	pi.registerCommand("orca-setup", {
		description:
			"Ensure the workspace policy exists and probe Orca daemon health.",
		handler: setupHandler,
	});

	pi.registerCommand("orca-start", {
		description:
			"Re-enable Orca protection for this Pi session and verify setup.",
		handler: async (_args, ctx) => {
			stateFor(ctx).bypass = false;
			const result = await setupOrca(ctx, runtime);
			stateFor(ctx).status = result.status;
			updateStatus(ctx);
			const suffix =
				result.status === "ready"
					? "Orca protection is enabled for this Pi session."
					: result.message;
			const type =
				result.status === "ready"
					? "info"
					: result.status === "missing"
						? "error"
						: "warning";
			notify(ctx, suffix, type);
		},
	});

	pi.registerCommand("orca-stop", {
		description:
			"Disable Orca protection for this Pi session until /orca-start.",
		handler: (_args, ctx) => {
			stateFor(ctx).bypass = true;
			updateStatus(ctx);
			notify(
				ctx,
				"Orca disabled for this Pi session only. Bash calls will run without Orca evaluation until /orca-start.",
				"warning",
			);
		},
	});

	pi.registerCommand("orca-doctor", {
		description: "Run Orca doctor and show setup or daemon health diagnostics.",
		handler: async (_args, ctx) => {
			const result = await runOrcaCommand(["doctor"], runtime);
			if (result.error) {
				notify(ctx, orcaInstallMessage(), "error");
				return;
			}
			notify(
				ctx,
				summarizeCommandOutput(result) ||
					`orca doctor exited with ${result.code ?? "unknown"}`,
				result.code === 0 ? "info" : "warning",
			);
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
				notify(
					ctx,
					"Orca bypass disabled. Bash calls will be evaluated by Orca.",
					"info",
				);
				return;
			}

			const nextMode = parseMode(requested);
			if (!nextMode) {
				notify(
					ctx,
					"Usage: /orca-mode [auto|ask|noninteractive-block|strict|allow-with-warning|bypass on|bypass off]",
					"warning",
				);
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
		clearOrcaWidget(ctx);
		notify(
			ctx,
			`Orca unavailable; allowing bash command with warning.\n\n${repair}`,
			"warning",
		);
		return undefined;
	}
	if (mode === "strict" || mode === "noninteractive-block") {
		const card = {
			variant: "block" as const,
			title: "ORCA BLOCKED",
			summary: repair,
		};
		showOrcaWidget(ctx, card);
		return block(formatOrcaDecisionSummary(card));
	}

	const card = buildOrcaAskCard(repair);
	showOrcaWidget(ctx, card);
	const choice = await ctx.ui?.select?.(
		"ORCA needs your decision",
		[...ASK_OPTIONS],
		{ timeout: 60_000, signal: ctx.signal },
	);
	switch (choice) {
		case "Run once anyway":
			clearOrcaWidget(ctx);
			notify(
				ctx,
				"Allowed this bash command once without Orca evaluation.",
				"warning",
			);
			return undefined;
		case "Disable Orca for this Pi session":
			clearOrcaWidget(ctx);
			actions.disableSession();
			notify(
				ctx,
				"Orca disabled for this Pi session only. Use /orca-start to re-enable.",
				"warning",
			);
			return undefined;
		case "Show repair instructions / run doctor":
			clearOrcaWidget(ctx);
			notify(ctx, repair, "error");
			return block(
				formatOrcaDecisionSummary({
					variant: "block",
					title: "ORCA BLOCKED",
					summary: repair,
				}),
			);
		case "Block":
		default:
			clearOrcaWidget(ctx);
			return block(
				formatOrcaDecisionSummary({
					variant: "block",
					title: "ORCA BLOCKED",
					summary: repair,
				}),
			);
	}
}

async function setupOrca(
	ctx: PiContext,
	runtime: Required<
		Pick<OrcaExtensionOptions, "orcaBin" | "spawn" | "timeoutMs">
	> & { env?: NodeJS.ProcessEnv },
): Promise<SetupResult> {
	const cwd = resolveCwd(ctx.cwd);
	const policyPath = resolve(cwd, ".orca", "policy.yaml");
	if (!existsSync(policyPath)) {
		const init = await runOrcaCommand(
			["init", "--preset", "generic-agent"],
			runtime,
			cwd,
		);
		if (init.error) return { status: "missing", message: orcaInstallMessage() };
		if (init.code !== 0 || !existsSync(policyPath)) {
			return {
				status: "degraded",
				message: `Orca policy setup failed (exit ${init.code ?? "unknown"}). ${summarizeCommandOutput(init)}`,
			};
		}
	}

	const doctor = await runOrcaCommand(["doctor"], runtime, cwd);
	if (doctor.error) return { status: "missing", message: orcaInstallMessage() };
	if (doctor.code !== 0) {
		return {
			status: "degraded",
			message: `Orca policy is ready, but the health probe exited with ${doctor.code ?? "unknown"}. ${summarizeCommandOutput(doctor)}`,
		};
	}
	return {
		status: "ready",
		message: "Orca policy is ready and daemon health checks passed.",
	};
}

function runProcess(
	file: string,
	args: string[],
	stdin: string | undefined,
	spawn: SpawnLike,
	timeoutMs: number,
	env?: NodeJS.ProcessEnv,
	cwd?: string,
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
				env,
				cwd,
			});
		} catch (error) {
			settle({ code: null, stdout, stderr, error: asError(error), timedOut });
			return;
		}

		child.stdout?.on("data", (chunk) => {
			const appended = appendBounded(
				stdout,
				String(chunk),
				MAX_CHILD_OUTPUT_BYTES,
			);
			stdout = appended.text;
			if (appended.exceeded && !outputExceeded) {
				outputExceeded = true;
				settle({
					code: null,
					stdout,
					stderr,
					error: new Error("Orca output exceeded maximum size"),
					timedOut,
				});
				controller.abort();
			}
		});
		child.stderr?.on("data", (chunk) => {
			const appended = appendBounded(
				stderr,
				String(chunk),
				MAX_CHILD_OUTPUT_BYTES,
			);
			stderr = appended.text;
			if (appended.exceeded && !outputExceeded) {
				outputExceeded = true;
				settle({
					code: null,
					stdout,
					stderr,
					error: new Error("Orca output exceeded maximum size"),
					timedOut,
				});
				controller.abort();
			}
		});
		child.on("error", (errorOrCode: Error | number | null) => {
			settle({
				code: null,
				stdout,
				stderr,
				error: asError(errorOrCode),
				timedOut,
			});
		});
		child.on("close", (codeOrError: Error | number | null) => {
			settle({
				code: typeof codeOrError === "number" ? codeOrError : null,
				stdout,
				stderr,
				timedOut,
			});
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

function resolveBundledPackageRoot(): string | undefined {
	try {
		const require = createRequire(import.meta.url);
		return dirname(require.resolve("@orca-sec/orca/package.json"));
	} catch {
		return undefined;
	}
}

function isExecutableFile(path: string): boolean {
	try {
		accessSync(
			path,
			process.platform === "win32" ? constants.F_OK : constants.X_OK,
		);
		return true;
	} catch {
		return false;
	}
}

function isCompatiblePathOrca(
	env: NodeJS.ProcessEnv,
	runner: SpawnSyncLike,
): boolean {
	const result = runner("orca", ["--version"], {
		encoding: "utf8",
		env,
		shell: false,
		timeout: 2_000,
	});
	if (result.error || result.status !== 0) return false;
	return new RegExp(
		`\\borca\\s+${REQUIRED_ORCA_VERSION.replaceAll(".", "\\.")}\\b`,
	).test(result.stdout ?? "");
}

function appendBounded(
	current: string,
	chunk: string,
	maxBytes: number,
): { text: string; exceeded: boolean } {
	const currentBytes = Buffer.byteLength(current);
	const chunkBytes = Buffer.byteLength(chunk);
	if (currentBytes + chunkBytes <= maxBytes)
		return { text: current + chunk, exceeded: false };
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

function clearOrcaWidget(ctx: PiContext): void {
	ctx.ui?.setWidget?.(BLOCK_WIDGET_KEY, undefined);
}

function showOrcaWidget(ctx: PiContext, card: OrcaDecisionCard): void {
	if (!ctx.ui?.setWidget) return;
	ctx.ui.setWidget(BLOCK_WIDGET_KEY, buildOrcaWidget(card));
}

function buildOrcaWidget(card: OrcaDecisionCard): string[] {
	const contentWidth = 62;
	const isBlock = card.variant === "block";
	const frame = isBlock
		? { topLeft: "┏", topRight: "┓", side: "┃", teeLeft: "┣", teeRight: "┫", bottomLeft: "┗", bottomRight: "┛", rule: "━" }
		: { topLeft: "┌", topRight: "┐", side: "│", teeLeft: "├", teeRight: "┤", bottomLeft: "└", bottomRight: "┘", rule: "─" };
	const masthead = isBlock ? " ORCA // BLOCKED " : " ORCA // YOUR CALL ";
	const stateLine = isBlock
		? "COMMAND STOPPED BEFORE EXECUTION"
		: "ORCA PAUSED THIS COMMAND";
	const lines = [
		buildLabeledBorder(frame.topLeft, frame.topRight, frame.rule, masthead, contentWidth),
		`${frame.side} ${stateLine.padEnd(contentWidth - 2)} ${frame.side}`,
		`${frame.teeLeft}${frame.rule.repeat(contentWidth)}${frame.teeRight}`,
	];
	for (const line of wrapText(card.summary, contentWidth - 2)) {
		lines.push(`${frame.side} ${line.padEnd(contentWidth - 2)} ${frame.side}`);
	}
	lines.push(`${frame.teeLeft}${frame.rule.repeat(contentWidth)}${frame.teeRight}`);
	lines.push(...formatWidgetRow("Rule", card.rule, contentWidth, frame.side));
	if (card.pack)
		lines.push(...formatWidgetRow("Pack", card.pack, contentWidth, frame.side));
	if (card.severity)
		lines.push(
			...formatWidgetRow(
				"Severity",
				capitalize(card.severity),
				contentWidth,
				frame.side,
			),
		);
	if (card.nextStep)
		lines.push(
			...formatWidgetRow("Next", card.nextStep, contentWidth, frame.side),
		);
	if (!isBlock)
		lines.push(
			...formatWidgetRow(
				"Choose",
				"Run once, repair Orca, or keep it blocked.",
				contentWidth,
				frame.side,
			),
		);
	lines.push(
		`${frame.bottomLeft}${frame.rule.repeat(contentWidth)}${frame.bottomRight}`,
	);
	return lines;
}

function buildLabeledBorder(
	left: string,
	right: string,
	rule: string,
	label: string,
	width: number,
): string {
	const remaining = Math.max(0, width - label.length);
	const before = Math.min(3, remaining);
	return `${left}${rule.repeat(before)}${label}${rule.repeat(remaining - before)}${right}`;
}

function buildOrcaDecisionCard(
	response: unknown,
	variant: OrcaDecisionCard["variant"],
): OrcaDecisionCard {
	const reason = getDecisionReason(response);
	const rule = getRuleId(response);
	const pack = getStringFieldAny(response, ["pack_id", "packId"]);
	const severity = getStringFieldAny(response, ["severity"]);
	const nextStep = getNextStep(response);
	return {
		variant,
		title: variant === "ask" ? "ORCA NEEDS YOUR DECISION" : "ORCA BLOCKED",
		summary: sanitizeVisibleText(reason),
		rule,
		pack,
		severity,
		nextStep,
	};
}

function buildOrcaAskCard(reason: string): OrcaDecisionCard {
	return {
		variant: "ask",
		title: "ORCA NEEDS YOUR DECISION",
		summary: sanitizeVisibleText(reason),
	};
}

function formatOrcaDecisionSummary(card: OrcaDecisionCard): string {
	const parts = [card.summary];
	if (card.rule) parts.push(`rule ${card.rule}`);
	if (card.pack && card.pack !== card.rule?.split(":")[0]) parts.push(`pack ${card.pack}`);
	if (card.severity) parts.push(`severity ${card.severity}`);
	return sanitizeVisibleText(`Orca ${card.variant === "ask" ? "needs your decision" : "blocked this bash command"}: ${parts.join(" • ")}`);
}

function getDecisionReason(response: unknown): string {
	return (
		getStringFieldAny(response, ["reason", "message"]) ??
		getNestedStringField(response, ["error", "message"]) ??
		"Orca blocked this bash command."
	);
}

function getRuleId(response: unknown): string | undefined {
	return getStringFieldAny(response, ["rule_id", "ruleId"]);
}

function getNextStep(response: unknown): string | undefined {
	const remediation = Array.isArray((response as OrcaEvaluateResponse | null)?.remediation)
		? (response as OrcaEvaluateResponse).remediation
		: undefined;
	const description = remediation?.find((entry) => entry?.description)?.description;
	return description ? sanitizeVisibleText(description) : undefined;
}

function getStringFieldAny(
	value: unknown,
	keys: string[],
): string | undefined {
	for (const key of keys) {
		const field = getStringField(value, key);
		if (field) return field;
	}
	return undefined;
}

function capitalize(value: string): string {
	return value.charAt(0).toUpperCase() + value.slice(1);
}

function wrapText(value: string, width: number): string[] {
	const text = sanitizeVisibleText(value);
	if (!text) return [""];
	const words = text.split(/\s+/);
	const lines: string[] = [];
	let current = "";
	for (const word of words) {
		if (!current) {
			current = word;
			continue;
		}
		if (`${current} ${word}`.length <= width) {
			current = `${current} ${word}`;
			continue;
		}
		lines.push(current);
		current = word;
	}
	if (current) lines.push(current);
	return lines.flatMap((line) => {
		if (line.length <= width) return [line];
		const chunks: string[] = [];
		for (let i = 0; i < line.length; i += width) chunks.push(line.slice(i, i + width));
		return chunks;
	});
}

function formatWidgetRow(
	label: string,
	value: string | undefined,
	width: number,
	side: string,
): string[] {
	if (!value) return [];
	const contentWidth = width - 2;
	const rowLabel = `${label}:`;
	const available = Math.max(1, contentWidth - rowLabel.length - 1);
	const wrapped = wrapText(value, available);
	return wrapped.map((line, index) => {
		const prefix = index === 0 ? rowLabel : "".padEnd(rowLabel.length, " ");
		return `${side} ${prefix} ${line.padEnd(available)} ${side}`;
	});
}

function notify(
	ctx: PiContext,
	message: string,
	type: "info" | "warning" | "error",
): void {
	ctx.ui?.notify?.(truncate(sanitizeVisibleText(message), 2_000), type);
}

function repairMessage(reason: string): string {
	return `Orca could not evaluate this bash command: ${sanitizeVisibleText(reason)}\n\nRun /orca-setup, then /orca-doctor. The daemon starts automatically on the first evaluation.`;
}

function orcaInstallMessage(): string {
	return "Orca CLI was not found. Reinstall npm:@orca-sec/pi-orca, or set ORCA_BIN to an executable Orca path, then run /orca-setup.";
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

function getNestedStringField(
	value: unknown,
	path: string[],
): string | undefined {
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
