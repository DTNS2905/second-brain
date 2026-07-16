---
tags:
  - ai
  - mcp
  - protocol
  - transport
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports
---

# AI MCP - Transports

> The two standard transports (`stdio` + Streamable HTTP), the deprecated HTTP+SSE story, and when to pick which. Back to [[AI MCP Guide]].

---

## Two Standard Transports

The spec defines **exactly two** standard transports. Custom transports are permitted but must round-trip the same JSON-RPC 2.0 messages.

| Transport | Direction | Use for |
|-----------|-----------|---------|
| **`stdio`** | Local subprocess. Host launches the server as a child process, writes JSON-RPC to its stdin, reads from stdout. Stderr is for logs. | Local integrations that ship as a CLI (filesystem, git, Playwright, custom developer tools) |
| **Streamable HTTP** | Single HTTP endpoint the server hosts. Client POSTs requests; server may respond with plain JSON or upgrade the response to a Server-Sent Events stream. | Remote/hosted servers, multi-tenant integrations, browser-based clients |

The spec: "Clients SHOULD support stdio whenever possible." Servers commonly ship in one binary supporting both.

---

## `stdio` — The Default

Every MCP-aware host knows how to launch a subprocess and pipe stdin/stdout. There is no port, no auth negotiation, no TLS. The security boundary is: **whoever installed the config can spawn arbitrary processes**.

```
   host                                 server (child process)
   ────                                 ─────────────────────
   spawn("npx @playwright/mcp")
   │
   ├─ stdin  ───▶  {"jsonrpc":"2.0","id":1,"method":"initialize",...}
   │
   ◀── stdout ──   {"jsonrpc":"2.0","id":1,"result":{...}}
   │
   ├── (repeat) ──▶
   │
   ◀─ stderr ──    server logs, warnings, tracebacks
```

Framing: newline-delimited JSON. One message per line, no trailing whitespace inside a message.

Credentials: pulled from **environment variables** the host passes to the child. Spec says stdio "SHOULD NOT" use OAuth — see [[AI MCP - Security & Authorization]].

---

## Streamable HTTP — The Current Remote Transport

Introduced in spec revision `2025-03-26` (spec [PR #206](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/206)). Design goal: one endpoint, works with plain request/response, upgrades to streaming only when needed.

### The endpoint

The server MUST expose **a single HTTP path** (the "MCP endpoint") that accepts **both POST and GET**.

| Method | Purpose |
|--------|---------|
| `POST /mcp` | Client sends a JSON-RPC request. Server responds with either a JSON body or a `text/event-stream` (SSE) response that streams zero or more messages before closing. |
| `GET /mcp` | Client opens a long-lived SSE stream to receive **server-initiated** messages (notifications, sampling requests, elicitation prompts). Optional — many servers don't need it. |

The server chooses per-request whether to answer inline JSON or upgrade to SSE. That flexibility is the "streamable" in Streamable HTTP.

### Session management via `Mcp-Session-Id`

Servers **MAY** assign a session ID at initialization time by including an `Mcp-Session-Id` response header on the `InitializeResult`. If assigned:

- Client **MUST** echo it on every subsequent request in an `Mcp-Session-Id` header.
- If the client gets a `404` on a request carrying an `Mcp-Session-Id`, it **MUST** start a new session with a fresh `initialize` (no session ID attached).

This lets servers scale horizontally: any node that owns the session can serve the request; expired sessions force a clean re-init.

---

## The Deprecated HTTP+SSE Transport

The original remote transport shipped with spec `2024-11-05` used **two separate endpoints**: one HTTP endpoint for client → server requests, and a separate long-lived SSE endpoint for server → client streaming.

Problems that motivated the replacement:

- **Two-endpoint routing** was awkward for load balancers, CDNs, and serverless runtimes.
- **Persistent SSE connections** are expensive per client and don't map onto request/response infrastructure.
- **Reconnection semantics** were under-specified.

Streamable HTTP collapses everything to one endpoint that behaves like a normal HTTP API in the common case (JSON response) and upgrades to SSE only when the response is streamed. The spec's Backwards Compatibility section refers verbatim to "the deprecated HTTP+SSE transport (from protocol version 2024-11-05)"; the draft changelog reclassifies it "as Deprecated under the feature lifecycle policy."

The TypeScript SDK shipped Streamable HTTP in `v1.10.0` (April 2025).

```
❌ HTTP+SSE (deprecated — 2024-11-05):
   POST /messages   ← client → server requests
   GET  /sse        ← long-lived server → client stream

✅ Streamable HTTP (current — 2025-03-26+):
   POST /mcp        ← request; response may be JSON or SSE
   GET  /mcp        ← (optional) long-lived stream for server-initiated msgs
```

---

## When to Pick Which

| Situation | Transport |
|-----------|-----------|
| Local dev tool the user installs on their machine | **stdio** |
| Server needs filesystem access on the user's box | **stdio** |
| Multi-user hosted service (GitHub SaaS integration, cloud DB, corporate tool) | **Streamable HTTP** |
| Browser-based host / cannot spawn subprocesses | **Streamable HTTP** |
| Server needs OAuth-authenticated user context | **Streamable HTTP** — stdio can't reach an auth server the user has to click through |

Most reference servers (`filesystem`, `git`, `playwright/mcp`) are stdio-first. Managed products (GitHub's official MCP server, Cloudflare's) tend to be Streamable HTTP.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Standard transports | Exactly two: `stdio` + **Streamable HTTP** |
| Streamable HTTP shape | Single endpoint, POST + GET, response may be JSON or SSE-upgraded |
| Sessions | `Mcp-Session-Id` header; 404 forces a fresh `initialize` |
| Deprecated | HTTP+SSE (spec `2024-11-05`), replaced by Streamable HTTP in `2025-03-26` (PR #206) |
| Default | Prefer stdio when possible; HTTP only when the server is remote or user-authenticated |

---

## Related Notes

- [[AI MCP - Lifecycle & Initialization]] — session IDs live in the init handshake
- [[AI MCP - Security & Authorization]] — OAuth 2.1 is HTTP-only; stdio uses env vars
- [[AI MCP - Building a Server]] — official SDKs support both transports
