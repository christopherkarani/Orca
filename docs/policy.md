# Policy

Policies are versioned with `version: 1`. Missing versions, unknown modes, invalid rule shapes, oversized files, malformed patterns, and unknown keys are invalid.

Deny beats allow. In CI mode, ask decisions become deny unless an explicit allow rule applies. Strict and CI paths fail closed for invalid policies.

Validate policies with:

```sh
./zig-out/bin/aegis policy check policies/default.yaml
```

All preset files under `policies/presets/*.yaml` are covered by security regression tests.
