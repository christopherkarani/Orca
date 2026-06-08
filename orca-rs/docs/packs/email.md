# Email Packs

This document describes packs in the `email` category.

## Packs in this Category

- [AWS SES](#emailses)
- [SendGrid](#emailsendgrid)
- [Mailgun](#emailmailgun)
- [Postmark](#emailpostmark)

---

## AWS SES

**Pack ID:** `email.ses`

Protects against destructive AWS Simple Email Service operations like identity deletion, template deletion, and configuration set removal.

### Keywords

Commands containing these keywords are checked against this pack:

- `ses`
- `sesv2`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `ses-list-identities` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+list-identities(?=\s\|$)` |
| `ses-list-templates` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+list-templates(?=\s\|$)` |
| `ses-list-configuration-sets` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+list-configuration-sets\b` |
| `ses-list-receipt-rules` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+list-receipt-rules\b` |
| `ses-list-receipt-rule-sets` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+list-receipt-rule-sets\b` |
| `ses-get-identity-verification-attributes` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-identity-verification-attributes\b` |
| `ses-get-identity-dkim-attributes` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-identity-dkim-attributes\b` |
| `ses-get-identity-notification-attributes` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-identity-notification-attributes\b` |
| `ses-get-template` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-template(?=\s\|$)` |
| `ses-describe-configuration-set` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+describe-configuration-set\b` |
| `ses-describe-receipt-rule` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+describe-receipt-rule\b` |
| `ses-describe-receipt-rule-set` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+describe-receipt-rule-set\b` |
| `ses-get-send-quota` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-send-quota(?=\s\|$)` |
| `ses-get-send-statistics` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+ses\s+get-send-statistics\b` |
| `sesv2-list-email-identities` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+list-email-identities\b` |
| `sesv2-list-email-templates` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+list-email-templates\b` |
| `sesv2-list-configuration-sets` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+list-configuration-sets\b` |
| `sesv2-list-contact-lists` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+list-contact-lists\b` |
| `sesv2-list-dedicated-ip-pools` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+list-dedicated-ip-pools\b` |
| `sesv2-get-email-identity` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+get-email-identity\b` |
| `sesv2-get-email-template` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+get-email-template\b` |
| `sesv2-get-configuration-set` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+get-configuration-set\b` |
| `sesv2-get-contact-list` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+get-contact-list\b` |
| `sesv2-get-dedicated-ip-pool` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+get-dedicated-ip-pool\b` |
| `sesv2-get-account` | `\baws\b(?:\s+--?\S+(?:\s+\S+)?)*\s+sesv2\s+get-account(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `ses-delete-identity` | aws ses delete-identity removes a verified email identity. | high |
| `ses-delete-template` | aws ses delete-template removes an email template. | medium |
| `ses-delete-configuration-set` | aws ses delete-configuration-set removes a configuration set. | high |
| `ses-delete-receipt-rule-set` | aws ses delete-receipt-rule-set removes a receipt rule set. | critical |
| `ses-delete-receipt-rule` | aws ses delete-receipt-rule removes a receipt rule. | high |
| `sesv2-delete-email-identity` | aws sesv2 delete-email-identity removes a verified email identity. | high |
| `sesv2-delete-email-template` | aws sesv2 delete-email-template removes an email template. | medium |
| `sesv2-delete-configuration-set` | aws sesv2 delete-configuration-set removes a configuration set. | high |
| `sesv2-delete-contact-list` | aws sesv2 delete-contact-list removes a contact list. | high |
| `sesv2-delete-dedicated-ip-pool` | aws sesv2 delete-dedicated-ip-pool removes a dedicated IP pool. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "email.ses:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "email.ses:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## SendGrid

**Pack ID:** `email.sendgrid`

Protects against destructive SendGrid API operations like template deletion, API key deletion, and domain authentication removal.

### Keywords

Commands containing these keywords are checked against this pack:

- `sendgrid`
- `api.sendgrid.com`

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `sendgrid-delete-template` | DELETE to SendGrid /v3/templates removes a transactional template. | high |
| `sendgrid-delete-api-key` | DELETE to SendGrid /v3/api_keys removes an API key. | critical |
| `sendgrid-delete-whitelabel-domain` | DELETE to SendGrid /v3/whitelabel/domains removes domain authentication. | critical |
| `sendgrid-delete-sender` | DELETE to SendGrid /v3/senders or /v3/verified_senders removes a sender identity. | high |
| `sendgrid-delete-teammate` | DELETE to SendGrid /v3/teammates removes a teammate from the account. | medium |
| `sendgrid-delete-suppression` | DELETE to SendGrid suppression endpoints removes entries from suppression lists. | high |
| `sendgrid-delete-webhook` | DELETE to SendGrid /v3/user/webhooks removes a webhook configuration. | medium |
| `sendgrid-delete-subuser` | DELETE to SendGrid /v3/subusers removes a subuser account. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "email.sendgrid:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "email.sendgrid:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Mailgun

**Pack ID:** `email.mailgun`

Protects against destructive Mailgun API operations like domain deletion, route deletion, and mailing list removal.

### Keywords

Commands containing these keywords are checked against this pack:

- `mailgun`
- `api.mailgun.net`

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `mailgun-delete-domain` | DELETE to Mailgun /v3/domains removes a domain configuration. | critical |
| `mailgun-delete-route` | DELETE to Mailgun /v3/routes removes an email route. | high |
| `mailgun-delete-list` | DELETE to Mailgun /v3/lists removes a mailing list. | high |
| `mailgun-delete-template` | DELETE to Mailgun templates endpoint removes an email template. | medium |
| `mailgun-delete-webhook` | DELETE to Mailgun webhooks endpoint removes a webhook. | medium |
| `mailgun-delete-credential` | DELETE to Mailgun credentials endpoint removes SMTP credentials. | high |
| `mailgun-delete-tag` | DELETE to Mailgun tags endpoint removes a tag. | low |
| `mailgun-delete-suppression` | DELETE to Mailgun suppression endpoints removes suppression entries. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "email.mailgun:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "email.mailgun:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Postmark

**Pack ID:** `email.postmark`

Protects against destructive Postmark API operations like server deletion, template deletion, and sender signature removal.

### Keywords

Commands containing these keywords are checked against this pack:

- `postmark`
- `api.postmarkapp.com`

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `postmark-delete-server` | DELETE to Postmark /servers removes a server configuration. | critical |
| `postmark-delete-template` | DELETE to Postmark /templates removes an email template. | medium |
| `postmark-delete-domain` | DELETE to Postmark /domains removes a domain configuration. | critical |
| `postmark-delete-sender-signature` | DELETE to Postmark /senders removes a sender signature. | high |
| `postmark-delete-webhook` | DELETE to Postmark /webhooks removes a webhook configuration. | medium |
| `postmark-delete-suppression` | DELETE to Postmark suppressions endpoint removes suppression entries. | high |
| `postmark-delete-message-stream` | DELETE to Postmark /message-streams removes a message stream. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "email.postmark:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "email.postmark:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
