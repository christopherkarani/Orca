import assert from 'node:assert/strict';
import { chmod, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import orcaPlugin from '../dist/index.js';

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

test('permission.ask denies an Orca ask if OpenCode invokes the legacy callback', async () => {
  await withFakeOrca(async (plugin) => {
    const permissionAsk = plugin['permission.ask'];
    assert.ok(permissionAsk);
    const output = { status: 'ask' };

    await permissionAsk({ sessionID: 'session-1', command: 'rm file.txt' }, output);

    assert.equal(output.status, 'deny');
  });
});
