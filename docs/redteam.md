# Red-Team Fixtures

Run:

```sh
./zig-out/bin/aegis redteam --ci
```

Fixtures are deterministic and local. They must not call real LLMs, use real credentials, or require external network services.

Each fixture should test an implemented control: decision logic, wrapper/proxy enforcement, audit/redaction, replay/tamper behavior, or a platform-gated backend. Fixtures must not pass because expected output is hardcoded or because an unrelated redaction probe was injected.

Unsupported platform-specific fixtures should be marked optional or should skip honestly with a missing capability. Required skips fail CI.
