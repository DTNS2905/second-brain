---
tags:
  - ai
  - mcp
  - protocol
  - primitives
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18
---

# AI MCP - Tools Primitive

> Model-controlled callable functions — the LLM decides when to invoke them. Back to [[AI MCP Guide]].

---

## Who Controls It

**The model.** Tools are advertised to the LLM as function-call targets; the LLM emits a call intent whenever it decides the tool is useful. Compare with:

| Primitive | Controlled by | Trigger |
|-----------|---------------|---------|
| **Tools** | Model | LLM decides mid-reasoning |
| [[AI MCP - Resources Primitive\|Resources]] | Application (host) | Host loads context deliberately |
| [[AI MCP - Prompts Primitive\|Prompts]] | User | User picks a slash-command |

---

## Methods

| Method | Direction | Purpose |
|--------|-----------|---------|
| `tools/list` | client → server | Enumerate available tools |
| `tools/call` | client → server | Invoke a named tool with arguments |
| `notifications/tools/list_changed` | server → client | Tool inventory has mutated; refetch |

Advertised in the server's `initialize` capability block:

```json
"capabilities": { "tools": { "listChanged": true } }
```

---

## `tools/list` — Discovery

```json
// request
{ "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {} }

// response
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "get_weather",
        "description": "Return current weather for a city.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "city":    { "type": "string" },
            "units":   { "type": "string", "enum": ["metric","imperial"] }
          },
          "required": ["city"]
        }
      }
    ]
  }
}
```

Fields:

- `name` — stable identifier, `snake_case` by convention
- `description` — the prose the LLM reads to decide when to call this tool. **This is prompt real-estate** — treat it like production copy
- `inputSchema` — a **JSON Schema** describing the arguments. Hosts translate this into their model provider's function-calling shape

Server MAY also include an `outputSchema` (spec 2025-06-18+) to describe structured results.

---

## `tools/call` — Invocation

```json
// request
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": { "city": "Hanoi", "units": "metric" }
  }
}

// success response
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      { "type": "text", "text": "Hanoi: 32°C, humid, light rain." }
    ]
  }
}
```

### Content blocks

`content` is an ordered array. Each block has a `type`:

| Block type | Payload |
|------------|---------|
| `text` | `text: string` — for LLM consumption |
| `image` | `data: base64`, `mimeType: string` — for vision-capable models |
| `audio` | `data: base64`, `mimeType: string` |
| `resource` | Embedded resource reference — points at a URI the client can then `resources/read` |
| `resource_link` | Just the pointer, no inline data |

Mixing is fine: `[ text, image, text ]` is valid and common for tools that return an annotated screenshot.

### Structured content (spec 2025-06-18+)

For tools that return JSON, the result can also carry a `structuredContent` field mirroring the tool's `outputSchema`. This is what typed clients consume directly instead of re-parsing the `text` block.

---

## Error Handling — The `isError` Convention

MCP separates **transport errors** (JSON-RPC `error`) from **execution errors** (a normal `result` with `isError: true`).

### ❌ Wrong — surfacing a tool failure as a JSON-RPC error

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "error": { "code": -32000, "message": "Weather API rate-limited" }
}
```

This looks like the *protocol* failed, so the client aborts the whole call. The LLM never sees the failure text.

### ✅ Right — return a result and flag it

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "isError": true,
    "content": [
      { "type": "text", "text": "Weather API rate-limited. Try again in 60s." }
    ]
  }
}
```

The LLM sees the error message as tool output and can decide to retry, apologize, or fall back. JSON-RPC `error` is reserved for genuine protocol violations (unknown method, malformed params).

---

## Naming and Discoverability

Every registered MCP tool ends up as an ID in the host that looks like `mcp__<server>__<tool>`. Example: `mcp__playwright__browser_click`, `mcp__github__create_issue`.

- Names are namespaced by server — no cross-server collisions
- `description` is what the LLM sees; keep it under a few hundred chars and include a use-case hint
- List size matters: a server that advertises 200 tools will bloat every request context sent to the model

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Control | Model-controlled — LLM emits calls itself |
| Discovery | `tools/list` returns name + description + JSON Schema |
| Invocation | `tools/call` with `arguments`; result carries `content` blocks |
| Result types | `text`, `image`, `audio`, `resource`, `resource_link`; plus `structuredContent` |
| Errors | Use `isError: true` in `result`, not a JSON-RPC `error`, so the LLM can react |
| Refresh | `notifications/tools/list_changed` triggers a refetch |

---

## Related Notes

- [[AI MCP - Resources Primitive]] — the app-controlled counterpart
- [[AI MCP - Building a Server]] — a concrete tool registration
- [[AI Agentic Browser Automation - Playwright as Browser Layer]] — `@playwright/mcp` exposes browser actions as MCP tools
