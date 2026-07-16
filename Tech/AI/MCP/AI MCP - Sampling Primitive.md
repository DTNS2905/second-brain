---
tags:
  - ai
  - mcp
  - protocol
  - primitives
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18
---

# AI MCP - Sampling Primitive

> The reverse-direction primitive: the **server** asks the **host's LLM** to complete a message. Back to [[AI MCP Guide]].

---

## The Reversal

Every other primitive so far has the client calling the server. Sampling flips the arrow:

```
   normal:      client ──── tools/call ────▶ server
   sampling:    server ──── sampling/createMessage ────▶ client (which runs the LLM)
```

The server is asking, *"please have your LLM answer this for me — and hand me back the completion."*

Client-offered primitive. Servers may only use it if the client advertised `"sampling": {}` at init. See [[AI MCP - Lifecycle & Initialization]].

---

## Method — `sampling/createMessage`

```json
// server → client
{
  "method": "sampling/createMessage",
  "params": {
    "messages": [
      {
        "role": "user",
        "content": { "type": "text", "text": "Classify this bug report: <text>" }
      }
    ],
    "modelPreferences": {
      "hints": [{ "name": "claude-3-5-sonnet" }],
      "costPriority": 0.3,
      "speedPriority": 0.4,
      "intelligencePriority": 0.9
    },
    "systemPrompt": "You are a bug triage classifier.",
    "maxTokens": 500,
    "includeContext": "thisServer"
  }
}

// client → server (after LLM runs + human approves)
{
  "result": {
    "role": "assistant",
    "content": { "type": "text", "text": "category=performance; severity=high" },
    "model": "claude-3-5-sonnet-20241022",
    "stopReason": "end_turn"
  }
}
```

Key fields:

| Field | Meaning |
|-------|---------|
| `messages` | The conversation for the client's LLM to complete. |
| `modelPreferences.hints` | Server-suggested model names. Hints, not mandates. |
| `costPriority` / `speedPriority` / `intelligencePriority` | Weights 0..1 the client uses to pick a model. |
| `systemPrompt` | Server-supplied system prompt. Client MAY override or ignore. |
| `includeContext` | `"none"`, `"thisServer"`, or `"allServers"` — how much of the current session's context to inject. |
| `maxTokens` | Cap on the completion length. |

The client is the boss: it decides which model actually runs, whether the system prompt is honored, and whether the request goes through at all.

---

## Human-in-the-Loop is a Feature, Not a Bug

The spec is deliberate: sampling is expected to be gated by the user. A well-behaved client shows the user:

- Which server is asking
- What messages the server proposed
- What model + system prompt would be used
- Options to **approve, edit, or reject** — for both the request and the response

The reason: a compromised or malicious server that could freely invoke the user's LLM would have a free jailbreak channel plus a way to spend the user's API budget. Gating keeps the trust boundary honest — see [[AI MCP - Security & Authorization]].

---

## Use Cases

Sampling makes sense when the **server** needs LLM judgment that it doesn't have local access to:

- A "sequential thinking" server that recursively asks the LLM to expand a plan
- A code-review server that asks the LLM to grade a diff before deciding what to report
- A data-analysis server that generates natural-language summaries of query results
- Any agentic sub-task inside a server that shouldn't ship its own model dependency

The alternative is embedding a model client (Anthropic SDK / OpenAI SDK) inside the server — which forces model choice on the user, requires the server to hold API keys, and duplicates cost. Sampling delegates all of that to the host.

---

## What Sampling Is *Not* For

- **Not for tool results.** If your server needs the LLM to interpret data, return the raw data as a tool result and let the *outer* conversation handle it.
- **Not for prompt orchestration the user should see.** If a user-facing thought belongs in the conversation, put it there — don't do it in a hidden sampling loop.
- **Not for state you could keep in the server.** Sampling per step is expensive; batch when possible.

---

## Evolution — MRTR in the Draft Spec

The current-stable protocol (`2025-06-18`) has the server initiate `sampling/createMessage` directly. The draft after `2025-11-25` introduces the **Multi Round-Trip Requests (MRTR)** pattern: instead of a server-initiated request, the server returns an `InputRequiredResult` with `resultType: "input_required"` whose `inputRequests` field lists what it needs (sampling, roots, elicitation).

Semantically equivalent, mechanically simpler: HTTP infrastructure only ever sees client→server requests. When these notes are updated to the newer revision, expect `sampling/createMessage` (and its siblings) to move from "server-initiated method" to "input request inside an MRTR envelope."

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Direction | Server → client — the server asks the host's LLM to complete a message |
| Client capability | Server may only call it if the client advertised `"sampling": {}` at init |
| Model choice | Server hints; client decides |
| Human-in-the-loop | Expected default — user approves the request, may edit the response |
| Use for | Agentic sub-tasks inside a server without shipping its own model dependency |
| Draft evolution | MRTR reframes server-initiated sampling as an `InputRequiredResult` |

---

## Related Notes

- [[AI MCP - Roots & Elicitation]] — the other client-offered primitives, with the same MRTR-in-draft caveat
- [[AI MCP - Security & Authorization]] — why sampling is gated by user approval
- [[AI MCP - Lifecycle & Initialization]] — where the client declares its `sampling` capability
