---
tags:
  - web
  - rendering
  - performance
  - frontend
created: 2026-10-21
source: https://web.dev/articles/rendering-performance
---

# Web Reflow and Repaint Guide

> Master reference for what the browser does after the DOM or CSS changes: **reflow** (recompute geometry), **repaint** (redraw pixels), and **composite** (assemble layers on the GPU), plus how to keep each one cheap.

---

## Terminology

| Term | Also called | What it means |
|------|-------------|---------------|
| **Reflow** | Layout (Chrome/WebKit name) | Recompute size and position of boxes. Firefox's engine calls this "reflow". |
| **Repaint** | Paint | Record draw commands (text, colors, borders, shadows) and rasterize them into pixels. |
| **Composite** | Compositing | Combine already-painted layers in the right order, on the compositor thread / GPU. |
| **Forced synchronous layout** | Forced reflow | JS reads geometry while layout is dirty, so the browser must run layout *right now*, mid-script. |
| **Layout thrashing** | | Forced layout inside a loop: write → read → write → read… |

**Rule of thumb:** reflow always causes repaint. Repaint does not always cause reflow. Compositing alone causes neither.

---

## Contents

| Note | Covers |
|------|--------|
| [[Web Reflow and Repaint - Pixel Pipeline]] | JS → Style → Layout → Paint → Composite, the three paths, frame budget, Chromium RenderingNG stages |
| [[Web Reflow and Repaint - Forced Layout and Thrashing]] | APIs that force layout, the thrashing loop, read/write batching |
| [[Web Reflow and Repaint - Compositor-Only Animations]] | `transform`/`opacity`, `will-change`, layer cost |
| [[Web Reflow and Repaint - Containment and content-visibility]] | `contain`, `content-visibility: auto`, limiting layout scope |
| [[Web Reflow and Repaint - Measuring in DevTools]] | Performance panel, Forced reflow insight, paint flashing, LoAF |
| [[Web Reflow and Repaint - In React]] | Where React causes reflow, `useLayoutEffect`, ResizeObserver, animating without re-renders |

---

## The three paths (cheat sheet)

```
Layout path      JS/CSS → Style → Layout → Paint → Composite   (width, height, top, left, font-size, adding DOM)
Paint-only path  JS/CSS → Style →          Paint → Composite   (color, background, box-shadow, visibility)
Composite path   JS/CSS → Style →                  Composite   (transform, opacity)
```

Pick the shortest path that achieves the visual change.

---

## Budget

| Number | Meaning |
|--------|---------|
| ~16.7 ms | One frame at 60 Hz |
| ~10 ms | Realistic budget for *your* work per frame (browser needs the rest) |
| ≤ 200 ms | INP "good" threshold, from input to next paint |

---

## Top 5 rules

1. **Read, then write.** Batch all geometry reads before any DOM/style writes. See [[Web Reflow and Repaint - Forced Layout and Thrashing]].
2. **Animate `transform` and `opacity` only.** Never `top`/`left`/`width`/`height` per frame. See [[Web Reflow and Repaint - Compositor-Only Animations]].
3. **Shrink the blast radius.** Layout is usually document-wide. `contain` and `content-visibility` cut it down. See [[Web Reflow and Repaint - Containment and content-visibility]].
4. **Keep the DOM small.** Layout cost scales with the number of boxes. Virtualize long lists ([[React Re-renders - List Performance]]).
5. **Measure, don't guess.** Look for purple Layout bars and "Forced reflow" warnings. See [[Web Reflow and Repaint - Measuring in DevTools]].

---

## Related Notes

- [[Web Rendering Patterns Guide]] — *where* HTML is produced (SPA/SSR/SSG); this guide is *how the browser turns it into pixels*
- [[React Reconciliation - Virtual DOM and Fiber]] — why React batches DOM writes
- [[React Hooks - useLayoutEffect]] — React's hook for "measure before paint"
