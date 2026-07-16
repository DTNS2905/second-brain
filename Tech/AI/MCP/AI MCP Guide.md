---
tags:
  - ai
  - mcp
  - protocol
  - anthropic
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18
---

# AI MCP Guide

> The **Model Context Protocol** — an open, JSON-RPC 2.0 protocol from Anthropic that standardizes how LLM apps consume external tools and data. One host ↔ many servers, one client per server. Target spec revision: **2025-06-18**.

---

## Contents

| Note | Covers |
|------|--------|
| [[AI MCP - Protocol Overview]] | What MCP is, why it exists, the M×N problem, "USB-C for LLMs" framing, vs plain tool-use |
| [[AI MCP - Architecture (Host, Client, Server)]] | Three-role model, JSON-RPC 2.0 wire format, capability negotiation, data + transport layers |
| [[AI MCP - Transports]] | `stdio` and **Streamable HTTP**; deprecation of HTTP+SSE (spec PR #206); when to pick which |
| [[AI MCP - Lifecycle & Initialization]] | `initialize` handshake, `notifications/initialized`, protocol version negotiation, session IDs |
| [[AI MCP - Tools Primitive]] | Model-controlled callable functions; `tools/list`, `tools/call`; JSON Schema inputs |
| [[AI MCP - Resources Primitive]] | Application-controlled read-only data; URI templates; `resources/list`, `resources/read`, subscriptions |
| [[AI MCP - Prompts Primitive]] | User-controlled templated messages exposed as slash-commands; argument completion |
| [[AI MCP - Sampling Primitive]] | Server → client direction; `sampling/createMessage`; model hints; human-in-the-loop |
| [[AI MCP - Roots & Elicitation]] | Filesystem-context boundaries (Roots) + mid-tool-call user input (Elicitation, new in 2025-06-18) |
| [[AI MCP - Security & Authorization]] | OAuth 2.1 for HTTP transports; PKCE, PRM (RFC 9728), DCR (RFC 7591), Resource Indicators (RFC 8707) |
| [[AI MCP - Building a Server]] | TypeScript + Python SDKs; minimal server; Claude Desktop config; MCP Inspector |
| [[AI MCP - Clients & Ecosystem]] | Claude Desktop, Claude Code, VS Code, Cursor, Zed, Windsurf; primitive-support matrix; reference servers |

---

## Vocabulary (define once, use everywhere)

| Term | Meaning |
|------|---------|
| **Host** | The user-facing LLM application — e.g. Claude Desktop, Claude Code, VS Code Copilot, Cursor. Initiates connections and hosts the model. |
| **Client** | A connector inside the host, **one per server**, that owns the JSON-RPC session with that server. Not user-visible. |
| **Server** | An external process that exposes capabilities (Tools, Resources, Prompts) to the host. Local (stdio) or remote (HTTP). |
| **Primitive** | A first-class protocol feature. Six of them: three server-offered (Tools, Resources, Prompts) + three client-offered (Sampling, Roots, Elicitation). |
| **Tool** | A model-controlled callable function. The LLM decides when to invoke it. |
| **Resource** | An application-controlled piece of read-only context — a file, DB row, API response. The host decides when to load it. |
| **Prompt** | A user-controlled templated message, usually surfaced as a slash-command. |
| **Transport** | The wire channel: `stdio` (local subprocess) or **Streamable HTTP** (single endpoint with optional SSE). |
| **Capability** | A feature flag declared during the `initialize` handshake — each side advertises what it supports. |
| **Spec revision** | Dated versions of the protocol (e.g. `2025-06-18`). Negotiated at init. |

---

## When to Reach for MCP

Reach for MCP when you need to **wire an LLM to an external system** and want that wiring to be reusable across models and clients.

- Building a tool once and having it work in Claude Desktop, Claude Code, VS Code Copilot, Cursor, and Zed — without rewriting per host — is the payoff.
- If you only need tool-use inside your own bespoke agent and won't reuse the tool elsewhere, plain function-calling against your model provider's SDK is simpler.

Compare to plain tool-use: MCP is a **protocol**, not an API. Function-calling standardizes the wire format between one model and one caller. MCP standardizes the wire format between **any** LLM and **any** integration — decoupling the M models from the N integrations. See [[AI MCP - Protocol Overview]].

---

## Mental Model

```
┌──────────────────────────┐          ┌────────────┐
│         HOST             │          │  Server A  │  (e.g. filesystem)
│  (Claude Desktop, etc.)  │◀───┐     └────────────┘
│                          │    │
│  ┌────────────────────┐  │    │     ┌────────────┐
│  │       LLM          │  │    ├────▶│  Server B  │  (e.g. GitHub)
│  └────────────────────┘  │    │     └────────────┘
│                          │    │
│  ┌──────┐ ┌──────┐ ┌───┐ │    │     ┌────────────┐
│  │Cli.A │ │Cli.B │ │...│─┼────┘     │  Server C  │  (e.g. Playwright)
│  └──────┘ └──────┘ └───┘ │◀─────────│            │
└──────────────────────────┘          └────────────┘
   1 host · N clients · N servers · 1 client per server
```

Every arrow is JSON-RPC 2.0 over either stdio or Streamable HTTP. The LLM never speaks to a server directly — it emits a tool-call intent, the host's client dispatches it, and the server replies. See [[AI MCP - Architecture (Host, Client, Server)]].

---

## Spec Revisions at a Glance

| Revision | Notable change |
|----------|----------------|
| `2024-11-05` | Original public spec. HTTP+SSE transport. |
| `2025-03-26` | **Streamable HTTP** replaces HTTP+SSE (spec [PR #206](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/206)). |
| **`2025-06-18`** | **Elicitation** primitive added. OAuth 2.1 authorization framework formalized. **← target of these notes.** |
| `2025-11-25` | Newer stable revision (referenced in draft changelog). |
| draft | **MRTR** (Multi Round-Trip Requests) pattern — replaces server-initiated `roots/list` / `sampling/createMessage` / `elicitation/create` with an `InputRequiredResult`. |

These notes target **`2025-06-18`** because it is the last revision where every claim below was verified end-to-end against the spec. Where a change in `2025-11-25` or the draft materially affects a topic, the affected note calls it out in an "Evolution" section.

---

## Related Notes

- [[AI Agentic Browser Automation - Playwright as Browser Layer]] — Playwright ships an MCP server (`@playwright/mcp`) that plugs into any MCP-aware host
- [[AI Agentic Browser Automation Guide]] — the adjacent topic on LLM-driven browser agents; MCP is one of the tool-wiring stories that made it practical
