---
tags:
  - web
  - rendering
  - performance
  - frontend
created: 2026-10-21
source: https://web.dev/articles/rendering-performance
---

# Web Reflow and Repaint - Pixel Pipeline

> The five stages every visual change goes through, and which stages a given CSS property lets you skip. Part of [[Web Reflow and Repaint Guide]].

---

## The five stages

```
JavaScript ─► Style ─► Layout ─► Paint ─► Composite
  (main thread ─────────────────────────┤  compositor / GPU)
```

| Stage | What happens | Output |
|-------|--------------|--------|
| **JavaScript** | Code changes DOM or styles. CSS animations, transitions and the Web Animations API can also drive changes without JS. | Dirty DOM / styles |
| **Style** | Match CSS selectors to elements, compute final values. | Computed styles |
| **Layout** (reflow) | Compute each box's size and position. One box can push others. | Geometry (fragment tree) |
| **Paint** (repaint) | Record draw calls for text, colors, images, borders, shadows, usually per layer. Then rasterize. | Display lists → pixels |
| **Composite** | Draw the layers in the correct order to the screen. | The frame |

---

## The three paths

### 1. Layout path (most expensive)

```
JS/CSS → Style → Layout → Paint → Composite
```

Triggered by **geometric** changes: `width`, `height`, `margin`, `padding`, `top`, `left`, `border-width`, `font-size`, `display`, inserting/removing DOM nodes, changing text content, resizing the window.

### 2. Paint-only path

```
JS/CSS → Style → Paint → Composite
```

Triggered by **visual but non-geometric** changes: `color`, `background-color`, `background-image`, `box-shadow`, `border-radius`, `outline`, `visibility`.

### 3. Composite-only path (cheapest)

```
JS/CSS → Style → Composite
```

Triggered by `transform` and `opacity` on an element that has its own compositor layer. Best for animation and scrolling. See [[Web Reflow and Repaint - Compositor-Only Animations]].

> Which path a property takes can differ between engines. The groups above are the common case. Measure when it matters ([[Web Reflow and Repaint - Measuring in DevTools]]).

---

## Layout is lazy, until you ask

The browser does **not** run layout after each DOM write. It marks the tree dirty and runs Style + Layout once, right before the next frame.

```js
el.style.width = '100px';   // marks layout dirty
el.style.height = '50px';   // still dirty, no work yet
el.classList.add('wide');   // still dirty
// ...frame ends → one style + one layout
```

This is why batching writes is free. The trouble starts when JS **reads** geometry while the tree is dirty. That forces layout immediately. See [[Web Reflow and Repaint - Forced Layout and Thrashing]].

---

## Scope: why one change can be expensive

- Layout is **almost always scoped to the whole document**. A one-pixel change near the top can reflow everything below it.
- Cost grows with the **number of boxes**. web.dev shows a trace where layout of a 1,618-element tree took over 28 ms. That is nearly two frames for a single layout.
- Use `contain` / `content-visibility` to draw a boundary. See [[Web Reflow and Repaint - Containment and content-visibility]].

---

## Frame budget

| | |
|---|---|
| Display refresh | 60 Hz → **16.66 ms** per frame (120 Hz → 8.3 ms) |
| Your budget | about **10 ms**. The browser needs the rest for its own work. |
| Discrete interaction | INP ≤ **200 ms** is "good" |

If Style + Layout + Paint plus your JS goes over budget, the frame is dropped (jank).

---

## Under the hood: Chromium RenderingNG

The five-stage model is a simplification. Chromium's actual pipeline:

| # | Stage | Thread |
|---|-------|--------|
| 1 | Animate | main or compositor |
| 2 | Style | main |
| 3 | Layout | main |
| 4 | Pre-paint (property trees, invalidation) | main |
| 5 | Scroll | main or compositor |
| 6 | Paint (build display list) | main |
| 7 | Commit (hand off to compositor) | main → compositor |
| 8 | Layerize | compositor |
| 9 | Raster / decode / paint worklets | compositor + Viz/GPU |
| 10 | Activate | compositor |
| 11 | Aggregate | Viz |
| 12 | Draw | Viz / GPU |

**Key insight:** stages 8–12 run **off the main thread**. Animations and scrolling that only touch the compositor keep running even while your JS blocks the main thread.

Source: https://developer.chrome.com/docs/chromium/renderingng-architecture

---

## Related

- [[Web Reflow and Repaint - Forced Layout and Thrashing]]
- [[React Lifecycle - Mount Semantics]] — where "browser paints" fits in React's commit sequence
