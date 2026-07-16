---
tags:
  - ai
  - mcp
  - protocol
  - primitives
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18
---

# AI MCP - Prompts Primitive

> User-controlled templated messages — usually surfaced as slash-commands. Back to [[AI MCP Guide]].

---

## Who Controls It

**The user.** Prompts are pre-baked message templates the server offers; the host surfaces them as UI (a `/` command menu, a button, a snippet picker). The user picks; the arguments get filled in; the resulting messages are injected into the LLM conversation.

Compare:

| Primitive | Controlled by | Trigger |
|-----------|---------------|---------|
| [[AI MCP - Tools Primitive\|Tools]] | Model | LLM decides mid-reasoning |
| [[AI MCP - Resources Primitive\|Resources]] | Application (host) | Host attaches context |
| **Prompts** | User | User picks a slash-command |

---

## Methods

| Method | Direction | Purpose |
|--------|-----------|---------|
| `prompts/list` | client → server | Enumerate available prompts |
| `prompts/get` | client → server | Materialize a prompt with argument values |
| `completion/complete` | client → server | Autocomplete a prompt argument (also works for resource templates) |
| `notifications/prompts/list_changed` | server → client | Prompt inventory changed |

Capability block:

```json
"capabilities": { "prompts": { "listChanged": true } }
```

---

## `prompts/list` — Discovery

```json
// response
{
  "prompts": [
    {
      "name": "summarize_pr",
      "description": "Summarize a GitHub pull request",
      "arguments": [
        { "name": "repo", "description": "owner/repo", "required": true },
        { "name": "number", "description": "PR number",  "required": true }
      ]
    }
  ]
}
```

`arguments` is a list of expected inputs — not JSON Schema, just names, descriptions, and a `required` flag. The host renders these as form fields, or lets the LLM fill them.

---

## `prompts/get` — Materialization

```json
// request
{
  "method": "prompts/get",
  "params": {
    "name": "summarize_pr",
    "arguments": { "repo": "anthropics/claude-code", "number": "1234" }
  }
}

// response
{
  "result": {
    "description": "Summarize a GitHub pull request",
    "messages": [
      {
        "role": "user",
        "content": {
          "type": "text",
          "text": "Summarize PR #1234 in anthropics/claude-code. Diff:\n\n<diff here>"
        }
      }
    ]
  }
}
```

The server returns a **sequence of ready-to-inject messages**. The host prepends or replaces the conversation with them. Because the server is composing the message, it can pull in fresh context (like the actual PR diff) at prompt-time.

Messages carry the standard content-block types — `text`, `image`, `audio`, embedded `resource` — same as tool results. See [[AI MCP - Tools Primitive]] for the block shape.

---

## Argument Completion — `completion/complete`

Prompts (and resource templates) can advertise arguments; the host can autocomplete them as the user types:

```json
// request
{
  "method": "completion/complete",
  "params": {
    "ref": { "type": "ref/prompt", "name": "summarize_pr" },
    "argument": { "name": "repo", "value": "anth" }
  }
}

// response
{
  "result": {
    "completion": {
      "values": ["anthropics/claude-code", "anthropics/anthropic-sdk-python"],
      "total": 2,
      "hasMore": false
    }
  }
}
```

Same method also completes resource-template variables — pass `ref: { type: "ref/resource", uri: "..." }` instead.

---

## Prompts as Slash-Commands

In practice, hosts surface prompts as `/` commands. In Claude Desktop and Claude Code, a server exposing a `summarize_pr` prompt shows up as `/summarize_pr` in the composer. In VS Code Copilot chat, they appear in the slash-menu. The user fills the arguments inline; the host calls `prompts/get`; the resulting messages become the next turn.

This is why the primitive is **user-controlled**: nothing happens until the user hits `/`. The LLM cannot invoke a prompt.

---

## When to Use Prompts vs Tools

| Situation | Primitive |
|-----------|-----------|
| Repeatable workflow the user will trigger deliberately ("summarize this PR", "review diff for bugs") | **Prompt** |
| Action the LLM should decide about mid-conversation ("check the weather", "search the repo") | **Tool** |
| One-off content injection ("this file") | **Resource** |

Rule of thumb: if the natural UI is a **button** or **`/command`**, model it as a prompt. If it's something the model *decides* to reach for, model it as a tool.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Control | User-controlled — surfaced as slash-commands |
| Discovery | `prompts/list` returns name, description, argument list |
| Materialization | `prompts/get` returns a list of ready-to-inject messages |
| Completion | `completion/complete` autocompletes arguments (also for resource templates) |
| Refresh | `notifications/prompts/list_changed` triggers a refetch |
| Reach for | Repeatable, user-triggered workflows |

---

## Related Notes

- [[AI MCP - Tools Primitive]] — model-controlled counterpart
- [[AI MCP - Resources Primitive]] — completion works the same way
- [[AI MCP - Clients & Ecosystem]] — which hosts render prompts as `/` commands
