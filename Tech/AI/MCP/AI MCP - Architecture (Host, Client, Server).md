---
tags:
  - ai
  - mcp
  - protocol
  - architecture
created: 2026-07-16
source: https://modelcontextprotocol.io/docs/learn/architecture
---

# AI MCP - Architecture (Host, Client, Server)

> The three-role model, the JSON-RPC 2.0 wire format, and how capability negotiation works. Back to [[AI MCP Guide]].

---

## The Three Roles

| Role | Definition | In practice |
|------|------------|-------------|
| **Host** | The user-facing LLM application. Owns the model, the UI, and the permission decisions. Initiates every connection. | Claude Desktop, Claude Code, VS Code (Copilot), Cursor, Zed, Windsurf |
| **Client** | An internal connector inside the host. **One client per server**, 1:1 lifetime. Not visible to the user. | Not user-facing — instantiated by the host per configured server |
| **Server** | An external process that exposes capabilities (Tools, Resources, Prompts) over the protocol. Stateless w.r.t. other servers. | `filesystem`, `github`, `playwright/mcp`, `postgres`, your own custom server |

**Rule:** one host can talk to many servers, but each connection is mediated by its own dedicated client. Servers are unaware of each other; the host is the only place that composes across them.

```
                         HOST
   ┌──────────────────────────────────────────────┐
   │                                              │
   │   LLM  ◀──────────  Host logic (routes,      │
   │                     perms, transcripts)      │
   │                       ▲       ▲       ▲      │
   │                       │       │       │      │
   │                   Client A  Client B  Client C
   │                       │       │       │      │
   └───────────────────────┼───────┼───────┼──────┘
                           │       │       │
                        stdio     stdio    HTTP
                           │       │       │
                        ┌──▼─┐  ┌──▼─┐  ┌──▼─┐
                        │Srv │  │Srv │  │Srv │
                        │ A  │  │ B  │  │ C  │
                        └────┘  └────┘  └────┘
```

---

## Two Layers of the Spec

The spec explicitly separates:

| Layer | Responsibility |
|-------|----------------|
| **Data layer** | JSON-RPC 2.0 messages, lifecycle handshake, primitives, notifications. Same regardless of transport. |
| **Transport layer** | Bytes on the wire. Message framing, connection setup, authorization. See [[AI MCP - Transports]]. |

This is why the same server code can be exposed over stdio locally and Streamable HTTP remotely with only a transport swap.

---

## JSON-RPC 2.0 — The Wire Format

Every message is a JSON-RPC 2.0 payload. Three shapes:

### Request (expects a response)

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}
```

### Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": { "tools": [ ... ] }
}
```

### Notification (no response — no `id`)

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized"
}
```

### Error

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": { "code": -32601, "message": "Method not found" }
}
```

Standard JSON-RPC error codes apply: `-32700` parse error, `-32600` invalid request, `-32601` method not found, `-32602` invalid params, `-32603` internal error. MCP layers additional semantic errors on top per-method (e.g. tool-call errors use a `isError` result flag rather than a JSON-RPC error — see [[AI MCP - Tools Primitive]]).

---

## Capability Negotiation

At `initialize` time, both sides declare what they support. Neither may use a feature the other didn't advertise.

### Client → server (what the client can *offer* to the server)

```json
"capabilities": {
  "roots":       { "listChanged": true },
  "sampling":    {},
  "elicitation": {}
}
```

### Server → client (what the server *exposes*)

```json
"capabilities": {
  "tools":     { "listChanged": true },
  "resources": { "subscribe": true, "listChanged": true },
  "prompts":   { "listChanged": true },
  "logging":   {}
}
```

`listChanged` = the side promises to emit `notifications/*/list_changed` when its inventory mutates. `subscribe` = resources are subscribable for updates.

The negotiation is **strict on absence**: if a server didn't advertise `tools`, the client MUST NOT call `tools/list`. See [[AI MCP - Lifecycle & Initialization]] for the full handshake.

---

## Who Plays What Role in Real Clients

| Product | Role | Notes |
|---------|------|-------|
| **Claude Desktop** | Host | Original reference host. Stdio only for user-installed servers via config file. |
| **Claude Code** | Host | CLI host. Supports stdio and HTTP. `.claude/settings.json` and project-scoped config. |
| **VS Code (Copilot)** | Host | Ships MCP support in agent mode. |
| **Cursor** | Host | MCP config via `mcp.json` in project or user scope. |
| **Zed / Windsurf** | Host | MCP-capable. |
| **`@modelcontextprotocol/inspector`** | Not a host, a debugger — connects as a client to any server and lets you drive it manually. |

See [[AI MCP - Clients & Ecosystem]] for the primitive-support matrix per host.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Roles | Host (LLM app) · Client (1:1 connector) · Server (integration process) |
| Wire | JSON-RPC 2.0 — requests, responses, notifications, errors |
| Layers | Data (semantic) + Transport (wire) |
| Capabilities | Both sides declare features at init; neither may use un-negotiated features |
| Composition | Host is the only place that talks to multiple servers; servers are isolated |

---

## Related Notes

- [[AI MCP - Lifecycle & Initialization]] — the handshake in detail
- [[AI MCP - Transports]] — how bytes actually move
- [[AI MCP - Tools Primitive]] — what messages look like once the session is up
