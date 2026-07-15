---
tags:
  - ai
  - agentic-browser-automation
  - automation
  - browser-use
  - python
created: 2026-07-15
source: https://docs.browser-use.com/open-source/quickstart
---

# AI Agentic Browser Automation - browser-use Library

> The reference open-source implementation of the agentic loop. Python, MIT, 100k+ ★. Back to [[AI Agentic Browser Automation Guide]].

---

## What It Is

`browser-use` is a Python library that wires **any LLM** into **Playwright** to complete natural-language web tasks. It ships:

- an `Agent` class that runs the [[AI Agentic Browser Automation - Observation-Action Loop|Observation-Action Loop]],
- a serializer that turns the page into an [[AI Agentic Browser Automation - Accessibility Tree for LLMs|indexed a11y tree]],
- an [[AI Agentic Browser Automation - Action Space|action space]] the LLM can call,
- a `@tools.action` decorator for domain-specific extensions.

**License:** MIT · **Repo:** `github.com/browser-use/browser-use` · **Score:** 89.1% on WebVoyager (state-of-the-art among open-source, mid-2026).

---

## Install

```bash
pip install browser-use
playwright install chromium
```

Set your LLM key in a `.env`:

```
OPENAI_API_KEY=sk-...
# or
ANTHROPIC_API_KEY=sk-ant-...
# or
GOOGLE_API_KEY=...
```

---

## Hello World

```python
import asyncio
from browser_use import Agent, ChatBrowserUse
from dotenv import load_dotenv

load_dotenv()

async def main():
    llm = ChatBrowserUse(model='openai/gpt-4o')

    agent = Agent(
        task="Find the number of stars on the browser-use GitHub repository.",
        llm=llm,
    )

    history = await agent.run()
    print(history[-1].result)

if __name__ == "__main__":
    asyncio.run(main())
```

What happens under the hood — each cycle of [[AI Agentic Browser Automation - Observation-Action Loop]]:

1. Agent opens Chromium via Playwright, navigates to `github.com`.
2. Captures a11y tree + screenshot.
3. LLM chooses `search`, types `browser-use/browser-use`, presses Enter.
4. New state captured; LLM clicks the result.
5. Repo page loads; LLM reads the "Stars" link value.
6. Emits `done(result="105k stars")`.

---

## Architecture

```
              ┌───────────────────────────────────────┐
              │              Agent                    │
              │  ┌─────────┐    ┌──────────────────┐  │
              │  │  Loop   │◀──▶│  Message history │  │
              │  └────┬────┘    └──────────────────┘  │
              │       │                                │
              │       ▼                                │
              │  ┌─────────┐    ┌──────────────────┐  │
              │  │  LLM    │    │  Action Executor │  │
              │  │(pluggable)   │  (Playwright)    │  │
              │  └─────────┘    └──────────────────┘  │
              └───────────────────────────────────────┘
                        │                    │
              ┌─────────▼──────────┐  ┌──────▼────────┐
              │  ChatOpenAI /       │  │   Chromium /  │
              │  ChatAnthropic /    │  │   Firefox /   │
              │  ChatGoogle /       │  │   WebKit      │
              │  ChatBrowserUse     │  │               │
              └─────────────────────┘  └───────────────┘
```

The LLM slot is **pluggable** — swap `ChatBrowserUse` for `ChatAnthropic(model='claude-sonnet-4-5')` or `ChatOpenAI(model='gpt-4o')` without touching agent code.

---

## Custom Tools

Extend the [[AI Agentic Browser Automation - Action Space]] with domain logic:

```python
from browser_use import Agent, Tools, ChatBrowserUse

tools = Tools()

@tools.action(description='Extract all email addresses on the current page.')
async def get_emails(page) -> list[str]:
    text = await page.inner_text('body')
    import re
    return re.findall(r'[\w.-]+@[\w.-]+', text)

agent = Agent(
    task="Visit example.com and list every email you find.",
    llm=ChatBrowserUse(model='openai/gpt-4o'),
    tools=tools,
)
await agent.run()
```

The description feeds directly into the LLM's tool list — write it as a prompt for the model, not a docstring for humans.

---

## Configuration You'll Actually Change

| Option | Default | Change when |
|--------|---------|-------------|
| `max_steps` | 25 | Task is long-running; raise to 50–100 for research flows. |
| `use_vision` | `True` | Set `False` to cut token cost when the a11y tree alone is enough. |
| `headless` | `False` | Set `True` in production; keep `False` locally to watch decisions. |
| `browser_class` | `Chromium` | Switch to `Firefox` / `WebKit` for cross-browser QA agents. |
| `save_conversation_path` | `None` | Log every LLM turn to disk for later evaluation. |

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Install | `pip install browser-use && playwright install chromium` |
| Core object | `Agent(task=..., llm=...)` + `await agent.run()` |
| LLM slot | Pluggable — OpenAI, Anthropic, Google, or `ChatBrowserUse` |
| Extending | `@tools.action` decorator; description is the model's prompt |
| Benchmark | 89.1% WebVoyager (SOTA open-source, mid-2026) |

---

## Related Notes

- [[AI Agentic Browser Automation - Observation-Action Loop]] — the loop this library runs
- [[AI Agentic Browser Automation - Action Space]] — the tools it exposes to the LLM
- [[AI Agentic Browser Automation - Playwright as Browser Layer]] — the browser it drives
- [[AI Agentic Browser Automation - Framework Comparison]] — how it compares to Stagehand, Skyvern, and closed-source options
