# Pack Expansion Index

Last updated: 2026-01-10

This is the master index for the pack expansion initiative. It consolidates
the hierarchy, dependency order, and resolved decisions so contributors can
quickly navigate the work.

## Complete Hierarchy

```
Master Epic (pcq)
│
├── FOUNDATION (Must complete first)
│   │
│   ├── Testing Infrastructure (e7j) [P0]
│   │   ├── Unit test template (i79) [CLOSED]
│   │   ├── E2E test framework (ly4)
│   │   ├── Logging infrastructure (jdb)
│   │   ├── Test fixtures database (l968) [CLOSED]
│   │   ├── CI/CD integration (6ozg)
│   │   ├── Performance regression testing (qxc7)
│   │   ├── Pack dev/validation tooling (hxgx)
│   │   └── E2E scenario definitions (ct5s) [CLOSED]
│   │
│   ├── Design Decisions (8u1) [P0] [CLOSED]
│   │   ├── Completion validation checklist (ltou) [CLOSED]
│   │   └── Pack task template (ikf2) [CLOSED]
│   │
│   ├── Operational Infrastructure [P1]
│   │   ├── Pack maintenance/versioning (ewbq)
│   │   ├── Production monitoring (hi1t)
│   │   ├── Coverage gap audit (me0s)
│   │   └── User experience (rm2n)
│   │
│   └── Documentation (mbq7) [P1]
│
├── Tier 1: Critical Security Gaps (6ae) [P0] - 22 pack tasks
│   ├── secrets.*: vault, aws_secrets, onepassword, doppler (4)
│   ├── cicd.*: github_actions DONE, gitlab_ci, jenkins, circleci (4)
│   ├── messaging.*: kafka, rabbitmq, nats, sqs_sns (4)
│   ├── search.*: elasticsearch, opensearch, algolia, meilisearch (4)
│   ├── backup.*: restic, borg, rclone, velero (4)
│   ├── rsync (78a) - PROMOTED from remote.*
│   └── s3 (3a1) - PROMOTED from storage.*
│
├── Tier 2: High Value (hhh) [P1] - 19 pack tasks
│   ├── platform.github (3w5) - repos, releases, deploy keys, webhooks
│   ├── platform.gitlab (z2q) - projects, releases, runners
│   ├── platform.railway - projects, services, functions, environments, volumes, variables, deployments
│   ├── dns.*: cloudflare, route53, generic (3)
│   ├── loadbalancer.*: nginx, elb, haproxy, traefik (4)
│   ├── monitoring.*: datadog, pagerduty, prometheus, newrelic (4)
│   └── payment.*: stripe, braintree, square (3)
│
└── Tier 3: Valuable (9ic) [P2] - 17 pack tasks
    ├── remote.*: ssh, scp (2) - rsync promoted out
    ├── cdn.*: cloudflare_workers, fastly, cloudfront (3)
    ├── apigateway.*: aws, kong, apigee (3)
    ├── featureflags.*: launchdarkly, split, flipt, unleash (4)
    ├── email.*: sendgrid, ses, mailgun, postmark (4)
    └── storage.*: gcs, azure_blob, minio (3) - s3 promoted out
```

## Resolved Decisions

### rsync and S3 Promotion (DECIDED in bnyn)
**Decision**: Promote both to Tier 1.
- rsync (78a): now P0, blocks Tier 1 epic directly.
- S3 (3a1): now P0, blocks Tier 1 epic directly.
- Rationale: both are top-5 developer footguns based on incident data.

### GitHub/GitLab Pack Boundaries (DECIDED in qdhh)
**Decision**: Keep packs separate but clarify boundaries.
- cicd.github_actions: secrets, variables, workflows, runs, API actions.
- platform.github: repos, releases, deploy keys, webhooks, collaborators.
- Same pattern for GitLab (cicd.gitlab_ci vs platform.gitlab).

## Work Order

1. **Foundation First** - testing infra, design decisions, dev tooling.
2. **Tier 1** - critical packs (secrets, cicd, messaging, search, backup + rsync, s3).
3. **Tier 2** - high-value packs (platform, dns, loadbalancer, monitoring, payment).
4. **Tier 3** - valuable packs (remote, cdn, apigateway, featureflags, email, storage).

## Key Reference Beads

| ID | Purpose | Status |
|----|---------|--------|
| ikf2 | Pack task template - required sections | CLOSED |
| ltou | Completion checklist - validation before merge | CLOSED |
| ct5s | E2E scenario definitions - test case examples | CLOSED |
| hxgx | Dev tooling - pattern tester, validator, debugger | OPEN |
| ewbq | Maintenance strategy - CLI version tracking | OPEN |
| bnyn | Priority decision - rsync/S3 promotion | CLOSED |
| qdhh | Scope decision - GitHub/GitLab boundaries | CLOSED |
| hcyz | Tier rationale - why strict ordering | OPEN |

## Testing Requirements Summary

Every pack MUST have:
- Unit tests (>= 90% coverage)
- E2E test file with scenarios
- Performance < 500 microseconds
- Completion checklist passed
- Documentation updated

## Commands

```bash
bd ready                              # Packs ready to implement
bd list --status=open | rg PACK       # All pack tasks
bd show <id>                          # Pack details
bd blocked                            # Blocked items
```
