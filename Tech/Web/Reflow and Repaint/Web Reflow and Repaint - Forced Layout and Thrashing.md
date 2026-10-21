---
tags:
  - web
  - rendering
  - performance
  - frontend
created: 2026-10-21
source: https://web.dev/articles/avoid-large-complex-layouts-and-layout-thrashing
---

# Web Reflow and Repaint - Forced Layout and Thrashing

> Layout normally runs once per frame. Reading geometry from JS while styles are dirty forces it to run *now*. Doing that in a loop is layout thrashing. Part of [[Web Reflow and Repaint Guide]].

---

## Forced synchronous layout

```js
box.classList.add('big');           // write: layout is now dirty
const h = box.offsetHeight;         // read: browser must recalc style + layout NOW
```

The read cannot return a stale value, so the browser stops your script, runs Style + Layout, then answers.

Two facts from Paul Irish's list:

- A read is **only expensive if something invalidated layout first**. Reading `offsetHeight` twice in a row with no write in between costs almost nothing.
- Forced layout **always recalculates style first**, so you pay for both.

---

## What forces layout (Blink)

| Category | APIs |
|----------|------|
| **Box metrics** | `offsetLeft/Top/Width/Height`, `offsetParent`, `clientLeft/Top/Width/Height`, `getClientRects()`, `getBoundingClientRect()` |
| **Scroll** | `scrollWidth/Height`, reading *or* setting `scrollLeft/Top`, `scrollBy()`, `scrollTo()`, `scrollIntoView()` |
| **Focus** | `el.focus()`, `input.select()` |
| **Text** | `el.innerText` (unlike `textContent`) |
| **Window** | `innerWidth/Height`, `scrollX/Y`, `visualViewport.*` |
| **Document** | `elementFromPoint()` |
| **Mouse events** | `event.offsetX/Y`, `event.layerX/Y` |
| **Computed style** | `getComputedStyle()`: always style. Also layout for geometry props (`width`, `height`, `top`, `transform`…), shadow-tree elements, or viewport media queries |
| **Range / SVG** | `range.getBoundingClientRect()`, `getBBox()`, `getComputedTextLength()` |

Source: https://gist.github.com/paulirish/5d52fb081b3570c81e3a. It is built from Blink source but mostly holds for WebKit and Gecko too.

**Cheap swaps:**
- `textContent` instead of `innerText` when you only need the text.
- `ResizeObserver` / `IntersectionObserver` instead of polling `getBoundingClientRect()`. Both deliver geometry the browser already computed.

---

## Layout thrashing

```js
// ❌ Each iteration: write invalidates, next read forces layout. N layouts.
for (const p of paragraphs) {
  p.style.width = box.offsetWidth + 'px';
}
```

```js
// ✅ Read once, then write. 1 layout (at frame end).
const width = box.offsetWidth;
for (const p of paragraphs) {
  p.style.width = width + 'px';
}
```

Harder version: reads and writes that depend on each element:

```js
// ❌ interleaved
items.forEach(el => {
  const h = el.offsetHeight;          // read  (forces layout after previous write)
  el.style.height = h * 2 + 'px';     // write (invalidates)
});

// ✅ two phases
const heights = items.map(el => el.offsetHeight);          // all reads
items.forEach((el, i) => el.style.height = heights[i] * 2 + 'px'); // all writes
```

---

## Batching across unrelated code: `requestAnimationFrame`

Thrashing often comes from **different modules**, each doing its own read+write. Fix it by scheduling writes for the next frame:

```js
function onScroll() {
  const top = header.getBoundingClientRect().top;   // read now
  requestAnimationFrame(() => {
    header.classList.toggle('stuck', top <= 0);      // write next frame
  });
}
```

Libraries like **FastDOM** formalize this as `measure()` / `mutate()` queues. Usually two arrays and a rAF are all you need.

---

## Gotchas

- **Debug logging can thrash.** `console.log(el.offsetHeight)` inside a loop is a read.
- **Setting `scrollTop` is a read too.** The browser needs layout to clamp the value.
- **Third-party scripts** (analytics, ads) often read layout on scroll. Check them in the trace.
- **`display: none` → `block` and back** triggers full layout. Toggle `visibility` or `opacity` if the element's space should stay reserved.

---

## Related

- [[Web Reflow and Repaint - Pixel Pipeline]] — why layout is lazy by default
- [[Web Reflow and Repaint - Measuring in DevTools]] — the "Forced reflow" insight finds these
- [[Web Reflow and Repaint - In React]] — the same problem inside `useLayoutEffect`
