# Staged Writes Example

After an Orca-mediated session creates staged writes:

```sh
../../zig-out/bin/orca diff --session last
../../zig-out/bin/orca apply --session last --file docs/example.md
../../zig-out/bin/orca discard --session last
```

Staging is review workflow coverage for Orca-mediated writes. It is not a claim of transparent filesystem enforcement on every platform.
