# CI

Aegis has no hosted service requirement.

## GitHub Actions Example

```yaml
name: aegis
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Zig
        run: |
          echo "Install Zig 0.15.2 using your pinned toolchain action or cache"
      - name: Build
        run: zig build
      - name: Test
        run: zig build test
      - name: Aegis red-team
        run: ./zig-out/bin/aegis redteam --ci --json > aegis-redteam.json
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: aegis-audit
          path: |
            .aegis/**
            aegis-redteam.json
```

See `docs/ci/github-actions.md` and `examples/ci/github-actions.yml`.

## Non-interactive Mode

Use `--mode ci` for commands and `--ci` for red-team. In CI, ask becomes deny.

## Audit Artifacts

Upload `.aegis/sessions/**`, `events.jsonl`, `summary.json`, and `summary.md` only if they contain synthetic or approved data. Redaction is applied before persistence, but audit artifacts can still reveal file names and command shapes.
