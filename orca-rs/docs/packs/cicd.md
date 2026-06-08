# CI/CD Packs

This document describes packs in the `cicd` category.

## Packs in this Category

- [GitHub Actions](#cicdgithub_actions)
- [GitLab CI](#cicdgitlab_ci)
- [Jenkins](#cicdjenkins)
- [CircleCI](#cicdcircleci)

---

## GitHub Actions

**Pack ID:** `cicd.github_actions`

Protects against destructive GitHub Actions operations like deleting secrets/variables or using gh api DELETE against /actions endpoints.

### Keywords

Commands containing these keywords are checked against this pack:

- `gh`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `gh-actions-secret-list` | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|variable\|workflow\|run\|api)\b)\S+)?)*\s+secret\s+list\b` |
| `gh-actions-variable-list` | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|variable\|workflow\|run\|api)\b)\S+)?)*\s+variable\s+list\b` |
| `gh-actions-workflow-list` | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|variable\|workflow\|run\|api)\b)\S+)?)*\s+workflow\s+list\b` |
| `gh-actions-workflow-view` | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|variable\|workflow\|run\|api)\b)\S+)?)*\s+workflow\s+view\b` |
| `gh-actions-run-list` | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|variable\|workflow\|run\|api)\b)\S+)?)*\s+run\s+list\b` |
| `gh-actions-run-view` | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|variable\|workflow\|run\|api)\b)\S+)?)*\s+run\s+view\b` |
| `gh-actions-api-explicit-get` | `^(?!(?=.*(?:-X\s*\|--method(?:=\|\s+))DELETE\b))gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|variable\|workflow\|run\|api)\b)\S+)?)*\s+api\b.*(?:-X\s*\|--method(?:=\|\s+))GET\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `gh-actions-secret-remove` | gh secret delete/remove deletes GitHub Actions secrets. This can break CI and may be hard to recover. | high |
| `gh-actions-variable-remove` | gh variable delete/remove deletes GitHub Actions variables. This can break workflows. | medium |
| `gh-actions-workflow-disable` | gh workflow disable disables workflows. This is reversible, but can disrupt CI. | low |
| `gh-actions-run-cancel` | gh run cancel cancels a running workflow. This is reversible, but may disrupt deployments. | low |
| `gh-actions-api-delete-secrets` | gh api DELETE against /actions/secrets deletes GitHub Actions secrets. | high |
| `gh-actions-api-delete-variables` | gh api DELETE against /actions/variables deletes GitHub Actions variables. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "cicd.github_actions:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "cicd.github_actions:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## GitLab CI

**Pack ID:** `cicd.gitlab_ci`

Protects against destructive GitLab CI/CD operations like deleting variables, removing artifacts, and unregistering runners.

### Keywords

Commands containing these keywords are checked against this pack:

- `glab`
- `gitlab-runner`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `glab-variable-list` | `glab(?:\s+--?\S+(?:\s+\S+)?)*\s+variable\s+list\b` |
| `glab-ci-list` | `glab(?:\s+--?\S+(?:\s+\S+)?)*\s+ci\s+list\b` |
| `glab-ci-view` | `glab(?:\s+--?\S+(?:\s+\S+)?)*\s+ci\s+view\b` |
| `glab-ci-status` | `glab(?:\s+--?\S+(?:\s+\S+)?)*\s+ci\s+status\b` |
| `gitlab-runner-list` | `gitlab-runner(?:\s+--?\S+(?:\s+\S+)?)*\s+list\b` |
| `gitlab-runner-status` | `gitlab-runner(?:\s+--?\S+(?:\s+\S+)?)*\s+status\b` |
| `glab-api-explicit-get` | `glab(?:\s+--?\S+(?:\s+\S+)?)*\s+api\b.*(?:-X\s*\|--method(?:=\|\s+))GET\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `glab-variable-delete` | glab variable delete removes CI variables and can break pipelines. | high |
| `glab-ci-delete` | glab ci delete removes pipeline artifacts or pipelines. | medium |
| `glab-api-delete-variables` | glab api DELETE against variables endpoints removes CI variables. | high |
| `gitlab-runner-unregister` | gitlab-runner unregister removes runners and can halt CI. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "cicd.gitlab_ci:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "cicd.gitlab_ci:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Jenkins

**Pack ID:** `cicd.jenkins`

Protects against destructive Jenkins CLI/API operations like deleting jobs, nodes, credentials, or build history.

### Keywords

Commands containing these keywords are checked against this pack:

- `jenkins-cli`
- `jenkins`
- `doDelete`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `jenkins-cli-list-jobs` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+list-jobs\b` |
| `jenkins-cli-get-job` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+get-job\b` |
| `jenkins-cli-build` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+build\b` |
| `jenkins-cli-who-am-i` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+who-am-i\b` |
| `jenkins-cli-list-views` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+list-views\b` |
| `jenkins-cli-list-plugins` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+list-plugins\b` |
| `jenkins-cli-get-node` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+get-node\b` |
| `jenkins-cli-get-credentials` | `(?:jenkins-cli\|java\s+-jar\s+\S*jenkins-cli\.jar)(?:\s+--?\S+(?:\s+\S+)?)*\s+get-credentials\b` |
| `jenkins-curl-explicit-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))POST\b)(?=.*\bdoDelete\b))curl(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-X\s*\|--request(?:=\|\s+))GET\b.*(?:jenkins\|/job/\|/api/)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `jenkins-cli-delete-job` | jenkins-cli delete-job deletes Jenkins jobs and can break pipelines. | critical |
| `jenkins-cli-delete-node` | jenkins-cli delete-node deletes Jenkins nodes and can halt CI. | high |
| `jenkins-cli-delete-credentials` | jenkins-cli delete-credentials removes stored credentials. | high |
| `jenkins-cli-delete-builds` | jenkins-cli delete-builds removes build history and artifacts. | medium |
| `jenkins-cli-delete-view` | jenkins-cli delete-view removes Jenkins views. | low |
| `jenkins-curl-do-delete` | curl POST to Jenkins doDelete endpoints deletes jobs or resources. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "cicd.jenkins:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "cicd.jenkins:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## CircleCI

**Pack ID:** `cicd.circleci`

Protects against destructive CircleCI operations like deleting contexts, removing secrets, deleting orbs/namespaces, or removing pipelines.

### Keywords

Commands containing these keywords are checked against this pack:

- `circleci`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `circleci-context-list` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+context\s+list\b` |
| `circleci-orb-list` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+orb\s+list\b` |
| `circleci-orb-info` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+orb\s+info\b` |
| `circleci-pipeline-list` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+pipeline\s+list\b` |
| `circleci-project-list` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+project\s+list\b` |
| `circleci-namespace-list` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+namespace\s+list\b` |
| `circleci-config-validate` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+config\s+validate\b` |
| `circleci-local-execute` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+local\s+execute\b` |
| `circleci-policy-status` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+policy\s+status\b` |
| `circleci-diagnostic` | `circleci(?:\s+--?\S+(?:\s+\S+)?)*\s+diagnostic\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `circleci-context-delete` | circleci context delete removes contexts and their secrets. | critical |
| `circleci-context-remove-secret` | circleci context remove-secret deletes secrets from a context. | high |
| `circleci-orb-delete` | circleci orb delete removes an orb from the registry. | high |
| `circleci-namespace-delete` | circleci namespace delete removes an orb namespace. | critical |
| `circleci-pipeline-delete` | circleci pipeline delete removes pipeline history. | medium |
| `circleci-api-delete-envvar` | curl DELETE against CircleCI envvar endpoints removes environment variables. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "cicd.circleci:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "cicd.circleci:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
