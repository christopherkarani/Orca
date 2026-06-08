# Pattern Audit Report
Generated: 2026-04-30T22:58:33.693996

## `src/packs/apigateway/apigee.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `gcloud-apigee-apis-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+apis\s+list(...` |
| safe | `gcloud-apigee-apis-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+apis\s+descr...` |
| safe | `gcloud-apigee-environments-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+environments...` |
| safe | `gcloud-apigee-environments-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+environments...` |
| safe | `gcloud-apigee-developers-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+developers\s...` |
| safe | `gcloud-apigee-developers-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+developers\s...` |
| safe | `gcloud-apigee-products-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+products\s+l...` |
| safe | `gcloud-apigee-products-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+products\s+d...` |
| safe | `gcloud-apigee-organizations-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+organization...` |
| safe | `gcloud-apigee-organizations-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+organization...` |
| safe | `gcloud-apigee-deployments-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+deployments\...` |
| safe | `gcloud-apigee-deployments-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+deployments\...` |
| safe | `apigeecli-apis-list` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+apis\s+list(?=\s\|$)` |
| safe | `apigeecli-apis-get` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+apis\s+get(?=\s\|$)` |
| safe | `apigeecli-products-list` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+products\s+list(?=\s...` |
| safe | `apigeecli-products-get` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+products\s+get(?=\s\|$)` |
| safe | `apigeecli-developers-list` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+developers\s+list(?=...` |
| safe | `apigeecli-developers-get` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+developers\s+get(?=\...` |
| safe | `apigeecli-envs-list` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+envs\s+list(?=\s\|$)` |
| safe | `apigeecli-envs-get` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+envs\s+get(?=\s\|$)` |
| safe | `apigeecli-orgs-list` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+orgs\s+list(?=\s\|$)` |
| safe | `apigeecli-orgs-get` | Found '(?=' | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+orgs\s+get(?=\s\|$)` |

## `src/packs/apigateway/aws.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `apigateway-get-rest-api` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-rest-...` |
| safe | `apigateway-get-rest-apis` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-rest-...` |
| safe | `apigateway-get-resources` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-resou...` |
| safe | `apigateway-get-resource` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-resou...` |
| safe | `apigateway-get-method` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-metho...` |
| safe | `apigateway-get-stages` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-stage...` |
| safe | `apigateway-get-stage` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-stage...` |
| safe | `apigateway-get-deployments` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-deplo...` |
| safe | `apigateway-get-deployment` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-deplo...` |
| safe | `apigateway-get-api-keys` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-api-k...` |
| safe | `apigateway-get-api-key` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-api-k...` |
| safe | `apigateway-get-authorizers` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-autho...` |
| safe | `apigateway-get-models` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-model...` |
| safe | `apigateway-get-usage-plans` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-usage...` |
| safe | `apigateway-get-domain-names` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-domai...` |
| safe | `apigatewayv2-get-apis` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-api...` |
| safe | `apigatewayv2-get-api` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-api...` |
| safe | `apigatewayv2-get-routes` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-rou...` |
| safe | `apigatewayv2-get-route` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-rou...` |
| safe | `apigatewayv2-get-integrations` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-int...` |
| safe | `apigatewayv2-get-integration` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-int...` |
| safe | `apigatewayv2-get-stages` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-sta...` |
| safe | `apigatewayv2-get-stage` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-sta...` |
| safe | `apigatewayv2-get-authorizers` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-aut...` |
| safe | `apigatewayv2-get-domain-names` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-dom...` |
| safe | `apigateway-help` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+(?:help\|...` |
| safe | `apigatewayv2-help` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+(?:help...` |

## `src/packs/apigateway/kong.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `kong-version` | Found '(?=' | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:version\|--version\|-v...` |
| safe | `kong-help` | Found '(?=' | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:help\|--help\|-h)(?=\s...` |
| safe | `kong-health` | Found '(?=' | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+health(?=\s\|$)` |
| safe | `kong-check` | Found '(?=' | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| safe | `kong-config-parse` | Found '(?=' | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+config\s+(?:parse\|init)(...` |
| safe | `deck-version` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:version\|--version)(?=...` |
| safe | `deck-help` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:help\|--help\|-h)(?=\s...` |
| safe | `deck-ping` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+ping(?=\s\|$)` |
| safe | `deck-dump` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+dump(?=\s\|$)` |
| safe | `deck-diff` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| safe | `deck-validate` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+validate(?=\s\|$)` |
| safe | `deck-convert` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+convert(?=\s\|$)` |
| safe | `deck-file` | Found '(?=' | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+file(?=\s\|$)` |
| safe | `kong-admin-explicit-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?=.*(...` |

## `src/packs/backup/borg.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `borg-list` | Found '(?=' | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+list(?=\s\|$)` |
| safe | `borg-info` | Found '(?=' | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+info(?=\s\|$)` |
| safe | `borg-diff` | Found '(?=' | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| safe | `borg-check` | Found '(?=' | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| safe | `borg-create` | Found '(?=' | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+create(?=\s\|$)` |
| safe | `borg-extract` | Found '(?=' | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+extract(?=\s\|$)` |
| safe | `borg-mount` | Found '(?=' | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+mount(?=\s\|$)` |

## `src/packs/backup/rclone.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `rclone-copy` | Found '(?=' | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+copy(?=\s\|$)` |
| safe | `rclone-ls` | Found '(?=' | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+ls(?=\s\|$)` |
| safe | `rclone-lsd` | Found '(?=' | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+lsd(?=\s\|$)` |
| safe | `rclone-lsl` | Found '(?=' | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+lsl(?=\s\|$)` |
| safe | `rclone-size` | Found '(?=' | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+size(?=\s\|$)` |
| safe | `rclone-check` | Found '(?=' | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| safe | `rclone-config` | Found '(?=' | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |

## `src/packs/backup/restic.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `restic-snapshots` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+snapshots(?=\s\|$)` |
| safe | `restic-ls` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+ls(?=\s\|$)` |
| safe | `restic-stats` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+stats(?=\s\|$)` |
| safe | `restic-check` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| safe | `restic-diff` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| safe | `restic-find` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+find(?=\s\|$)` |
| safe | `restic-backup` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+backup(?=\s\|$)` |
| safe | `restic-restore` | Found '(?=' | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+restore(?=\s\|$)` |

## `src/packs/backup/velero.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `velero-backup-get` | Found '(?=' | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+get(?=\s\|$)` |
| safe | `velero-backup-describe` | Found '(?=' | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+describe(?=\s\|$)` |
| safe | `velero-backup-logs` | Found '(?=' | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+logs(?=\s\|$)` |
| safe | `velero-backup-create` | Found '(?=' | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+create(?=\s\|$)` |
| safe | `velero-schedule-get` | Found '(?=' | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+schedule\s+get(?=\s\|$)` |
| safe | `velero-restore-create` | Found '(?=' | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+restore\s+create(?=\s\|$)` |
| safe | `velero-version` | Found '(?=' | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |

## `src/packs/cdn/cloudflare_workers.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `wrangler-whoami` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+whoami(?=\s\|$)` |
| safe | `wrangler-kv-get` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+kv:key\s+get(?=\s\|$)` |
| safe | `wrangler-kv-list` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+kv:key\s+list(?=\s\|$)` |
| safe | `wrangler-kv-namespace-list` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+kv:namespace\s+list(?...` |
| safe | `wrangler-r2-object-get` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+r2\s+object\s+get(?=\...` |
| safe | `wrangler-r2-bucket-list` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+r2\s+bucket\s+list(?=...` |
| safe | `wrangler-d1-list` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+d1\s+list(?=\s\|$)` |
| safe | `wrangler-d1-info` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+d1\s+info(?=\s\|$)` |
| safe | `wrangler-dev` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+dev(?=\s\|$)` |
| safe | `wrangler-tail` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+tail(?=\s\|$)` |
| safe | `wrangler-version` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-v\|--version\|ver...` |
| safe | `wrangler-help` | Found '(?=' | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-h\|--help\|help)(...` |

## `src/packs/cdn/fastly.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `fastly-service-list` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+service\s+list(?=\s\|$)` |
| safe | `fastly-service-describe` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+service\s+describe(?=\s...` |
| safe | `fastly-service-search` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+service\s+search(?=\s\|$)` |
| safe | `fastly-domain-list` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+domain\s+list(?=\s\|$)` |
| safe | `fastly-domain-describe` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+domain\s+describe(?=\s\|$)` |
| safe | `fastly-backend-list` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+backend\s+list(?=\s\|$)` |
| safe | `fastly-backend-describe` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+backend\s+describe(?=\s...` |
| safe | `fastly-vcl-list` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+vcl\s+list(?=\s\|$)` |
| safe | `fastly-vcl-describe` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+vcl\s+describe(?=\s\|$)` |
| safe | `fastly-version-list` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+version\s+list(?=\s\|$)` |
| safe | `fastly-whoami` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+whoami(?=\s\|$)` |
| safe | `fastly-profile` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+profile(?=\s\|$)` |
| safe | `fastly-version` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-v\|--version\|versi...` |
| safe | `fastly-help` | Found '(?=' | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-h\|--help\|help)(?=...` |

## `src/packs/cicd/github_actions.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `gh-actions-secret-list` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| safe | `gh-actions-variable-list` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| safe | `gh-actions-workflow-list` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| safe | `gh-actions-workflow-view` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| safe | `gh-actions-run-list` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| safe | `gh-actions-run-view` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| safe | `gh-actions-api-explicit-get` | Found '!' | `^(?!(?=.*(?:-X\|--method)\s+DELETE\b))gh(?:\s+--?[A-Za-z]...` |
| destructive | `gh-actions-secret-remove` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| destructive | `gh-actions-variable-remove` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| destructive | `gh-actions-workflow-disable` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| destructive | `gh-actions-run-cancel` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| destructive | `gh-actions-api-delete-secrets` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |
| destructive | `gh-actions-api-delete-variables` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:secret\|var...` |

## `src/packs/cicd/jenkins.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `jenkins-curl-explicit-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+POST\b)(?=.*\bdoDelete\b...` |
| destructive | `jenkins-curl-do-delete` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+POST\b)(?=.*\bdoDele...` |

## `src/packs/cloud/aws.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `ec2-terminate-dry-run` | Found '!' | `aws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ec2\s+terminate-instances...` |
| safe | `ec2-delete-dry-run` | Found '!' | `aws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ec2\s+delete-[^\s...` |
| safe | `s3-ls` | Found '(?=' | `aws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+ls(?=\s\|$)` |
| safe | `s3-cp` | Found '(?=' | `aws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+cp(?=\s\|$)` |
| safe | `sts-identity` | Found '(?=' | `aws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sts\s+get-caller-identit...` |

## `src/packs/cloud/azure.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `az-show` | Found '(?=' | `az\b(?:\s+--?\S+(?:\s+\S+)?)*\s+\S+\s+show(?=\s\|$)` |
| safe | `az-list` | Found '(?=' | `az\b(?:\s+--?\S+(?:\s+\S+)?)*\s+\S+\s+list(?=\s\|$)` |
| safe | `az-account` | Found '(?=' | `az\b(?:\s+--?\S+(?:\s+\S+)?)*\s+account(?=\s\|$)` |
| safe | `az-configure` | Found '(?=' | `az\b(?:\s+--?\S+(?:\s+\S+)?)*\s+configure(?=\s\|$)` |
| safe | `az-login` | Found '(?=' | `az\b(?:\s+--?\S+(?:\s+\S+)?)*\s+login(?=\s\|$)` |
| safe | `az-version` | Found '(?=' | `az\b(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |

## `src/packs/cloud/gcp.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `gcloud-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+\S+\s+\S+\s+describe(...` |
| safe | `gcloud-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+\S+\s+\S+\s+list(?=\s...` |
| safe | `gsutil-ls` | Found '(?=' | `gsutil\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ls(?=\s\|$)` |
| safe | `gsutil-cp` | Found '(?=' | `gsutil\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cp(?=\s\|$)` |
| safe | `gcloud-config` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |
| safe | `gcloud-auth` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+auth(?=\s\|$)` |
| safe | `gcloud-info` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+info(?=\s\|$)` |
| destructive | `gsutil-rb` | Found '(?=' | `gsutil\b.*?\brb(?=\s\|$)` |

## `src/packs/containers/compose.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `compose-down-no-volumes` | Found '!' | `(?:docker-compose\|docker\s+compose)\s+down(?!\s+.*(?:-v\...` |

## `src/packs/containers/docker.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `docker-ps` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ps(?=\s\|$)(?:\s+...` |
| safe | `docker-images` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+images(?=\s\|$)(?...` |
| safe | `docker-logs` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+logs(?=\s\|$)(?:\...` |
| safe | `docker-inspect` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+inspect(?=\s\|$)(...` |
| safe | `docker-build` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+build(?=\s\|$)(?:...` |
| safe | `docker-pull` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+pull(?=\s\|$)(?:\...` |
| safe | `docker-run` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+run(?=\s\|$)(?:\s...` |
| safe | `docker-exec` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+exec(?=\s\|$)(?:\...` |
| safe | `docker-stats` | Found '(?=' | `^\s*docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+stats(?=\s\|$)(?:...` |

## `src/packs/containers/podman.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `podman-ps` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ps(?=\s\|$)` |
| safe | `podman-images` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+images(?=\s\|$)` |
| safe | `podman-logs` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+logs(?=\s\|$)` |
| safe | `podman-inspect` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+inspect(?=\s\|$)` |
| safe | `podman-build` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+build(?=\s\|$)` |
| safe | `podman-pull` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+pull(?=\s\|$)` |
| safe | `podman-run` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+run(?=\s\|$)` |
| safe | `podman-exec` | Found '(?=' | `podman\b(?:\s+--?\S+(?:\s+\S+)?)*\s+exec(?=\s\|$)` |

## `src/packs/core/filesystem.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `rm-rf-tmp` | Found '!' | `^rm\s+-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*\s+(?:/tmp/(?!\.\....` |
| safe | `rm-fr-tmp` | Found '!' | `^rm\s+-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*\s+(?:/tmp/(?!\.\....` |
| safe | `rm-rf-var-tmp` | Found '!' | `^rm\s+-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*\s+(?:/var/tmp/(?!...` |
| safe | `rm-fr-var-tmp` | Found '!' | `^rm\s+-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*\s+(?:/var/tmp/(?!...` |
| safe | `rm-rf-tmpdir` | Found '!' | `^rm\s+-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*\s+(?:\$TMPDIR/(?!...` |
| safe | `rm-fr-tmpdir` | Found '!' | `^rm\s+-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*\s+(?:\$TMPDIR/(?!...` |
| safe | `rm-rf-tmpdir-brace` | Found '!' | `^rm\s+-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*\s+(?:\$\{TMPDIR\}...` |
| safe | `rm-fr-tmpdir-brace` | Found '!' | `^rm\s+-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*\s+(?:\$\{TMPDIR\}...` |
| safe | `rm-rf-tmpdir-quoted` | Found '!' | `^rm\s+-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*\s+(?:"\$TMPDIR/(?...` |
| safe | `rm-fr-tmpdir-quoted` | Found '!' | `^rm\s+-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*\s+(?:"\$TMPDIR/(?...` |
| safe | `rm-rf-tmpdir-brace-quoted` | Found '!' | `^rm\s+-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*\s+(?:"\$\{TMPDIR\...` |
| safe | `rm-fr-tmpdir-brace-quoted` | Found '!' | `^rm\s+-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*\s+(?:"\$\{TMPDIR\...` |
| safe | `rm-r-f-tmp` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-[rR]\s+(-[a-zA-Z]+\s+)*-f\s+(?:/tm...` |
| safe | `rm-f-r-tmp` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-f\s+(-[a-zA-Z]+\s+)*-[rR]\s+(?:/tm...` |
| safe | `rm-r-f-var-tmp` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-[rR]\s+(-[a-zA-Z]+\s+)*-f\s+(?:/va...` |
| safe | `rm-f-r-var-tmp` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-f\s+(-[a-zA-Z]+\s+)*-[rR]\s+(?:/va...` |
| safe | `rm-r-f-tmpdir` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-[rR]\s+(-[a-zA-Z]+\s+)*-f\s+(?:\$T...` |
| safe | `rm-f-r-tmpdir` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-f\s+(-[a-zA-Z]+\s+)*-[rR]\s+(?:\$T...` |
| safe | `rm-r-f-tmpdir-brace` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-[rR]\s+(-[a-zA-Z]+\s+)*-f\s+(?:\$\...` |
| safe | `rm-f-r-tmpdir-brace` | Found '!' | `^rm\s+(-[a-zA-Z]+\s+)*-f\s+(-[a-zA-Z]+\s+)*-[rR]\s+(?:\$\...` |
| safe | `rm-recursive-force-tmp` | Found '!' | `^rm\s+.*--recursive.*--force\s+(?:/tmp/(?!\.\.(?:/\|\s\|$...` |
| safe | `rm-force-recursive-tmp` | Found '!' | `^rm\s+.*--force.*--recursive\s+(?:/tmp/(?!\.\.(?:/\|\s\|$...` |
| safe | `rm-recursive-force-var-tmp` | Found '!' | `^rm\s+.*--recursive.*--force\s+(?:/var/tmp/(?!\.\.(?:/\|\...` |
| safe | `rm-force-recursive-var-tmp` | Found '!' | `^rm\s+.*--force.*--recursive\s+(?:/var/tmp/(?!\.\.(?:/\|\...` |
| safe | `rm-recursive-force-tmpdir` | Found '!' | `^rm\s+.*--recursive.*--force\s+(?:\$TMPDIR/(?!\.\.(?:/\|\...` |
| safe | `rm-force-recursive-tmpdir` | Found '!' | `^rm\s+.*--force.*--recursive\s+(?:\$TMPDIR/(?!\.\.(?:/\|\...` |
| safe | `rm-recursive-force-tmpdir-brace` | Found '!' | `^rm\s+.*--recursive.*--force\s+(?:\$\{TMPDIR\}/(?!\.\.(?:...` |
| safe | `rm-force-recursive-tmpdir-brace` | Found '!' | `^rm\s+.*--force.*--recursive\s+(?:\$\{TMPDIR\}/(?!\.\.(?:...` |
| safe | `find-delete-tmp` | Found '!' | `^find\s+/tmp(?:/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(?:/\|\s\...` |
| safe | `find-delete-var-tmp` | Found '!' | `^find\s+/var/tmp(?:/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(?:/\...` |
| safe | `find-delete-tmpdir` | Found '!' | `^find\s+\$TMPDIR(?:/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(?:/\...` |
| safe | `find-delete-tmpdir-brace` | Found '!' | `^find\s+\$\{TMPDIR\}(?:/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(...` |
| safe | `unlink-tmp` | Found '!' | `^unlink\s+/tmp/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(?:/\|\s\|...` |
| safe | `unlink-var-tmp` | Found '!' | `^unlink\s+/var/tmp/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(?:/\|...` |
| safe | `unlink-tmpdir` | Found '!' | `^unlink\s+\$TMPDIR/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(?:/\|...` |
| safe | `unlink-tmpdir-brace` | Found '!' | `^unlink\s+\$\{TMPDIR\}/(?!\.\.(?:/\|\s\|$)\|[^\s]*/\.\.(?...` |
| safe | `truncate-tmp` | Found '!' | `^truncate\s+(?:-s\s+\S+\|--size=\S+)\s+/tmp/(?!\.\.(?:/\|...` |
| safe | `truncate-var-tmp` | Found '!' | `^truncate\s+(?:-s\s+\S+\|--size=\S+)\s+/var/tmp/(?!\.\.(?...` |
| safe | `truncate-tmpdir` | Found '!' | `^truncate\s+(?:-s\s+\S+\|--size=\S+)\s+\$TMPDIR/(?!\.\.(?...` |
| safe | `truncate-tmpdir-brace` | Found '!' | `^truncate\s+(?:-s\s+\S+\|--size=\S+)\s+\$\{TMPDIR\}/(?!\....` |
| safe | `shred-tmp` | Found '!' | `^shred(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\...` |
| safe | `shred-var-tmp` | Found '!' | `^shred(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\...` |
| safe | `shred-tmpdir` | Found '!' | `^shred(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\...` |
| safe | `shred-tmpdir-brace` | Found '!' | `^shred(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\...` |
| safe | `tar-remove-files-tmp` | Found '(?=' | `^tar(?=\s+[^\|;&]*--remove-files\b)(?:\s+(?:-[a-zA-Z][a-z...` |
| safe | `tar-remove-files-var-tmp` | Found '(?=' | `^tar(?=\s+[^\|;&]*--remove-files\b)(?:\s+(?:-[a-zA-Z][a-z...` |
| safe | `tar-remove-files-tmpdir` | Found '(?=' | `^tar(?=\s+[^\|;&]*--remove-files\b)(?:\s+(?:-[a-zA-Z][a-z...` |
| safe | `tar-remove-files-tmpdir-brace` | Found '(?=' | `^tar(?=\s+[^\|;&]*--remove-files\b)(?:\s+(?:-[a-zA-Z][a-z...` |
| safe | `dd-tmp` | Found '(?=' | `^dd(?=\s+[^\|;&]*\bof=)(?:\s+(?:[a-zA-Z]+=\S+\|--?[a-zA-Z...` |
| safe | `dd-var-tmp` | Found '(?=' | `^dd(?=\s+[^\|;&]*\bof=)(?:\s+(?:[a-zA-Z]+=\S+\|--?[a-zA-Z...` |
| safe | `dd-tmpdir` | Found '(?=' | `^dd(?=\s+[^\|;&]*\bof=)(?:\s+(?:[a-zA-Z]+=\S+\|--?[a-zA-Z...` |
| safe | `dd-tmpdir-brace` | Found '(?=' | `^dd(?=\s+[^\|;&]*\bof=)(?:\s+(?:[a-zA-Z]+=\S+\|--?[a-zA-Z...` |
| safe | `mv-tmp` | Found '!' | `^mv(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\s\|...` |
| safe | `mv-var-tmp` | Found '!' | `^mv(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\s\|...` |
| safe | `mv-tmpdir` | Found '!' | `^mv(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\s\|...` |
| safe | `mv-tmpdir-brace` | Found '!' | `^mv(?:\s+(?:-[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^/~$\-\s][^\s\|...` |
| destructive | `cp-sensitive-then-delete` | Found '(?=' | `\bcp\b[^\|;&]*(?:\s(?:-[A-Za-z]*a[A-Za-z]*\|--archive)\b)...` |
| destructive | `ln-symlink-sensitive-then-delete` | Found '(?=' | `\bln\b[^\|;&]*\s-[A-Za-z]*s[A-Za-z]*[^\|;&]*?(?:\s\|=)(?:...` |
| destructive | `rsync-sensitive-then-delete` | Found '(?=' | `\brsync\b[^\|;&]*(?:\s(?:-[A-Za-z]*a[A-Za-z]*\|--archive)...` |
| destructive | `find-delete-root-home",
            // End anchor `(?:\s|$|[;&|)\n])` accepts shell separators,
            // newlines, and a subshell-close `)` after `-delete` so
            // `(find /etc -delete)` and `find /etc -delete | tee log`
            // both fire. Without `)` in the set, subshell forms
            // silently bypass.
            r#"\bfind\b[^|;&]*?(?:\s|=)['"\\]?(?:/(?:etc|usr|bin|sbin|root|boot|lib|lib64|var|home|sys|proc|dev|opt)(?:/|(?=\s|$|['"]))|/(?=\s|$|['"])|~(?=\s|$|/)|\$\{?HOME\b)[^|;&]*?\s-delete(?:\s|$|[;&|)\n])"#,
            "find <sensitive-path> -delete is bytewise-equivalent to rm -rf on root/home and is EXTREMELY DANGEROUS. This command will NOT be executed.",
            Critical,
            "`find <path> -delete` is the bytewise-equivalent of `rm -rf <path>`: \
             it recursively removes every file and (when -depth is implied) every \
             directory matched by the predicate. Targeting `/`, `~`, `$HOME`, or any \
             top-level system directory (`/etc`, `/usr`, `/var`, `/home`, `/boot`, \
             `/dev`, `/proc`, `/sys`, `/lib`, `/lib64`, `/opt`, `/root`) destroys \
             the operating system or user data the same way `rm -rf` would.\n\n\
             There is NO recovery without backups.\n\n\
             If you only need to delete files matching a pattern, use a much more \
             specific path:\n  \
             find /path/to/specific/subdir -name '*.tmp' -delete\n\n\
             Always preview first:\n  \
             find /path -type f | head -20",
            FIND_DELETE_SUGGESTIONS
        ),
        // ----- `find ... -delete` (High: any other target) -----
        //
        // The general rule fires after the safe-pattern whitelist (which
        // allows `find /tmp/...`, `/var/tmp/...`, `$TMPDIR/...`, and
        // `${TMPDIR}/...`). Any other `find ... -delete` is an
        // unscoped destructive operation that should require human
        // approval, exactly like the parallel `rm-rf-general` rule.
        destructive_pattern!(
            "find-delete-general",
            // `\bfind\b` (not `^\s*find\b`) so the rule fires in compound
            // forms (`echo foo; find . -delete`, `(find . -delete)`) and
            // on path-prefixed binaries. `-delete(?:\s|$|[;&|)\n])` (not
            // `\b`) so `-delete-this-not-a-flag` — where `\b` happily
            // allows the following `-` — does NOT false-positive, while
            // shell separators and subshell-close are still accepted.
            r"\bfind\b[^|;&]*\s-delete(?:\s|$|[;&|)\n])",
            "find ... -delete is destructive (bytewise-equivalent to rm -rf on the matched tree) and requires human approval.",
            High,
            "`find ... -delete` recursively deletes every path matched by the find \
             expression. The action flag `-delete` implies `-depth` (so directories \
             are deleted after their contents). With no path predicate it deletes \
             the entire starting tree. Common pitfalls:\n\n\
             - `find . -delete` deletes the current working directory's contents.\n\
             - `find <path> -delete` with a wide -name glob matches more than expected.\n\
             - `-delete` errors are silent by default — failures don't stop the walk.\n\n\
             Safer alternatives:\n\
             - Drop -delete to preview: `find <path> ...` (just lists matches)\n\
             - Add -print -delete to log each deletion as it happens\n\
             - Use `find /tmp/<subdir> ... -delete` (allowed under temp dirs)\n\
             - For a few files: `find ... | xargs -t -p rm -i` for confirmation",
            FIND_DELETE_SUGGESTIONS
        ),
        // ----- `unlink <file>` (Critical: root/home/system target) -----
        //
        // `unlink <file>` is the raw POSIX unlink(2) primitive — semantic
        // equivalent of `rm <file>` (single file, no recursion). On a
        // sensitive target (`/etc/passwd`, `~/.ssh/id_*`, `$HOME/...`) it
        // is one-shot data destruction with no recovery and no recursion
        // budget to slow it down.
        //
        // The regex matches `unlink` at any word boundary (so it fires in
        // compound forms and after `sudo`/`env` wrappers, and on
        // path-prefixed binaries via PATH_NORMALIZER), then a sensitive
        // path token. Single argument only — multi-arg unlink isn't
        // standard.
        destructive_pattern!(
            "unlink-root-home` | Found '(?=' | `\bunlink\s+['"\\]?(?:/(?:etc\|usr\|bin\|sbin\|root\|boot\...` |
| destructive | `truncate-zero-root-home` | Found '(?=' | `\btruncate\b[^\|;&]*?(?:\s-s\s+(?:0\b\|-\d+)\|\s--size=(?...` |
| destructive | `shred-root-home` | Found '(?=' | `\bshred\b[^\|;&]*?\s+['"\\]?(?:/(?:etc\|usr\|bin\|sbin\|r...` |
| destructive | `tar-remove-files-root-home` | Found '(?=' | `\btar\b[^\|;&]*?\s--remove-files\b[^\|;&]*?(?:\s\|=)['"\\...` |
| destructive | `dd-overwrite-root-home` | Found '!' | `\bdd\b[^\|;&]*?\bof=['"\\]?(?!/dev/)(?:/(?:etc\|usr\|bin\...` |
| destructive | `dd-overwrite-general` | Found '!' | `\bdd\b[^\|;&]*?\bof=['"\\]?(?!/dev/)\S` |
| destructive | `mv-sensitive-source-root-home` | Found '(?=' | `\bmv\b[^\|;&]*?(?:\s\|=)(?:['"\\]\|\$['"])?(?:/(?:etc\|us...` |
| destructive | `redirect-truncate-root-home` | Found '(?<!' | `(?<![<>])(?:[12]?>\\|?\|&>)\s*(?:['"\\]\|\$['"])?(?!/dev/...` |

## `src/packs/core/git.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `restore-staged-long` | Found '!' | `(?:^\|[^[:alnum:]_-])git\s+(?:\S+\s+)*restore\s+--staged\...` |
| safe | `restore-staged-short` | Found '!' | `(?:^\|[^[:alnum:]_-])git\s+(?:\S+\s+)*restore\s+-S\s+(?!....` |
| destructive | `checkout-ref-discard` | Found '!' | `(?:^\|[^[:alnum:]_-])git\s+(?:\S+\s+)*checkout\s+(?!-b\b)...` |
| destructive | `restore-worktree` | Found '!' | `(?:^\|[^[:alnum:]_-])git\s+(?:\S+\s+)*restore\s+(?!--stag...` |
| destructive | `push-force-long` | Found '!' | `(?:^\|[^[:alnum:]_-])git\s+(?:\S+\s+)*push\s+(?:\S+\s+)*-...` |

## `src/packs/database/mongodb.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `mongo-find` | Found '!' | `^(?!.*(?:dropDatabase\|dropCollection\|\.drop\s*\(\|\.(?:...` |
| safe | `mongo-count` | Found '!' | `^(?!.*(?:dropDatabase\|dropCollection\|\.drop\s*\(\|\.(?:...` |
| safe | `mongo-aggregate` | Found '!' | `^(?!.*(?:dropDatabase\|dropCollection\|\.drop\s*\(\|\.(?:...` |
| safe | `mongodump-no-drop` | Found '!' | `mongodump\s+(?!.*--drop)` |
| safe | `mongo-explain` | Found '!' | `^(?!.*(?:dropDatabase\|dropCollection\|\.drop\s*\(\|\.(?:...` |

## `src/packs/database/mysql.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `mysqldump-no-drop` | Found '!' | `mysqldump\s+(?!.*--add-drop-database)(?!.*--add-drop-table)` |

## `src/packs/database/postgresql.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `pg-dump-no-clean` | Found '!' | `pg_dump\s+(?!.*--clean)(?!.*-c\b)` |

## `src/packs/database/redis.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `redis-get` | Found '!' | `(?i)^(?!.*\b(?:FLUSHALL\|FLUSHDB\|DEBUG\|SHUTDOWN\|CONFIG...` |
| safe | `redis-scan` | Found '!' | `(?i)^(?!.*\b(?:FLUSHALL\|FLUSHDB\|DEBUG\|SHUTDOWN\|CONFIG...` |
| safe | `redis-info` | Found '!' | `(?i)^(?!.*\b(?:FLUSHALL\|FLUSHDB\|DEBUG\|SHUTDOWN\|CONFIG...` |
| safe | `redis-keys` | Found '!' | `(?i)^(?!.*\b(?:FLUSHALL\|FLUSHDB\|DEBUG\|SHUTDOWN\|CONFIG...` |
| safe | `redis-dbsize` | Found '!' | `(?i)^(?!.*\b(?:FLUSHALL\|FLUSHDB\|DEBUG\|SHUTDOWN\|CONFIG...` |
| safe | `redis-config-get` | Found '!' | `(?i)^(?!.*\b(?:FLUSHALL\|FLUSHDB\|DEBUG\|SHUTDOWN\|CONFIG...` |

## `src/packs/dns/cloudflare.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `cloudflare-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s*DELETE\b)(?=.*\bapi\.clo...` |
| destructive | `cloudflare-api-delete-dns-record` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s*DELETE\b)(?=.*\bapi\...` |
| destructive | `cloudflare-api-delete-zone` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s*DELETE\b)(?=.*\bapi\...` |

## `src/packs/dns/generic.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `dns-dig-safe` | Found '!' | `\bdig\b(?!.*(?i:\b(?:axfr\|ixfr)\b))` |

## `src/packs/email/ses.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `ses-list-identities` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+list-identities(...` |
| safe | `ses-list-templates` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+list-templates(?...` |
| safe | `ses-get-template` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-template(?=\...` |
| safe | `ses-get-send-quota` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-send-quota(?...` |
| safe | `sesv2-get-account` | Found '(?=' | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+get-account(?=...` |

## `src/packs/featureflags/flipt.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `flipt-flag-list` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+flag\s+list(?=\s\|$)` |
| safe | `flipt-flag-get` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+flag\s+get(?=\s\|$)` |
| safe | `flipt-flag-create` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+flag\s+create(?=\s\|$)` |
| safe | `flipt-flag-update` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+flag\s+update(?=\s\|$)` |
| safe | `flipt-segment-list` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+segment\s+list(?=\s\|$)` |
| safe | `flipt-segment-get` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+segment\s+get(?=\s\|$)` |
| safe | `flipt-segment-create` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+segment\s+create(?=\s\|$)` |
| safe | `flipt-namespace-list` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+namespace\s+list(?=\s\|$)` |
| safe | `flipt-namespace-get` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+namespace\s+get(?=\s\|$)` |
| safe | `flipt-namespace-create` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+namespace\s+create(?=\s\|$)` |
| safe | `flipt-rule-list` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+rule\s+list(?=\s\|$)` |
| safe | `flipt-rule-get` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+rule\s+get(?=\s\|$)` |
| safe | `flipt-rule-create` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+rule\s+create(?=\s\|$)` |
| safe | `flipt-evaluate` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+evaluate(?=\s\|$)` |
| safe | `flipt-help` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--help\|-h\|help)(?=\...` |
| safe | `flipt-version` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--version\|version)(?...` |
| safe | `flipt-server` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:server\|serve)(?=\s\|$)` |
| safe | `flipt-config` | Found '(?=' | `flipt(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |

## `src/packs/featureflags/launchdarkly.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `ldcli-flags-list` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+flags\s+list(?=\s\|$)` |
| safe | `ldcli-flags-get` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+flags\s+get(?=\s\|$)` |
| safe | `ldcli-flags-create` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+flags\s+create(?=\s\|$)` |
| safe | `ldcli-flags-update` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+flags\s+update(?=\s\|$)` |
| safe | `ldcli-projects-list` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+projects\s+list(?=\s\|$)` |
| safe | `ldcli-projects-get` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+projects\s+get(?=\s\|$)` |
| safe | `ldcli-projects-create` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+projects\s+create(?=\s\|$)` |
| safe | `ldcli-environments-list` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+environments\s+list(?=\s...` |
| safe | `ldcli-environments-get` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+environments\s+get(?=\s\|$)` |
| safe | `ldcli-environments-create` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+environments\s+create(?=...` |
| safe | `ldcli-segments-list` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+segments\s+list(?=\s\|$)` |
| safe | `ldcli-segments-get` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+segments\s+get(?=\s\|$)` |
| safe | `ldcli-segments-create` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+segments\s+create(?=\s\|$)` |
| safe | `ldcli-metrics-list` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+metrics\s+list(?=\s\|$)` |
| safe | `ldcli-metrics-get` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+metrics\s+get(?=\s\|$)` |
| safe | `ldcli-help` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--help\|-h\|help)(?=\...` |
| safe | `ldcli-version` | Found '(?=' | `ldcli(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--version\|version)(?...` |
| safe | `launchdarkly-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?=.*a...` |
| destructive | `launchdarkly-api-delete-environments` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `launchdarkly-api-delete-flags` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `launchdarkly-api-delete-segments` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `launchdarkly-api-delete-projects` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `launchdarkly-api-delete-generic` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |

## `src/packs/featureflags/split.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `split-splits-list` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+splits\s+list(?=\s\|$)` |
| safe | `split-splits-get` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+splits\s+get(?=\s\|$)` |
| safe | `split-splits-create` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+splits\s+create(?=\s\|$)` |
| safe | `split-splits-update` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+splits\s+update(?=\s\|$)` |
| safe | `split-environments-list` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+environments\s+list(?=\s...` |
| safe | `split-environments-get` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+environments\s+get(?=\s\|$)` |
| safe | `split-environments-create` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+environments\s+create(?=...` |
| safe | `split-segments-list` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+segments\s+list(?=\s\|$)` |
| safe | `split-segments-get` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+segments\s+get(?=\s\|$)` |
| safe | `split-segments-create` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+segments\s+create(?=\s\|$)` |
| safe | `split-traffic-types-list` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+traffic-types\s+list(?=\...` |
| safe | `split-traffic-types-get` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+traffic-types\s+get(?=\s...` |
| safe | `split-workspaces-list` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+workspaces\s+list(?=\s\|$)` |
| safe | `split-workspaces-get` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+workspaces\s+get(?=\s\|$)` |
| safe | `split-help` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--help\|-h\|help)(?=\...` |
| safe | `split-version` | Found '(?=' | `split(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--version\|version)(?...` |
| safe | `split-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?=.*a...` |
| destructive | `split-api-delete-splits` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `split-api-delete-environments` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `split-api-delete-segments` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `split-api-delete-generic` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |

## `src/packs/featureflags/unleash.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `unleash-features-list` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+features?\s+list(?=\s\|$)` |
| safe | `unleash-features-get` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+features?\s+get(?=\s\|$)` |
| safe | `unleash-features-create` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+features?\s+create(?=\...` |
| safe | `unleash-features-update` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+features?\s+update(?=\...` |
| safe | `unleash-features-enable` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+features?\s+enable(?=\...` |
| safe | `unleash-projects-list` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+projects?\s+list(?=\s\|$)` |
| safe | `unleash-projects-get` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+projects?\s+get(?=\s\|$)` |
| safe | `unleash-projects-create` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+projects?\s+create(?=\...` |
| safe | `unleash-environments-list` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+environments?\s+list(?...` |
| safe | `unleash-environments-get` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+environments?\s+get(?=...` |
| safe | `unleash-strategies-list` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+strategies?\s+list(?=\...` |
| safe | `unleash-strategies-get` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+strategies?\s+get(?=\s...` |
| safe | `unleash-help` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--help\|-h\|help)(?...` |
| safe | `unleash-version` | Found '(?=' | `unleash(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--version\|version)...` |
| safe | `unleash-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?=.*/...` |
| destructive | `unleash-api-delete-features` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `unleash-api-delete-projects` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |
| destructive | `unleash-api-delete-generic` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\s+DELETE\|--request\s+DELETE)\b)(?...` |

## `src/packs/infrastructure/ansible.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| destructive | `playbook-all-hosts` | Found '!' | `ansible-playbook\s+(?!.*(?:--check(?:\s\|$)\|--limit)).*-i...` |

## `src/packs/infrastructure/pulumi.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `pulumi-preview` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+preview(?=\s\|$)` |
| safe | `pulumi-stack-ls` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+stack\s+ls(?=\s\|$)` |
| safe | `pulumi-stack-select` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+stack\s+select(?=\s\|$)` |
| safe | `pulumi-stack-init` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+stack\s+init(?=\s\|$)` |
| safe | `pulumi-config` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |
| safe | `pulumi-whoami` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+whoami(?=\s\|$)` |
| safe | `pulumi-version` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |
| safe | `pulumi-about` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+about(?=\s\|$)` |
| safe | `pulumi-logs` | Found '(?=' | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+logs(?=\s\|$)` |
| destructive | `destroy` | Found '(?=' | `pulumi\b.*?\bdestroy(?=\s\|$)` |

## `src/packs/infrastructure/terraform.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `terraform-plan` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+plan(?=\s\|$)(?!\s...` |
| safe | `terraform-init` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+init(?=\s\|$)` |
| safe | `terraform-validate` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+validate(?=\s\|$)` |
| safe | `terraform-fmt` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+fmt(?=\s\|$)` |
| safe | `terraform-show` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| safe | `terraform-output` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+output(?=\s\|$)` |
| safe | `terraform-state-list` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+state\s+list(?=\s\|$)` |
| safe | `terraform-state-show` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+state\s+show(?=\s\|$)` |
| safe | `terraform-graph` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+graph(?=\s\|$)` |
| safe | `terraform-version` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |
| safe | `terraform-providers` | Found '(?=' | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+providers(?=\s\|$)` |
| destructive | `destroy` | Found '(?=' | `terraform\b.*?\bdestroy(?=\s\|$)` |

## `src/packs/kubernetes/helm.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `helm-list` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+list(?=\s\|$)` |
| safe | `helm-status` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+status(?=\s\|$)` |
| safe | `helm-history` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+history(?=\s\|$)` |
| safe | `helm-show` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| safe | `helm-inspect` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+inspect(?=\s\|$)` |
| safe | `helm-get` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+get(?=\s\|$)` |
| safe | `helm-search` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+search(?=\s\|$)` |
| safe | `helm-repo` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+repo(?=\s\|$)` |
| safe | `helm-template` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+template(?=\s\|$)` |
| safe | `helm-lint` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+lint(?=\s\|$)` |
| safe | `helm-diff` | Found '(?=' | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| destructive | `uninstall` | Found '!' | `helm\b.*?\b(?:uninstall\|delete)\b(?!.*--dry-run(?:...` |
| destructive | `rollback` | Found '!' | `helm\b.*?\brollback\b(?!.*--dry-run(?:=(?:true\|client...` |

## `src/packs/kubernetes/kubectl.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `kubectl-get` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+get(?=\s\|$)` |
| safe | `kubectl-describe` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+describe(?=\s\|$)` |
| safe | `kubectl-logs` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+logs(?=\s\|$)` |
| safe | `kubectl-diff` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| safe | `kubectl-explain` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+explain(?=\s\|$)` |
| safe | `kubectl-top` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+top(?=\s\|$)` |
| safe | `kubectl-config` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |
| safe | `kubectl-api` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+api-(?:resources\|ve...` |
| safe | `kubectl-version` | Found '(?=' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |
| destructive | `delete-workload` | Found '!' | `kubectl\b.*?\bdelete\s+(?:deployment\|statefulset\|daemon...` |
| destructive | `delete-pvc` | Found '!' | `kubectl\b.*?\bdelete\s+(?:pvc\|persistentvolumeclaim)\b(?...` |
| destructive | `delete-pv` | Found '!' | `kubectl\b.*?\bdelete\s+(?:pv\|persistentvolume)\b(?!.*--d...` |

## `src/packs/kubernetes/kustomize.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `kustomize-build` | Found '!' | `kustomize\b(?:\s+--?\S+(?:\s+\S+)?)*\s+build\b(?!.*\\|)` |
| safe | `kubectl-kustomize` | Found '!' | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+kustomize\b(?!.*\\|)` |
| destructive | `kustomize-delete` | Found '!' | `kustomize\b.*?\bbuild\s+.*\\|\s*kubectl\b(?!.*--dry...` |
| destructive | `kubectl-kustomize-delete` | Found '!' | `kubectl\b.*?\bkustomize\s+.*\\|\s*kubectl\b(?!.*--...` |
| destructive | `kubectl-delete-k` | Found '!' | `kubectl\b.*?\bdelete\s+-k\b(?!.*--dry-run)` |

## `src/packs/loadbalancer/traefik.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `traefik-version` | Found '(?=' | `\btraefik\s+version(?=\s\|$)` |
| safe | `traefik-healthcheck` | Found '(?=' | `\btraefik\s+healthcheck(?=\s\|$)` |
| safe | `traefik-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s*DELETE\b)(?=.*\btraefik\...` |
| safe | `traefik-api-read` | Found '!' | `curl\b(?!.*\s(?:-X\|--request)\s*(?:DELETE\|PUT\|POST\|PA...` |
| destructive | `traefik-api-delete` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s*DELETE\b)(?=.*\btrae...` |

## `src/packs/messaging/kafka.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `kafka-topics-list` | Found '!' | `kafka-topics(?:\.sh)?\b(?!.*\s--delete\b).*\s--list\b` |
| safe | `kafka-topics-describe` | Found '!' | `kafka-topics(?:\.sh)?\b(?!.*\s--delete\b).*\s--describe\b` |
| safe | `kafka-consumer-groups-list` | Found '!' | `kafka-consumer-groups(?:\.sh)?\b(?!.*\s(?:--delete\|--reset-offsets...` |
| safe | `kafka-consumer-groups-describe` | Found '!' | `kafka-consumer-groups(?:\.sh)?\b(?!.*\s(?:--delete\|--reset-offsets...` |
| safe | `kafka-acls-list` | Found '!' | `kafka-acls(?:\.sh)?\b(?!.*\s--remove\b).*\s--list\b` |
| safe | `kafka-configs-describe` | Found '!' | `kafka-configs(?:\.sh)?\b(?!.*\s--delete-config\b).*\s--describe\b` |

## `src/packs/messaging/nats.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `nats-stream-info` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+stream\s+info(?=\s\|$)` |
| safe | `nats-stream-ls` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+stream\s+ls(?=\s\|$)` |
| safe | `nats-consumer-info` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+consumer\s+info(?=\s\|$)` |
| safe | `nats-consumer-ls` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+consumer\s+ls(?=\s\|$)` |
| safe | `nats-kv-get` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+kv\s+get(?=\s\|$)` |
| safe | `nats-kv-ls` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+kv\s+ls(?=\s\|$)` |
| safe | `nats-pub` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+pub(?=\s\|$)` |
| safe | `nats-sub` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+sub(?=\s\|$)` |
| safe | `nats-server-info` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+server\s+info(?=\s\|$)` |
| safe | `nats-bench` | Found '(?=' | `nats(?:\s+--?\S+(?:\s+\S+)?)*\s+bench(?=\s\|$)` |

## `src/packs/mod.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `bt_safe_1` | Found '(?=' | `(?=.*safe_target)rm\s+--dry-run` |
| safe | `bt_safe_2` | Found '(?=' | `(?=.*other_target)rm\s+--interactive` |
| safe | `bt_safe_1` | Found '(?=' | `(?=.*safe_target)rm\s+--dry-run` |
| safe | `bt_safe_1` | Found '(?=' | `(?=.*safe_target)rm\s+--dry-run` |

## `src/packs/monitoring/datadog.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `datadog-ci-monitors-list` | Found '(?=' | `datadog-ci\b(?:\s+--?\S+(?:\s+\S+)?)*\s+monitors\s+(?:get...` |
| safe | `datadog-ci-dashboards-list` | Found '(?=' | `datadog-ci\b(?:\s+--?\S+(?:\s+\S+)?)*\s+dashboards\s+(?:g...` |
| safe | `datadog-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.datad...` |
| destructive | `datadog-api-delete` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.d...` |

## `src/packs/monitoring/newrelic.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `newrelic-entity-search` | Found '(?=' | `\bnewrelic\b(?:\s+--?\S+(?:\s+\S+)?)*\s+entity\s+search(?...` |
| safe | `newrelic-apm-app-get` | Found '(?=' | `\bnewrelic\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apm\s+application...` |
| safe | `newrelic-query` | Found '(?=' | `\bnewrelic\b(?:\s+--?\S+(?:\s+\S+)?)*\s+query(?=\s\|$)` |
| safe | `newrelic-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+(?:POST\|DELETE)\b)(?=.*...` |
| destructive | `newrelic-api-delete` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.n...` |
| destructive | `newrelic-graphql-delete-mutation` | Found '(?=' | `(?i)\bcurl\b(?=.*api\.newrelic\.com[^\s]*?/graphql\b)(?=....` |

## `src/packs/monitoring/pagerduty.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `pagerduty-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.pager...` |
| destructive | `pagerduty-api-delete-service` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.p...` |
| destructive | `pagerduty-api-delete-schedule` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.p...` |

## `src/packs/monitoring/prometheus.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `prometheus-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+(?:POST\|DELETE)\b)(?=.*...` |
| safe | `grafana-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+(?:POST\|DELETE)\b)(?=.*...` |
| destructive | `prometheus-tsdb-delete-series` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+POST\b)(?=.*\/api\/v...` |
| destructive | `grafana-api-delete-dashboard` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*\/api\...` |
| destructive | `grafana-api-delete-datasource` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*\/api\...` |
| destructive | `grafana-api-delete-alert-notification` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*\/api\...` |

## `src/packs/monitoring/splunk.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `splunk-list` | Found '(?=' | `splunk\b(?:\s+--?\S+(?:\s+\S+)?)*\s+list(?=\s\|$)` |
| safe | `splunk-show` | Found '(?=' | `splunk\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| safe | `splunk-search` | Found '(?=' | `splunk\b(?:\s+--?\S+(?:\s+\S+)?)*\s+search(?=\s\|$)` |

## `src/packs/package_managers/mod.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `npm-install` | Found '(?=' | `\bnpm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:install\|i\|ci)(?=\s\|$)` |
| safe | `yarn-add` | Found '(?=' | `\byarn\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:add\|install)(?=\s\|$)` |
| safe | `pnpm-install` | Found '(?=' | `\bpnpm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:add\|install\|i)(?...` |
| safe | `npm-list` | Found '(?=' | `\bnpm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:list\|ls\|info\|view...` |
| safe | `yarn-list` | Found '(?=' | `\byarn\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:list\|info\|why)(?...` |
| safe | `npm-audit` | Found '(?=' | `\bnpm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+audit(?=\s\|$)` |
| safe | `yarn-audit` | Found '(?=' | `\byarn\b(?:\s+--?\S+(?:\s+\S+)?)*\s+audit(?=\s\|$)` |
| safe | `pip-list` | Found '(?=' | `\bpip\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:list\|show\|freeze)(...` |
| safe | `poetry-show` | Found '(?=' | `\bpoetry\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| safe | `poetry-env-list` | Found '(?=' | `\bpoetry\b(?:\s+--?\S+(?:\s+\S+)?)*\s+env\s+list(?=\s\|$)` |
| safe | `apt-list` | Found '(?=' | `\bapt\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:list\|show\|search)(...` |
| safe | `apt-get-list` | Found '!' | `\bapt-get\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:update\|upgrade)(...` |
| destructive | `npm-publish` | Found '!' | `\bnpm\b.*?\bpublish\b(?!.*--dry-run(?:=true)?(?:\s\|$))` |
| destructive | `yarn-publish` | Found '!' | `\byarn\b.*?\bpublish\b(?!.*--dry-run(?:=true)?(?:\s\|$))` |
| destructive | `pnpm-publish` | Found '!' | `\bpnpm\b.*?\bpublish\b(?!.*--dry-run(?:=true)?(?:\s\|$))` |
| destructive | `npm-unpublish` | Found '(?=' | `\bnpm\b.*?\bunpublish(?=\s\|$)` |
| destructive | `pip-uninstall` | Found '(?=' | `\bpip(?:3)?\b.*?\buninstall(?=\s\|$)` |
| destructive | `apt-remove` | Found '(?=' | `\bapt(?:-get)?\b.*?\b(?:remove\|purge\|autoremove)(?=\s\|$)` |
| destructive | `yum-remove` | Found '(?=' | `\b(?:yum\|dnf)\b.*?\b(?:remove\|erase\|autoremove)(?=\s\|$)` |
| destructive | `cargo-publish` | Found '!' | `\bcargo\b.*?\bpublish\b(?!.*--dry-run(?:=true)?(?:\s\|$))` |
| destructive | `cargo-yank` | Found '(?=' | `\bcargo\b.*?\byank(?=\s\|$)` |
| destructive | `brew-uninstall` | Found '(?=' | `\bbrew\b.*?\b(?:uninstall\|remove)(?=\s\|$)` |
| destructive | `poetry-publish` | Found '!' | `\bpoetry\b.*?\bpublish\b(?!.*--dry-run(?:=true)?(?:\s\|$))` |
| destructive | `poetry-remove` | Found '(?=' | `\bpoetry\b.*?\bremove(?=\s\|$)` |

## `src/packs/payment/braintree.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `braintree-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*braintreeg...` |
| destructive | `braintree-api-delete` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*braint...` |

## `src/packs/payment/square.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `square-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*...` |

## `src/packs/payment/stripe.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `stripe-api-get` | Found '!' | `(?i)^(?!(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.strip...` |
| destructive | `stripe-api-delete` | Found '(?=' | `(?i)\bcurl\b(?=.*(?:-X\|--request)\s+DELETE\b)(?=.*api\.s...` |

## `src/packs/platform/github.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `gh-repo-list-view` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-gist-list-view` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-release-list-view` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-issue-list-view` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-ssh-key-list` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-secret-list` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-variable-list` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-auth-status` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-status` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| safe | `gh-api-explicit-get` | Found '!' | `^(?!(?=.*(?:-X\|--method)\s+DELETE\b))gh(?:\s+--?[A-Za-z]...` |
| destructive | `gh-repo-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-repo-archive` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-gist-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-release-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-issue-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-ssh-key-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-secret-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-variable-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-repo-deploy-key-delete` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-run-cancel` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-api-delete-actions-secret` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-api-delete-actions-variable` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-api-delete-hook` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-api-delete-deploy-key` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-api-delete-release` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |
| destructive | `gh-api-delete-repo` | Found '!' | `gh(?:\s+--?[A-Za-z][A-Za-z0-9-]*\b(?:\s+(?!(?:repo\|gist\...` |

## `src/packs/remote/scp.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `scp-to-home` | Found '!' | `scp\b.*\s(?:(?:\S+@)?\S+:)?~/(?!\S*\.\./)\S+\s*$` |
| safe | `scp-to-tmp` | Found '!' | `scp\b.*\s(?:(?:\S+@)?\S+:)?/tmp/(?!\S*\.\./)\S*\s*$` |
| safe | `scp-to-var-tmp` | Found '!' | `scp\b.*\s(?:(?:\S+@)?\S+:)?/var/tmp(?:/(?!\S*\.\./)\S*)?\s*$` |

## `src/packs/search/elasticsearch.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `es-curl-get-search` | Found '!' | `(?i)^(?!(?=.*-X\s*(?:DELETE\|POST\|PUT)\b)(?=.*(?:elastic...` |
| safe | `es-curl-get-cat` | Found '!' | `(?i)^(?!(?=.*-X\s*(?:DELETE\|POST\|PUT)\b)(?=.*(?:elastic...` |
| safe | `es-curl-get-cluster-health` | Found '!' | `(?i)^(?!(?=.*-X\s*(?:DELETE\|POST\|PUT)\b)(?=.*(?:elastic...` |
| destructive | `es-curl-delete-doc` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |
| destructive | `es-curl-delete-by-query` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*POST\b)(?=.*\b(?:https?://)?[^\s'\"...` |
| destructive | `es-curl-close-index` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*POST\b)(?=.*\b(?:https?://)?[^\s'\"...` |
| destructive | `es-curl-delete-index` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |
| destructive | `es-curl-cluster-settings` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*PUT\b)(?=.*\b(?:https?://)?[^\s'\"]...` |

## `src/packs/search/meilisearch.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `meili-curl-get-stats` | Found '!' | `(?i)^(?!(?=.*-X\s*DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=....` |
| safe | `meili-curl-get-health` | Found '!' | `(?i)^(?!(?=.*-X\s*DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=....` |
| safe | `meili-curl-get-version` | Found '!' | `(?i)^(?!(?=.*-X\s*DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=....` |
| safe | `meili-curl-search` | Found '!' | `(?i)^(?!(?=.*-X\s*DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=....` |
| destructive | `meili-curl-delete-document` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |
| destructive | `meili-curl-delete-documents` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |
| destructive | `meili-curl-delete-batch` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*POST\b)(?=.*\b(?:https?://)?[^\s'\"...` |
| destructive | `meili-curl-delete-key` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |
| destructive | `meili-curl-delete-index` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |

## `src/packs/search/opensearch.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `os-curl-get-search` | Found '!' | `(?i)^(?!(?=.*-X\s*(?:DELETE\|POST)\b)(?=.*(?:opensearch\|...` |
| safe | `os-curl-get-cat` | Found '!' | `(?i)^(?!(?=.*-X\s*(?:DELETE\|POST)\b)(?=.*(?:opensearch\|...` |
| safe | `os-curl-get-cluster-health` | Found '!' | `(?i)^(?!(?=.*-X\s*(?:DELETE\|POST)\b)(?=.*(?:opensearch\|...` |
| destructive | `os-curl-delete-doc` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |
| destructive | `os-curl-delete-by-query` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*POST\b)(?=.*\b(?:https?://)?[^\s'\"...` |
| destructive | `os-curl-close-index` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*POST\b)(?=.*\b(?:https?://)?[^\s'\"...` |
| destructive | `os-curl-delete-index` | Found '(?=' | `(?i)\bcurl\b(?=.*-X\s*DELETE\b)(?=.*\b(?:https?://)?[^\s'...` |

## `src/packs/secrets/aws_secrets.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `aws-secretsmanager-list` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+secretsmanager\s+list-secr...` |
| safe | `aws-secretsmanager-describe` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+secretsmanager\s+describe-...` |
| safe | `aws-secretsmanager-get` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+secretsmanager\s+get-secre...` |
| safe | `aws-secretsmanager-list-versions` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+secretsmanager\s+list-secr...` |
| safe | `aws-secretsmanager-get-resource-policy` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+secretsmanager\s+get-resou...` |
| safe | `aws-secretsmanager-get-random-password` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+secretsmanager\s+get-rando...` |
| safe | `aws-ssm-get-parameter` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+ssm\s+get-parameter(?=\s\|$)` |
| safe | `aws-ssm-get-parameters` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+ssm\s+get-parameters(?=\s\|$)` |
| safe | `aws-ssm-describe-parameters` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+ssm\s+describe-parameters(...` |

## `src/packs/secrets/doppler.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `doppler-secrets-get` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+secrets\s+get(?=\s\|$)` |
| safe | `doppler-secrets-list` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+secrets\s+list(?=\s\|$)` |
| safe | `doppler-run` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+run(?=\s\|$)` |
| safe | `doppler-configure` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+configure(?=\s\|$)` |
| safe | `doppler-setup` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+setup(?=\s\|$)` |
| safe | `doppler-projects-list` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+projects\s+list(?=\s\|$)` |
| safe | `doppler-environments-list` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+environments\s+list(?=...` |
| safe | `doppler-configs-list` | Found '(?=' | `doppler(?:\s+--?\S+(?:\s+\S+)?)*\s+configs\s+list(?=\s\|$)` |

## `src/packs/secrets/onepassword.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `op-whoami` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+whoami(?=\s\|$)` |
| safe | `op-account-get` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+account\s+get(?=\s\|$)` |
| safe | `op-read` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+read(?=\s\|$)` |
| safe | `op-item-get` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+item\s+get(?=\s\|$)` |
| safe | `op-item-list` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+item\s+list(?=\s\|$)` |
| safe | `op-document-get` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+document\s+get(?=\s\|$)` |
| safe | `op-vault-list` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+vault\s+list(?=\s\|$)` |
| safe | `op-vault-get` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+vault\s+get(?=\s\|$)` |
| safe | `op-user-list` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+user\s+list(?=\s\|$)` |
| safe | `op-group-list` | Found '(?=' | `op(?:\s+--?\S+(?:\s+\S+)?)*\s+group\s+list(?=\s\|$)` |

## `src/packs/secrets/vault.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `vault-status` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+status(?=\s\|$)` |
| safe | `vault-version` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |
| safe | `vault-read` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+read(?=\s\|$)` |
| safe | `vault-kv-get` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+kv\s+get(?=\s\|$)` |
| safe | `vault-kv-list` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+kv\s+list(?=\s\|$)` |
| safe | `vault-secrets-list` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+secrets\s+list(?=\s\|$)` |
| safe | `vault-policy-list` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+policy\s+list(?=\s\|$)` |
| safe | `vault-token-lookup` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+token\s+lookup(?=\s\|$)` |
| safe | `vault-auth-list` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+auth\s+list(?=\s\|$)` |
| safe | `vault-audit-list` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+audit\s+list(?=\s\|$)` |
| safe | `vault-lease-lookup` | Found '(?=' | `vault(?:\s+--?\S+(?:\s+\S+)?)*\s+lease\s+lookup(?=\s\|$)` |

## `src/packs/storage/azure_blob.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `az-storage-container-list` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+container\s+l...` |
| safe | `az-storage-container-show` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+container\s+s...` |
| safe | `az-storage-container-exists` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+container\s+e...` |
| safe | `az-storage-blob-list` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+list(?...` |
| safe | `az-storage-blob-show` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+show(?...` |
| safe | `az-storage-blob-exists` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+exists...` |
| safe | `az-storage-blob-download` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+downlo...` |
| safe | `az-storage-blob-download-batch` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+downlo...` |
| safe | `az-storage-blob-url` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+url(?=...` |
| safe | `az-storage-blob-metadata-show` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+metada...` |
| safe | `az-storage-account-list` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+account\s+lis...` |
| safe | `az-storage-account-show` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+account\s+sho...` |
| safe | `az-storage-account-keys-list` | Found '(?=' | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+account\s+key...` |
| safe | `azcopy-list` | Found '(?=' | `\bazcopy\s+(?:--\S+\s+)*list(?=\s\|$)` |
| safe | `azcopy-copy` | Found '(?=' | `\bazcopy\s+(?:--\S+\s+)*copy(?=\s\|$)` |
| safe | `azcopy-jobs-list` | Found '(?=' | `\bazcopy\s+(?:--\S+\s+)*jobs\s+list(?=\s\|$)` |
| safe | `azcopy-jobs-show` | Found '(?=' | `\bazcopy\s+(?:--\S+\s+)*jobs\s+show(?=\s\|$)` |
| safe | `azcopy-login` | Found '(?=' | `\bazcopy\s+(?:--\S+\s+)*login(?=\s\|$)` |
| safe | `azcopy-env` | Found '(?=' | `\bazcopy\s+(?:--\S+\s+)*env(?=\s\|$)` |

## `src/packs/storage/gcs.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `gsutil-ls` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*ls(?=\s\|$)` |
| safe | `gsutil-cat` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*cat(?=\s\|$)` |
| safe | `gsutil-stat` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*stat(?=\s\|$)` |
| safe | `gsutil-du` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*du(?=\s\|$)` |
| safe | `gsutil-hash` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*hash(?=\s\|$)` |
| safe | `gsutil-version` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*version(?=\s\|$)` |
| safe | `gsutil-help` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*help(?=\s\|$)` |
| safe | `gsutil-cp` | Found '(?=' | `gsutil\s+(?:-[a-zA-Z]+\s+)*cp(?=\s\|$)` |
| safe | `gcloud-storage-buckets-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:...` |
| safe | `gcloud-storage-buckets-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:...` |
| safe | `gcloud-storage-objects-list` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:...` |
| safe | `gcloud-storage-objects-describe` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:...` |
| safe | `gcloud-storage-ls` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:...` |
| safe | `gcloud-storage-cat` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:...` |
| safe | `gcloud-storage-cp` | Found '(?=' | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:...` |
| destructive | `gsutil-rb` | Found '(?=' | `gsutil\b.*?\brb(?=\s\|$)` |
| destructive | `gsutil-rm` | Found '(?=' | `gsutil\b.*?\brm(?=\s\|$)` |

## `src/packs/storage/minio.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `mc-ls` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*ls(?=\s\|$)` |
| safe | `mc-cat` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*cat(?=\s\|$)` |
| safe | `mc-head` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*head(?=\s\|$)` |
| safe | `mc-stat` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*stat(?=\s\|$)` |
| safe | `mc-cp` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*cp(?=\s\|$)` |
| safe | `mc-diff` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*diff(?=\s\|$)` |
| safe | `mc-find` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*find(?=\s\|$)` |
| safe | `mc-du` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*du(?=\s\|$)` |
| safe | `mc-version` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*version(?=\s\|$)` |
| safe | `mc-admin-info` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*admin\s+info(?=\s\|$)` |
| safe | `mc-admin-user-list` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*admin\s+user\s+list(?=\s\|$)` |
| safe | `mc-admin-policy-list` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*admin\s+policy\s+list(?=\s\|$)` |
| safe | `mc-alias-list` | Found '(?=' | `\bmc\s+(?:--?\S+\s+)*alias\s+list(?=\s\|$)` |

## `src/packs/storage/s3.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `s3-list` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+ls(?=\s\|$)` |
| safe | `s3-copy` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+cp(?=\s\|$)` |
| safe | `s3-presign` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+presign(?=\s\|$)` |
| safe | `s3-mb` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+mb(?=\s\|$)` |
| safe | `s3-rm-dryrun` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+rm(?=\s\|$)[^\n;&\|]*...` |
| safe | `s3-sync-delete-dryrun` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+sync(?=\s\|$)[^\n;&\|...` |
| safe | `s3-sync-dryrun-delete` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+sync(?=\s\|$)[^\n;&\|...` |
| safe | `s3api-list-objects` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3api\s+list-objects(?:-v2...` |
| safe | `s3api-get-object` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3api\s+get-object(?=\s\|$)` |
| safe | `s3api-head-object` | Found '(?=' | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3api\s+head-object(?=\s\|$)` |

## `src/packs/system/disk.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `btrfs-subvolume-list` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+subvolume\s+list(?=\s\|$)` |
| safe | `btrfs-subvolume-show` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+subvolume\s+show(?=\s\|$)` |
| safe | `btrfs-filesystem-show` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+filesystem\s+show(?=\s...` |
| safe | `btrfs-filesystem-df` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+filesystem\s+df(?=\s\|$)` |
| safe | `btrfs-filesystem-usage` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+filesystem\s+usage(?=\...` |
| safe | `btrfs-device-stats` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+device\s+stats(?=\s\|$)` |
| safe | `btrfs-property-get` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+property\s+(?:get\|lis...` |
| safe | `btrfs-scrub-status` | Found '(?=' | `btrfs\b(?:\s+--?\S+(?:\s+\S+)?)*\s+scrub\s+status(?=\s\|$)` |
| safe | `dmsetup-ls` | Found '(?=' | `dmsetup\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ls(?=\s\|$)` |
| safe | `dmsetup-status` | Found '(?=' | `dmsetup\b(?:\s+--?\S+(?:\s+\S+)?)*\s+status(?=\s\|$)` |
| safe | `dmsetup-info` | Found '(?=' | `dmsetup\b(?:\s+--?\S+(?:\s+\S+)?)*\s+info(?=\s\|$)` |
| safe | `dmsetup-table` | Found '(?=' | `dmsetup\b(?:\s+--?\S+(?:\s+\S+)?)*\s+table(?=\s\|$)` |
| safe | `dmsetup-deps` | Found '(?=' | `dmsetup\b(?:\s+--?\S+(?:\s+\S+)?)*\s+deps(?=\s\|$)` |
| destructive | `fdisk-edit` | Found '!' | `fdisk\s+['"]?/dev/(?!.*-l)` |
| destructive | `parted-modify` | Found '!' | `parted\b[^\n;&\|]*?['"]?/dev/\S+['"]?(?:\s+--)?\s...` |

## `src/packs/system/permissions.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `chmod-non-recursive` | Found '!' | `chmod\s+(?!-[rR])(?:\d{3,4}\|[ugoa][+-][rwxXst]+)\s+[^/]` |

## `src/packs/system/services.rs`

| Kind | Name | Reason | Regex Preview |
|------|------|--------|---------------|
| safe | `systemctl-status` | Found '(?=' | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+status(?=\s\|$)` |
| safe | `service-status` | Found '(?=' | `service\s+\S+\s+status(?=\s\|$)` |
| safe | `systemctl-list` | Found '(?=' | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+list-(?:units\|uni...` |
| safe | `systemctl-show` | Found '(?=' | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| safe | `systemctl-is` | Found '(?=' | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+is-(?:active\|enab...` |
| safe | `systemctl-reload` | Found '(?=' | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+daemon-reload(?=\s...` |
| safe | `systemctl-cat` | Found '(?=' | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cat(?=\s\|$)` |
