import { execSync } from 'child_process';
import { existsSync } from 'fs';
import { join, resolve } from 'path';

interface OrcaResponse {
  version?: number;
  decision: 'allow' | 'block' | 'warn' | 'ask' | 'context_only' | 'error';
  risk?: 'low' | 'medium' | 'high' | 'critical' | 'unknown';
  category?: string;
  reason?: string;
  rule?: string | null;
  message?: string;
  redactions?: Array<{ field: string; reason: string }>;
  host_limitations?: string[];
}

interface PluginLogger {
  debug?: (message: string) => void;
  info: (message: string) => void;
  warn: (message: string) => void;
  error: (message: string) => void;
}

/**
 * Minimal type for the OpenClaw Plugin API passed at runtime.
 * Matches OpenClawPluginApi from the openclaw/plugin-sdk types.
 */
interface OpenClawPluginApi {
  id: string;
  name: string;
  version?: string;
  description?: string;
  source: string;
  config: unknown;
  pluginConfig?: Record<string, unknown>;
  runtime: unknown;
  logger: PluginLogger;
  on: <K extends string>(
    hookName: K,
    handler: (event: unknown, ctx: unknown) => unknown | Promise<unknown>,
    opts?: { priority?: number }
  ) => void;
  registerHook?: (
    events: string | string[],
    handler: (event: unknown) => unknown | Promise<unknown>,
    opts?: { hookName?: string; priority?: number; register?: boolean }
  ) => void;
}

const SECRET_KEYS = [
  'password', 'token', 'secret', 'api_key', 'apikey', 'api_secret',
  'auth', 'authorization', 'bearer', 'private_key', 'access_token',
  'refresh_token', 'credential', 'passwd', 'pwd',
];

function redactSecrets(data: unknown): unknown {
  if (data === null || data === undefined) return data;
  if (typeof data === 'string') return data;
  if (Array.isArray(data)) return data.map(redactSecrets);
  if (typeof data !== 'object') return data;

  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
    const lowerKey = key.toLowerCase();
    if (SECRET_KEYS.some((s) => lowerKey.includes(s))) {
      result[key] = '[REDACTED]';
    } else {
      result[key] = redactSecrets(value);
    }
  }
  return result;
}

function buildPayload(event: string, data: unknown, sessionId?: string): object {
  return {
    version: 1,
    host: 'openclaw',
    event,
    payload: redactSecrets(data),
    session_id: sessionId,
    timestamp: new Date().toISOString(),
  };
}

function findOrca(cwd?: string): string | null {
  try {
    const which = execSync('which orca', { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'ignore'] });
    const bin = which.trim();
    if (bin) return bin;
  } catch {
    // orca not in PATH
  }

  const candidates = [
    cwd ? join(cwd, 'zig-out', 'bin', 'orca') : null,
    cwd ? join(cwd, '..', 'zig-out', 'bin', 'orca') : null,
    cwd ? join(cwd, '..', '..', 'zig-out', 'bin', 'orca') : null,
    resolve('zig-out', 'bin', 'orca'),
    resolve('..', 'zig-out', 'bin', 'orca'),
    resolve('..', '..', 'zig-out', 'bin', 'orca'),
  ].filter((p): p is string => p !== null);

  for (const p of candidates) {
    if (existsSync(p)) return p;
  }

  return null;
}

async function callOrca(
  orcaBin: string,
  event: string,
  data: unknown,
  sessionId: string | undefined,
  blocking: boolean,
  logger: PluginLogger | undefined
): Promise<OrcaResponse> {
  const payload = buildPayload(event, data, sessionId);
  const payloadJson = JSON.stringify(payload);

  let stdout = '';

  try {
    stdout = execSync(`${orcaBin} hook openclaw ${event}`, {
      input: payloadJson,
      encoding: 'utf-8',
      timeout: blocking ? 15000 : 10000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    if (!stdout.trim()) {
      return { decision: 'allow' };
    }

    return JSON.parse(stdout) as OrcaResponse;
  } catch (err: unknown) {
    const safeErr = redactSecrets({ message: (err as Error).message });
    logger?.error?.(`[orca] Hook ${event} failed: ${(safeErr as { message: string }).message}`);

    return blocking
      ? {
          decision: 'block',
          risk: 'high',
          category: 'unknown',
          reason: 'orca_hook_error',
          message: 'Orca hook failed; blocking as a precaution.',
        }
      : {
          decision: 'allow',
          risk: 'unknown',
          category: 'unknown',
          reason: 'orca_hook_error',
          message: 'Orca hook failed; allowing because this event is non-blocking.',
        };
  }
}

/**
 * Detect whether api.on is likely a no-op.
 * OpenClaw loads npm plugins with registrationMode "cli-metadata", where
 * api.on is wired to a no-op function. This is a known limitation.
 */
function isOnNoop(api: OpenClawPluginApi): boolean {
  if (typeof api.on !== 'function') return true;

  // Heuristic: try registering a test hook. If api.on is a real typed-hook
  // registrar, unknown hook names are silently ignored but still accepted.
  // A no-op will also silently accept them, so this is not a definitive test.
  // We use a secondary heuristic: check if the plugin source path suggests a
  // bundled vs npm/global install.
  const source = api.source || '';
  if (source.includes('node_modules') || source.includes('.openclaw/npm')) {
    return true;
  }

  return false;
}

export default function orcaPlugin(api: OpenClawPluginApi): void {
  const cwd = process.cwd();
  const sessionId = undefined;
  const orcaBin = findOrca(cwd);
  const { logger } = api;

  if (!orcaBin) {
    logger?.warn?.(
      '[orca] Binary not found in PATH or typical build paths. ' +
        'Run: ./scripts/install-orca-plugin.sh openclaw project (or .\scripts\install-orca-plugin.ps1 openclaw project on Windows).'
    );
    return;
  }

  if (typeof api.on !== 'function') {
    logger?.warn?.(
      '[orca] OpenClaw plugin API does not expose hook registration (api.on). ' +
        'Plugin will not register lifecycle hooks.'
    );
    return;
  }

  const onIsNoop = isOnNoop(api);

  if (onIsNoop) {
    logger?.warn?.(
      '[orca] Detected npm/global plugin install. ' +
        'OpenClaw currently wires api.on to a no-op for non-bundled plugins, ' +
        'so before_tool_call / after_tool_call hooks will NOT fire. ' +
        'For full runtime guardrails, run OpenClaw through Orca:  ' +
        '`orca run -- openclaw`  ' +
        '(see https://github.com/christopherkarani/Orca#openclaw-plugin).'
    );
  }

  logger?.info?.(`[orca] Plugin loaded. Binary: ${orcaBin}`);

  api.on('session_start', async (event) => {
    logger?.info?.('[orca] Plugin ready for session.');
    await callOrca(
      orcaBin,
      'session.start',
      { session_id: (event as { sessionId?: string })?.sessionId },
      sessionId,
      false,
      logger
    );
  });

  api.on('before_tool_call', async (event) => {
    const response = await callOrca(orcaBin, 'tool.before', event, sessionId, true, logger);

    if (response.decision === 'block') {
      const msg = response.message || response.reason || 'Blocked by Orca policy';
      logger?.error?.(`[orca] Blocked tool execution: ${msg}`);
      return { block: true, blockReason: msg };
    }

    if (response.decision === 'warn') {
      logger?.warn?.(`[orca] Warning: ${response.message || response.reason}`);
    }

    return { params: (event as { params?: Record<string, unknown> })?.params };
  });

  api.on('after_tool_call', async (event) => {
    await callOrca(orcaBin, 'tool.after', event, sessionId, false, logger);
  });

  api.on('session_end', async (event) => {
    await callOrca(orcaBin, 'session.end', event, sessionId, false, logger);
  });
}
