# Remote Access Packs

This document describes packs in the `remote` category.

## Packs in this Category

- [rsync](#remotersync)
- [ssh](#remotessh)
- [scp](#remotescp)

---

## rsync

**Pack ID:** `remote.rsync`

Protects against destructive rsync operations like --delete and its variants.

### Keywords

Commands containing these keywords are checked against this pack:

- `rsync`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `rsync-dry-run` | `rsync\b.*\s--dry-run\b` |
| `rsync-short-dry-run` | `rsync\b.*\s+-[A-Za-z]*n[A-Za-z]*\b` |
| `rsync-list-only` | `rsync\b.*\s--list-only\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `rsync-delete` | rsync --delete removes destination files not present in source. | high |
| `rsync-del-short` | rsync --del is a short alias for --delete and is destructive. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "remote.rsync:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "remote.rsync:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## ssh

**Pack ID:** `remote.ssh`

Protects against destructive SSH operations like remote command execution and key management.

### Keywords

Commands containing these keywords are checked against this pack:

- `ssh`
- `ssh-keygen`
- `ssh-keyscan`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `ssh-version` | `ssh\s+-V\b` |
| `ssh-version-long` | `ssh\s+--version\b` |
| `ssh-keygen-list` | `ssh-keygen\s+.*-l\b` |
| `ssh-keygen-fingerprint` | `ssh-keygen\s+.*-lf?\b` |
| `ssh-keyscan` | `ssh-keyscan\b` |
| `ssh-add-list` | `ssh-add\s+-[lL]\b` |
| `ssh-agent` | `ssh-agent\b` |
| `ssh-help` | `ssh\s+--?h(elp)?\b` |
| `ssh-keygen-help` | `ssh-keygen\s+--?h(elp)?\b` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `ssh-remote-rm-rf` | SSH remote execution contains destructive rm -rf command. | critical |
| `ssh-remote-git-reset-hard` | SSH remote execution contains destructive git reset --hard command. | high |
| `ssh-remote-git-clean` | SSH remote execution contains destructive git clean -f command. | high |
| `ssh-keygen-remove-host` | ssh-keygen -R removes entries from known_hosts file. | medium |
| `ssh-add-delete-all` | ssh-add -d/-D removes identities from the SSH agent. | medium |
| `ssh-remote-sudo-rm` | SSH remote execution with sudo rm is high-risk. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "remote.ssh:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "remote.ssh:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## scp

**Pack ID:** `remote.scp`

Protects against destructive SCP operations like overwrites to system paths.

### Keywords

Commands containing these keywords are checked against this pack:

- `scp`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `scp-help` | `scp\b.*\s--?h(elp)?\b` |
| `scp-download` | `scp\b.*\s(?:\S+@)?\S+:\S+\s+\.\S*\s*$` |
| `scp-to-home` | `scp\b.*\s(?:(?:\S+@)?\S+:)?~/(?!\S*\.\./)\S+\s*$` |
| `scp-to-tmp` | `scp\b.*\s(?:(?:\S+@)?\S+:)?/tmp/(?!\S*\.\./)\S*\s*$` |
| `scp-to-var-tmp` | `scp\b.*\s(?:(?:\S+@)?\S+:)?/var/tmp(?:/(?!\S*\.\./)\S*)?\s*$` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `scp-recursive-root` | scp -r to root (/) is extremely dangerous. | critical |
| `scp-to-etc` | scp to /etc/ can overwrite system configuration. | high |
| `scp-to-var` | scp to /var/ can overwrite system data. | high |
| `scp-to-boot` | scp to /boot/ can corrupt boot configuration. | critical |
| `scp-to-usr` | scp to /usr/ can overwrite system binaries. | high |
| `scp-to-bin` | scp to /bin/ or /sbin/ can overwrite system binaries. | critical |
| `scp-to-lib` | scp to /lib/ can overwrite system libraries. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "remote.scp:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "remote.scp:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
