# Custom Pack Authoring Guide

This guide covers creating external YAML packs for orca. Custom packs let you
define organization-specific security policies without modifying the orca binary.

## Quick Start

1. Create a pack file at `~/.config/orca/packs/mycompany.yaml`
2. Define at least one pattern (safe or destructive)
3. Validate with `orca pack validate ~/.config/orca/packs/mycompany.yaml`
4. Restart orca or reload config

See `examples/packs/example.yaml` for a complete working example.

## Pack File Structure

```yaml
# Required fields
schema_version: 1                    # Always use 1 (current version)
id: mycompany.policies               # namespace.name format
name: MyCompany Security Policies    # Human-readable name
version: 1.0.0                       # Your pack's semantic version

# Optional fields
description: |
  What this pack protects against.

keywords:                            # Trigger evaluation (recommended)
  - mycommand
  - mytool

destructive_patterns:                # Patterns that block/warn
  - name: pattern-id
    pattern: regex-pattern
    severity: critical               # critical/high/medium/low
    description: Short denial reason
    explanation: |                   # Optional detailed explanation
      Longer help text with alternatives.

safe_patterns:                       # Patterns that explicitly allow
  - name: safe-pattern-id
    pattern: safe-regex-pattern
    description: Why this is allowed
```

## Field Reference

### Required Pack Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier in `namespace.name` format. Must match `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$` |
| `name` | string | Human-readable pack name shown in messages |
| `version` | string | Semantic version (`X.Y.Z`) for your own tracking |

### Optional Pack Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `schema_version` | integer | 1 | Schema version for forward compatibility |
| `description` | string | none | What this pack protects against |
| `keywords` | array | `[]` | Keywords that trigger pattern matching |
| `destructive_patterns` | array | `[]` | Patterns that block or warn |
| `safe_patterns` | array | `[]` | Patterns that explicitly allow |

### Destructive Pattern Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Stable identifier within the pack |
| `pattern` | string | yes | fancy-regex pattern to match |
| `severity` | string | no | `critical`, `high` (default), `medium`, `low` |
| `description` | string | no | Short reason shown on denial |
| `explanation` | string | no | Detailed explanation for verbose output |

### Safe Pattern Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Stable identifier within the pack |
| `pattern` | string | yes | fancy-regex pattern to match |
| `description` | string | no | Why this command is allowed |

## Severity Levels

Severity determines the default action when a command matches:

| Severity | Default Action | Use Case |
|----------|---------------|----------|
| `critical` | Always deny | Irreversible operations (rm -rf /, DROP DATABASE) |
| `high` | Deny (allowlistable) | Dangerous but sometimes needed (force push, truncate) |
| `medium` | Warn but allow | Worth noting but not blocking (large deletes) |
| `low` | Log only | Learning/audit purposes |

## Keywords Best Practices

Keywords gate pattern evaluation. Commands without any keywords skip the pack
entirely, improving performance.

**Do:**
- Use specific, unambiguous keywords: `kubectl`, `terraform`, `mycompany-deploy`
- Include common aliases if applicable: `k` for kubectl
- Keep the list short (< 10 keywords)

**Don't:**
- Use single letters or common words: `a`, `run`, `do`
- Include partial matches: `rm` instead of `rm -rf`
- Omit keywords (forces evaluation on every command)

## Regex Pattern Guidelines

Patterns use [fancy-regex](https://docs.rs/fancy-regex) syntax, which supports:
- Standard regex: `\s`, `\w`, `.*`, `[a-z]+`
- Lookahead: `(?=...)`, `(?!...)`
- Lookbehind: `(?<=...)`, `(?<!...)`
- Backreferences: `\1`, `\2`

### Performance Considerations

orca uses a dual regex engine:
- **Linear engine** (O(n)): For simple patterns without lookahead/lookbehind
- **Backtracking engine**: For patterns requiring advanced features

Simple patterns are faster. The validator reports which engine each pattern uses.

### Pattern Specificity

Write patterns that match **exactly** what you want to block:

```yaml
# Too broad - matches "rm" anywhere
pattern: rm

# Too narrow - misses "rm -rf --no-preserve-root"
pattern: rm\s+-rf\s+/

# Good - matches rm -rf variations targeting root or system paths
pattern: \brm\s+(?:-[a-zA-Z]*r[a-zA-Z]*\s+)*(?:-[a-zA-Z]*f[a-zA-Z]*\s+)*(?:/|/\*|/usr|/etc|/var|/home)
```

### Anchoring

Use word boundaries (`\b`) to avoid matching substrings:

```yaml
# Matches "deploy", "deployer", "redeploy"
pattern: deploy

# Only matches "deploy" as a word
pattern: \bdeploy\b
```

### Flag Handling

Match flags flexibly to handle different orderings:

```yaml
# Handles: --env prod, --env=prod, --env  prod
pattern: --env\s*[=\s]?\s*prod
```

## Schema Versioning

The `schema_version` field enables forward compatibility:

- **Version 1** (current): All fields documented in this guide
- Future versions may add new fields but will maintain backward compatibility
- Packs with `schema_version` higher than supported are rejected with a clear error

When orca adds new features (e.g., new pattern fields), the schema version
increments. Your existing packs continue working; only new features require
updating `schema_version`.

## Pack ID Collision Rules

External packs **cannot** override built-in packs. This prevents accidental or
malicious security bypasses.

### Built-in Pack Namespaces (Reserved)

- `core.*` - Git, filesystem operations
- `database.*` - PostgreSQL, MySQL, MongoDB, Redis, SQLite
- `containers.*` - Docker, Podman, Compose
- `kubernetes.*` - kubectl, Helm, Kustomize
- `cloud.*` - AWS, Azure, GCP
- `storage.*` - S3, GCS, MinIO, Azure Blob
- `infrastructure.*` - Terraform, Pulumi, Ansible
- `backup.*` - Restic, rclone
- `cdn.*`, `apigateway.*`, `monitoring.*`, `messaging.*`, `search.*`, `secrets.*`
- ...and others (see `orca packs list` for full list)

### Choosing Your Namespace

Use a unique namespace that identifies your organization:

```yaml
# Good - unique to your organization
id: acmecorp.deploy
id: myproject.database
id: internal.tools

# Bad - collides with built-in
id: core.git          # Error: collides with built-in pack 'Git'
id: database.custom   # Might collide with future built-ins
```

### Collision Detection

The validator checks for collisions:

```
$ orca pack validate malicious.yaml
Error: Pack ID 'core.git' collides with built-in pack 'Git'.
External packs cannot override built-in security packs.
```

## Validation

Always validate packs before deployment:

```bash
orca pack validate ~/.config/orca/packs/mycompany.yaml
```

The validator checks:
- YAML syntax
- Schema compliance
- ID format (`namespace.name`)
- Version format (semantic versioning)
- Pattern compilation (catches invalid regex)
- Duplicate pattern names
- Built-in pack collisions
- Regex engine selection (reports linear vs backtracking)

### Example Validation Output

```
Validating: mycompany.yaml

Pack Information:
  ID:      mycompany.deploy
  Name:    MyCompany Deployment Policies
  Version: 1.0.0

Patterns:
  prod-direct-deploy (destructive, critical) [linear engine]
  staging-dev-deploy (safe) [linear engine]

Engine Summary: 2 patterns, 100% linear (optimal performance)

Result: Valid
```

## Loading Custom Packs

### Configuration

Add pack paths in your config file:

```toml
# ~/.config/orca/config.toml or .orca.toml
[packs]
custom_paths = [
  "~/.config/orca/packs/*.yaml",
  ".orca/packs/*.yaml",
  "/etc/orca/packs/*.yaml"
]
```

### Load Order and Precedence

1. **Built-in packs** load first (cannot be overridden)
2. **External packs** load in path order (later paths override earlier)
3. For duplicate external IDs, last loaded wins

This allows:
- System-wide packs in `/etc/orca/packs/`
- User overrides in `~/.config/orca/packs/`
- Project-specific packs in `.orca/packs/`

### Fail-Open Loading

Invalid pack files generate warnings but don't block loading:

```
Warning: Failed to load pack from /etc/orca/packs/broken.yaml: Invalid pattern 'test-pattern' ([unclosed): regex parse error
Loaded 3 external packs (1 warning)
```

This ensures a typo in one pack doesn't disable all protection.

## FAQ

### Q: My pattern isn't matching. How do I debug?

Use `orca test` with your command:

```bash
orca test "deploy --env prod"
```

This shows which packs evaluated and which patterns matched.

### Q: Can I override a built-in pattern?

No. Built-in packs cannot be overridden by external packs for security.
Instead, use allowlists to permit specific commands:

```toml
# ~/.config/orca/allowlist.toml
[[rules]]
command_prefix = "git push --force origin feature/"
reason = "Force push allowed on feature branches"
```

### Q: How do I test my pack before deploying?

```bash
# Validate syntax and patterns
orca pack validate mypack.yaml

# Test against specific commands
orca test --pack-path mypack.yaml "dangerous-command"
```

### Q: What happens if schema_version is higher than supported?

orca rejects the pack with a clear error:

```
Error: Schema version 99 is not supported (max: 1)
```

This prevents newer packs from silently failing on older orca versions.

### Q: Can I use lookahead/lookbehind in patterns?

Yes. fancy-regex supports all common regex features. However, patterns with
lookahead/lookbehind use the backtracking engine, which is slightly slower.
The validator reports which engine each pattern uses.

### Q: How many patterns can I have in a pack?

There's no hard limit, but for performance:
- Aim for < 50 patterns per pack
- Use keywords to skip evaluation when possible
- Prefer specific patterns over broad ones

### Q: How do I share packs with my team?

Options:
1. Check packs into your repo in `.orca/packs/`
2. Host on a shared filesystem (`/etc/orca/packs/`)
3. Distribute via your configuration management system

## See Also

- `docs/pack.schema.yaml` - JSON Schema for pack files
- `docs/configuration.md` - General orca configuration
- `examples/packs/example.yaml` - Complete working example
