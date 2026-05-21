# Credential Guardrails

Orca implements defense-in-depth credential protection across eight layers. This document describes how each layer works, what patterns are detected, and how to configure credential management.

## Overview

When you run an AI agent through Orca, your environment variables, files, and network requests may contain sensitive credentials. Orca detects and protects these automatically—before they reach the agent process, before they are written to disk, and before they leave your machine.

The protection layers are:

1. [Secret Detection Engine](#1-secret-detection-engine) — Pattern matching for API keys, tokens, and passwords
2. [Environment Variable Filtering](#2-environment-variable-filtering) — Strips secrets before child process spawn
3. [Credential Broker System](#3-credential-broker-system) — Secure resolution without exposing raw values
4. [Policy Validation](#4-policy-validation) — Rejects unsafe credential configurations
5. [Network Exfiltration Detection](#5-network-exfiltration-detection) — Blocks secrets in URLs
6. [Command Classification](#6-command-classification) — Denies credential inspection commands
7. [File System Guards](#7-file-system-guards) — Blocks access to credential files
8. [Audit Trail Protection](#8-audit-trail-protection) — Redacts secrets before persistence

---

## 1. Secret Detection Engine

**File**: `src/audit/redact_bridge.zig`

The core engine detects and classifies sensitive values using pattern matching and entropy analysis.

### Environment Variable Name Patterns

The following env var name patterns are automatically flagged as secret-like:

| Pattern | Examples |
|---------|----------|
| `*TOKEN*` | `GITHUB_TOKEN`, `API_TOKEN`, `NPM_TOKEN` |
| `*SECRET*` | `AWS_SECRET`, `APP_SECRET` |
| `*PASSWORD*` | `DB_PASSWORD`, `ADMIN_PASSWORD` |
| `*PASSWD*` | `ROOT_PASSWD` |
| `*PRIVATE*` | `PRIVATE_KEY` |
| `*KEY*` | `API_KEY`, `ENCRYPTION_KEY` |
| `AWS_*` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `AZURE_*` | `AZURE_CLIENT_SECRET` |
| `GITHUB_TOKEN` | Exact match |
| `GH_TOKEN` | Exact match |
| `OPENAI_API_KEY` | Exact match |
| `ANTHROPIC_API_KEY` | Exact match |
| `GOOGLE_API_KEY` | Exact match |
| `GOOGLE_APPLICATION_CREDENTIALS` | Exact match |
| `NPM_TOKEN` | Exact match |
| `PYPI_TOKEN` | Exact match |
| `SSH_AUTH_SOCK` | Exact match |

### Value Classification

Orca inspects values and classifies them into specific secret types:

| Secret Type | Pattern | Example |
|-------------|---------|---------|
| **AWS Access Key** | `AKIA` or `ASIA` prefix, 20 chars | `AKIAIOSFODNN7EXAMPLE` |
| **GitHub Token** | `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` prefix (20+ chars) or `github_pat_` (30+ chars) | `ghp_xxxxxxxxxxxxxxxxxxxx` |
| **OpenAI API Key** | `sk-` prefix, 20+ chars | `sk-xxxxxxxxxxxxxxxxxxxx` |
| **Anthropic API Key** | `sk-ant-` prefix, 24+ chars | `sk-ant-xxxxxxxxxxxxxxxx` |
| **JWT** | Three base64 parts separated by dots | `eyJhbG...eyJzdWI...c2lnbmF0dXJl` |
| **PEM Private Key** | `-----BEGIN PRIVATE KEY-----` | RSA/EC private keys |
| **SSH Private Key** | `-----BEGIN OPENSSH PRIVATE KEY-----` | Ed25519/RSA keys |
| **Cloud Credentials JSON** | Contains `"type"` + `"service_account"` or `"private_key"` | Google service account |
| **High-Entropy String** | 32-512 chars, 3+ character classes, 16+ unique chars | Generic API keys |

### Redaction Format

When a secret is detected, it is replaced with a redaction label that includes a SHA-256 fingerprint prefix:

```
[REDACTED:env:GITHUB_TOKEN:sha256:a1b2c3d4]
[REDACTED:secret:github_token:sha256:e5f6g7h8]
```

The fingerprint is the first 8 hex characters of the SHA-256 hash of the raw value. This allows you to verify whether two redactions refer to the same secret without exposing the secret itself.

### Embedded Secret Detection

The engine also finds secrets embedded in:
- Shell command text (e.g., `echo OPENAI_API_KEY=sk-...`)
- URL query parameters (e.g., `?token=ghp_...`)
- JSON payloads (e.g., `{"api_key":"sk-..."}`)
- Environment variable assignments in strings

---

## 2. Environment Variable Filtering

**File**: `src/intercept/env.zig`

Before launching the agent process, Orca filters the environment variables based on policy mode and detected secrets.

### Filtering Behavior by Mode

| Mode | Behavior |
|------|----------|
| `strict` / `ci` / `redteam` | Removes all secret-like env vars. Only explicitly allowed vars pass through. |
| `ask` | Removes secret-like vars unless explicitly allowed. Prompts for risky ones. |
| `observe` | Passes all vars through but records redactions for audit. |

### Secretless Mode

Run with `--secretless` to replace secret values with broker references:

```bash
orca run --secretless -- claude
```

In this mode:
- `GITHUB_TOKEN=ghp_xxxxxxxx` becomes `GITHUB_TOKEN=orca-secret://local-dummy/env/GITHUB_TOKEN/a1b2c3d4`
- The agent sees the reference, not the raw value
- The agent can pass the reference to tools that understand Orca brokers
- Raw values are never written to policy, audit, or replay artifacts

### Redaction Records

When env vars are filtered, Orca creates redaction records for the audit trail:

```
Name: GITHUB_TOKEN
Label: [REDACTED:env:GITHUB_TOKEN:sha256:a1b2c3d4]
Reason: environment variable name matches secret pattern
```

---

## 3. Credential Broker System

**File**: `src/intercept/credentials.zig`

Orca supports multiple credential brokers for secure secret resolution. The broker system ensures raw secrets are never stored in policy files or exposed in logs.

### Supported Brokers

| Broker | Type | Description |
|--------|------|-------------|
| `local-dummy` | Reference-only | Creates `orca-secret://` references without resolving values. Used for testing and secretless mode. |
| `env-file-dev` | File-based | Reads from `.orca/*.env` files. Local development only. |
| `1password-cli` | CLI integration | Resolves via `op read` command. Requires 1Password CLI. |
| `macos-keychain` | OS integration | Resolves via `/usr/bin/security` command. macOS only. |
| `infisical-agent-vault` | Config boundary | Status/config check only. Resolution disabled pending verification. |

### Configuration

```yaml
credentials:
  default_broker: onepassword
  brokers:
    onepassword:
      type: 1password-cli
      account: my-team
    env_dev:
      type: env-file-dev
      path: .orca/dev-secrets.env
    macos:
      type: macos-keychain
  refs:
    github_pat:
      broker: onepassword
      ref: "op://Engineering/GitHub PAT/token"
    aws_key:
      broker: env_dev
      ref: "AWS_ACCESS_KEY_ID"
```

### Security Features

- **Secure memory wiping**: Resolved secrets are zeroed in memory before deallocation (`@memset(value, 0)`)
- **Timeout protection**: Broker CLI commands time out after 5 seconds with automatic kill
- **Redacted errors**: Errors are classified as `login-required`, `missing-ref`, `timeout` without leaking details
- **Path validation**: `env-file-dev` paths must be under `.orca/` and contain `dev`
- **Reference checking**: `orca credentials check` validates broker availability without printing values

### Checking Broker Status

```bash
# Check all brokers
orca credentials check

# Check a specific credential reference
orca credentials check github_pat
```

Output:
```
Credential brokers:
- onepassword (1password-cli): available - op CLI found; ref checks use op read without printing values
- env_dev (env-file-dev): available - dev env file readable
- macos (macos-keychain): limited - macOS security CLI found; ref checks query keychain without printing values
```

---

## 4. Policy Validation

**File**: `src/policy/validate.zig`

Orca validates credential configurations when loading policies and rejects unsafe setups.

### Validation Rules

- **Broker names** must be unique (case-insensitive)
- **Credential refs** must be unique (case-insensitive)
- **Credential refs** cannot contain raw secret values (rejected if `classifyString()` detects a secret)
- **Env-file paths** must be relative, under `.orca/`, and contain `dev`
- **Service credential references** must point to defined refs
- **Default broker** must exist if brokers are configured

### Example: Rejected Configurations

```yaml
# REJECTED: Raw secret in credential ref
credentials:
  refs:
    github_pat:
      ref: "ghp_fakeSyntheticTokenValue1234567890"  # Error: InvalidPolicy

# REJECTED: Unsafe env-file path
credentials:
  brokers:
    env_dev:
      type: env-file-dev
      path: /tmp/secrets.env  # Error: InvalidPolicy

# REJECTED: Missing broker for ref
credentials:
  refs:
    github_pat:
      ref: "GITHUB_PAT"
      broker: missing_broker  # Error: InvalidPolicy
```

---

## 5. Network Exfiltration Detection

**File**: `src/intercept/network.zig`

Orca scans network destinations for secret-like values in URLs and flags potential exfiltration.

### Detected Patterns

| Signal | Score | Description |
|--------|-------|-------------|
| `secret_like_url_value` | 95 | API key or token detected in URL path or query |
| `long_query_string` | 70 | Query string exceeds 120 characters |
| `base64_like_url_component` | 70 | Base64-like string in URL path or query |
| `high_entropy_dns_label` | 75 | High-entropy subdomain (possible DNS exfiltration) |
| `paste_site_destination` | 85 | Destination is a paste site (pastebin, gist, etc.) |
| `webhook_request_bin_destination` | 90 | Destination is a webhook/request bin |
| `tunneling_service_destination` | 85 | Destination is a tunneling service (ngrok, etc.) |
| `direct_ip_destination` | 70 | Direct IP address instead of domain |
| `long_subdomain` | 65 | Subdomain exceeds 48 characters |
| `many_unknown_domains` | 75 | Repeated attempts to unknown domains |

### URL Redaction

When secrets are detected in URLs, they are redacted before audit persistence:

```
https://example.com/path?token=[REDACTED:secret:openai_api_key:sha256:a1b2c3d4]&ok=1
```

Orca also handles percent-encoded secrets:

```
https://example.com/path?token=sk%2DfakeSyntheticOpenAIKey1234567890
# Detected and redacted despite URL encoding
```

### Policy Configuration

```yaml
network:
  detect_exfiltration:
    dns: true
    long_query_strings: true
    secret_patterns: true
```

---

## 6. Command Classification

**File**: `src/intercept/commands.zig`

Orca classifies commands by risk and denies credential inspection attempts automatically.

### Credential Inspection Risk Class

Commands that attempt to read credential files are classified as `credential_inspection` (risk score: 96, mandatory deny):

| Command | Reason |
|---------|--------|
| `cat .env` | Credential file inspection |
| `cat ~/.ssh/id_ed25519` | SSH private key inspection |
| `type %USERPROFILE%\.ssh\id_ed25519` | Windows credential inspection |
| `cat ~/.aws/credentials` | AWS credential inspection |

### Detected Credential Paths

The classifier checks for access to:
- `.env` and `.env.*` files
- `~/.ssh/` directory
- `~/.aws/` directory
- `~/.gcloud/` directory
- `~/.azure/` directory
- `~/.config/gh/` directory
- `id_rsa` and `id_ed25519` keys
- Windows credential stores (`%USERPROFILE%\.ssh\`, `%APPDATA%\gh\`)
- Browser login data and cookies

---

## 7. File System Guards

**File**: `src/intercept/files.zig`

Orca denies file read/write access to credential paths through built-in rules.

### Built-in Read Deny Patterns

The following patterns are denied by default for file reads:

```
./.env
./.env.*
~/.ssh/**
~/.aws/**
~/.gcloud/**
~/.azure/**
~/.config/gh/**
**/id_rsa
**/id_ed25519
**/*_rsa
**/*_ed25519
**/*credentials*
**/*credential*
**/*secret*
**/*token*
~/Library/Keychains/**
./Library/Keychains/**
~/Library/Application Support/**/Cookies*
~/Library/Application Support/Google/Chrome/**
~/Library/Application Support/BraveSoftware/**
~/Library/Application Support/Firefox/**
~/.zsh_history
~/.bash_history
```

### Built-in Write Deny Patterns

```
./.git/**
./.orca/**
```

### Symlink Protection

Orca resolves symlinks and denies access if they escape the workspace or point to protected paths.

---

## 8. Audit Trail Protection

**Files**: `src/audit/writer.zig`, `src/audit/summary.zig`

All audit events are redacted before persistence to ensure secrets never reach the logs.

### Pre-Write Redaction

Before writing to `events.jsonl`:
- Event targets are scanned for secrets
- Secret values are replaced with redaction labels
- Command arguments are redacted
- Network destinations are redacted

### Tamper Detection

The audit log uses hash-chain verification:
- Each event includes a hash of the previous event
- Modifying the log breaks the chain
- Replay verification detects tampering

### Summary Redaction

Session summaries (`summary.json`, `summary.md`) also redact:
- Policy content
- Command arguments
- Any secret-like values

---

## Integration Points

The guardrails integrate at multiple stages:

```
Policy Load → Validation → Runtime → Audit
     ↓           ↓           ↓         ↓
  validate   reject raw   filter/    redact
  config     secrets      block      before
                          secrets    write
```

1. **Policy Load**: Credential configurations are validated
2. **Pre-Execution**: Environment is filtered, secrets replaced
3. **Runtime**: Commands, files, and network are evaluated
4. **Audit**: All events are redacted before persistence

---

## Testing

Orca includes comprehensive tests for credential guardrails:

```bash
# Run all tests
zig build test

# Specific credential tests
zig build test -- src/intercept/credentials.zig
zig build test -- src/audit/redact_bridge.zig
zig build test -- src/intercept/env.zig
zig build test -- src/policy/validate.zig
```

### Synthetic Test Values

Tests use synthetic secrets that are still treated as sensitive:

```
ghp_fakeSyntheticTokenValue1234567890
sk-fakeSyntheticOpenAIKey1234567890
sk-ant-fakeSyntheticAnthropicKey1234567890
```

These are detected and redacted exactly like real secrets.

---

## See Also

- [Policy Reference](policy.md) — Full policy schema including credentials section
- [Network](network.md) — Network exfiltration detection and proxy configuration
- [Commands](commands.md) — Command risk classification and approvals
- [Threat Model](threat-model.md) — Security assumptions and trust boundaries
- [Edge Sensitive Data Redaction](edge/sensitive-data-redaction.md) — Edge-specific redaction rules
