---
tags:
  - ai
  - mcp
  - protocol
  - primitives
created: 2026-07-16
source: https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation
---

# AI MCP - Roots & Elicitation

> Two client-offered primitives: **Roots** scope which filesystem locations a server may reach into; **Elicitation** (new in `2025-06-18`) lets a server ask the user for structured input mid-tool-call. Back to [[AI MCP Guide]].

---

## Roots

### What Roots Do

The client tells the server: *"here are the filesystem locations you're allowed to operate on."* Nothing outside those roots is in-scope.

Roots are **not enforcement** — they're a **declaration** the server is expected to respect. Enforcement lives in the transport (stdio's process boundary, HTTP's auth). Roots are the *intent*.

Typical example: opening a project in Claude Code sets a root to the project directory; every server the host launches sees that root as its context boundary.

### Method

| Method | Direction | Purpose |
|--------|-----------|---------|
| `roots/list` | server → client | Ask the client for the current root set |
| `notifications/roots/list_changed` | client → server | Root set has changed; refetch |

Capability block (client side):

```json
"capabilities": { "roots": { "listChanged": true } }
```

### Shape

```json
// response to roots/list
{
  "roots": [
    { "uri": "file:///Users/me/projects/my-app", "name": "my-app" },
    { "uri": "file:///Users/me/projects/shared-lib", "name": "shared-lib" }
  ]
}
```

Every root is a URI. The spec doesn't restrict schemes to `file://` — a host could expose `git://`, `https://api.foo.com/tenants/42/`, etc. — but filesystem paths are the canonical case.

### Why Roots Matter

Without roots, a filesystem or search server has no principled way to know the boundary. It has to guess: `cwd`? `$HOME`? Everything the process can read? Roots give the server an explicit scope so it can:

- Only index files inside the roots (performance)
- Refuse paths outside the roots (safety)
- Emit resource templates parameterized on the root (correctness)

---

## Elicitation (new in spec `2025-06-18`)

### What Elicitation Does

Sometimes a tool needs extra info the LLM can't produce and the user hasn't provided. Elicitation lets the **server** interrupt the tool call and **ask the user directly** through the host's UI — then continue with the answer.

Example flow:

```
   user:  "Deploy the app"
   LLM:   → tool_call: deploy_app
   server:                     ← elicitation/create
                                 "Which environment?"
                                 schema: { env: enum(staging, prod) }
   host:  (shows a picker to the user)
   user:  picks "staging"
   host:                       → { action: "accept", content: { env: "staging" } }
   server:                     (continues the deploy)
   server:                     ← tool_call result
```

Before this primitive, servers had to either fail the call and hope the LLM re-called with the right args, or bake all decisions into arguments up-front. Elicitation makes conversational-but-typed input a first-class step.

### Method — `elicitation/create`

Server-initiated, requires the client to have advertised `"elicitation": {}` at init.

```json
// server → client
{
  "method": "elicitation/create",
  "params": {
    "message": "Which environment do you want to deploy to?",
    "requestedSchema": {
      "type": "object",
      "properties": {
        "env": { "type": "string", "enum": ["staging","prod"] },
        "confirm": { "type": "boolean" }
      },
      "required": ["env"]
    }
  }
}
```

**`requestedSchema` is deliberately restricted:** only flat objects, primitive properties (`string`, `number`, `integer`, `boolean`, `enum`), and standard string formats (`email`, `uri`, `date`, `date-time`). No nested objects, no arrays. The reason: the host has to render the schema into a UI form — flat + primitive maps trivially to native controls; nested/JSON-Schema-in-full does not.

### Response — the Three-Valued `action`

```json
// client → server, after asking the user
{
  "result": {
    "action": "accept",     // or "decline" or "cancel"
    "content": { "env": "staging" }  // present only when action == "accept"
  }
}
```

| Action | Meaning |
|--------|---------|
| `accept` | User provided the answer. `content` matches `requestedSchema`. |
| `decline` | User actively refused. `content` is omitted. |
| `cancel` | User dismissed / walked away. `content` is omitted. |

The server must handle all three. Treating `decline` and `cancel` as if they were `accept` with default values is a bug.

### Why Not Just Another Tool?

You could imagine "make the server call a `ask_user` tool the client provides." Elicitation is better because:

- It's **initiated by the server mid-tool-call**, not by the model. The model doesn't have to be re-prompted to ask.
- It's **synchronous within the current tool invocation** — the tool doesn't need to bail and be re-called.
- It's **typed** — the client renders form controls, not free-text.
- It's **rejectable** — `decline` and `cancel` are first-class outcomes.

### Design Guardrails (from the spec)

- Servers **MUST NOT** use elicitation to solicit secrets, credentials, or personally identifiable information they wouldn't need for the immediate task.
- Clients **SHOULD** clearly display which server is asking, and give a way to always decline.

---

## Both Are Client-Offered

Both Roots and Elicitation are declared in the **client's** capability block at `initialize` time:

```json
"capabilities": {
  "roots":       { "listChanged": true },
  "elicitation": {}
}
```

Servers may only invoke them if the client advertised them. Same pattern as [[AI MCP - Sampling Primitive|Sampling]].

---

## Evolution — MRTR in the Draft Spec

The draft after `2025-11-25` folds all three server-initiated methods — `roots/list`, `sampling/createMessage`, and `elicitation/create` — into a **Multi Round-Trip Requests (MRTR)** pattern. Instead of the server sending a request, the server *returns* an `InputRequiredResult` from its current work item, whose `inputRequests` array lists what it needs. The client answers with a follow-up call. Semantically equivalent; mechanically it means HTTP intermediaries only see client-initiated requests.

Notes here document the `2025-06-18` behavior. If you're implementing against the newer draft, expect the method-name framing to disappear and be replaced by input-request objects inside results.

---

## Summary

| Concept | Roots | Elicitation |
|---------|-------|-------------|
| Introduced | Original | Spec `2025-06-18` |
| Offered by | Client | Client |
| Server method | `roots/list` | `elicitation/create` |
| Payload | List of URIs (typically filesystem) | `message` + restricted JSON Schema |
| Purpose | Scope which locations the server may reach | Ask the user for typed input mid-tool-call |
| Response shape | `roots: [{uri,name}]` | `action: accept/decline/cancel`, `content` on accept |
| Draft change | Folded into MRTR `InputRequiredResult` | Same |

---

## Related Notes

- [[AI MCP - Sampling Primitive]] — the third client-offered primitive
- [[AI MCP - Lifecycle & Initialization]] — where capabilities are declared
- [[AI MCP - Resources Primitive]] — resources living inside a root
