# Edge Troubleshooting

## `edge` Not Found

Run `zig build` and use `./zig-out/bin/edge`. Packaged installs should place the binary under the package `bin/` layout.

## Runtime Assets Missing

Run:

```sh
./zig-out/bin/edge deployment assets
```

Required schemas, docs, policies, examples, red-team fixtures, and safety-case templates must be present.

## Policy Validation Errors

Run `edge policy check <policy>`. Unknown keys, invalid safety limits, missing vehicle binding, or invalid watchdog settings fail validation.

## Scenario Validation Errors

Use the command family that matches the scenario type: `safety scenario`, `data scenario`, `health scenario`, `px4 scenario`, or `ardupilot scenario`.

## Fake Adapter Failures

Fake adapter failures usually indicate invalid fixture data, mismatched expected decisions, or unsupported command coverage. They do not indicate real aircraft behavior.

## PX4 SITL Unavailable

PX4 SITL tests skip unless explicitly enabled with the expected local simulator configuration. A skip is not a pass.

## ArduPilot SITL Unavailable

ArduPilot SITL tests skip unless explicitly enabled with the expected local simulator configuration. A skip is not a pass.

## Red-Team Fixture Failures

Run:

```sh
./zig-out/bin/edge redteam validate
./zig-out/bin/edge redteam --ci
```

Required fixture failures should be treated as product regressions. Unsupported and skipped fixtures must remain distinct from passes.

## Safety-Case Generation Failures

Confirm the policy and scenario paths are readable and valid, then rerun:

```sh
./zig-out/bin/edge safety-case generate --policy <policy> --scenario <scenario>
```

## Hash-Chain Verification Failure

Treat a replay verification failure as evidence integrity failure. Regenerate the demo evidence and inspect `.edge/sessions/<session-id>/events.jsonl`.

## Secrets And Redaction Questions

Raw secrets must not persist in logs, replay output, proof artifacts, or safety reports. The data guard redacts before persistence.

## ARM64 Packaging Issues

Run:

```sh
./zig-out/bin/edge deployment package-info --arch linux-arm64
```

Only documented Linux package targets are supported in this phase.

## Bench-Mode Warnings

Bench mode is `hardware_bench_no_actuation`. It is not flight evidence and should not be used as a real aircraft procedure.
