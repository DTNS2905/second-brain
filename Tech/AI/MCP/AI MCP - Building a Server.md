---
tags:
  - ai
  - mcp
  - protocol
  - sdk
  - typescript
  - python
created: 2026-07-16
source: https://github.com/modelcontextprotocol/typescript-sdk
---

# AI MCP - Building a Server

> Concrete walkthrough — SDKs, a minimal TypeScript server that exposes one tool and one resource, the Claude Desktop config file, and debugging with the MCP Inspector. Back to [[AI MCP Guide]].

---

## Official SDKs

Maintained under `github.com/modelcontextprotocol`:

| Language | Package | Notes |
|----------|---------|-------|
| **TypeScript** | `@modelcontextprotocol/sdk` | Reference; Streamable HTTP shipped in v1.10.0 (Apr 2025). |
| **Python** | `mcp` (PyPI) | Reference; FastMCP-style decorator API. |
| **Java** | `io.modelcontextprotocol.sdk` | Official. |
| **Kotlin** | official | Official. |
| **C#** | official | Official. |
| **Go** | official | Official. |
| **Ruby** | community-led, adopted | Actively developed. |
| **Rust** | community-led, adopted | Actively developed. |

If the SDK matters for a project, check the repo's README for its current transport + primitive coverage — feature parity is *close* but not *exact* across languages.

---

## Minimal TypeScript Server

Ship a server that exposes one tool (`get_weather`) and one resource (a static greeting file).

```bash
npm init -y
npm i @modelcontextprotocol/sdk zod
```

```ts
// server.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const server = new Server(
  { name: "example-server", version: "0.1.0" },
  { capabilities: { tools: {}, resources: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_weather",
      description: "Return current weather for a city.",
      inputSchema: {
        type: "object",
        properties: { city: { type: "string" } },
        required: ["city"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  if (params.name === "get_weather") {
    const city = params.arguments?.city as string;
    return {
      content: [{ type: "text", text: `${city}: 32°C, humid.` }],
    };
  }
  return {
    isError: true,
    content: [{ type: "text", text: `Unknown tool: ${params.name}` }],
  };
});

server.setRequestHandler(ListResourcesRequestSchema, async () => ({
  resources: [
    { uri: "greeting://hello", name: "Greeting", mimeType: "text/plain" },
  ],
}));

server.setRequestHandler(ReadResourceRequestSchema, async ({ params }) => ({
  contents: [
    { uri: params.uri, mimeType: "text/plain", text: "Hello from MCP!" },
  ],
}));

await server.connect(new StdioServerTransport());
```

Run it: `node --experimental-strip-types server.ts` (or transpile with `tsc`).

---

## Wiring Into Claude Desktop

Config file location (macOS): `~/Library/Application Support/Claude/claude_desktop_config.json`. Windows: `%APPDATA%\Claude\claude_desktop_config.json`.

```json
{
  "mcpServers": {
    "example": {
      "command": "node",
      "args": ["/Users/me/example-server/dist/server.js"],
      "env": {
        "WEATHER_API_KEY": "sk-..."
      }
    }
  }
}
```

Key fields:

- `command` + `args` — Claude Desktop spawns this as a child process and speaks stdio
- `env` — extra environment vars for the child (this is how stdio servers receive credentials)

Restart Claude Desktop to pick up config changes. On next launch, the server's tools and resources appear in the composer.

**Claude Code** uses a different config surface — `.claude/settings.json` (project) or `~/.claude/settings.json` (user) with the same `mcpServers` shape plus support for HTTP transport entries.

---

## Debugging With the MCP Inspector

The [MCP Inspector](https://github.com/modelcontextprotocol/inspector) is an interactive debugger that connects to any MCP server as a client — no host required.

```bash
npx @modelcontextprotocol/inspector node /path/to/server.js
```

It opens a local web UI where you can:

- See the negotiated capabilities
- List and call tools with arbitrary arguments
- List and read resources
- Watch notifications stream in
- Inspect the raw JSON-RPC traffic in both directions

Use it before wiring the server into Claude Desktop — you'll catch schema mistakes, error-handling bugs, and slow calls in seconds rather than through the host's UI.

---

## Iteration Loop

A typical build cycle:

```
   1. Edit server code
   2. Run Inspector → verify tools/resources/prompts
   3. Test edge cases (missing args, bad inputs, isError paths)
   4. Wire into Claude Desktop or Claude Code
   5. Verify LLM discovers and calls it correctly
   6. Tighten `description` for tools until the LLM reliably picks the right one
```

Step 6 is where most polish happens. The `description` is prompt real-estate — the LLM only calls tools whose descriptions it can map to the current task. Iterate on wording like you would on production copy.

---

## HTTP Transport Variant

For Streamable HTTP, swap the transport:

```ts
import express from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

const app = express();
app.use(express.json());

app.all("/mcp", async (req, res) => {
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: () => crypto.randomUUID(),
  });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
});

app.listen(3000);
```

Then plug **OAuth 2.1** in front — see [[AI MCP - Security & Authorization]] for the mandatory bits (PRM, PKCE, resource indicators).

---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Tool `description` is too vague → LLM doesn't call it | Rewrite as "use this when the user asks X" |
| Returning a JSON-RPC `error` for a tool failure | Return `{ isError: true, content: [...] }` instead — see [[AI MCP - Tools Primitive]] |
| Server dies silently under stdio | Log to **stderr** — stdout is the JSON-RPC channel, anything else there breaks framing |
| Streamable HTTP session drifts | Rotate `Mcp-Session-Id` cleanly; return `404` on stale sessions |
| Nested/complex elicitation schema fails to render | Elicitation's `requestedSchema` is flat + primitives only — see [[AI MCP - Roots & Elicitation]] |

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Official SDKs | TypeScript, Python, Java, Kotlin, C#, Go (+ community Ruby, Rust) |
| Minimal server | Register tool/resource handlers → `server.connect(StdioServerTransport)` |
| Claude Desktop config | `~/Library/Application Support/Claude/claude_desktop_config.json` with an `mcpServers` block |
| Debugger | `npx @modelcontextprotocol/inspector <cmd>` — web UI that acts as a client |
| Loop | Inspector first, host second; iterate `description` last |
| HTTP variant | Same handlers, swap transport, add OAuth 2.1 |

---

## Related Notes

- [[AI MCP - Tools Primitive]] — the wire shape for what you're registering
- [[AI MCP - Security & Authorization]] — mandatory bits when going HTTP
- [[AI MCP - Clients & Ecosystem]] — where the server can plug in besides Claude Desktop
