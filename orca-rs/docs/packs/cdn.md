# CDN Packs

This document describes packs in the `cdn` category.

## Packs in this Category

- [Cloudflare Workers](#cdncloudflare_workers)
- [Fastly CDN](#cdnfastly)
- [AWS CloudFront](#cdncloudfront)

---

## Cloudflare Workers

**Pack ID:** `cdn.cloudflare_workers`

Protects against destructive Cloudflare Workers, KV, R2, and D1 operations via the Wrangler CLI.

### Keywords

Commands containing these keywords are checked against this pack:

- `wrangler`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `wrangler-whoami` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+whoami(?=\s\|$)` |
| `wrangler-kv-get` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+kv:key\s+get(?=\s\|$)` |
| `wrangler-kv-list` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+kv:key\s+list(?=\s\|$)` |
| `wrangler-kv-namespace-list` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+kv:namespace\s+list(?=\s\|$)` |
| `wrangler-r2-object-get` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+r2\s+object\s+get(?=\s\|$)` |
| `wrangler-r2-bucket-list` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+r2\s+bucket\s+list(?=\s\|$)` |
| `wrangler-d1-list` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+d1\s+list(?=\s\|$)` |
| `wrangler-d1-info` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+d1\s+info(?=\s\|$)` |
| `wrangler-dev` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+dev(?=\s\|$)` |
| `wrangler-tail` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+tail(?=\s\|$)` |
| `wrangler-version` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-v\|--version\|version)(?=\s\|$)` |
| `wrangler-help` | `wrangler(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-h\|--help\|help)(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `wrangler-delete` | wrangler delete removes a Worker from Cloudflare. | critical |
| `wrangler-deployments-rollback` | wrangler deployments rollback reverts to a previous Worker version. | high |
| `wrangler-kv-key-delete` | wrangler kv:key delete removes a key from KV storage. | medium |
| `wrangler-kv-namespace-delete` | wrangler kv:namespace delete removes an entire KV namespace. | critical |
| `wrangler-kv-bulk-delete` | wrangler kv:bulk delete removes multiple keys from KV storage. | high |
| `wrangler-r2-object-delete` | wrangler r2 object delete removes an object from R2 storage. | medium |
| `wrangler-r2-bucket-delete` | wrangler r2 bucket delete removes an entire R2 bucket. | critical |
| `wrangler-d1-delete` | wrangler d1 delete removes a D1 database. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "cdn.cloudflare_workers:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "cdn.cloudflare_workers:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Fastly CDN

**Pack ID:** `cdn.fastly`

Protects against destructive Fastly CLI operations like service, domain, backend, and VCL deletion.

### Keywords

Commands containing these keywords are checked against this pack:

- `fastly`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `fastly-service-list` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+service\s+list(?=\s\|$)` |
| `fastly-service-describe` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+service\s+describe(?=\s\|$)` |
| `fastly-service-search` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+service\s+search(?=\s\|$)` |
| `fastly-domain-list` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+domain\s+list(?=\s\|$)` |
| `fastly-domain-describe` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+domain\s+describe(?=\s\|$)` |
| `fastly-backend-list` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+backend\s+list(?=\s\|$)` |
| `fastly-backend-describe` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+backend\s+describe(?=\s\|$)` |
| `fastly-vcl-list` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+vcl\s+list(?=\s\|$)` |
| `fastly-vcl-describe` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+vcl\s+describe(?=\s\|$)` |
| `fastly-version-list` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+version\s+list(?=\s\|$)` |
| `fastly-whoami` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+whoami(?=\s\|$)` |
| `fastly-profile` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+profile(?=\s\|$)` |
| `fastly-version` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-v\|--version\|version)(?=\s\|$)` |
| `fastly-help` | `fastly(?:\s+--?\S+(?:\s+\S+)?)*\s+(?:-h\|--help\|help)(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `fastly-service-delete` | fastly service delete removes a Fastly service entirely. | critical |
| `fastly-domain-delete` | fastly domain delete removes a domain from a service. | high |
| `fastly-backend-delete` | fastly backend delete removes a backend origin server. | high |
| `fastly-vcl-delete` | fastly vcl delete removes VCL configuration. | high |
| `fastly-dictionary-delete` | fastly dictionary delete removes an edge dictionary. | high |
| `fastly-dictionary-item-delete` | fastly dictionary-item delete removes dictionary entries. | medium |
| `fastly-acl-delete` | fastly acl delete removes an access control list. | high |
| `fastly-acl-entry-delete` | fastly acl-entry delete removes ACL entries. | medium |
| `fastly-logging-delete` | fastly logging delete removes logging endpoints. | high |
| `fastly-version-activate` | fastly service version activate can cause service disruption if misconfigured. | high |
| `fastly-compute-delete` | fastly compute delete removes compute package. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "cdn.fastly:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "cdn.fastly:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## AWS CloudFront

**Pack ID:** `cdn.cloudfront`

Protects against destructive AWS CloudFront operations like deleting distributions, cache policies, and functions.

### Keywords

Commands containing these keywords are checked against this pack:

- `cloudfront`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `cloudfront-list-distributions` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+list-distributions\b` |
| `cloudfront-list-cache-policies` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+list-cache-policies\b` |
| `cloudfront-list-origin-request-policies` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+list-origin-request-policies\b` |
| `cloudfront-list-functions` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+list-functions\b` |
| `cloudfront-list-invalidations` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+list-invalidations\b` |
| `cloudfront-get-distribution` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+get-distribution\b` |
| `cloudfront-get-distribution-config` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+get-distribution-config\b` |
| `cloudfront-get-cache-policy` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+get-cache-policy\b` |
| `cloudfront-get-origin-request-policy` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+get-origin-request-policy\b` |
| `cloudfront-get-function` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+get-function\b` |
| `cloudfront-get-invalidation` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+get-invalidation\b` |
| `cloudfront-describe-function` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+cloudfront\s+describe-function\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `cloudfront-delete-distribution` | aws cloudfront delete-distribution removes a CloudFront distribution. | critical |
| `cloudfront-delete-cache-policy` | aws cloudfront delete-cache-policy removes a cache policy. | high |
| `cloudfront-delete-origin-request-policy` | aws cloudfront delete-origin-request-policy removes an origin request policy. | high |
| `cloudfront-delete-function` | aws cloudfront delete-function removes a CloudFront function. | high |
| `cloudfront-delete-response-headers-policy` | aws cloudfront delete-response-headers-policy removes a response headers policy. | high |
| `cloudfront-delete-key-group` | aws cloudfront delete-key-group removes a key group used for signed URLs. | critical |
| `cloudfront-create-invalidation` | aws cloudfront create-invalidation creates a cache invalidation (has cost implications). | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "cdn.cloudfront:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "cdn.cloudfront:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
