---
tags:
  - web
  - rendering
  - performance
  - animation
  - frontend
created: 2026-10-21
source: https://web.dev/articles/stick-to-compositor-only-properties-and-manage-layer-count
---

# Web Reflow and Repaint - Compositor-Only Animations

> Animate properties that skip layout *and* paint, so each frame is just the GPU moving an already-painted layer. Part of [[Web Reflow and Repaint Guide]].

---

## The two safe properties

| Property | Replaces |
|----------|----------|
| `transform` | `top`, `left`, `width`, `height`, `margin` (for movement/scale/rotation) |
| `opacity` | fading via `visibility`/`display` toggles or color alpha |

`filter` is also composited in some engines, but that depends on the browser. Don't rely on it without checking a trace.

```css
/* ❌ Layout every frame */
.drawer { transition: left 300ms; left: -300px; }
.drawer.open { left: 0; }

/* ✅ Composite only */
.drawer { transition: transform 300ms; transform: translateX(-100%); }
.drawer.open { transform: translateX(0); }
```

---

## Why it's cheap

The compositor already has the element's pixels as a texture. Moving, scaling or fading a texture needs no new layout and no new paint. It also runs on the **compositor thread**, so it keeps animating while the main thread is busy with JS. See the RenderingNG table in [[Web Reflow and Repaint - Pixel Pipeline]].

---

## Layers and `will-change`

An element needs its **own layer** for its transform/opacity changes to skip paint. Browsers promote some elements automatically, for example during an active transform animation. You can hint ahead of time:

```css
.card-being-dragged {
  will-change: transform;
}
```

- Legacy hack: `transform: translateZ(0)`. Prefer `will-change`.
- Add it **just before** the animation, and remove it after if you can.

### Layers are not free

- Each layer costs **memory** and GPU texture upload bandwidth.
- Too many layers ("layer explosion") can make things *slower*, especially on low-memory phones.

```css
/* ❌ Never */
* { will-change: transform; }
```

> "Do not promote elements unnecessarily." — web.dev

Inspect layers in DevTools → **Layers** panel, or Rendering → **Layer borders**.

---

## Common substitutions

| Want | Don't animate | Animate |
|------|---------------|---------|
| Slide in | `left`, `margin-left` | `transform: translateX()` |
| Grow a card | `width`, `height` | `transform: scale()` (counter-scale children if text distorts) |
| Fade | `display`, `visibility` | `opacity` |
| Shadow pulse on hover | `box-shadow` (paints each frame) | `opacity` of a pseudo-element that already has the shadow |
| Expand accordion | `height: 0 → auto` | `transform: scaleY()`, or accept layout but `contain` it |

**FLIP technique** (First, Last, Invert, Play): measure the start and end positions once, then animate the difference with `transform`. Layout runs twice in total, not once per frame.

---

## JS-driven animations

```js
// ❌ layout per frame
function tick(t) { el.style.left = x(t) + 'px'; requestAnimationFrame(tick); }

// ✅ composite per frame
function tick(t) { el.style.transform = `translateX(${x(t)}px)`; requestAnimationFrame(tick); }

// ✅✅ let the browser run it (can stay on the compositor)
el.animate([{ transform: 'translateX(0)' }, { transform: 'translateX(300px)' }],
           { duration: 300, easing: 'ease-out' });
```

The Web Animations API and CSS transitions/animations on `transform`/`opacity` can run fully on the compositor. A rAF loop always needs the main thread every frame.

---

## Related

- [[Web Reflow and Repaint - In React]] — animating without re-rendering every frame
- [[Web Reflow and Repaint - Measuring in DevTools]] — paint flashing shows what still repaints
