---
tags:
  - web
  - rendering
  - performance
  - css
  - frontend
created: 2026-10-21
source: https://developer.mozilla.org/en-US/docs/Web/CSS/content-visibility
---

# Web Reflow and Repaint - Containment and content-visibility

> Layout is document-wide by default. CSS containment tells the browser "nothing inside here affects the outside", so a change only re-lays out and repaints that subtree. Part of [[Web Reflow and Repaint Guide]].

---

## `contain`

| Value | Isolates |
|-------|----------|
| `layout` | Internal layout can't affect outside, and outside can't affect inside |
| `paint` | Descendants are clipped to the box. Off-screen means its contents need no painting |
| `size` | The box is sized as if it had no children (you must give it a size) |
| `inline-size` | `size`, but only in the inline direction (this is what container queries use) |
| `style` | Counters/quotes stay scoped |
| `content` | = `layout paint style`. **The safe default.** |
| `strict` | = `size layout paint style` |

```css
.widget {
  contain: content;   /* changes inside .widget don't reflow the page */
}
```

Side effects of `layout`/`paint`/`content`/`strict`: the element becomes a **containing block** for `position: absolute/fixed` descendants and creates a new **stacking context**. That can break a dropdown that is meant to escape the box.

**Good candidates:** widgets, cards in a grid, chat messages, list rows, and third-party embeds. Anything whose inner changes shouldn't move the rest of the page.

---

## `content-visibility`

| Value | Behavior |
|-------|----------|
| `visible` | Default |
| `auto` | Applies layout + style + paint containment. **Skips layout and paint entirely while off-screen.** Content stays in the DOM, in the accessibility tree, and findable with Ctrl+F |
| `hidden` | Always skip, like `display: none` on children, but cached rendering state is kept for fast re-show |

```css
.feed-item {
  content-visibility: auto;
  contain-intrinsic-size: auto 500px;
}
```

- `contain-intrinsic-size` is a **placeholder size** for skipped content. Without it, skipped items collapse to 0 height and the scrollbar jumps.
- The `auto` keyword lets the browser **remember the last real size** after the item has rendered once. `500px` is used only before the first render.
- Fires `contentvisibilityautostatechange` when skipping starts or stops, so you can pause canvas or video work off-screen.

**Support:** Baseline 2024 (all major engines since Sept 2024).

---

## content-visibility vs virtualization

| | `content-visibility: auto` | Virtualized list (react-window etc.) |
|---|---|---|
| DOM size | Full. Every node exists | Only visible rows exist |
| Layout/paint cost off-screen | Skipped | Doesn't exist |
| Memory, style recalc | Still pays for every node | Minimal |
| Find-in-page, a11y, SEO | ✅ Works | ❌ Off-screen rows missing |
| Effort | 2 lines of CSS | Library + fixed/measured row heights |

Start with `content-visibility` for long, mostly-static pages (articles, docs, feeds of hundreds of items). Move to virtualization when there are thousands of rows or style recalc itself is the bottleneck. See [[React Re-renders - List Performance]].

---

## Related

- [[Web Reflow and Repaint - Pixel Pipeline]] — "layout is scoped to the whole document"
- [[Web Reflow and Repaint - Measuring in DevTools]] — check that layout root shrank after adding `contain`
