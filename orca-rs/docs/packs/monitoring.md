# Monitoring Packs

This document describes packs in the `monitoring` category.

## Packs in this Category

- [Splunk](#monitoringsplunk)
- [Datadog](#monitoringdatadog)
- [PagerDuty](#monitoringpagerduty)
- [New Relic](#monitoringnewrelic)
- [Prometheus/Grafana](#monitoringprometheus)

---

## Splunk

**Pack ID:** `monitoring.splunk`

Protects against destructive Splunk CLI/API operations like index removal and REST API DELETE calls

### Keywords

Commands containing these keywords are checked against this pack:

- `splunk`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `splunk-list` | `splunk\b(?:\s+--?\S+(?:\s+\S+)?)*\s+list(?=\s\|$)` |
| `splunk-show` | `splunk\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| `splunk-search` | `splunk\b(?:\s+--?\S+(?:\s+\S+)?)*\s+search(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `splunk-remove-index` | splunk remove index deletes an index and its data permanently. | critical |
| `splunk-clean-eventdata` | splunk clean eventdata permanently deletes indexed data. | critical |
| `splunk-delete-user-role` | splunk delete user/role removes access configurations. Verify before deleting. | high |
| `splunk-api-delete` | Splunk REST DELETE calls can permanently remove objects. Verify the endpoint. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "monitoring.splunk:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "monitoring.splunk:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Datadog

**Pack ID:** `monitoring.datadog`

Protects against destructive Datadog CLI/API operations like deleting monitors and dashboards.

### Keywords

Commands containing these keywords are checked against this pack:

- `datadog-ci`
- `datadoghq`
- `datadog`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `datadog-ci-monitors-list` | `datadog-ci\b(?:\s+--?\S+(?:\s+\S+)?)*\s+monitors\s+(?:get\|list)(?=\s\|$)` |
| `datadog-ci-dashboards-list` | `datadog-ci\b(?:\s+--?\S+(?:\s+\S+)?)*\s+dashboards\s+(?:get\|list)(?=\s\|$)` |
| `datadog-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*api\.datadoghq\.com.*\/(?:monitor\|dashboard\|synthetics)\/))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*api\.datadoghq\.com` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `datadog-ci-monitors-delete` | datadog-ci monitors delete removes a Datadog monitor. | high |
| `datadog-ci-dashboards-delete` | datadog-ci dashboards delete removes a Datadog dashboard. | high |
| `datadog-api-delete` | Datadog API DELETE calls remove monitors/dashboards/synthetics. | high |
| `terraform-datadog-destroy` | terraform destroy targeting Datadog resources removes monitoring infrastructure. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "monitoring.datadog:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "monitoring.datadog:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## PagerDuty

**Pack ID:** `monitoring.pagerduty`

Protects against destructive PagerDuty CLI/API operations like deleting services and schedules (which can break incident routing).

### Keywords

Commands containing these keywords are checked against this pack:

- `pd`
- `pagerduty`
- `api.pagerduty.com`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `pd-service-read` | `\bpd\b(?:\s+--?\S+(?:\s+\S+)?)*\s+service\s+(?:list\|get)\b` |
| `pd-schedule-read` | `\bpd\b(?:\s+--?\S+(?:\s+\S+)?)*\s+schedule\s+(?:list\|get)\b` |
| `pd-incident-list` | `\bpd\b(?:\s+--?\S+(?:\s+\S+)?)*\s+incident\s+list\b` |
| `pagerduty-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*api\.pagerduty\.com[^\s]*?/(?:services\|schedules)/[^\s]+))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*api\.pagerduty\.com` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `pd-service-delete` | pd service delete removes a PagerDuty service, which can break incident routing. | critical |
| `pd-schedule-delete` | pd schedule delete removes a PagerDuty schedule. | high |
| `pd-escalation-policy-delete` | pd escalation-policy delete removes a PagerDuty escalation policy. | high |
| `pd-user-delete` | pd user delete removes a PagerDuty user. | high |
| `pd-team-delete` | pd team delete removes a PagerDuty team. | high |
| `pagerduty-api-delete-service` | PagerDuty API DELETE /services/{id} deletes a PagerDuty service. | critical |
| `pagerduty-api-delete-schedule` | PagerDuty API DELETE /schedules/{id} deletes a PagerDuty schedule. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "monitoring.pagerduty:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "monitoring.pagerduty:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## New Relic

**Pack ID:** `monitoring.newrelic`

Protects against destructive New Relic CLI/API operations like deleting entities or alerting resources.

### Keywords

Commands containing these keywords are checked against this pack:

- `newrelic`
- `api.newrelic.com`
- `graphql`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `newrelic-entity-search` | `\bnewrelic\b(?:\s+--?\S+(?:\s+\S+)?)*\s+entity\s+search(?=\s\|$)` |
| `newrelic-apm-app-get` | `\bnewrelic\b(?:\s+--?\S+(?:\s+\S+)?)*\s+apm\s+application\s+get(?=\s\|$)` |
| `newrelic-query` | `\bnewrelic\b(?:\s+--?\S+(?:\s+\S+)?)*\s+query(?=\s\|$)` |
| `newrelic-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:POST\|DELETE)\b)(?=.*api\.newrelic\.com))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*api\.newrelic\.com` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `newrelic-entity-delete` | newrelic entity delete removes a New Relic entity, impacting observability. | high |
| `newrelic-apm-app-delete` | newrelic apm application delete removes an APM application. | high |
| `newrelic-workload-delete` | newrelic workload delete removes a workload definition. | high |
| `newrelic-synthetics-delete` | newrelic synthetics delete removes a synthetics monitor. | high |
| `newrelic-api-delete` | New Relic API DELETE calls remove monitoring/alerting resources. | high |
| `newrelic-graphql-delete-mutation` | New Relic GraphQL delete mutations can remove monitoring resources. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "monitoring.newrelic:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "monitoring.newrelic:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Prometheus/Grafana

**Pack ID:** `monitoring.prometheus`

Protects against destructive Prometheus/Grafana operations like deleting time series data or dashboards/datasources.

### Keywords

Commands containing these keywords are checked against this pack:

- `promtool`
- `grafana-cli`
- `/api/v1/admin/tsdb/delete_series`
- `delete_series`
- `/api/dashboards`
- `/api/datasources`
- `/api/alert-notifications`
- `/etc/prometheus`
- `rules.d`
- `prometheusrule`
- `servicemonitor`
- `podmonitor`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `promtool-check-rules` | `\bpromtool\b(?:\s+--?\S+(?:\s+\S+)?)*\s+check\s+rules\b` |
| `promtool-query` | `\bpromtool\b(?:\s+--?\S+(?:\s+\S+)?)*\s+query\b` |
| `prometheus-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:POST\|DELETE)\b)(?=.*(?:/api/v1/admin/tsdb/delete_series\b\|/api/(?:dashboards\|datasources\|alert-notifications)/)))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\/api\/v1\/` |
| `grafana-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:POST\|DELETE)\b)(?=.*(?:/api/v1/admin/tsdb/delete_series\b\|/api/(?:dashboards\|datasources\|alert-notifications)/)))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\/api\/` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `prometheus-rules-file-delete` | Deleting Prometheus rule/config files can break alerting and monitoring coverage. | critical |
| `prometheus-tsdb-delete-series` | Prometheus TSDB delete_series permanently deletes time series data. | critical |
| `kubectl-delete-prometheus-operator-resources` | kubectl delete of Prometheus Operator resources (PrometheusRule/ServiceMonitor/PodMonitor) removes alerting/target configuration. | high |
| `grafana-cli-plugins-uninstall` | grafana-cli plugins uninstall removes a Grafana plugin, potentially breaking dashboards. | high |
| `grafana-api-delete-dashboard` | Grafana API DELETE /api/dashboards/... deletes dashboards. | high |
| `grafana-api-delete-datasource` | Grafana API DELETE /api/datasources/... deletes datasources. | high |
| `grafana-api-delete-alert-notification` | Grafana API DELETE /api/alert-notifications/... deletes alert notification channels. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "monitoring.prometheus:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "monitoring.prometheus:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
