# Architecture Contracts for Aegis v1.0

This file defines cross-phase contracts so different Codex agents can implement separate phases without creating incompatible modules.

## Design Rule

Aegis should be built as a small core library plus CLI commands. CLI modules should parse input and render output; core modules should implement decisions, sessions, audit, redaction, sandboxing, MCP, and staging.

Avoid embedding business logic in CLI print functions.

## Canonical Decisions

This file is subordinate to `CANONICAL_IMPLEMENTATION_DECISIONS.md`. If a module path or implementation detail differs between the two files, use the canonical decisions file. In particular, production code should converge on separate `src/policy/` and `src/audit/` modules rather than burying those concerns inside `src/core/`.

---


## Module Boundaries

### `src/cli/`

Responsibilities:

- argument parsing;
- help text;
- command routing;
- rendering user-facing output;
- mapping errors to exit codes.

Must not:

- make security decisions directly;
- write audit events directly except via audit APIs;
- parse MCP or policy internals directly.

### `src/core/`

Responsibilities:

- sessions;
- events;
- decisions;
- errors;
- platform capabilities;
- shared utilities;
- supervisor interfaces.

### `src/policy/`

Responsibilities:

- load policy;
- validate policy;
- compile matchers;
- evaluate actions;
- explain decisions.

Must expose a stable API similar to:

```zig
pub const Action = union(enum) {
    env_read: EnvAction,
    file_read: FileAction,
    file_write: FileAction,
    command_exec: CommandAction,
    network_connect: NetworkAction,
    mcp_tool_call: MCPToolAction,
    mcp_resource_read: MCPResourceAction,
    mcp_prompt_get: MCPPromptAction,
    mcp_sampling_request: MCPSamplingAction,
};

pub const Evaluation = struct {
    decision: Decision,
    matched_rule: ?RuleRef,
    explanation: []const u8,
};

pub fn evaluate(policy: *const Policy, action: Action, ctx: EvaluationContext) !Evaluation;
```

The exact names may differ, but every enforcement surface should call one policy evaluation path.

### `src/audit/`

Responsibilities:

- event serialization;
- event hash chain;
- redaction before persistence;
- session summary;
- replay verification.

All persistent logs must go through this module.

### `src/intercept/`

Responsibilities:

- env filtering;
- file/path policy checks;
- command classification;
- network destination classification;
- common enforcement helpers.

### `src/mcp/`

Responsibilities:

- MCP transport abstractions;
- JSON-RPC parsing;
- stdio proxy;
- tool/resource/prompt/sampling mediation;
- MCP manifests.

### `src/sandbox/`

Responsibilities:

- platform backend selection;
- capability reporting;
- OS-specific process/sandbox setup;
- fallback observe/wrapper mode.

### `src/redteam/`

Responsibilities:

- fixture parsing;
- deterministic fixture execution;
- scorecards;
- regression outputs.

---

## Core Data Contracts

### `Decision`

Every security-relevant action resolves to one of:

```text
allow
ask
deny
observe
redact
stage
broker
```

`Decision` must include:

- result;
- reason;
- matched rule if any;
- risk score if applicable;
- whether user approval is required;
- whether CI mode may proceed.

### `Event`

Every event must include:

- schema version;
- session ID;
- event ID;
- timestamp;
- event type;
- actor;
- target;
- optional decision;
- redactions applied;
- previous hash;
- event hash.

Events must be serialized deterministically for hash-chain verification.

### `Policy`

Policy must be versioned:

```yaml
version: 1
```

Policy must define defaults for:

- mode;
- env;
- files;
- commands;
- network;
- MCP;
- audit.

Invalid policy fails closed unless explicitly checking in a non-enforcing command.

### `BackendCapabilities`

Every backend must report actual capabilities, not desired capabilities.

Suggested capability states:

```text
active
partial
observe
limited
unavailable
unknown
```

Do not use boolean-only capability reporting for user-facing output; booleans hide important differences.

---

## MCP Protocol Contract

Aegis must treat MCP messages as JSON-RPC 2.0 messages over a transport.

For stdio transport:

- server is launched as a subprocess;
- server reads JSON-RPC messages from stdin;
- server writes JSON-RPC messages to stdout;
- messages are UTF-8;
- messages are newline-delimited;
- messages must not contain embedded newlines;
- server stderr may contain logs and should not be interpreted as protocol messages;
- stdout must contain only valid MCP messages.

Aegis must enforce maximum message size, maximum schema depth, and safe handling of invalid JSON.

---

## Audit Contract

The audit module must be the only persistent event writer.

Before writing any event:

1. normalize event fields;
2. redact secrets;
3. serialize deterministically;
4. compute hash chain;
5. append to `events.jsonl`.

Replay verification must detect:

- modified event;
- deleted event;
- reordered event;
- invalid final summary hash.

---

## Filesystem Staging Contract

The staging engine must expose functions equivalent to:

```zig
stageCreate(session, workspace_path, bytes)
stageUpdate(session, workspace_path, bytes)
stageDelete(session, workspace_path)
listStaged(session)
diffStaged(session, optional_path)
applyStaged(session, optional_path)
discardStaged(session, optional_path)
```

Every staged entry must include:

- original path;
- normalized workspace-relative path;
- staged path;
- original hash if file existed;
- staged hash;
- operation;
- timestamp;
- actor if known.

---

## Command Guard Contract

The command guard must separate:

1. parsing/tokenization;
2. risk classification;
3. policy evaluation;
4. approval handling;
5. execution/delegation.

Shims must avoid recursion. A shim calling `aegis shim exec -- git status` must resolve the real `git` binary without resolving back to the shim.

---

## Network Guard Contract

Network policy must separate:

1. destination parsing;
2. policy matching;
3. exfiltration heuristics;
4. enforcement mechanism;
5. audit event emission.

User-facing output must distinguish:

- transparent OS enforcement;
- proxy-mediated enforcement;
- wrapper-mediated enforcement;
- observe-only logging.

---

## Dependency Contract

New dependencies require a short dependency note in the phase handoff. Avoid dependencies where Zig stdlib is sufficient.

Security-sensitive parsers must enforce limits:

- max bytes;
- max nesting depth;
- max number of fields/items;
- max number of tools/resources/prompts;
- timeout or bounded read behavior where applicable.

---

## Test Contract

Every security feature needs at least one positive and one negative test.

Examples:

- allowed path and denied path;
- allowed command and denied command;
- allowed MCP tool and denied MCP tool;
- redacted secret and non-secret preserved;
- valid policy and invalid policy;
- untampered audit and tampered audit.
