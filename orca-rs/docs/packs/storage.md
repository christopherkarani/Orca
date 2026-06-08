# Storage Packs

This document describes packs in the `storage` category.

## Packs in this Category

- [AWS S3](#storages3)
- [Google Cloud Storage](#storagegcs)
- [MinIO](#storageminio)
- [Azure Blob Storage](#storageazure_blob)

---

## AWS S3

**Pack ID:** `storage.s3`

Protects against destructive S3 operations like bucket removal, recursive deletes, and sync --delete.

### Keywords

Commands containing these keywords are checked against this pack:

- `s3`
- `s3api`
- `rb`
- `delete-bucket`
- `delete-object`
- `delete-objects`
- `--delete`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `s3-list` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+ls(?=\s\|$)` |
| `s3-copy` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+cp(?=\s\|$)` |
| `s3-presign` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+presign(?=\s\|$)` |
| `s3-mb` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+mb(?=\s\|$)` |
| `s3-rm-dryrun` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+rm(?=\s\|$)[^\n;&\|]*\s--dryrun(?=\s\|$)` |
| `s3-sync-delete-dryrun` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+sync(?=\s\|$)[^\n;&\|]*\s--delete(?=\s\|$)[^\n;&\|]*\s--dryrun(?=\s\|$)` |
| `s3-sync-dryrun-delete` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3\s+sync(?=\s\|$)[^\n;&\|]*\s--dryrun(?=\s\|$)[^\n;&\|]*\s--delete(?=\s\|$)` |
| `s3api-list-objects` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3api\s+list-objects(?:-v2)?(?=\s\|$)` |
| `s3api-get-object` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3api\s+get-object(?=\s\|$)` |
| `s3api-head-object` | `aws(?:\s+--?\S+(?:\s+\S+)?)*\s+s3api\s+head-object(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `s3-rb` | aws s3 rb removes an S3 bucket and is destructive. | critical |
| `s3-rm` | aws s3 rm deletes S3 objects and is destructive. | high |
| `s3-sync-delete` | aws s3 sync --delete removes destination objects not in source. | high |
| `s3api-delete-bucket` | aws s3api delete-bucket permanently deletes a bucket. | critical |
| `s3api-delete-object` | aws s3api delete-object permanently deletes an object. | medium |
| `s3api-delete-objects` | aws s3api delete-objects permanently deletes multiple objects. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "storage.s3:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "storage.s3:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Google Cloud Storage

**Pack ID:** `storage.gcs`

Protects against destructive GCS operations like bucket removal, object deletion, and recursive deletes.

### Keywords

Commands containing these keywords are checked against this pack:

- `gsutil`
- `gcloud`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `gsutil-ls` | `gsutil\s+(?:-[a-zA-Z]+\s+)*ls(?=\s\|$)` |
| `gsutil-cat` | `gsutil\s+(?:-[a-zA-Z]+\s+)*cat(?=\s\|$)` |
| `gsutil-stat` | `gsutil\s+(?:-[a-zA-Z]+\s+)*stat(?=\s\|$)` |
| `gsutil-du` | `gsutil\s+(?:-[a-zA-Z]+\s+)*du(?=\s\|$)` |
| `gsutil-hash` | `gsutil\s+(?:-[a-zA-Z]+\s+)*hash(?=\s\|$)` |
| `gsutil-version` | `gsutil\s+(?:-[a-zA-Z]+\s+)*version(?=\s\|$)` |
| `gsutil-help` | `gsutil\s+(?:-[a-zA-Z]+\s+)*help(?=\s\|$)` |
| `gsutil-cp` | `gsutil\s+(?:-[a-zA-Z]+\s+)*cp(?=\s\|$)` |
| `gcloud-storage-buckets-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:\s+--?\S+(?:\s+\S+)?)*)?\s+storage\s+buckets\s+list(?=\s\|$)` |
| `gcloud-storage-buckets-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:\s+--?\S+(?:\s+\S+)?)*)?\s+storage\s+buckets\s+describe(?=\s\|$)` |
| `gcloud-storage-objects-list` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:\s+--?\S+(?:\s+\S+)?)*)?\s+storage\s+objects\s+list(?=\s\|$)` |
| `gcloud-storage-objects-describe` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:\s+--?\S+(?:\s+\S+)?)*)?\s+storage\s+objects\s+describe(?=\s\|$)` |
| `gcloud-storage-ls` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:\s+--?\S+(?:\s+\S+)?)*)?\s+storage\s+ls(?=\s\|$)` |
| `gcloud-storage-cat` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:\s+--?\S+(?:\s+\S+)?)*)?\s+storage\s+cat(?=\s\|$)` |
| `gcloud-storage-cp` | `gcloud\b(?:\s+--?\S+(?:\s+\S+)?)*(?:\s+(?:alpha\|beta)(?:\s+--?\S+(?:\s+\S+)?)*)?\s+storage\s+cp(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `gsutil-rb` | gsutil rb removes a GCS bucket. | critical |
| `gsutil-rm` | gsutil rm deletes objects from GCS. | high |
| `gsutil-rsync-delete` | gsutil rsync -d deletes destination objects not in source. | high |
| `gcloud-storage-buckets-delete` | gcloud storage buckets delete removes a GCS bucket. | critical |
| `gcloud-storage-objects-delete` | gcloud storage objects delete removes objects from GCS. | high |
| `gcloud-storage-rm` | gcloud storage rm removes objects from GCS. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "storage.gcs:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "storage.gcs:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## MinIO

**Pack ID:** `storage.minio`

Protects against destructive MinIO Client (mc) operations like bucket removal, object deletion, and admin operations.

### Keywords

Commands containing these keywords are checked against this pack:

- `mc`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `mc-ls` | `\bmc\s+(?:--?\S+\s+)*ls(?=\s\|$)` |
| `mc-cat` | `\bmc\s+(?:--?\S+\s+)*cat(?=\s\|$)` |
| `mc-head` | `\bmc\s+(?:--?\S+\s+)*head(?=\s\|$)` |
| `mc-stat` | `\bmc\s+(?:--?\S+\s+)*stat(?=\s\|$)` |
| `mc-cp` | `\bmc\s+(?:--?\S+\s+)*cp(?=\s\|$)` |
| `mc-diff` | `\bmc\s+(?:--?\S+\s+)*diff(?=\s\|$)` |
| `mc-find` | `\bmc\s+(?:--?\S+\s+)*find(?=\s\|$)` |
| `mc-du` | `\bmc\s+(?:--?\S+\s+)*du(?=\s\|$)` |
| `mc-version` | `\bmc\s+(?:--?\S+\s+)*version(?=\s\|$)` |
| `mc-help` | `\bmc\s+(?:--?\S+\s+)*(?:--help\|-h)\b` |
| `mc-admin-info` | `\bmc\s+(?:--?\S+\s+)*admin\s+info(?=\s\|$)` |
| `mc-admin-user-list` | `\bmc\s+(?:--?\S+\s+)*admin\s+user\s+list(?=\s\|$)` |
| `mc-admin-policy-list` | `\bmc\s+(?:--?\S+\s+)*admin\s+policy\s+list(?=\s\|$)` |
| `mc-alias-list` | `\bmc\s+(?:--?\S+\s+)*alias\s+list(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `mc-rb` | mc rb removes a MinIO bucket. | critical |
| `mc-rm` | mc rm deletes objects from MinIO. | high |
| `mc-admin-bucket-delete` | mc admin bucket delete removes a bucket via admin API. | critical |
| `mc-mirror-remove` | mc mirror --remove deletes destination objects not in source. | high |
| `mc-admin-user-remove` | mc admin user remove/disable affects user access. | high |
| `mc-admin-policy-remove` | mc admin policy remove/unset modifies access policies. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "storage.minio:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "storage.minio:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Azure Blob Storage

**Pack ID:** `storage.azure_blob`

Protects against destructive Azure Blob Storage operations like container deletion, blob deletion, and azcopy remove.

### Keywords

Commands containing these keywords are checked against this pack:

- `az storage`
- `azcopy`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `az-storage-container-list` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+container\s+list(?=\s\|$)` |
| `az-storage-container-show` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+container\s+show(?=\s\|$)` |
| `az-storage-container-exists` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+container\s+exists(?=\s\|$)` |
| `az-storage-blob-list` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+list(?=\s\|$)` |
| `az-storage-blob-show` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+show(?=\s\|$)` |
| `az-storage-blob-exists` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+exists(?=\s\|$)` |
| `az-storage-blob-download` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+download(?=\s\|$)` |
| `az-storage-blob-download-batch` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+download-batch(?=\s\|$)` |
| `az-storage-blob-url` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+url(?=\s\|$)` |
| `az-storage-blob-metadata-show` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+blob\s+metadata\s+show(?=\s\|$)` |
| `az-storage-account-list` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+account\s+list(?=\s\|$)` |
| `az-storage-account-show` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+account\s+show(?=\s\|$)` |
| `az-storage-account-keys-list` | `\baz\b(?:\s+--?\S+(?:\s+\S+)?)*\s+storage\s+account\s+keys\s+list(?=\s\|$)` |
| `azcopy-list` | `\bazcopy\s+(?:--\S+\s+)*list(?=\s\|$)` |
| `azcopy-copy` | `\bazcopy\s+(?:--\S+\s+)*copy(?=\s\|$)` |
| `azcopy-jobs-list` | `\bazcopy\s+(?:--\S+\s+)*jobs\s+list(?=\s\|$)` |
| `azcopy-jobs-show` | `\bazcopy\s+(?:--\S+\s+)*jobs\s+show(?=\s\|$)` |
| `azcopy-login` | `\bazcopy\s+(?:--\S+\s+)*login(?=\s\|$)` |
| `azcopy-env` | `\bazcopy\s+(?:--\S+\s+)*env(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `az-storage-container-delete` | az storage container delete removes an Azure storage container. | critical |
| `az-storage-blob-delete-batch` | az storage blob delete-batch removes multiple blobs from Azure storage. | high |
| `az-storage-blob-delete` | az storage blob delete removes a blob from Azure storage. | medium |
| `az-storage-account-delete` | az storage account delete removes an entire Azure storage account. | critical |
| `azcopy-remove` | azcopy remove deletes files from Azure storage. | high |
| `azcopy-sync-delete` | azcopy sync --delete-destination removes destination files not in source. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "storage.azure_blob:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "storage.azure_blob:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
