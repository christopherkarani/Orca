# Compatibility Matrix

Use `orca doctor` for the authoritative report on a specific machine. This matrix uses Orca capability vocabulary: `active`, `partial`, `wrapper-only`, `observe-only`, `limited`, `unavailable`, and `unsupported`.

| Feature | Linux | macOS | Windows |
|---|---|---|---|
| Launch arbitrary command | active | active | active |
| Env filtering | active | active | active |
| Secret redaction | active | active | active |
| Audit/replay | active | active | active |
| Staged writes | active | active | active |
| Command guard | wrapper-only | wrapper-only | wrapper-only |
| Shell/PATH shims | wrapper-only | wrapper-only | wrapper-only |
| MCP stdio proxy | active | active | active |
| MCP manifests | active | active | active |
| MCP sampling controls | active | active | active |
| Network decision engine | active | active | active |
| Proxy-mediated network enforcement | unavailable | unavailable | unavailable |
| Transparent network enforcement | observe-only | limited | limited |
| Transparent filesystem enforcement | unavailable; staged writes active | limited | limited |
| Strong sandbox | unavailable | unavailable | unavailable |
| Process cleanup | active or partial | active | partial |
| Red-team suite | active | active | active |

`wrapper-only` means Orca-mediated command paths are protected by shims or wrappers. It is not transparent OS enforcement.
