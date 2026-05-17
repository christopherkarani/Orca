# Red-team

Red-team fixtures are deterministic local checks for Orca controls.

## Categories

Current fixture categories include prompt injection, secret exfiltration, shell abuse, network exfiltration, filesystem bypass, and MCP tool poisoning.

## Run

```sh
./zig-out/bin/orca redteam --ci
./zig-out/bin/orca redteam fixtures --fixture prompt-injection/readme-env-read --ci
```

## JSON Output

```sh
./zig-out/bin/orca redteam --json --ci > redteam.json
```

## CI Mode

`--ci` is non-interactive and exits non-zero if a required fixture fails or is unsupported.

## Adding Fixtures

Read [contributing-fixtures.md](contributing-fixtures.md). Fixtures must use synthetic data, no real secrets, no real LLMs, and no external network services.

## Skipped Or Unsupported

Some fixtures may be platform-gated. A skipped unsupported result means the host lacks the required backend feature; it is not a pass for that protection.
