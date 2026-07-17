import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import orcaPlugin from '../dist/index.js';

const pluginRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

async function withFakeOrca(run) {
  const directory = await mkdtemp(join(tmpdir(), 'orca-opencode-plugin-'));
  const orcaBin = join(directory, 'orca');
  const originalPath = process.env.PATH;

  await writeFile(
    orcaBin,
    `#!/bin/sh
payload=$(cat)
case "$payload" in
  *'"command":"rm -rf'* ) printf '%s\\n' '{"decision":"block","message":"command blocked"}' ;;
  *'"command":"rm'* ) printf '%s\\n' '{"decision":"ask","message":"approval required"}' ;;
  * ) printf '%s\\n' '{"decision":"allow"}' ;;
esac
`
  );
  await chmod(orcaBin, 0o755);
  process.env.PATH = `${directory}:${originalPath ?? ''}`;

  try {
    await run(await orcaPlugin({ directory, worktree: directory }));
  } finally {
    process.env.PATH = originalPath;
    await rm(directory, { recursive: true, force: true });
  }
}

for (const [command, message] of [
  ['rm file.txt', 'approval required'],
  ['rm -r build', 'approval required'],
  ['rm -rf build', 'command blocked'],
]) {
  test(`tool.execute.before blocks ${command}`, async () => {
    await withFakeOrca(async (plugin) => {
      const before = plugin['tool.execute.before'];
      assert.ok(before);

      await assert.rejects(
        before(
          { tool: 'bash', sessionID: 'session-1', callID: 'call-1' },
          { args: { command } }
        ),
        new RegExp(`Orca blocked tool execution: ${message}`)
      );
    });
  });
}

test('permission.ask keeps host ask for Orca ask (approve-and-resume)', async () => {
  await withFakeOrca(async (plugin) => {
    const permissionAsk = plugin['permission.ask'];
    assert.ok(permissionAsk);
    const output = { status: 'ask' };

    await permissionAsk({ sessionID: 'session-1', command: 'rm file.txt' }, output);

    // Native permission UI: Orca ask must not hard-deny without resume.
    assert.equal(output.status, 'ask');
  });
});

test('permission.ask denies Orca block', async () => {
  await withFakeOrca(async (plugin) => {
    const permissionAsk = plugin['permission.ask'];
    assert.ok(permissionAsk);
    const output = { status: 'ask' };

    await permissionAsk({ sessionID: 'session-1', command: 'rm -rf build' }, output);

    assert.equal(output.status, 'deny');
  });
});

test('permission.ask fail-closes unknown decisions', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'orca-opencode-plugin-'));
  const orcaBin = join(directory, 'orca');
  const originalPath = process.env.PATH;
  await writeFile(
    orcaBin,
    `#!/bin/sh
printf '%s\\n' '{"decision":"unexpected","message":"bad decision"}'
`
  );
  await chmod(orcaBin, 0o755);
  process.env.PATH = `${directory}:${originalPath ?? ''}`;
  try {
    const plugin = await orcaPlugin({ directory, worktree: directory });
    const permissionAsk = plugin['permission.ask'];
    assert.ok(permissionAsk);
    const output = { status: 'ask' };
    await permissionAsk({ sessionID: 'session-1', command: 'echo hi' }, output);
    assert.equal(output.status, 'deny');
  } finally {
    process.env.PATH = originalPath;
    await rm(directory, { recursive: true, force: true });
  }
});

test('tool.execute.before still hard-blocks Orca ask (no resume on that path)', async () => {
  await withFakeOrca(async (plugin) => {
    const before = plugin['tool.execute.before'];
    assert.ok(before);
    await assert.rejects(
      before(
        { tool: 'bash', sessionID: 'session-1', callID: 'call-1' },
        { args: { command: 'rm file.txt' } }
      ),
      /Orca blocked tool execution: approval required/
    );
  });
});

test('orca.ts is a single-source sync of src/index.ts', async () => {
  const src = await readFile(join(pluginRoot, 'src/index.ts'), 'utf8');
  const dropIn = await readFile(join(pluginRoot, 'orca.ts'), 'utf8');
  assert.equal(
    dropIn,
    src,
    'orca.ts must match src/index.ts (npm run build copies src → orca.ts)'
  );
});
