# Load Balancer Packs

This document describes packs in the `loadbalancer` category.

## Packs in this Category

- [HAProxy](#loadbalancerhaproxy)
- [nginx](#loadbalancernginx)
- [Traefik](#loadbalancertraefik)
- [AWS ELB](#loadbalancerelb)

---

## HAProxy

**Pack ID:** `loadbalancer.haproxy`

Protects against destructive HAProxy load balancer operations like stopping the service or disabling backends via runtime API.

### Keywords

Commands containing these keywords are checked against this pack:

- `haproxy`
- `socat`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `haproxy-config-check` | `\bhaproxy\s+-c\b` |
| `haproxy-version` | `\bhaproxy\s+-v+\b` |
| `systemctl-status-haproxy` | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+status\s+haproxy(?:\.service)?\b` |
| `service-status-haproxy` | `service\s+haproxy\s+status\b` |
| `haproxy-socat-show` | `(?:echo\|printf)\s+['"]?show\s+(?:stat\|info\|servers\|backend\|pools\|sess\|errors\|table)['"]?\s*\\|\s*socat\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `haproxy-soft-stop` | haproxy -sf sends a soft stop signal, terminating the load balancer gracefully. | high |
| `haproxy-hard-stop` | haproxy -st sends a hard stop signal, immediately terminating the load balancer. | high |
| `haproxy-systemctl-stop` | systemctl stop haproxy stops the HAProxy service. | high |
| `haproxy-service-stop` | service haproxy stop stops the HAProxy service. | high |
| `haproxy-socat-disable-server` | Disabling a server via HAProxy runtime API removes it from the load balancer pool. | high |
| `haproxy-socat-shutdown-sessions` | Shutting down sessions via HAProxy runtime API terminates active connections. | high |
| `haproxy-socat-disable-frontend` | Disabling a frontend via HAProxy runtime API stops accepting new connections. | high |
| `haproxy-socat-shutdown-frontend` | Shutting down a frontend via HAProxy runtime API terminates it immediately. | high |
| `haproxy-config-delete` | Removing files from /etc/haproxy deletes HAProxy configuration. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "loadbalancer.haproxy:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "loadbalancer.haproxy:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## nginx

**Pack ID:** `loadbalancer.nginx`

Protects against destructive nginx load balancer operations like stopping the service or deleting config files.

### Keywords

Commands containing these keywords are checked against this pack:

- `nginx`
- `/etc/nginx`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `nginx-config-test` | `nginx\s+-t\b` |
| `nginx-config-dump` | `nginx\s+-T\b` |
| `nginx-version` | `nginx\s+-v\b` |
| `nginx-version-full` | `nginx\s+-V\b` |
| `nginx-reload` | `nginx\s+-s\s+reload\b` |
| `systemctl-status-nginx` | `systemctl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+status\s+nginx(?:\.service)?\b` |
| `service-status-nginx` | `service\s+nginx\s+status\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `nginx-stop` | nginx -s stop shuts down nginx and stops the load balancer. | high |
| `nginx-quit` | nginx -s quit gracefully stops nginx and halts traffic handling. | high |
| `systemctl-stop-nginx` | systemctl stop nginx stops the nginx service and disrupts traffic. | high |
| `service-stop-nginx` | service nginx stop stops the nginx service and disrupts traffic. | high |
| `nginx-config-delete` | Removing files from /etc/nginx deletes nginx configuration. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "loadbalancer.nginx:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "loadbalancer.nginx:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Traefik

**Pack ID:** `loadbalancer.traefik`

Protects against destructive Traefik load balancer operations like stopping containers, deleting config, or API deletions.

### Keywords

Commands containing these keywords are checked against this pack:

- `traefik`
- `ingressroute`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `traefik-version` | `\btraefik\s+version(?=\s\|$)` |
| `traefik-healthcheck` | `\btraefik\s+healthcheck(?=\s\|$)` |
| `traefik-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*\btraefik\b.*\b/api/))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\btraefik\b.*\b/api/` |
| `traefik-api-read` | `curl\b(?!.*\s(?:-X\s*\|--request(?:=\|\s+))(?:DELETE\|PUT\|POST\|PATCH)\b).*\btraefik\b.*\b/api/(?:overview\|entrypoints\|routers\|services\|middlewares\|version\|rawdata)` |
| `docker-traefik-inspect` | `docker\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:inspect\|logs)\s+.*\btraefik\b` |
| `kubectl-traefik-get` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:get\|describe)\s+.*\bingressroute` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `traefik-docker-stop` | Stopping the Traefik container halts all traffic routing. | critical |
| `traefik-docker-rm` | Removing the Traefik container destroys the load balancer. | critical |
| `traefik-compose-down` | docker-compose down on Traefik stops and removes the load balancer. | critical |
| `traefik-kubectl-delete-pod` | Deleting Traefik pods/deployments disrupts traffic routing. | critical |
| `traefik-kubectl-delete-ingressroute` | Deleting IngressRoute CRDs removes Traefik routing rules. | high |
| `traefik-config-delete` | Removing Traefik config files disrupts load balancer configuration. | critical |
| `traefik-api-delete` | DELETE operations against Traefik API can remove routing configuration. | high |
| `traefik-systemctl-stop` | systemctl stop traefik stops the Traefik service. | high |
| `traefik-service-stop` | service traefik stop stops the Traefik service. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "loadbalancer.traefik:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "loadbalancer.traefik:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## AWS ELB

**Pack ID:** `loadbalancer.elb`

Protects against destructive AWS Elastic Load Balancing (ELB/ALB/NLB) operations like deleting load balancers, target groups, or deregistering targets from live traffic.

### Keywords

Commands containing these keywords are checked against this pack:

- `elbv2`
- `delete-load-balancer`
- `delete-target-group`
- `deregister-targets`
- `delete-listener`
- `delete-rule`
- `deregister-instances-from-load-balancer`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `elbv2-describe-load-balancers` | `\baws\b(?:\s+(?:--profile\|--region\|--output\|--endpoint-url)\s+\S+\|\s+--\S+)*\s+elbv2\s+describe-load-balancers\b` |
| `elbv2-describe-target-groups` | `\baws\b(?:\s+(?:--profile\|--region\|--output\|--endpoint-url)\s+\S+\|\s+--\S+)*\s+elbv2\s+describe-target-groups\b` |
| `elbv2-describe-target-health` | `\baws\b(?:\s+(?:--profile\|--region\|--output\|--endpoint-url)\s+\S+\|\s+--\S+)*\s+elbv2\s+describe-target-health\b` |
| `elb-describe-load-balancers` | `\baws\b(?:\s+(?:--profile\|--region\|--output\|--endpoint-url)\s+\S+\|\s+--\S+)*\s+elb\s+describe-load-balancers\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `elbv2-delete-load-balancer` | aws elbv2 delete-load-balancer permanently deletes the load balancer. | high |
| `elbv2-delete-target-group` | aws elbv2 delete-target-group permanently deletes the target group. | high |
| `elbv2-deregister-targets` | aws elbv2 deregister-targets removes targets from the load balancer, impacting live traffic. | high |
| `elbv2-delete-listener` | aws elbv2 delete-listener deletes a listener, potentially breaking traffic routing. | high |
| `elbv2-delete-rule` | aws elbv2 delete-rule deletes a listener rule, potentially breaking routing. | high |
| `elb-delete-load-balancer` | aws elb delete-load-balancer permanently deletes the classic load balancer. | high |
| `elb-deregister-instances` | aws elb deregister-instances-from-load-balancer removes instances from the load balancer, impacting live traffic. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "loadbalancer.elb:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "loadbalancer.elb:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
