# Network Guard

The network guard parses destinations, applies policy, and flags exfiltration heuristics. It does not imply transparent OS-level egress blocking unless `aegis doctor` reports active enforcement.

Strict defaults deny direct IPs, localhost, private networks, cloud metadata endpoints, and invalid destinations unless explicitly allowed. Deny beats allow.

Heuristics cover long query strings, base64-like URL components, high-entropy DNS labels, long subdomains, paste sites, webhook/request-bin sites, tunneling services, direct IPs, and secret-like URL values. Secret-like URL values are redacted before audit persistence.

Tests do not require external network access.
