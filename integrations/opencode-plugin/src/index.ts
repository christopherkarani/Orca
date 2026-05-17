import { execSync } from 'child_process';
import { existsSync } from 'fs';
import { join, resolve } from 'path';

interface OpenCodeContext {
  hooks: {
    on: (event: string, handler: (data: unknown) => unknown | Promise<unknown>) => void;
  };
  shell?: {
    $: (strings: TemplateStringsArray, ...values: unknown[]) => Promise<{ stdout: string; stderr: string; exitCode: number }>;
  };
  logger?: {
    info: (msg: string) => void;
    warn: (msg: string) => void;
    error: (msg: string) => void;
  };
  session?: {
    id?: string;
    cwd?: string;
  };
}

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
    host: 'opencode',
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
  shell: OpenCodeContext['shell'],
  logger: OpenCodeContext['logger']
): Promise<OrcaResponse> {
  const payload = buildPayload(event, data, sessionId);
  const payloadJson = JSON.stringify(payload);

  let stdout = '';

  try {
    if (shell?.$) {
      const result = await shell.$`echo ${payloadJson} | ${orcaBin} hook opencode ${event}`;
      stdout = result.stdout ?? '';
    } else {
      stdout = execSync(`${orcaBin} hook opencode ${event}`, {
        input: payloadJson,
        encoding: 'utf-8',
        timeout: blocking ? 15000 : 10000,
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    }

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

export default function orcaPlugin(context: OpenCodeContext): void {
  const cwd = context.session?.cwd ?? process.cwd();
  const sessionId = context.session?.id;
  const orcaBin = findOrca(cwd);
  const { shell, logger } = context;

  if (!orcaBin) {
    logger?.warn?.(
      '[orca] Binary not found in PATH or typical build paths. ' +
        'Run: ./scripts/install-orca-plugin.sh opencode project (or .\\scripts\\install-orca-plugin.ps1 opencode project on Windows).'
    );
    return;
  }

  logger?.info?.(`[orca] Plugin loaded. Binary: ${orcaBin}`);

  context.hooks.on('session.created', async (session: unknown) => {
    logger?.info?.('[orca] Plugin ready for session.');
    await callOrca(orcaBin, 'SessionStart', { session_id: (session as { id?: string })?.id }, sessionId, false, shell, logger);
  });

  context.hooks.on('tool.execute.before', async (toolCall: unknown) => {
    const response = await callOrca(orcaBin, 'PreToolUse', toolCall, sessionId, true, shell, logger);

    if (response.decision === 'block') {
      const msg = response.message || response.reason || 'Blocked by Orca policy';
      logger?.error?.(`[orca] Blocked tool execution: ${msg}`);
      throw new Error(`Orca blocked tool execution: ${msg}`);
    }

    if (response.decision === 'warn') {
      logger?.warn?.(`[orca] Warning: ${response.message || response.reason}`);
    }

    return toolCall;
  });

  context.hooks.on('tool.execute.after', async (result: unknown) => {
    await callOrca(orcaBin, 'PostToolUse', result, sessionId, false, shell, logger);
    return result;
  });

  context.hooks.on('permission.asked', async (permission: unknown) => {
    const response = await callOrca(orcaBin, 'PermissionRequest', permission, sessionId, true, shell, logger);

    if (response.decision === 'block') {
      const msg = response.message || response.reason || 'Blocked by Orca policy';
      logger?.error?.(`[orca] Blocked permission: ${msg}`);
      throw new Error(`Orca blocked permission request: ${msg}`);
    }

    if (response.decision === 'warn') {
      logger?.warn?.(`[orca] Permission warning: ${response.message || response.reason}`);
    }

    return permission;
  });

  context.hooks.on('file.edited', async (edit: unknown) => {
    await callOrca(orcaBin, 'FileEdit', edit, sessionId, false, shell, logger);
    return edit;
  });

  context.hooks.on('command.executed', async (command: unknown) => {
    await callOrca(orcaBin, 'CommandExecuted', command, sessionId, false, shell, logger);
    return command;
  });

  context.hooks.on('session.updated', async (session: unknown) => {
    await callOrca(orcaBin, 'SessionUpdate', session, sessionId, false, shell, logger);
    return session;
  });

  context.hooks.on('session.idle', async (session: unknown) => {
    await callOrca(orcaBin, 'SessionIdle', session, sessionId, false, shell, logger);
    return session;
  });

  context.hooks.on('session.error', async (error: unknown) => {
    const safeError = redactSecrets({
      message: (error as { message?: string })?.message,
      stack: (error as { stack?: string })?.stack,
      type: (error as { type?: string })?.type,
    });
    await callOrca(orcaBin, 'SessionError', safeError, sessionId, false, shell, logger);
    return error;
  });

  context.hooks.on('shell.env', async (env: unknown) => {
    const safeEnv = redactSecrets(env);
    await callOrca(orcaBin, 'ShellEnv', safeEnv, sessionId, false, shell, logger);
    return env;
  });
}
