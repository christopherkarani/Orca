# Staged Writes Example

After an Aegis-mediated session creates staged writes:

```sh
../../zig-out/bin/aegis diff --session last
../../zig-out/bin/aegis apply --session last --file docs/example.md
../../zig-out/bin/aegis discard --session last
```

Staging is review workflow coverage for Aegis-mediated writes. It is not a claim of transparent filesystem enforcement on every platform.
