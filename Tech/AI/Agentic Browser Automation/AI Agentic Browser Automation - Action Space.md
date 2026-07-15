---
tags:
  - ai
  - agentic-browser-automation
  - automation
created: 2026-07-15
source: https://docs.browser-use.com/open-source/customize/tools/available
---

# AI Agentic Browser Automation - Action Space

> The tools an agent can call — and the constraints on that toolset. Back to [[AI Agentic Browser Automation Guide]].

---

## Core Actions

Every action operates on the current [[AI Agentic Browser Automation - Accessibility Tree for LLMs|indexed a11y tree]] snapshot. `index` refers to an element's numeric ID in that snapshot.

| Action | Parameters | Use case |
|--------|------------|----------|
| `click` | `index` | Buttons, links, checkboxes, radio buttons. |
| `type` | `index`, `text` | Fill a focused text field character by character (fires keydown events). |
| `fill` | `index`, `text` | Direct value assignment — faster than `type`, skips key events. |
| `scroll` | `direction`, `amount` | Reveal off-screen content; `amount` in pixels or `"page"`. |
| `navigate` | `url` | Load a new URL (or `"back"` / `"forward"` / `"reload"`). |
| `screenshot` | `full_page?` | Capture visual state — used sparingly to save tokens. |
| `get_state` | — | Force re-serialize the page (URL, title, a11y tree, indexed elements). |
| `extract` | `index`, `attribute?` | Read text or an attribute (`href`, `value`, `aria-label`) from an element. |
| `execute_code` | `js` | Run arbitrary JavaScript — escape hatch for shadow DOM, complex queries. |
| `done` | `result` | Terminate the loop and return `result` to the caller. |

`browser-use` also ships convenience actions: `open_tab`, `switch_tab`, `close_tab`, `send_keys` (keyboard shortcuts like `Ctrl+F`), and `wait` (seconds).

---

## What Actions Deliberately Do Not Exist

| ❌ Missing | Why |
|------------|-----|
| `set_dom(html)` | No direct DOM injection — the agent must interact like a user, so behavior is reproducible on real users' machines. |
| `click_by_selector('#foo')` | CSS selectors bypass the a11y tree — the LLM would drift from the shared semantic model. |
| `eval_and_navigate(js)` | `execute_code` cannot change the URL; navigation flows through the observable `navigate` tool. |
| `bypass_cookie_banner()` | Agents should learn to close banners like a user, not magic them away. |

The constraint is intentional: everything the agent does should be replayable by a human running the same clicks. This is what makes the loop **auditable** ([[AI Agentic Browser Automation - Observation-Action Loop]]).

---

## Action Format on the Wire

The LLM emits JSON that matches the tool's parameter schema. Example single step:

```json
✅ {"action": "click", "index": 42}
✅ {"action": "type",  "index": 3, "text": "browser-use"}
✅ {"action": "done",  "result": "The repo has 105,000 stars."}
```

An off-schema emission (missing `index`, wrong type) is caught by tool validation and returned to the LLM as an error — it retries next step.

```json
❌ {"action": "click", "coordinates": [247, 384]}   // no `coordinates` in schema
❌ {"action": "click", "selector": "#submit"}        // no `selector` in schema
❌ {"action": "click"}                                // missing required `index`
```

---

## When to Add a Custom Action

Reach for `@tools.action` (see [[AI Agentic Browser Automation - browser-use Library]]) when:

- The task repeats a **specific data shape** — e.g. "extract product listings" → one tool that returns `list[Product]` beats teaching the LLM to walk the DOM every time.
- You need a **shadow-DOM query** — write it once in JS, expose it as an action.
- You want to **enforce a policy** — e.g. `add_to_cart(sku)` that internally logs the purchase for audit before executing.

Rule of thumb: if the LLM is doing the same 3-step sub-flow more than twice in your tests, fold it into a custom action.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Actions target indexed a11y-tree elements — never selectors or coordinates |
| Core set is small (~10 actions) — power comes from composing them |
| No DOM injection, no selector-based click — replayability is the constraint |
| Custom actions via `@tools.action` — collapse repeated sub-flows into one tool |
| `done` is how the LLM terminates the loop |

---

## Related Notes

- [[AI Agentic Browser Automation - Observation-Action Loop]] — where actions get executed
- [[AI Agentic Browser Automation - Accessibility Tree for LLMs]] — where indexes come from
- [[AI Agentic Browser Automation - browser-use Library]] — the Python API that wraps this action set
