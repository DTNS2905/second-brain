---
tags:
  - ai
  - agentic-browser-automation
  - automation
created: 2026-07-15
source: https://blog.logrocket.com/exploring-agent-browser-ai-agents-web/
---

# AI Agentic Browser Automation - Observation-Action Loop

> The core pattern every browser agent follows. Back to [[AI Agentic Browser Automation Guide]].

---

## The Loop

```
   ┌──────────────────────────────────────────────────┐
   │                                                  │
   ▼                                                  │
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐│
│ Observe │──▶│ Decide  │──▶│ Execute │──▶│ Feedback││
└─────────┘   └─────────┘   └─────────┘   └─────────┘│
     ▲              │                                │
     │              └── goal met? ──────────────────▶│  ✓ stop
     └───────────────── otherwise ────────────────── ┘
```

| Step | Who does it | What happens |
|------|-------------|--------------|
| **Observe** | Browser (Playwright) | Capture page state: URL, title, [[AI Agentic Browser Automation - Accessibility Tree for LLMs\|accessibility tree]], optional screenshot. |
| **Decide** | LLM | Read state + task + history. Emit next action as structured JSON — `{"action": "click", "index": 12}`. |
| **Execute** | Browser (Playwright) | Run the action. See [[AI Agentic Browser Automation - Action Space]] for the full list. |
| **Feedback** | Browser (Playwright) | Wait for DOM to settle, capture new state, detect errors (nav failed, element gone). |

The loop repeats until the LLM emits a `done(result)` action or a max-steps guard trips.

---

## Why the Loop, Not "Write Me a Playwright Script"?

An LLM can generate a Playwright script from a task description — but only for **known** flows. Agentic browsing exists because:

- Pages change between visits (dynamic content, A/B tests, cookie banners).
- Selectors go stale (a CSS class renamed → the script breaks).
- Judgement is needed mid-flow (which of 5 search results is the right one?).

Emitting **one action at a time** lets the LLM react to what actually happened, not what it hoped would happen.

---

## Determinism vs Vision-Only

Two ways to see the page:

```
❌ Vision-only:  screenshot ──▶ LLM ──▶ "click at pixel (247, 384)"
✅ Hybrid:       a11y tree + screenshot ──▶ LLM ──▶ "click element index 12"
```

Vision-only agents (early Claude Computer Use, Anthropic's `computer_use_20250124`) hallucinate coordinates on ambiguous UIs. Hybrid agents look up an element by its indexed a11y-tree entry — no coordinate math, no hallucination. See [[AI Agentic Browser Automation - Accessibility Tree for LLMs]].

---

## Failure Modes

| Failure | Cause | Mitigation |
|---------|-------|------------|
| **Max steps exceeded** | LLM stuck in a click-loop on the same page | Track state hashes; break loop if no progress in N steps. |
| **Hallucinated element index** | LLM references an index that doesn't exist in the current state | Validate index against latest state before executing. |
| **Stale state** | Action fired against pre-navigation DOM | Await `networkidle` / DOM-quiet before capturing next state. |
| **Silent success** | Action worked but LLM keeps clicking | Give the model a `done` action and prompt it to end when goal met. |

---

## Anatomy of One Step (log excerpt from `browser-use`)

```
Step 4/25 → task: "Find the stars on browser-use repo"
  observe: url=https://github.com/browser-use/browser-use
           interactive_elements=[
             12: link "Stars" (state=focusable),
             13: button "Watch" ...
           ]
  decide:  action=extract, index=12, want="star count as integer"
  execute: playwright.locator(index=12).text_content()
  result:  "105k"
  → next: done(result="105,000 stars")
```

Every step is a JSON record — trivial to replay, diff, or feed into an evaluator.

---

## Summary

| Concept       | Takeaway                                                             |
| ------------- | -------------------------------------------------------------------- |
| Loop shape    | Observe → Decide → Execute → Feedback, until `done` or max-steps     |
| State format  | a11y tree + optional screenshot (**hybrid** is best practice)        |
| Action format | Structured JSON referencing indexed elements — not pixel coordinates |
| Debuggability | Every step is a discrete, replayable record                          |
| Alternative   | Write a plain Playwright script when the flow is fixed               |

---

## Related Notes

- [[AI Agentic Browser Automation - Accessibility Tree for LLMs]] — the "state" side of the loop
- [[AI Agentic Browser Automation - Action Space]] — the "action" side of the loop
- [[AI Agentic Browser Automation - browser-use Library]] — a concrete implementation
