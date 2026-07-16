---
tags:
  - ai
  - agentic-browser-automation
  - automation
created: 2026-07-15
source: https://github.com/browser-use/browser-use
---

# AI Agentic Browser Automation Guide

> How LLM-driven agents drive a real browser to complete web tasks — with **Playwright** as the browser layer and **browser-use** as the reference open-source engine.

---

## Contents

| Note | Covers |
|------|--------|
| [[AI Agentic Browser Automation - Observation-Action Loop]] | The core loop: Observe → Decide → Execute → Feedback |
| [[AI Agentic Browser Automation - Accessibility Tree for LLMs]] | How the DOM is compressed into a semantic tree for the LLM |
| [[AI Agentic Browser Automation - Playwright as Browser Layer]] | Why Playwright is the browser under agentic frameworks |
| [[AI Agentic Browser Automation - browser-use Library]] | Reference open-source implementation (Python) with `Hello World` |
| [[AI Agentic Browser Automation - Action Space]] | The tools an agent can call: click, type, scroll, extract… |
| [[AI Agentic Browser Automation - Framework Comparison]] | browser-use vs Stagehand vs Skyvern vs Computer Use vs Operator |

---

## Vocabulary (define once, use everywhere)

| Term | Meaning |
|------|---------|
| **LLM** | Large Language Model — a text (and sometimes vision) model like GPT-4, Claude, Gemini. Does the "thinking" step. |
| **Agent** | A program that puts an LLM in a loop with tools, so it can act on the world instead of just replying. |
| **Tool / Action** | A callable capability exposed to the LLM — e.g. `click(element_id)`, `navigate(url)`. |
| **Accessibility tree (a11y tree)** | Browser-built semantic view of the page used by screen readers — and, now, LLMs. See [[AI Agentic Browser Automation - Accessibility Tree for LLMs]]. |
| **Playwright** | Microsoft's browser-automation library (Chromium/Firefox/WebKit). See [[AI Agentic Browser Automation - Playwright as Browser Layer]]. |
| **MCP (Model Context Protocol)** | Anthropic-originated open protocol that standardizes how LLMs call external tools. Playwright ships an MCP server. |
| **WebVoyager** | Benchmark of ~640 real-website tasks used to score browser agents. |

---

## When to Reach for This

Reach for an agentic browser stack when the task **needs a real browser** (JS-heavy site, login flow, human-only content) and the steps are **not known in advance** — i.e. you cannot pre-write a Playwright script because the page structure, the wording, or the required decisions vary per run.

If the flow is deterministic and repeatable, a plain Playwright script is cheaper and faster. If the flow needs judgement per page, an agent earns its cost.

---

## Mental Model

```
┌──────────┐    state (a11y tree + screenshot)   ┌──────────┐
│  Browser │────────────────────────────────────▶│   LLM    │
│(Playwright)│                                    │(GPT/Claude)│
│          │◀────── action (click, type…) ───────│          │
└──────────┘                                     └──────────┘
```

The LLM never touches the DOM directly. It only ever **describes** what it wants (`click element 42`) — Playwright is the muscle. That separation is why the loop is auditable: every step is a discrete tool call you can log, replay, or veto. See [[AI Agentic Browser Automation - Observation-Action Loop]].

---

## Related Notes

- [[AI MCP Guide]] — the deep-dive on the Model Context Protocol that `@playwright/mcp` implements
- (empty) — future notes on Prompt Engineering and Anthropic Computer Use will land here.
