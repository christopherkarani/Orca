import { describe, it, mock } from 'node:test';
import assert from 'node:assert';
import orcaPlugin, { isOnNoop } from '../src/index.ts';

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

describe('orcaPlugin', () => {
  it('warns about noop api.on for npm installs', () => {
    const api = makeApi({
      source: '/path/to/node_modules/orca-openclaw-plugin',
    });
    // Prevent early return from missing binary by providing a fake PATH
    // Since findOrca calls `which orca`, we can't easily stub it without
    // refactoring. Instead we accept that on CI/orca-installed machines
    // the test may take the binary-found path.
    // For unit testing we should ideally inject findOrca, but for now
    // we test the warning via isOnNoop directly.
    orcaPlugin(api);

    const warnCalls = (api.logger.warn as any).mock.calls;
    const noopWarning = warnCalls.find(
      (c: any) =>
        typeof c.arguments[0] === 'string' &&
        c.arguments[0].includes('api.on to a no-op')
    );
    assert.ok(noopWarning, 'Expected warning about noop api.on');
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
        c.arguments[0].includes('api.on to a no-op')
    );
    assert.strictEqual(noopWarning, undefined, 'Should not warn for bundled installs');
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
