---
tags:
  - ai
  - mcp
  - protocol
  - primitives
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18
---

# AI MCP - Resources Primitive

> Application-controlled read-only context — files, DB rows, API responses. Back to [[AI MCP Guide]].

---

## Who Controls It

**The host application (i.e. the app, not the model).** Resources are the "context injection" primitive: the host decides *which* to include in the prompt and *when*, based on user actions like "attach this file."

Contrast with [[AI MCP - Tools Primitive|Tools]], which the model chooses to invoke.

---

## Methods

| Method | Direction | Purpose |
|--------|-----------|---------|
| `resources/list` | client → server | Enumerate concrete resources |
| `resources/templates/list` | client → server | Enumerate URI-template resources (parameterized) |
| `resources/read` | client → server | Fetch content for a resource URI |
| `resources/subscribe` | client → server | Ask to be notified when a resource changes |
| `resources/unsubscribe` | client → server | Stop notifications |
| `notifications/resources/list_changed` | server → client | Inventory changed; refetch |
| `notifications/resources/updated` | server → client | A subscribed resource changed |

Capability block (server side):

```json
"capabilities": {
  "resources": { "subscribe": true, "listChanged": true }
}
```

---

## Static Resources — `resources/list`

```json
// response
{
  "resources": [
    {
      "uri": "file:///repo/README.md",
      "name": "README",
      "mimeType": "text/markdown",
      "description": "Project readme"
    },
    {
      "uri": "postgres://db/users/schema",
      "name": "users table schema",
      "mimeType": "application/json"
    }
  ]
}
```

Every resource has a stable URI. Schemes are server-defined — `file://`, `git://`, `postgres://`, `https://`, or something custom like `notes://daily/2026-07-16`.

---

## Template Resources — `resources/templates/list`

Parameterized resources use [RFC 6570 URI Templates](https://datatracker.ietf.org/doc/html/rfc6570):

```json
// response
{
  "resourceTemplates": [
    {
      "uriTemplate": "file:///repo/{path}",
      "name": "Repo file",
      "mimeType": "text/plain"
    },
    {
      "uriTemplate": "postgres://db/rows/{table}/{id}",
      "name": "Row by ID"
    }
  ]
}
```

The client expands the template with concrete values, then calls `resources/read`.

---

## `resources/read` — Fetching

```json
// request
{
  "method": "resources/read",
  "params": { "uri": "file:///repo/README.md" }
}

// response
{
  "result": {
    "contents": [
      {
        "uri": "file:///repo/README.md",
        "mimeType": "text/markdown",
        "text": "# My Project\n\n..."
      }
    ]
  }
}
```

Binary content uses `blob: base64` instead of `text: string`. A single `read` can return multiple `contents` items when a URI expands to several pieces (e.g. reading a directory).

---

## Subscriptions

Servers that declare `"subscribe": true` allow the client to watch specific URIs:

```
client                                            server
──────                                            ──────

resources/subscribe {uri: "file:///repo/notes.md"}
─────────────────────────────────────────────────▶

                                                  (file changes on disk)

              ◀── notifications/resources/updated { uri: "file:///repo/notes.md" }

resources/read {uri: "file:///repo/notes.md"}
─────────────────────────────────────────────────▶
                                                  (fresh contents)
```

The `updated` notification is a **kick** — it carries no payload. The client re-reads if it cares.

---

## Static vs Template — Rule of Thumb

| Situation | Use |
|-----------|-----|
| A finite, mostly-stable set the user picks from ("my project files", "recent chats") | Static — `resources/list` |
| Infinite or parameterized space ("any row in the users table") | Template — `resources/templates/list` |

Templates avoid the "list all 4 million rows in Postgres" problem. The client asks for the schema of the template, then plugs in the specific URI when the user or LLM identifies one.

---

## Argument Completion for Templates

Templates pair naturally with `completion/complete` (see [[AI MCP - Prompts Primitive]]). A UI can autocomplete `{path}` or `{table}` by asking the server for suggestions as the user types.

---

## Tools vs Resources — When to Pick Which

The line looks blurry at first ("both return data — what's the difference?"). The clarifying rule:

| Question | If yes → | If no → |
|----------|----------|---------|
| Does the LLM decide whether to fetch this? | [[AI MCP - Tools Primitive\|Tool]] | Resource |
| Does the user (or the host UI) explicitly attach this? | Resource | Tool |
| Does invoking it have side effects (writes, API calls)? | Tool | Resource |

Resources are for **reading known things into the context**. Tools are for **taking actions**, including reads that require the model's judgment about *whether* to run.

Some servers expose the same underlying data both ways: `filesystem` has `read_file` (tool, model chooses) and `file://path` (resource, user attaches).

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Control | Application-controlled — the host decides when to load |
| Discovery | `resources/list` (concrete) + `resources/templates/list` (parameterized) |
| Fetching | `resources/read` returns `contents[]` with `text` or `blob` |
| Subscriptions | Server emits `notifications/resources/updated` on change; client re-reads |
| URI schemes | Server-defined (`file://`, `postgres://`, anything) |
| Vs tools | Resources = passive context; Tools = active operations |

---

## Related Notes

- [[AI MCP - Tools Primitive]] — the model-controlled counterpart
- [[AI MCP - Prompts Primitive]] — completion works the same way
- [[AI MCP - Roots & Elicitation]] — Roots scope which filesystem URIs a server sees
