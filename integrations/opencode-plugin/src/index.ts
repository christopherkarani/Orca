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

type PluginContext = {
  directory: string;
  worktree: string;
};

type ToolExecuteBeforeInput = {
  tool: string;
  sessionID: string;
  callID: string;
};

type ToolExecuteBeforeOutput = {
  args: Record<string, unknown>;
};

type ToolExecuteAfterInput = ToolExecuteBeforeInput & {
  args: Record<string, unknown>;
};

type ToolExecuteAfterOutput = {
  title: string;
  output: string;
  metadata: unknown;
};

type PermissionAskOutput = {
  status: 'ask' | 'deny' | 'allow';
};

type ShellEnvInput = {
  cwd: string;
  sessionID?: string;
  callID?: string;
};

type ShellEnvOutput = {
  env: Record<string, string>;
};

type PluginHooks = {
  event?: (input: { event: Record<string, unknown> }) => Promise<void>;
  'tool.execute.before'?: (
    input: ToolExecuteBeforeInput,
    output: ToolExecuteBeforeOutput
  ) => Promise<void>;
  'tool.execute.after'?: (
    input: ToolExecuteAfterInput,
    output: ToolExecuteAfterOutput
  ) => Promise<void>;
  'permission.ask'?: (input: Record<string, unknown>, output: PermissionAskOutput) => Promise<void>;
  'shell.env'?: (input: ShellEnvInput, output: ShellEnvOutput) => Promise<void>;
};

const SECRET_KEYS = [
  'password', 'token', 'secret', 'api_key', 'apikey', 'api_secret',
  'auth', 'authorization', 'bearer', 'private_key', 'access_token',
  'refresh_token', 'credential', 'passwd', 'pwd',
];

const AUDIT_EVENT_TYPES = new Set([
  'session.created',
  'permission.replied',
  'file.edited',
  'command.executed',
  'session.updated',
  'session.idle',
  'session.error',
]);

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

function callOrca(
  orcaBin: string,
  event: string,
  data: unknown,
  sessionId: string | undefined,
  blocking: boolean
): OrcaResponse {
  const payloadJson = JSON.stringify(buildPayload(event, data, sessionId));

  try {
    const stdout = execSync(`${orcaBin} hook opencode ${event}`, {
      input: payloadJson,
      encoding: 'utf-8',
      timeout: blocking ? 15000 : 10000,
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 1024 * 1024,
    });

    if (!stdout.trim()) {
      return { decision: 'allow' };
    }

    return JSON.parse(stdout) as OrcaResponse;
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[orca] Hook ${event} failed: ${message}`);

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

function buildToolBeforePayload(
  input: ToolExecuteBeforeInput,
  output: ToolExecuteBeforeOutput
): Record<string, unknown> {
  return {
    tool: input.tool,
    sessionID: input.sessionID,
    callID: input.callID,
    ...output.args,
    args: output.args,
  };
}

function applyBlockingDecision(response: OrcaResponse, context: string): void {
  if (response.decision === 'block') {
    const msg = response.message || response.reason || 'Blocked by Orca policy';
    console.error(`[orca] Blocked ${context}: ${msg}`);
    throw new Error(`Orca blocked ${context}: ${msg}`);
  }

  if (response.decision === 'warn') {
    console.warn(`[orca] Warning: ${response.message || response.reason}`);
  }
}

function auditEventPayload(event: Record<string, unknown>): unknown {
  if (event.type === 'session.error') {
    return redactSecrets({
      message: event.message,
      stack: event.stack,
      type: event.type,
    });
  }
  return redactSecrets(event);
}

function sessionIdFromEvent(event: Record<string, unknown>): string | undefined {
  if (typeof event.sessionID === 'string') return event.sessionID;
  if (typeof event.session_id === 'string') return event.session_id;
  return undefined;
}

function sessionIdFromRecord(value: Record<string, unknown>): string | undefined {
  if (typeof value.sessionID === 'string') return value.sessionID;
  if (typeof value.session_id === 'string') return value.session_id;
  return undefined;
}

export default async function orcaPlugin(ctx: PluginContext): Promise<PluginHooks> {
  const cwd = ctx.worktree || ctx.directory || process.cwd();
  const orcaBin = findOrca(cwd);

  if (!orcaBin) {
    console.warn(
      '[orca] Binary not found in PATH or typical build paths. ' +
        'Run: ./scripts/install-orca-plugin.sh opencode project (or .\\scripts\\install-orca-plugin.ps1 opencode project on Windows).'
    );
    return {};
  }

  console.log(`[orca] Plugin loaded. Binary: ${orcaBin}`);

  return {
    event: async ({ event }) => {
      const eventType = typeof event.type === 'string' ? event.type : '';
      if (!AUDIT_EVENT_TYPES.has(eventType)) return;

      if (eventType === 'session.created') {
        console.log('[orca] Plugin ready for session.');
      }

      await callOrca(
        orcaBin,
        eventType,
        auditEventPayload(event),
        sessionIdFromEvent(event),
        false
      );
    },

    'tool.execute.before': async (input, output) => {
      const response = callOrca(
        orcaBin,
        'tool.execute.before',
        buildToolBeforePayload(input, output),
        input.sessionID,
        true
      );
      applyBlockingDecision(response, 'tool execution');
    },

    'tool.execute.after': async (input, output) => {
      await callOrca(
        orcaBin,
        'tool.execute.after',
        {
          tool: input.tool,
          sessionID: input.sessionID,
          callID: input.callID,
          args: input.args,
          title: output.title,
          output: output.output,
          metadata: output.metadata,
        },
        input.sessionID,
        false
      );
    },

    'permission.ask': async (input, output) => {
      const sessionId = sessionIdFromRecord(input);
      const response = callOrca(orcaBin, 'permission.asked', input, sessionId, true);

      if (response.decision === 'block') {
        const msg = response.message || response.reason || 'Blocked by Orca policy';
        console.error(`[orca] Blocked permission: ${msg}`);
        output.status = 'deny';
        return;
      }

      if (response.decision === 'warn') {
        console.warn(`[orca] Permission warning: ${response.message || response.reason}`);
      }
    },

    'shell.env': async (input, output) => {
      await callOrca(
        orcaBin,
        'shell.env',
        {
          cwd: input.cwd,
          sessionID: input.sessionID,
          callID: input.callID,
          env: redactSecrets(output.env),
        },
        input.sessionID,
        false
      );
    },
  };
}
