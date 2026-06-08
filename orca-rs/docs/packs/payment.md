# Payment Packs

This document describes packs in the `payment` category.

## Packs in this Category

- [Stripe](#paymentstripe)
- [Braintree](#paymentbraintree)
- [Square](#paymentsquare)

---

## Stripe

**Pack ID:** `payment.stripe`

Protects against destructive Stripe CLI/API operations like deleting webhook endpoints and customers, or rotating API keys without coordination.

### Keywords

Commands containing these keywords are checked against this pack:

- `stripe`
- `api.stripe.com`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `stripe-listen` | `\bstripe\b(?:\s+--?\S+(?:\s+\S+)?)*\s+listen\b` |
| `stripe-customers-list` | `\bstripe\b(?:\s+--?\S+(?:\s+\S+)?)*\s+customers\s+list\b` |
| `stripe-products-list` | `\bstripe\b(?:\s+--?\S+(?:\s+\S+)?)*\s+products\s+list\b` |
| `stripe-payments-list` | `\bstripe\b(?:\s+--?\S+(?:\s+\S+)?)*\s+payments\s+list\b` |
| `stripe-logs-tail` | `\bstripe\b(?:\s+--?\S+(?:\s+\S+)?)*\s+logs\s+tail\b` |
| `stripe-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*api\.stripe\.com.*\/v1\/))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*api\.stripe\.com.*\/v1\/` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `stripe-webhook-endpoints-delete` | stripe webhook_endpoints delete removes a Stripe webhook endpoint, breaking notifications. | high |
| `stripe-customers-delete` | stripe customers delete permanently deletes a customer. | critical |
| `stripe-products-delete` | stripe products delete permanently deletes a product. | high |
| `stripe-prices-delete` | stripe prices delete permanently deletes a price. | high |
| `stripe-coupons-delete` | stripe coupons delete permanently deletes a coupon. | high |
| `stripe-api-keys-roll` | stripe api_keys roll rotates API keys; coordinate to avoid outages. | medium |
| `stripe-api-delete` | Stripe API DELETE calls remove Stripe resources. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "payment.stripe:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "payment.stripe:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Braintree

**Pack ID:** `payment.braintree`

Protects against destructive Braintree/PayPal payment operations like deleting customers or cancelling subscriptions via API/SDK calls.

### Keywords

Commands containing these keywords are checked against this pack:

- `braintree`
- `braintreegateway.com`
- `braintree.`
- `gateway.customer.`
- `gateway.merchant_account.`
- `gateway.payment_method.`
- `gateway.subscription.`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `braintree-customer-find` | `\bbraintree\.Customer\.find\b` |
| `braintree-customer-search` | `\bgateway\.customer\.search\b` |
| `braintree-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*braintreegateway\.com))curl\s+.*(?:-X\s*\|--request(?:=\|\s+))GET\b.*braintreegateway\.com` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `braintree-api-delete` | Braintree API DELETE calls remove payment resources (customers, webhooks, etc.). | high |
| `braintree-customer-delete` | braintree.Customer.delete permanently deletes a Braintree customer. | critical |
| `braintree-gateway-customer-delete` | gateway.customer.delete permanently deletes a Braintree customer. | critical |
| `braintree-merchant-account-delete` | gateway.merchant_account.delete removes a Braintree merchant account. | critical |
| `braintree-payment-method-delete` | gateway.payment_method.delete removes a stored payment method. | high |
| `braintree-subscription-cancel` | gateway.subscription.cancel cancels a subscription, impacting billing. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "payment.braintree:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "payment.braintree:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Square

**Pack ID:** `payment.square`

Protects against destructive Square CLI/API operations like deleting catalog objects or customers (which can break payment flows).

### Keywords

Commands containing these keywords are checked against this pack:

- `square`
- `api.squareup.com`
- `connect.squareup.com`
- `connect.squareupsandbox.com`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `square-catalog-list` | `\bsquare\b(?:\s+--?\S+(?:\s+\S+)?)*\s+catalog\s+list\b` |
| `square-customers-list` | `\bsquare\b(?:\s+--?\S+(?:\s+\S+)?)*\s+customers\s+list\b` |
| `square-api-get` | `(?i)^(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))DELETE\b)(?=.*https?://(?:api\.squareup\.com\|connect\.squareup(?:sandbox)?\.com)))(?!(?=.*(?:-X\s*\|--request(?:=\|\s+))POST\b)(?=.*https?://(?:api\.squareup\.com\|connect\.squareup(?:sandbox)?\.com)[^\s'"]*/v2/catalog/batch-delete))\bcurl\b(?:[^\n]*?(?:-X\s*\|--request(?:=\|\s+))GET\b[^\n]*?https?://(?:api\.squareup\.com\|connect\.squareup(?:sandbox)?\.com)\|[^\n]*?https?://(?:api\.squareup\.com\|connect\.squareup(?:sandbox)?\.com)[^\n]*?(?:-X\s*\|--request(?:=\|\s+))GET\b)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `square-catalog-delete` | square catalog delete removes catalog objects, impacting products and inventory. | high |
| `square-api-delete-catalog-object` | Square API DELETE /v2/catalog/object/{id} deletes a catalog object. | high |
| `square-api-batch-delete-catalog-objects` | Square API POST /v2/catalog/batch-delete deletes multiple catalog objects. | critical |
| `square-api-delete-customer` | Square API DELETE /v2/customers/{id} deletes a customer. | critical |
| `square-api-delete-payment-link` | Square API DELETE /v2/online-checkout/payment-links/{id} deletes a payment link. | high |
| `square-api-delete-location` | Square API DELETE /v2/locations/{id} deletes a location. | critical |
| `square-api-delete-webhook-subscription` | Square API DELETE /v2/webhooks/subscriptions/{id} deletes a webhook subscription. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "payment.square:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "payment.square:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
