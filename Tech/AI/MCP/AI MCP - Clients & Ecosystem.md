---
tags:
  - ai
  - mcp
  - protocol
  - ecosystem
created: 2026-07-16
source: https://github.com/modelcontextprotocol/servers
---

# AI MCP - Clients & Ecosystem

> Which hosts speak MCP today, which primitives each supports, and the reference-server catalog. Back to [[AI MCP Guide]].

---

## Hosts (MCP Clients)

The hosts that ship MCP support as of writing:

| Host | Transport | Notes |
|------|-----------|-------|
| **Claude Desktop** | stdio | The original reference host. Config in `claude_desktop_config.json`. Broadest primitive support. |
| **Claude Code** | stdio + HTTP | CLI. `.claude/settings.json` (project) or `~/.claude/settings.json` (user). Supports HTTP servers via `url` entries. |
| **VS Code (Copilot Chat)** | stdio + HTTP | Agent-mode. Per-workspace config. |
| **Cursor** | stdio + HTTP | `mcp.json` in project or user scope. |
| **Zed** | stdio | AI Assistant panel; MCP support via extensions. |
| **Windsurf** | stdio + HTTP | Codeium's IDE. |
| **Continue.dev** | stdio | Open-source coding assistant. |
| **`@modelcontextprotocol/inspector`** | any | Not a real host — a debugger that connects as a client. Useful during development. |

Primitive-support parity varies. **Tools** are supported everywhere. **Resources** and **Prompts** are supported by Claude Desktop and Claude Code; other clients often support tools first and add the others later. **Sampling**, **Roots**, and **Elicitation** support is thinner still — check each host's docs for the current status before designing around them.

---

## Primitive-Support Rule of Thumb

```
                                     tools  resources  prompts  sampling  roots  elicitation
   Claude Desktop                      ✅       ✅        ✅        ~        ~        ~
   Claude Code                         ✅       ✅        ✅        ~        ~        ~
   VS Code (Copilot)                   ✅       partial   partial   ~        ~        ~
   Cursor                              ✅       partial   partial   ~        ~        ~
   Zed / Windsurf / Continue           ✅       varies    varies    ~        ~        ~

   ✅ = supported   ~ = check current docs; support is landing gradually
```

Rule when designing a server: **if you can express your feature as a tool, do.** Tools have universal client support. Reserve resources for genuine "attach this file" flows, prompts for slash-commands, and sampling/elicitation for the specific hosts you're targeting.

---

## Server Discovery

There is no single official server registry yet. Discovery today happens via:

- **`github.com/modelcontextprotocol/servers`** — the maintained catalog of reference implementations (source-of-truth for the official set)
- **Community lists** — `awesome-mcp-servers` and similar aggregations
- **Host-integrated pickers** — some hosts ship curated lists in their settings UI

A formal registry is on the roadmap in various spec discussions but not yet a shipped standard.

---

## Reference Servers — What Exists

From the `modelcontextprotocol/servers` repo, split into **reference** (officially maintained) and **third-party** (community / vendor-owned but widely used):

### Reference (official)

| Server | Purpose |
|--------|---------|
| `filesystem` | Read + write files under a scoped root |
| `git` | Query and manipulate a local git repo |
| `memory` | Simple persistent knowledge graph |
| `sequential-thinking` | Structured multi-step reasoning helper |
| `fetch` | HTTP requests |
| `everything` | Kitchen-sink test server — exercises every primitive |

### Third-party / vendor (widely used)

| Server | Owner | Purpose |
|--------|-------|---------|
| `@playwright/mcp` | Microsoft (Playwright team) | Drive a real browser via MCP. See [[AI Agentic Browser Automation - Playwright as Browser Layer]]. |
| GitHub MCP | GitHub | Issues, PRs, repos over the GitHub API |
| GitLab MCP | GitLab | Same for GitLab |
| Postgres MCP | community | Query and inspect Postgres |
| SQLite MCP | community | Local SQLite access |
| Slack MCP | community / vendor | Read + post to Slack |
| Puppeteer MCP | community | Alternative browser server |
| Brave Search MCP | Brave | Web search |
| Google Drive MCP | community | Files, docs |

Note: the historic `modelcontextprotocol/servers` repo has shifted some official reference servers out over time (as vendors take ownership of their own integrations). Always check the current repo README for the maintained set.

---

## Vendor MCPs Worth Knowing

Some large vendors publish first-party MCP servers that bring their APIs into every MCP client without per-host integration:

- **Atlassian** (Jira, Confluence)
- **Google Drive** / Workspace
- **Microsoft 365** / Graph
- **Slack**
- **HubSpot**
- **Figma**, **Canva** — design-tool integrations
- **Stripe**, **Notion**, **Linear**, and many others

The pitch matches the [[AI MCP - Protocol Overview|USB-C framing]]: one server implementation, immediate reach across every MCP-aware LLM app.

---

## Configuring a Server in Each Host

The JSON shape is close to identical across hosts. Claude Desktop / Claude Code:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    },
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/"
    }
  }
}
```

- `command` + `args` for stdio — the host spawns a child
- `type: "http"` + `url` for Streamable HTTP — the host makes HTTP calls, handling OAuth via the mechanisms in [[AI MCP - Security & Authorization]]

Cursor's `mcp.json` uses the same top-level shape. VS Code has a settings-UI variant that produces equivalent JSON.

---

## The Practical Testing Loop

```
   1. Write / install a server
   2. Debug with @modelcontextprotocol/inspector       ← host-independent
   3. Verify in Claude Desktop or Claude Code          ← full LLM in the loop
   4. Verify in VS Code Copilot / Cursor if needed     ← parity check
```

If a server works in Claude Desktop but not in Cursor, the culprit is usually **primitive coverage** (Cursor may not implement resources or prompts the way Claude does) rather than a wire-level bug.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Hosts | Claude Desktop, Claude Code, VS Code (Copilot), Cursor, Zed, Windsurf, Continue.dev — plus the Inspector debugger |
| Primitive coverage | **Tools** are universal; resources/prompts less so; sampling/roots/elicitation are thinnest |
| Discovery | No official registry yet — `github.com/modelcontextprotocol/servers` + community lists |
| Reference servers | filesystem, git, memory, sequential-thinking, fetch, everything |
| Vendor servers | Playwright, GitHub, GitLab, Atlassian, Slack, Postgres, and many others |
| Config | Nearly-identical `mcpServers` JSON shape across hosts |

---

## Related Notes

- [[AI MCP - Building a Server]] — the developer side of this ecosystem
- [[AI MCP - Security & Authorization]] — HTTP servers require OAuth 2.1
- [[AI Agentic Browser Automation - Playwright as Browser Layer]] — `@playwright/mcp` in context
- [[AI Agentic Browser Automation - Framework Comparison]] — where MCP-enabled browser tools sit
