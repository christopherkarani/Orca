# API Gateway Packs

This document describes packs in the `apigateway` category.

## Packs in this Category

- [AWS API Gateway](#apigatewayaws)
- [Kong API Gateway](#apigatewaykong)
- [Google Apigee](#apigatewayapigee)

---

## AWS API Gateway

**Pack ID:** `apigateway.aws`

Protects against destructive AWS API Gateway CLI operations for both REST APIs and HTTP APIs.

### Keywords

Commands containing these keywords are checked against this pack:

- `aws`
- `apigateway`
- `apigatewayv2`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `apigateway-get-rest-api` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-rest-api(?=\s\|$)` |
| `apigateway-get-rest-apis` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-rest-apis(?=\s\|$)` |
| `apigateway-get-resources` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-resources(?=\s\|$)` |
| `apigateway-get-resource` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-resource(?=\s\|$)` |
| `apigateway-get-method` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-method(?=\s\|$)` |
| `apigateway-get-stages` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-stages(?=\s\|$)` |
| `apigateway-get-stage` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-stage(?=\s\|$)` |
| `apigateway-get-deployments` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-deployments(?=\s\|$)` |
| `apigateway-get-deployment` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-deployment(?=\s\|$)` |
| `apigateway-get-api-keys` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-api-keys(?=\s\|$)` |
| `apigateway-get-api-key` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-api-key(?=\s\|$)` |
| `apigateway-get-authorizers` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-authorizers(?=\s\|$)` |
| `apigateway-get-models` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-models(?=\s\|$)` |
| `apigateway-get-usage-plans` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-usage-plans(?=\s\|$)` |
| `apigateway-get-domain-names` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+get-domain-names(?=\s\|$)` |
| `apigatewayv2-get-apis` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-apis(?=\s\|$)` |
| `apigatewayv2-get-api` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-api(?=\s\|$)` |
| `apigatewayv2-get-routes` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-routes(?=\s\|$)` |
| `apigatewayv2-get-route` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-route(?=\s\|$)` |
| `apigatewayv2-get-integrations` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-integrations(?=\s\|$)` |
| `apigatewayv2-get-integration` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-integration(?=\s\|$)` |
| `apigatewayv2-get-stages` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-stages(?=\s\|$)` |
| `apigatewayv2-get-stage` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-stage(?=\s\|$)` |
| `apigatewayv2-get-authorizers` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-authorizers(?=\s\|$)` |
| `apigatewayv2-get-domain-names` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+get-domain-names(?=\s\|$)` |
| `apigateway-help` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigateway\s+(?:help\|\-\-help)(?=\s\|$)` |
| `apigatewayv2-help` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigatewayv2\s+(?:help\|\-\-help)(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `apigateway-delete-rest-api` | aws apigateway delete-rest-api permanently removes a REST API and all its resources. | critical |
| `apigateway-delete-resource` | aws apigateway delete-resource removes an API resource and its methods. | high |
| `apigateway-delete-method` | aws apigateway delete-method removes an HTTP method from a resource. | medium |
| `apigateway-delete-stage` | aws apigateway delete-stage removes a deployment stage from an API. | high |
| `apigateway-delete-deployment` | aws apigateway delete-deployment removes a deployment from an API. | medium |
| `apigateway-delete-api-key` | aws apigateway delete-api-key removes an API key. | high |
| `apigateway-delete-authorizer` | aws apigateway delete-authorizer removes an authorizer from an API. | high |
| `apigateway-delete-model` | aws apigateway delete-model removes a model from an API. | medium |
| `apigateway-delete-domain-name` | aws apigateway delete-domain-name removes a custom domain name. | high |
| `apigateway-delete-usage-plan` | aws apigateway delete-usage-plan removes a usage plan. | high |
| `apigatewayv2-delete-api` | aws apigatewayv2 delete-api permanently removes an HTTP API. | critical |
| `apigatewayv2-delete-route` | aws apigatewayv2 delete-route removes a route from an HTTP API. | high |
| `apigatewayv2-delete-integration` | aws apigatewayv2 delete-integration removes an integration from an HTTP API. | high |
| `apigatewayv2-delete-stage` | aws apigatewayv2 delete-stage removes a stage from an HTTP API. | high |
| `apigatewayv2-delete-authorizer` | aws apigatewayv2 delete-authorizer removes an authorizer from an HTTP API. | high |
| `apigatewayv2-delete-domain-name` | aws apigatewayv2 delete-domain-name removes a custom domain name from an HTTP API. | high |
| `apigatewayv2-delete-route-response` | aws apigatewayv2 delete-route-response removes a route response from an HTTP API. | medium |
| `apigatewayv2-delete-integration-response` | aws apigatewayv2 delete-integration-response removes an integration response. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "apigateway.aws:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "apigateway.aws:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Kong API Gateway

**Pack ID:** `apigateway.kong`

Protects against destructive Kong Gateway CLI, deck CLI, and Admin API operations.

### Keywords

Commands containing these keywords are checked against this pack:

- `kong`
- `deck`
- `8001`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `kong-version` | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:version\|--version\|-v)(?=\s\|$)` |
| `kong-help` | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:help\|--help\|-h)(?=\s\|$)` |
| `kong-health` | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+health(?=\s\|$)` |
| `kong-check` | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| `kong-config-parse` | `kong(?:\s+--?\S+(?:\s+\S+)?)*\s+config\s+(?:parse\|init)(?=\s\|$)` |
| `deck-version` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:version\|--version)(?=\s\|$)` |
| `deck-help` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:help\|--help\|-h)(?=\s\|$)` |
| `deck-ping` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+ping(?=\s\|$)` |
| `deck-dump` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+dump(?=\s\|$)` |
| `deck-diff` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| `deck-validate` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+validate(?=\s\|$)` |
| `deck-convert` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+convert(?=\s\|$)` |
| `deck-file` | `deck(?:\s+--?\S+(?:\s+\S+)?)*\s+file(?=\s\|$)` |
| `kong-admin-explicit-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*(?:localhost\|127\.0\.0\.1):8001/))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*(?:localhost\|127\.0\.0\.1):8001/` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `deck-reset` | deck reset removes ALL Kong configuration. This is extremely dangerous and irreversible. | critical |
| `deck-sync-destructive` | deck sync with --select-tag can remove entities not matching the tag. | high |
| `kong-admin-delete-services` | DELETE request to Kong Admin API removes services. | high |
| `kong-admin-delete-routes` | DELETE request to Kong Admin API removes routes. | high |
| `kong-admin-delete-plugins` | DELETE request to Kong Admin API removes plugins. | medium |
| `kong-admin-delete-consumers` | DELETE request to Kong Admin API removes consumers. | high |
| `kong-admin-delete-upstreams` | DELETE request to Kong Admin API removes upstreams. | high |
| `kong-admin-delete-targets` | DELETE request to Kong Admin API removes targets. | medium |
| `kong-admin-delete-certificates` | DELETE request to Kong Admin API removes certificates. | high |
| `kong-admin-delete-snis` | DELETE request to Kong Admin API removes SNIs. | high |
| `kong-admin-delete-generic` | DELETE request to Kong Admin API can remove configuration. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "apigateway.kong:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "apigateway.kong:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Google Apigee

**Pack ID:** `apigateway.apigee`

Protects against destructive Google Apigee CLI and apigeecli operations.

### Keywords

Commands containing these keywords are checked against this pack:

- `apigee`
- `apigeecli`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `gcloud-apigee-apis-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+apis\s+list(?=\s\|$)` |
| `gcloud-apigee-apis-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+apis\s+describe(?=\s\|$)` |
| `gcloud-apigee-environments-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+environments\s+list(?=\s\|$)` |
| `gcloud-apigee-environments-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+environments\s+describe(?=\s\|$)` |
| `gcloud-apigee-developers-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+developers\s+list(?=\s\|$)` |
| `gcloud-apigee-developers-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+developers\s+describe(?=\s\|$)` |
| `gcloud-apigee-products-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+products\s+list(?=\s\|$)` |
| `gcloud-apigee-products-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+products\s+describe(?=\s\|$)` |
| `gcloud-apigee-organizations-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+organizations\s+list(?=\s\|$)` |
| `gcloud-apigee-organizations-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+organizations\s+describe(?=\s\|$)` |
| `gcloud-apigee-deployments-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+deployments\s+list(?=\s\|$)` |
| `gcloud-apigee-deployments-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+deployments\s+describe(?=\s\|$)` |
| `apigeecli-apis-list` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+apis\s+list(?=\s\|$)` |
| `apigeecli-apis-get` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+apis\s+get(?=\s\|$)` |
| `apigeecli-products-list` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+products\s+list(?=\s\|$)` |
| `apigeecli-products-get` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+products\s+get(?=\s\|$)` |
| `apigeecli-developers-list` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+developers\s+list(?=\s\|$)` |
| `apigeecli-developers-get` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+developers\s+get(?=\s\|$)` |
| `apigeecli-envs-list` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+envs\s+list(?=\s\|$)` |
| `apigeecli-envs-get` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+envs\s+get(?=\s\|$)` |
| `apigeecli-orgs-list` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+orgs\s+list(?=\s\|$)` |
| `apigeecli-orgs-get` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+orgs\s+get(?=\s\|$)` |
| `gcloud-apigee-help` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apigee\s+(?:--help\|-h\|help)\b` |
| `apigeecli-help` | `apigeecli(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:--help\|-h\|help\|version)\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `gcloud-apigee-apis-delete` | gcloud apigee apis delete removes an API proxy from Apigee. | high |
| `gcloud-apigee-environments-delete` | gcloud apigee environments delete removes an Apigee environment. | critical |
| `gcloud-apigee-developers-delete` | gcloud apigee developers delete removes a developer from Apigee. | high |
| `gcloud-apigee-products-delete` | gcloud apigee products delete removes an API product from Apigee. | high |
| `gcloud-apigee-organizations-delete` | gcloud apigee organizations delete removes an entire Apigee organization. | critical |
| `gcloud-apigee-deployments-undeploy` | gcloud apigee deployments undeploy removes an API deployment. | medium |
| `apigeecli-apis-delete` | apigeecli apis delete removes an API proxy from Apigee. | high |
| `apigeecli-products-delete` | apigeecli products delete removes an API product from Apigee. | high |
| `apigeecli-developers-delete` | apigeecli developers delete removes a developer from Apigee. | high |
| `apigeecli-envs-delete` | apigeecli envs delete removes an Apigee environment. | critical |
| `apigeecli-orgs-delete` | apigeecli orgs delete removes an entire Apigee organization. | critical |
| `apigeecli-apps-delete` | apigeecli apps delete removes a developer app from Apigee. | high |
| `apigeecli-keyvaluemaps-delete` | apigeecli keyvaluemaps delete removes a key-value map from Apigee. | high |
| `apigeecli-targetservers-delete` | apigeecli targetservers delete removes a target server from Apigee. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "apigateway.apigee:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "apigateway.apigee:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
