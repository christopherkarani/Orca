# MCP

Aegis supports stdio MCP proxying for servers launched through Aegis.

## Inspect

```sh
./zig-out/bin/aegis mcp inspect --name demo --command python3 -- fixtures/mcp/fake_server.py
```

`inspect` initializes the server, sends `notifications/initialized`, calls `tools/list`, and reports risk findings.

## Proxy

```sh
./zig-out/bin/aegis mcp proxy --name demo --policy policies/presets/mcp-dev.yaml --command python3 -- fixtures/mcp/fake_server.py
```

The proxy reads client JSON-RPC from stdin and writes protocol responses to stdout. Server stderr is logs, not protocol.

## Manifest Support

```sh
./zig-out/bin/aegis mcp manifest check examples/mcp/demo-manifest.yaml
./zig-out/bin/aegis mcp proxy --name demo --manifest examples/mcp/demo-manifest.yaml --command python3 -- fixtures/mcp/fake_server.py
```

Manifest defaults only apply when the launched command and manifest binding match.

## Mediated Methods

Aegis handles:

- `tools/list`
- `tools/call`
- `resources/list`
- `resources/read`
- `prompts/list`
- `prompts/get`
- sampling requests, default-denied unless policy permits them

## Protocol Warning

Stdio MCP stdout must contain only newline-delimited JSON-RPC protocol messages. Human logs belong on stderr.

## Remote/HTTP Status

Remote HTTP MCP, OAuth, and hosted gateway support are not v1.0 defaults. Use stdio proxying unless docs for a future phase say otherwise.

## Limitations

Aegis mediates MCP traffic that passes through `aegis mcp proxy`. It does not protect an MCP server launched directly by another client.
