# CI

Aegis supports local CI execution with `aegis run --mode ci -- <command>`.

CI mode is non-interactive. It is intended for repeatable repository automation where policy is checked in and audit artifacts are uploaded for review.

Start with:

```bash
aegis init --preset github-actions
aegis policy check .aegis/policy.yaml
aegis redteam --ci
```

For GitHub Actions, see [docs/ci/github-actions.md](ci/github-actions.md).
