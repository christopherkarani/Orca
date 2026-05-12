# Network Example

Run with no-network policy decisions:

```sh
../../zig-out/bin/aegis run --policy ../policies/strict-no-network.yaml --mode strict -- echo local-only
```

Allow one destination for Aegis-mediated decisions:

```sh
../../zig-out/bin/aegis run --network allowlist --allow-network api.github.com -- echo checked
```

Transparent network enforcement depends on `aegis doctor`.
