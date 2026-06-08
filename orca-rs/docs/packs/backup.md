# Backup Packs

This document describes packs in the `backup` category.

## Packs in this Category

- [BorgBackup](#backupborg)
- [Rclone](#backuprclone)
- [Restic](#backuprestic)
- [Velero](#backupvelero)

---

## BorgBackup

**Pack ID:** `backup.borg`

Protects against destructive borg operations like delete, prune, compact, and recreate.

### Keywords

Commands containing these keywords are checked against this pack:

- `borg`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `borg-list` | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+list(?=\s\|$)` |
| `borg-info` | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+info(?=\s\|$)` |
| `borg-diff` | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| `borg-check` | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| `borg-create` | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+create(?=\s\|$)` |
| `borg-extract` | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+extract(?=\s\|$)` |
| `borg-mount` | `borg(?:\s+--?\S+(?:\s+\S+)?)*\s+mount(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `borg-delete` | borg delete removes archives or entire repositories. | critical |
| `borg-prune` | borg prune removes archives based on retention rules. | high |
| `borg-compact` | borg compact reclaims space after deletions. | medium |
| `borg-recreate` | borg recreate can drop data from archives. | high |
| `borg-break-lock` | borg break-lock forces removal of repository locks. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "backup.borg:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "backup.borg:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Rclone

**Pack ID:** `backup.rclone`

Protects against destructive rclone operations like sync, delete, purge, dedupe, and move.

### Keywords

Commands containing these keywords are checked against this pack:

- `rclone`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `rclone-copy` | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+copy(?=\s\|$)` |
| `rclone-ls` | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+ls(?=\s\|$)` |
| `rclone-lsd` | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+lsd(?=\s\|$)` |
| `rclone-lsl` | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+lsl(?=\s\|$)` |
| `rclone-size` | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+size(?=\s\|$)` |
| `rclone-check` | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| `rclone-config` | `rclone(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |
| `rclone-dry-run` | `\brclone\b(?:\s+\S+)*\s+(?:--dry-run(?:=true)?\|-n)(?:\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `rclone-sync` | rclone sync deletes destination files not present in the source. | critical |
| `rclone-delete` | rclone delete removes files and directories from the target. | critical |
| `rclone-deletefile` | rclone deletefile removes a single file from the target. | high |
| `rclone-purge` | rclone purge deletes a path and all its contents. | critical |
| `rclone-cleanup` | rclone cleanup removes old/malformed uploads. | medium |
| `rclone-dedupe` | rclone dedupe can delete or rename duplicate files. | high |
| `rclone-move` | rclone move deletes source files after copying. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "backup.rclone:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "backup.rclone:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Restic

**Pack ID:** `backup.restic`

Protects against destructive restic operations like forgetting snapshots, pruning data, removing keys, and cache cleanup.

### Keywords

Commands containing these keywords are checked against this pack:

- `restic`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `restic-snapshots` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+snapshots(?=\s\|$)` |
| `restic-ls` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+ls(?=\s\|$)` |
| `restic-stats` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+stats(?=\s\|$)` |
| `restic-check` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+check(?=\s\|$)` |
| `restic-diff` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| `restic-find` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+find(?=\s\|$)` |
| `restic-backup` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+backup(?=\s\|$)` |
| `restic-restore` | `restic(?:\s+--?\S+(?:\s+\S+)?)*\s+restore(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `restic-forget` | restic forget removes snapshots and can permanently delete backup data. | critical |
| `restic-prune` | restic prune removes unreferenced data and is irreversible. | critical |
| `restic-key-remove` | restic key remove deletes encryption keys and can make backups unrecoverable. | critical |
| `restic-unlock-remove-all` | restic unlock --remove-all force-removes repository locks. | high |
| `restic-cache-cleanup` | restic cache --cleanup removes cached data from disk. | low |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "backup.restic:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "backup.restic:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Velero

**Pack ID:** `backup.velero`

Protects against destructive velero operations like deleting backups, schedules, and locations.

### Keywords

Commands containing these keywords are checked against this pack:

- `velero`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `velero-backup-get` | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+get(?=\s\|$)` |
| `velero-backup-describe` | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+describe(?=\s\|$)` |
| `velero-backup-logs` | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+logs(?=\s\|$)` |
| `velero-backup-create` | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+backup\s+create(?=\s\|$)` |
| `velero-schedule-get` | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+schedule\s+get(?=\s\|$)` |
| `velero-restore-create` | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+restore\s+create(?=\s\|$)` |
| `velero-version` | `velero(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `velero-backup-delete` | velero backup delete removes a backup and its data. | high |
| `velero-schedule-delete` | velero schedule delete removes scheduled backups. | medium |
| `velero-restore-delete` | velero restore delete removes restore records. | low |
| `velero-backup-location-delete` | velero backup-location delete removes a backup storage location. | high |
| `velero-snapshot-location-delete` | velero snapshot-location delete removes a snapshot location. | high |
| `velero-uninstall` | velero uninstall removes the Velero deployment and related resources. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "backup.velero:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "backup.velero:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
