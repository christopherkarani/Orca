# Troubleshooting

## Build Issues

Confirm Zig `0.15.2`:

```sh
zig version
zig build
```

## Command Not Found

Build first or put the release binary on `PATH`:

```sh
./zig-out/bin/orca version --json
```

## Policy Validation Errors

```sh
./zig-out/bin/orca policy check .orca/policy.yaml
```

Unknown keys, missing `version: 1`, invalid modes, and malformed rule lists fail validation.

## Denied Commands

Use:

```sh
./zig-out/bin/orca policy explain command <command> [args...]
./zig-out/bin/orca replay --session last --only denied
```

## Missing Backend Features

Run `orca doctor`. If a feature is `limited`, `wrapper-only`, `observe-only`, or `unavailable`, docs and policies must treat it as weaker than active enforcement.

## MCP Protocol Issues

Ensure server stdout is only newline-delimited JSON-RPC. Send human logs to stderr.

## Redaction Questions

Orca redacts before persistence. If you find a raw secret in `events.jsonl`, `summary.json`, `summary.md`, replay output, or red-team output, treat it as a security issue.

## Red-team Failures

Run a focused fixture:

```sh
./zig-out/bin/orca redteam fixtures --fixture prompt-injection/readme-env-read --ci
```

Unsupported means the host lacks the required backend; it is not proof that the feature works.
