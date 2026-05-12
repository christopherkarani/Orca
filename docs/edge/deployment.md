# Edge Deployment

Aegis Edge Phase 41 supports source, packaged, container, simulation, and no-actuation bench-preparation deployment checks.
It does not support real-flight deployment, live aircraft operation, autonomous flight procedures, flight instructions, detect-and-avoid, autopilot replacement, or regulatory certification.

Use:

```bash
aegis-edge deployment doctor
aegis-edge deployment assets
aegis-edge deployment check --profile examples/edge/deployment/profiles/source-local-fake.yaml
```

Profiles must identify the target architecture, deployment mode, environment, policy, scenario, runtime assets, network mode, audit/log paths, and limitations.
`real_flight` profiles are rejected.

Release artifacts must be verified with `checksums.txt` before install and must include schemas, policies, examples, docs, customer pilot materials, and package manifests. No service is enabled automatically and no hosted telemetry is configured.
