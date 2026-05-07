# GitHub Actions

This integration is local-only. It does not assume a hosted Aegis service, policy sync, telemetry, or model-provider secrets.

Use a CI policy:

```bash
aegis init --preset github-actions
aegis policy check .aegis/policy.yaml
```

Example workflow:

```yaml
name: Agent Task

on:
  workflow_dispatch:

jobs:
  agent:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Aegis
        run: ./scripts/install-aegis.sh
      - name: Check Aegis policy
        run: aegis policy check .aegis/policy.yaml
      - name: Run agent safely
        run: aegis run --mode ci -- ./scripts/agent-task.sh
      - name: Run red-team fixtures
        run: aegis redteam --ci
      - name: Upload Aegis audit logs
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: aegis-audit
          path: .aegis/sessions
```

You can also wrap a command with the repository-local composite action:

```yaml
- uses: ./.github/actions/aegis-run
  with:
    command: ./scripts/agent-task.sh
```

Security notes:

- CI mode never prompts. Ask decisions become denies unless policy explicitly allows the action.
- Do not put tokens or secrets in policy files, workflow examples, or audit artifacts.
- Aegis audit logs are redacted before persistence, but avoid running commands that intentionally print secrets.
- Platform sandbox capability depends on the runner OS. Use `aegis doctor` for the actual capability report.
