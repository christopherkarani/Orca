# GitHub Actions

This integration is local-only. It does not assume a hosted Orca service, policy sync, telemetry, or model-provider secrets.

Use a CI policy:

```bash
orca init --preset github-actions
orca policy check .orca/policy.yaml
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
      - name: Install Orca
        run: ./scripts/install.sh
      - name: Check Orca policy
        run: orca policy check .orca/policy.yaml
      - name: Run agent safely
        run: orca run --mode ci -- ./scripts/agent-task.sh
      - name: Run red-team fixtures
        run: orca redteam --ci
      - name: Upload Orca audit logs
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: orca-audit
          path: .orca/sessions
```

You can also wrap a command with the repository-local composite action:

```yaml
- uses: ./.github/actions/orca-run
  with:
    command: ./scripts/agent-task.sh
```

Security notes:

- CI mode never prompts. Ask decisions become denies unless policy explicitly allows the action.
- Do not put tokens or secrets in policy files, workflow examples, or audit artifacts.
- Orca audit logs are redacted before persistence, but avoid running commands that intentionally print secrets.
- Platform sandbox capability depends on the runner OS. Use `orca doctor` for the actual capability report.
