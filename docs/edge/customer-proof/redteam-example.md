# Red-Team Example

Run:

```sh
./zig-out/bin/aegis-edge redteam --ci
./zig-out/bin/aegis-edge redteam --category data-guard
./zig-out/bin/aegis-edge redteam --report safety-case
```

The red-team suite exercises deterministic fake/simulation fixtures. Optional SITL fixtures are skipped unless their local simulator gates are explicitly enabled. Skipped, unsupported, and inconclusive results are not passes.

Checked-in sample: `examples/edge/customer-proof/redteam-scorecard.md`.
