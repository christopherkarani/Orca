import { execSync } from 'child_process';
import { existsSync } from 'fs';
import { join, resolve } from 'path';

interface OpenCodeContext {
  hooks: {
    on: (event: string, handler: (data: any) => any | Promise<any>) => void;
  };
  shell?: {
    $: (strings: TemplateStringsArray, ...values: any[]) => Promise<{ stdout: string; stderr: string; exitCode: number }>;
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

function redactSecrets(data: any): any {
  if (data === null || data === undefined) return data;
  if (typeof data === 'string') return data;
  if (Array.isArray(data)) return data.map(redactSecrets);
  if (typeof data !== 'object') return data;

  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(data)) {
    const lowerKey = key.toLowerCase();
    if (SECRET_KEYS.some((s) => lowerKey.includes(s))) {
      result[key] = '[REDACTED]';
    } else {
      result[key] = redactSecrets(value);
    }
  }
  return result;
}

function buildPayload(event: string, data: any, sessionId?: string): object {
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
  } catch {}

  const candidates = [
    cwd ? join(cwd, 'zig-out', 'bin', 'orca') : null,
    cwd ? join(cwd, '..', 'zig-out', 'bin', 'orca') : null,
    cwd ? join(cwd, '..', '..', 'zig-out', 'bin', 'orca') : null,
    resolve('zig-out', 'bin', 'orca'),
    resolve('..', 'zig-out', 'bin', 'orca'),
    resolve('..', '..', 'zig-out', 'bin', 'orca'),
  ].filter(Boolean) as string[];

  for (const p of candidates) {
    if (existsSync(p)) return p;
  }

  return null;
}

async function callOrca(
  orcaBin: string,
  event: string,
  data: any,
  sessionId: string | undefined,
  blocking: boolean,
  shell: OpenCodeContext['shell'],
  logger: OpenCodeContext['logger']
): Promise<OrcaResponse> {
  const payload = buildPayload(event, data, sessionId);
  const payloadJson = JSON.stringify(payload);

  let stdout = '';
  let stderr = '';

  try {
    if (shell?.$) {
      const result = await shell.$`echo ${payloadJson} | ${orcaBin} hook opencode ${event}`;
      stdout = result.stdout ?? '';
      stderr = result.stderr ?? '';
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
  } catch (err: any) {
    const safeErr = redactSecrets({ message: err.message });
    logger?.error?.(`[orca] Hook ${event} failed: ${safeErr.message}`);

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
        'Build with: zig build (produces ./zig-out/bin/orca)'
    );
    return;
  }

  logger?.info?.(`[orca] Plugin loaded. Binary: ${orcaBin}`);

  context.hooks.on('session.created', async (session: any) => {
    logger?.info?.('[orca] Plugin ready for session.');
    await callOrca(orcaBin, 'SessionStart', { session_id: session?.id }, sessionId, false, shell, logger);
  });

  context.hooks.on('tool.execute.before', async (toolCall: any) => {
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

  context.hooks.on('tool.execute.after', async (result: any) => {
    await callOrca(orcaBin, 'PostToolUse', result, sessionId, false, shell, logger);
    return result;
  });

  context.hooks.on('permission.asked', async (permission: any) => {
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

  context.hooks.on('file.edited', async (edit: any) => {
    await callOrca(orcaBin, 'FileEdit', edit, sessionId, false, shell, logger);
    return edit;
  });

  context.hooks.on('command.executed', async (command: any) => {
    await callOrca(orcaBin, 'CommandExecuted', command, sessionId, false, shell, logger);
    return command;
  });

  context.hooks.on('session.updated', async (session: any) => {
    await callOrca(orcaBin, 'SessionUpdate', session, sessionId, false, shell, logger);
    return session;
  });

  context.hooks.on('session.idle', async (session: any) => {
    await callOrca(orcaBin, 'SessionIdle', session, sessionId, false, shell, logger);
    return session;
  });

  context.hooks.on('session.error', async (error: any) => {
    const safeError = redactSecrets({
      message: error?.message,
      stack: error?.stack,
      type: error?.type,
    });
    await callOrca(orcaBin, 'SessionError', safeError, sessionId, false, shell, logger);
    return error;
  });

  context.hooks.on('shell.env', async (env: any) => {
    const safeEnv = redactSecrets(env);
    await callOrca(orcaBin, 'ShellEnv', safeEnv, sessionId, false, shell, logger);
    return env;
  });
}
