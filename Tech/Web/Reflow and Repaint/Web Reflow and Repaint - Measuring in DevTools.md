---
tags:
  - web
  - rendering
  - performance
  - devtools
  - frontend
created: 2026-10-21
source: https://developer.chrome.com/docs/devtools/performance
---

# Web Reflow and Repaint - Measuring in DevTools

> How to see reflow and repaint instead of guessing: lab tools in Chrome DevTools and field data from the Long Animation Frames API. Part of [[Web Reflow and Repaint Guide]].

---

## Performance panel

1. DevTools → **Performance** → enable CPU throttling (4× or 6×) to match a mid-range phone.
2. Record, do the interaction, stop.
3. Read the **Main** track:

| Color | Event | Means |
|-------|-------|-------|
| Yellow | Scripting | Your JS |
| **Purple** | Recalculate Style, **Layout** | Reflow |
| **Green** | Paint, Composite Layers | Repaint / composite |

- **Forced reflow:** a Layout block nested *inside* a JS call stack, often flagged with a red corner. The **Forced reflow** insight in the Insights sidebar names the function that caused it.
- Click a Layout event → the summary shows **nodes that needed layout** / total nodes and the **layout root**. A small root means containment is working ([[Web Reflow and Repaint - Containment and content-visibility]]).
- A sawtooth of purple/yellow/purple/yellow inside one task = **layout thrashing** ([[Web Reflow and Repaint - Forced Layout and Thrashing]]).

---

## Rendering drawer

DevTools → ⋮ → More tools → **Rendering**:

| Toggle | Shows |
|--------|-------|
| **Paint flashing** | Green overlay on every area that repaints. A transform animation should show *no* flashing |
| **Layout Shift Regions** | Blue flash where content moved (relates to CLS) |
| **Layer borders** | Orange/olive outlines around composited layers |
| **Frame Rendering Stats** | Live FPS and GPU memory |

---

## Layers panel

DevTools → More tools → **Layers**: 3D view of every compositor layer, its memory cost, and **why it was promoted** ("has a will-change: transform hint", "overlaps other composited content"…). Use it to catch layer explosion ([[Web Reflow and Repaint - Compositor-Only Animations]]).

---

## Field data: Long Animation Frames (LoAF)

Lab traces only show your machine. To find forced reflow in real users' sessions:

```js
new PerformanceObserver(list => {
  for (const frame of list.getEntries()) {
    for (const script of frame.scripts) {
      if (script.forcedStyleAndLayoutDuration > 10) {
        console.warn('forced layout', script.sourceURL, script.sourceFunctionName,
                     script.forcedStyleAndLayoutDuration);
      }
    }
  }
}).observe({ type: 'long-animation-frame', buffered: true });
```

`forcedStyleAndLayoutDuration` on each script entry is the time spent in forced Style + Layout. Send it to your RUM pipeline. LoAF is Chromium-only.

---

## Quick micro-check in the console

```js
console.time('read');
document.querySelectorAll('.row').forEach(r => r.offsetHeight);
console.timeEnd('read');
```

Run it after a write (e.g. toggling a class on `<body>`) and compare with running it twice in a row. The first run pays for layout, the second is nearly free.

---

## Related metrics

| Metric | Reflow/repaint link |
|--------|---------------------|
| **INP** | Long style/layout/paint after an input delays the next paint |
| **CLS** | Unexpected reflow that moves visible content |
| **TBT** | Forced layouts inflate long tasks |

See [[Web Rendering Patterns Guide]] for the full metrics cheat sheet.
