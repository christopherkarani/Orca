# Network

Aegis includes a network decision engine and wrapper/proxy-mediated hooks.

## Modes

- `off`: deny network decisions.
- `allowlist`: allow only configured destinations.
- `ask`: ask interactively where supported.
- `observe`: log decisions.
- `open`: allow decisions.

```sh
./zig-out/bin/aegis run --no-network -- <command>
./zig-out/bin/aegis run --network allowlist --allow-network api.github.com -- <command>
```

## Policy

```yaml
network:
  mode: allowlist
  default: deny
  allow:
    - "api.github.com"
  ask:
    - "*.githubusercontent.com"
  deny:
    - "pastebin.com"
    - "*.ngrok.io"
    - "*.requestbin.net"
  detect_exfiltration:
    dns: true
    long_query_strings: true
    secret_patterns: true
```

## Exfiltration Heuristics

Aegis flags long query strings, base64-like URL parts, high-entropy DNS labels, paste sites, request bins, tunneling services, direct IP destinations, secret-like values, and repeated unknown domains.

## Enforcement Levels

Policy decision is not the same as transparent network enforcement. `aegis doctor` distinguishes decision engine, observation, proxy-mediated enforcement, and transparent enforcement.

## Redaction

URLs are redacted before audit persistence when they contain secret-like material.
