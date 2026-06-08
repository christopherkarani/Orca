# Search Packs

This document describes packs in the `search` category.

## Packs in this Category

- [Elasticsearch](#searchelasticsearch)
- [OpenSearch](#searchopensearch)
- [Algolia](#searchalgolia)
- [Meilisearch](#searchmeilisearch)

---

## Elasticsearch

**Pack ID:** `search.elasticsearch`

Protects against destructive Elasticsearch REST API operations like index deletion, delete-by-query, index close, and cluster setting changes.

### Keywords

Commands containing these keywords are checked against this pack:

- `elasticsearch`
- `curl`
- `http`
- `9200`
- `_search`
- `_cluster`
- `_cat`
- `_doc`
- `_all`
- `_delete_by_query`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `es-curl-get-search` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:DELETE\|POST\|PUT)\b)(?=.*(?:elastic\|:9200)))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:elastic\|:9200)[^\s'\"]*/(?:[^\s/]+/)?(?:_search\|_count\|_mapping\|_settings)\b` |
| `es-curl-get-cat` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:DELETE\|POST\|PUT)\b)(?=.*(?:elastic\|:9200)))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:elastic\|:9200)[^\s'\"]*/_cat/\S+` |
| `es-curl-get-cluster-health` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:DELETE\|POST\|PUT)\b)(?=.*(?:elastic\|:9200)))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:elastic\|:9200)[^\s'\"]*/_cluster/health\b` |
| `es-http-get-search` | `http\s+GET\s+(?:https?://)?\S*(?:elastic\|:9200)\S*/(?:\S+/)?(?:_search\|_count\|_mapping\|_settings)\b` |
| `es-http-get-cat` | `http\s+GET\s+(?:https?://)?\S*(?:elastic\|:9200)\S*/_cat/\S+` |
| `es-http-get-cluster-health` | `http\s+GET\s+(?:https?://)?\S*(?:elastic\|:9200)\S*/_cluster/health\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `es-curl-delete-doc` | curl -X DELETE against /_doc deletes a document from Elasticsearch. | medium |
| `es-curl-delete-by-query` | curl -X POST to _delete_by_query deletes documents matching the query. | high |
| `es-curl-close-index` | curl -X POST to _close closes an index, making it unavailable for reads/writes. | high |
| `es-curl-delete-index` | curl -X DELETE against an Elasticsearch index (or _all/*) deletes data permanently. | critical |
| `es-curl-cluster-settings` | curl -X PUT to /_cluster/settings changes cluster settings and can be dangerous. | high |
| `es-http-delete-doc` | http DELETE against /_doc deletes a document from Elasticsearch. | medium |
| `es-http-delete-by-query` | http POST to _delete_by_query deletes documents matching the query. | high |
| `es-http-close-index` | http POST to _close closes an index, making it unavailable for reads/writes. | high |
| `es-http-delete-index` | http DELETE against an Elasticsearch index (or _all/*) deletes data permanently. | critical |
| `es-http-cluster-settings` | http PUT to /_cluster/settings changes cluster settings and can be dangerous. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "search.elasticsearch:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "search.elasticsearch:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## OpenSearch

**Pack ID:** `search.opensearch`

Protects against destructive OpenSearch REST API operations and AWS CLI domain deletions.

### Keywords

Commands containing these keywords are checked against this pack:

- `opensearch`
- `aws`
- `curl`
- `http`
- `9200`
- `_search`
- `_cluster`
- `_cat`
- `_doc`
- `_all`
- `_delete_by_query`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `os-curl-get-search` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:DELETE\|POST)\b)(?=.*(?:opensearch\|:9200)))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:opensearch\|:9200)[^\s'\"]*/(?:[^\s/]+/)?(?:_search\|_count\|_mapping\|_settings)\b` |
| `os-curl-get-cat` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:DELETE\|POST)\b)(?=.*(?:opensearch\|:9200)))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:opensearch\|:9200)[^\s'\"]*/_cat/\S+` |
| `os-curl-get-cluster-health` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))(?:DELETE\|POST)\b)(?=.*(?:opensearch\|:9200)))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:opensearch\|:9200)[^\s'\"]*/_cluster/health\b` |
| `os-http-get-search` | `http\s+GET\s+(?:https?://)?\S*(?:opensearch\|:9200)\S*/(?:\S+/)?(?:_search\|_count\|_mapping\|_settings)\b` |
| `os-http-get-cat` | `http\s+GET\s+(?:https?://)?\S*(?:opensearch\|:9200)\S*/_cat/\S+` |
| `os-http-get-cluster-health` | `http\s+GET\s+(?:https?://)?\S*(?:opensearch\|:9200)\S*/_cluster/health\b` |
| `aws-opensearch-describe-domain` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+opensearch\s+describe-domain\b` |
| `aws-opensearch-list-domain-names` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+opensearch\s+list-domain-names\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `os-curl-delete-doc` | curl -X DELETE against /_doc deletes a document from OpenSearch. | medium |
| `os-curl-delete-by-query` | curl -X POST to _delete_by_query deletes documents matching the query. | high |
| `os-curl-close-index` | curl -X POST to _close closes an index, making it unavailable for reads/writes. | high |
| `os-curl-delete-index` | curl -X DELETE against an OpenSearch index (or _all/*) deletes data permanently. | critical |
| `os-http-delete-doc` | http DELETE against /_doc deletes a document from OpenSearch. | medium |
| `os-http-delete-by-query` | http POST to _delete_by_query deletes documents matching the query. | high |
| `os-http-close-index` | http POST to _close closes an index, making it unavailable for reads/writes. | high |
| `os-http-delete-index` | http DELETE against an OpenSearch index (or _all/*) deletes data permanently. | critical |
| `aws-opensearch-delete-domain` | aws opensearch delete-domain permanently deletes an OpenSearch domain. | critical |
| `aws-opensearch-delete-inbound-connection` | aws opensearch delete-inbound-connection removes an OpenSearch connection. | high |
| `aws-opensearch-delete-outbound-connection` | aws opensearch delete-outbound-connection removes an OpenSearch connection. | high |
| `aws-opensearch-delete-package` | aws opensearch delete-package removes an OpenSearch package. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "search.opensearch:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "search.opensearch:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Algolia

**Pack ID:** `search.algolia`

Protects against destructive Algolia operations like deleting indices, clearing objects, removing rules/synonyms, and deleting API keys.

### Keywords

Commands containing these keywords are checked against this pack:

- `algolia`
- `algoliasearch`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `algolia-indices-browse` | `algolia(?:\s+--?\S+(?:\s+\S+)?)*\s+indices\s+browse\b` |
| `algolia-indices-list` | `algolia(?:\s+--?\S+(?:\s+\S+)?)*\s+indices\s+list\b` |
| `algolia-search` | `algolia(?:\s+--?\S+(?:\s+\S+)?)*\s+search\b` |
| `algolia-settings-get` | `algolia(?:\s+--?\S+(?:\s+\S+)?)*\s+settings\s+get\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `algolia-indices-delete` | algolia indices delete permanently removes an Algolia index. | critical |
| `algolia-indices-clear` | algolia indices clear removes all objects from an Algolia index. | high |
| `algolia-rules-delete` | algolia rules delete removes index rules. | medium |
| `algolia-synonyms-delete` | algolia synonyms delete removes synonym entries. | medium |
| `algolia-apikeys-delete` | algolia apikeys delete removes API keys and can break integrations. | high |
| `algolia-sdk-delete-index` | Algolia SDK deleteIndex removes an index. | critical |
| `algolia-sdk-clear-objects` | Algolia SDK clearObjects removes all records from an index. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "search.algolia:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "search.algolia:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Meilisearch

**Pack ID:** `search.meilisearch`

Protects against destructive Meilisearch REST API operations like index deletion, document deletion, delete-batch, and API key removal.

### Keywords

Commands containing these keywords are checked against this pack:

- `meili`
- `meilisearch`
- `7700`
- `/indexes`
- `/keys`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `meili-curl-get-stats` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))POST\b)(?=.*documents/delete-batch\b))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:meili\|:7700)[^\s'\"]*/stats\b` |
| `meili-curl-get-health` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))POST\b)(?=.*documents/delete-batch\b))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:meili\|:7700)[^\s'\"]*/health\b` |
| `meili-curl-get-version` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))POST\b)(?=.*documents/delete-batch\b))curl\b.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*\b(?:https?://)?[^\s'\"]*(?:meili\|:7700)[^\s'\"]*/version\b` |
| `meili-curl-search` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*(?:meili\|:7700)))(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))POST\b)(?=.*documents/delete-batch\b))curl\b.*(?:-X\s*\|--request(?:=\|\s+))POST\b.*\b(?:https?://)?[^\s'\"]*(?:meili\|:7700)[^\s'\"]*/indexes/[^\s/]+/search\b` |
| `meili-http-get-stats` | `http\s+GET\s+(?:https?://)?\S*(?:meili\|:7700)\S*/stats\b` |
| `meili-http-get-health` | `http\s+GET\s+(?:https?://)?\S*(?:meili\|:7700)\S*/health\b` |
| `meili-http-get-version` | `http\s+GET\s+(?:https?://)?\S*(?:meili\|:7700)\S*/version\b` |
| `meili-http-search` | `http\s+POST\s+(?:https?://)?\S*(?:meili\|:7700)\S*/indexes/\S+/search\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `meili-curl-delete-document` | curl -X DELETE against /documents/{id} removes a document from Meilisearch. | medium |
| `meili-curl-delete-documents` | curl -X DELETE against /documents removes documents from Meilisearch. | high |
| `meili-curl-delete-batch` | curl -X POST to /documents/delete-batch deletes documents in bulk. | high |
| `meili-curl-delete-key` | curl -X DELETE against /keys removes a Meilisearch API key. | high |
| `meili-curl-delete-index` | curl -X DELETE against /indexes/{uid} deletes a Meilisearch index. | critical |
| `meili-http-delete-document` | http DELETE against /documents/{id} removes a document from Meilisearch. | medium |
| `meili-http-delete-documents` | http DELETE against /documents removes documents from Meilisearch. | high |
| `meili-http-delete-batch` | http POST to /documents/delete-batch deletes documents in bulk. | high |
| `meili-http-delete-key` | http DELETE against /keys removes a Meilisearch API key. | high |
| `meili-http-delete-index` | http DELETE against /indexes/{uid} deletes a Meilisearch index. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "search.meilisearch:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "search.meilisearch:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
