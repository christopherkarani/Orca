# MCP

Aegis mediates stdio MCP traffic that passes through `aegis mcp proxy`.

MCP stdout is protocol-only. Human/debug logs must go to stderr or audit, not MCP stdout. Messages are newline-delimited UTF-8 JSON-RPC and are bounded by the configured MCP message limit.

Aegis rejects invalid JSON, embedded newlines, oversized messages, malformed JSON-RPC IDs, suspicious or oversized `tools/list` responses, and server responses with mismatched IDs. Tool calls, resource reads, prompt gets, and sampling requests are policy-mediated. Sampling is default-deny unless policy or a verified manifest allows it.

Remote/HTTP MCP is not claimed as production-enforced unless a future backend explicitly implements and documents it.
