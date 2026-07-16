---
tags:
  - ai
  - mcp
  - protocol
  - lifecycle
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle
---

# AI MCP - Lifecycle & Initialization

> The `initialize` handshake, protocol version negotiation, session IDs, and shutdown behavior. Back to [[AI MCP Guide]].

---

## Three Phases

```
   ┌────────────────┐   ┌────────────────┐   ┌────────────────┐
   │  Initialize    │──▶│   Operation    │──▶│    Shutdown    │
   │  (handshake)   │   │ (normal work)  │   │  (transport-   │
   │                │   │                │   │   specific)    │
   └────────────────┘   └────────────────┘   └────────────────┘
```

The handshake is a strict prerequisite: **no other methods may be called before `initialize` completes.**

---

## The Handshake

### Step 1 — Client sends `initialize`

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-06-18",
    "capabilities": {
      "roots":       { "listChanged": true },
      "sampling":    {},
      "elicitation": {}
    },
    "clientInfo": {
      "name": "claude-desktop",
      "version": "0.9.3"
    }
  }
}
```

The client proposes a `protocolVersion` — one it can speak.

### Step 2 — Server responds

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-06-18",
    "capabilities": {
      "tools":     { "listChanged": true },
      "resources": { "subscribe": true, "listChanged": true },
      "prompts":   { "listChanged": true }
    },
    "serverInfo": {
      "name": "playwright-mcp",
      "version": "1.14.0"
    },
    "instructions": "Optional prose hints for the LLM about how to use this server."
  }
}
```

The server either echoes the client's proposed version or picks one it supports.

### Step 3 — Client emits `notifications/initialized`

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized"
}
```

This notification is a signal: *"handshake acknowledged, I'm ready."* Only after this does regular traffic begin.

### Version mismatch

If the client cannot speak the version the server picked, the spec says the client **SHOULD disconnect**. There is no in-band renegotiation.

---

## Capability Negotiation

Both sides advertise what they support. Neither may use un-negotiated features.

```
                       client                              server
                       ──────                              ──────
declares (offers)      roots            ────initialize───▶
                       sampling
                       elicitation
                                                          declares (offers)
                                        ◀────result─────  tools
                                                          resources
                                                          prompts

then, in operation:
  • server may only call sampling/roots/elicitation if client offered them
  • client may only call tools/resources/prompts if server offered them
  • either side may call methods it declared with `listChanged: true`
    → and must send the paired notification when its list mutates
```

See [[AI MCP - Architecture (Host, Client, Server)]] for the full capability shape.

---

## Session IDs (Streamable HTTP only)

For HTTP transports, the server MAY assign a session ID on the `InitializeResult` via an `Mcp-Session-Id` response header. If assigned, the client:

- **MUST** echo it on every subsequent HTTP request
- **MUST** start a new session (fresh `initialize`, no session ID attached) if it ever receives a `404` on a request carrying that ID

This lets stateless HTTP infrastructure (load balancers, serverless nodes) route consistently and reap idle sessions safely. See [[AI MCP - Transports]] for the transport-side details.

---

## Operation Phase

Once initialized, either side sends requests, responses, and notifications freely — bounded by the negotiated capabilities. Notifications include:

| Notification | Direction | Meaning |
|--------------|-----------|---------|
| `notifications/tools/list_changed` | server → client | Refresh your tool inventory |
| `notifications/resources/list_changed` | server → client | Refresh resource inventory |
| `notifications/resources/updated` | server → client | A subscribed resource changed |
| `notifications/prompts/list_changed` | server → client | Refresh prompt inventory |
| `notifications/roots/list_changed` | client → server | Root set has changed |
| `notifications/cancelled` | either | A prior request has been cancelled |
| `notifications/progress` | either | Streaming progress for a long-running request |

The client re-fetches the affected list on `list_changed` — the notification carries no payload.

---

## Shutdown

Shutdown is **transport-specific**:

| Transport | Shutdown |
|-----------|----------|
| **stdio** | The host closes the child's stdin; well-behaved servers exit cleanly on EOF. Host may `SIGTERM` after a timeout. |
| **Streamable HTTP** | The client stops sending requests and drops the SSE stream. Sessions time out server-side. There is no dedicated `shutdown` RPC. |

Errors during operation don't tear down the session by themselves — normal JSON-RPC error responses are just responses. The transport is only closed on a genuine transport failure or an explicit host decision.

---

## Reconnection

- **stdio** — if the child dies, the host respawns it and re-runs the full handshake.
- **Streamable HTTP** — on a dropped SSE stream, the client reconnects the `GET /mcp` stream. If the session ID is still valid, work resumes; if the server returns `404`, the client re-initializes.

Requests in flight when a session dies are lost — the caller must be prepared to retry.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Handshake | `initialize` (client) → response (server) → `notifications/initialized` (client) |
| Version negotiation | Client proposes; server picks; client disconnects if it can't speak the picked version |
| Capabilities | Advertised in both directions at init; strict on absence |
| Session ID | HTTP only, `Mcp-Session-Id` header; 404 → fresh init |
| Shutdown | Transport-specific — no dedicated RPC |
| List-changed | Notification with no payload; consumer re-fetches |

---

## Related Notes

- [[AI MCP - Architecture (Host, Client, Server)]] — where capabilities come from
- [[AI MCP - Transports]] — the session ID story
- [[AI MCP - Roots & Elicitation]] — capabilities that the *client* offers to the server
