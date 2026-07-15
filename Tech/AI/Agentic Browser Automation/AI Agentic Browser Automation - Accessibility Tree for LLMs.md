---
tags:
  - ai
  - agentic-browser-automation
  - automation
created: 2026-07-15
source: https://web.dev/articles/the-accessibility-tree
---

# AI Agentic Browser Automation - Accessibility Tree for LLMs

> How raw HTML gets compressed into a semantic tree the LLM can actually read. Back to [[AI Agentic Browser Automation Guide]].

---

## What Is the Accessibility Tree?

The **accessibility tree** (a11y tree) is a simplified, semantic version of the DOM built by the browser to feed screen readers. Every visible interactive element becomes one node with four fields:

| Field | Example | What it means |
|-------|---------|---------------|
| **Role** | `button`, `link`, `textbox`, `heading` | What the element *is*, semantically. |
| **Name / Label** | `"Save changes"`, `"Search"` | What a screen reader would announce. |
| **State** | `disabled`, `checked`, `expanded` | Current interactive state. |
| **Ref / Index** | `12`, `A0-B5-C3` | Stable ID the agent uses to refer to it. |

Everything else — CSS classes, decorative `<div>` wrappers, inline styles, scripts — is stripped.

---

## Before / After

Raw HTML — 400+ tokens of noise for the LLM:

```html
❌ <div class="btn-wrapper mx-auto flex items-center rounded-lg">
     <button
       type="submit"
       class="px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white font-medium rounded transition-colors duration-150 disabled:opacity-50"
       id="submit-btn-2xy4"
       data-analytics="save-form-submit"
       aria-describedby="save-tooltip">
       <svg class="w-4 h-4 mr-2">...</svg>
       Save changes
     </button>
   </div>
```

Same element as an a11y-tree node — ~15 tokens, unambiguous:

```
✅ [12] button "Save changes" (enabled)
```

The LLM cannot mis-click a Tailwind class it never sees.

---

## Element Indexing

`browser-use` walks the a11y tree and assigns a **numeric index** to every interactive node, starting at 0. The full serialized state looks like:

```
url: https://github.com/browser-use/browser-use
title: browser-use/browser-use: The AI browser automation library

interactive:
  [0]  link      "Skip to content"
  [1]  link      "GitHub"
  [2]  textbox   "Search or jump to…"   placeholder
  [3]  button    "Sign in"
  ...
  [42] button    "Star"                 (unchecked)
  [43] link      "105k"                 (Stars)
  ...
```

The LLM then references elements by index — `click 42` or `extract text from 43` — instead of by CSS selector or pixel coordinate. See the action list in [[AI Agentic Browser Automation - Action Space]].

---

## Hybrid Sensing: Tree + Screenshot

Best-in-class agents send **both**:

| Signal | Good for | Cost |
|--------|----------|------|
| A11y tree | Planning, unambiguous element refs, form-filling | ~200–400 tokens/snapshot |
| Screenshot | Spatial layout, visual anomalies, canvas/SVG content, verifying "did the modal close?" | ~1000–1500 tokens/snapshot (vision model) |

**Rule of thumb:** send the tree every step, send the screenshot only when the tree alone is ambiguous (visual comparison tasks, drag-and-drop, canvas UIs).

Token math: a full-page screenshot at low detail is roughly **4× the cost** of the tree. On a 30-step task that adds up fast — hybrid mode is why open-source agents can compete with vision-first proprietary ones on cost.

---

## What the Tree Cannot See

The a11y tree only shows what the DOM exposes semantically. Blind spots:

- **`<canvas>` / WebGL content** — no structure, need a screenshot.
- **Custom components missing ARIA roles** — a `<div onclick>` with no `role="button"` may not appear as interactive.
- **Visual state not encoded in DOM** — spinner colours, drag-preview positions, drawn charts.

If the site is a canvas app or ARIA-poor SPA, expect the agent to lean harder on vision.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| A11y tree | Browser-built semantic DOM view (role, name, state, ref) |
| Element index | Numeric ID the agent uses instead of selectors or coordinates |
| Hybrid sensing | Tree every step; screenshot only when needed |
| Token cost | Tree ≈ 200–400 tokens vs screenshot ≈ 1000+ tokens |
| Blind spots | Canvas, WebGL, ARIA-poor components |

---

## Related Notes

- [[AI Agentic Browser Automation - Observation-Action Loop]] — where the tree lives inside the loop
- [[AI Agentic Browser Automation - Playwright as Browser Layer]] — Playwright is what serializes the tree
- [[AI Agentic Browser Automation - Action Space]] — how the LLM uses indexes
