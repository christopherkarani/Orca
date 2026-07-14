import { describe, it, mock } from 'node:test';
import assert from 'node:assert';
import orcaPlugin, {
  isOnNoop,
  parseHookResponse,
  UNPROTECTED_NOOP_WARNING,
} from '../src/index.ts';

// Minimal mock API factory
function makeApi(overrides: Partial<Parameters<typeof orcaPlugin>[0]> = {}) {
  const logger = {
    debug: mock.fn(),
    info: mock.fn(),
    warn: mock.fn(),
    error: mock.fn(),
  };
  const on = mock.fn();
  return {
    id: 'test',
    name: 'test-plugin',
    source: '/bundled/plugins/orca',
    config: {},
    runtime: {},
    logger,
    on,
    ...overrides,
  };
}

describe('isOnNoop', () => {
  it('returns true when api.on is not a function', () => {
    const api = makeApi({ on: undefined as unknown as typeof makeApi extends (...args: any[]) => infer R ? R extends { on: infer O } ? O : never : never });
    assert.strictEqual(isOnNoop(api as any), true);
  });

  it('returns true when source contains node_modules', () => {
    const api = makeApi({ source: '/path/to/node_modules/orca-openclaw-plugin' });
    assert.strictEqual(isOnNoop(api), true);
  });

  it('returns true when source contains .openclaw/npm', () => {
    const api = makeApi({ source: '/home/user/.openclaw/npm/orca-openclaw-plugin' });
    assert.strictEqual(isOnNoop(api), true);
  });

  it('returns false for bundled plugin sources', () => {
    const api = makeApi({ source: '/Applications/OpenClaw.app/Contents/Plugins/orca' });
    assert.strictEqual(isOnNoop(api), false);
  });

  it('returns false when source is empty but on is a function', () => {
    const api = makeApi({ source: '' });
    assert.strictEqual(isOnNoop(api), false);
  });
});

describe('parseHookResponse (fail-closed blocking path)', () => {
  it('empty stdout on blocking path → block', () => {
    const r = parseHookResponse('', true);
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.reason, 'orca_empty_response');
  });

  it('whitespace-only stdout on blocking path → block', () => {
    const r = parseHookResponse('   \n\t  ', true);
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.reason, 'orca_empty_response');
  });

  it('malformed JSON on blocking path → block', () => {
    const r = parseHookResponse('{not-json', true);
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.reason, 'orca_parse_error');
  });

  it('missing decision on blocking path → block', () => {
    const r = parseHookResponse(JSON.stringify({ version: 1 }), true);
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.reason, 'orca_missing_decision');
  });

  it('non-string decision on blocking path → block', () => {
    const r = parseHookResponse(JSON.stringify({ decision: 42 }), true);
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.reason, 'orca_missing_decision');
  });

  it('ask decision on blocking path → block', () => {
    const r = parseHookResponse(
      JSON.stringify({ decision: 'ask', reason: 'needs_approval' }),
      true
    );
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.reason, 'orca_ask_unsupported');
  });

  it('unrecognized decision on blocking path → block', () => {
    const r = parseHookResponse(
      JSON.stringify({ decision: 'maybe', reason: 'weird' }),
      true
    );
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.reason, 'orca_unrecognized_decision');
  });

  it('allow decision passes through', () => {
    const r = parseHookResponse(
      JSON.stringify({ decision: 'allow', reason: 'policy_allow' }),
      true
    );
    assert.strictEqual(r.decision, 'allow');
  });

  it('block decision passes through', () => {
    const r = parseHookResponse(
      JSON.stringify({ decision: 'block', reason: 'policy_deny', message: 'nope' }),
      true
    );
    assert.strictEqual(r.decision, 'block');
    assert.strictEqual(r.message, 'nope');
  });

  it('empty stdout on non-blocking path → allow', () => {
    const r = parseHookResponse('', false);
    assert.strictEqual(r.decision, 'allow');
  });
});

describe('orcaPlugin', () => {
  it('warns about unprotected noop api.on for npm installs', () => {
    const api = makeApi({
      source: '/path/to/node_modules/orca-openclaw-plugin',
    });
    orcaPlugin(api);

    const warnCalls = (api.logger.warn as any).mock.calls;
    const noopWarning = warnCalls.find(
      (c: any) =>
        typeof c.arguments[0] === 'string' &&
        (c.arguments[0].includes('unprotected') ||
          c.arguments[0] === UNPROTECTED_NOOP_WARNING)
    );
    assert.ok(noopWarning, 'Expected unprotected warning about noop api.on');
    assert.ok(
      String(noopWarning.arguments[0]).includes('unprotected'),
      'Warning must include unprotected grade label'
    );
    assert.ok(
      String(noopWarning.arguments[0]).includes('orca run -- openclaw'),
      'Warning must recommend wrapper path'
    );
  });

  it('does not warn about noop when source is bundled', () => {
    const api = makeApi({
      source: '/Applications/OpenClaw.app/Contents/Plugins/orca',
    });
    orcaPlugin(api);

    const warnCalls = (api.logger.warn as any).mock.calls;
    const noopWarning = warnCalls.find(
      (c: any) =>
        typeof c.arguments[0] === 'string' &&
        c.arguments[0].includes('unprotected')
    );
    assert.strictEqual(noopWarning, undefined, 'Should not warn unprotected for bundled installs');
  });

  it('registers lifecycle hooks even when api.on is suspected noop', () => {
    const api = makeApi({
      source: '/path/to/node_modules/orca-openclaw-plugin',
    });
    orcaPlugin(api);

    const onCalls = (api.on as any).mock.calls;
    const events = onCalls.map((c: any) => c.arguments[0]);
    assert.ok(events.includes('session_start'));
    assert.ok(events.includes('before_tool_call'));
    assert.ok(events.includes('after_tool_call'));
    assert.ok(events.includes('session_end'));
  });
});
