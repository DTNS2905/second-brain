---
tags:
  - ai
  - mcp
  - protocol
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18
---

# AI MCP - Protocol Overview

> What MCP is, why it exists, and how it differs from plain function-calling. Back to [[AI MCP Guide]].

---

## In One Sentence

MCP is an **open protocol** that standardizes how LLM applications connect to external tools and data sources — so one integration works across every compliant client.

Announced by Anthropic in **late 2024** as open-source, MCP is now a joint effort across the AI ecosystem. Spec lives at `modelcontextprotocol.io`, reference implementations at `github.com/modelcontextprotocol`.

---

## The M×N Problem It Solves

Without a protocol, each LLM app has to write custom glue for each integration:

```
❌ Without MCP: M apps × N integrations = M·N adapters

   Claude Desktop ──┬── glue ──▶ filesystem
                   ├── glue ──▶ GitHub
                   ├── glue ──▶ Postgres
                   └── glue ──▶ Slack
   Cursor         ──┬── glue ──▶ filesystem   ← re-implemented
                   ├── glue ──▶ GitHub        ← re-implemented
                   ...
```

```
✅ With MCP: M apps + N servers = M + N implementations

   Claude Desktop ──┐               ┌── filesystem-server
   Cursor         ──┤               ├── github-server
   VS Code        ──┼─── MCP ───────┼── postgres-server
   Zed            ──┤               ├── slack-server
   Windsurf       ──┘               └── playwright-server
```

Every host speaks MCP once; every integration exposes MCP once; the combinations multiply for free.

---

## The "USB-C for LLMs" Framing

The Anthropic launch pitch: **USB-C, but for AI context.** One connector shape, many devices on each side. The value isn't the wire — it's that everybody wires the same way.

Concretely:

- A **host** learns MCP once → can consume every current and future MCP server.
- A **server** author learns MCP once → is instantly usable from every current and future MCP host.
- Model swaps (Claude ↔ GPT ↔ Gemini) do not require re-wiring the integrations.

---

## MCP vs Plain Function-Calling / Tool-Use

| Dimension | Model provider tool-use (OpenAI functions, Anthropic tool-use, Gemini function calling) | MCP |
|-----------|--------------------------------------------------------------------------------------|-----|
| **What it standardizes** | Wire format between **one model** and **one caller** | Wire format between **any host** and **any external integration** |
| **Scope** | A single API call | A stateful session with lifecycle, capabilities, notifications |
| **Direction** | One-way: host → model → tool | Bidirectional: server can request sampling from the host's LLM; can elicit input from the user |
| **Discovery** | Tools listed inline in each request | Servers advertise their tools/resources/prompts at connect time |
| **Deployment** | In-process — you write the tool executor | Out-of-process — the server is a separate binary or HTTP endpoint |
| **Reuse across models** | ❌ Rewrite per provider | ✅ Same server serves any MCP host |
| **State** | Stateless per request | Sessions, subscriptions, `list_changed` notifications |

Function-calling is a **primitive of the model API**. MCP is a **protocol between programs**. They compose: a host receives an MCP `tools/list` result → passes those tools into the model's function-calling API → when the model emits a call → the host dispatches via `tools/call`.

---

## What MCP Does *Not* Do

- MCP is **not a model.** It doesn't run inference. It only pipes context and actions between the model that lives in the host and the world outside.
- MCP is **not an agent framework.** It has no planning loop, no memory, no policy. Those live in the host.
- MCP is **not tied to Claude.** Any LLM can be behind the host. Any host can be non-Anthropic.

---

## Layered Architecture

The spec is split into two layers:

| Layer | What it defines |
|-------|-----------------|
| **Data layer** | JSON-RPC 2.0 message format, lifecycle handshake, the six primitives (Tools/Resources/Prompts/Sampling/Roots/Elicitation), notifications |
| **Transport layer** | How bytes move: `stdio` for local subprocesses, **Streamable HTTP** for remote servers. Includes auth, framing, connection lifecycle |

The same JSON-RPC message shape works across every transport. See [[AI MCP - Architecture (Host, Client, Server)]] and [[AI MCP - Transports]].

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Problem solved | M apps × N integrations → M + N via one shared protocol |
| Pitch | "USB-C for LLMs" — one connector, many devices on each side |
| Wire format | JSON-RPC 2.0 |
| Layers | Data (primitives, lifecycle) + Transport (stdio, Streamable HTTP) |
| vs function-calling | Standardizes across **hosts and integrations**, not just one API call |
| Not a model, not an agent, not Anthropic-only | Just the wiring |

---

## Related Notes

- [[AI MCP - Architecture (Host, Client, Server)]] — the three-role model in detail
- [[AI MCP - Transports]] — how bytes actually move
- [[AI MCP - Clients & Ecosystem]] — which hosts and servers exist today
