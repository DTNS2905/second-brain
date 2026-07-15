---
tags:
  - web
  - rendering-patterns
  - frontend
created: 2026-06-08
source: https://web.dev/articles/rendering-on-the-web
---

# Web Rendering Patterns Guide

> Master reference for SPA, SSR, SSG, and ISR — where HTML is built, performance tradeoffs, and when to use each.

---

## Contents

| Note | Covers |
|------|--------|
| [[Web Rendering Patterns - SPA]] | Client-side rendering: JS-driven, no server HTML, hydration-free |
| [[Web Rendering Patterns - SSR]] | Server-side rendering: HTML built per-request, hydration required |
| [[Web Rendering Patterns - SSG]] | Static generation: HTML built at build time, CDN-served, ISR |
| [[Web Rendering Patterns - Comparison]] | Full side-by-side table, decision flowchart, hybrid patterns |

---

## Pattern Definitions

| Pattern | Full Name | Where HTML is built | When |
|---------|-----------|--------------------|----|
| **SPA / CSR** | Single Page App / Client-Side Rendering | Browser (JS) | At runtime, in user's browser |
| **SSR** | Server-Side Rendering | Server | At request time, per visitor |
| **SSG** | Static Site Generation | Build server | At deploy time, once |
| **ISR** | Incremental Static Regeneration | Build + revalidation | At deploy + background refresh |

---

## Performance Metrics Cheat Sheet

> **TTFB** — Time to First Byte: how fast the server responds  
> **FCP** — First Contentful Paint: when visible content appears  
> **TTI** — Time to Interactive: when the page responds to input  
> **TBT** — Total Blocking Time: main thread blockage during load  
> **INP** — Interaction to Next Paint: responsiveness to user input

| Pattern | TTFB | FCP | TTI / INP | TBT |
|---------|------|-----|-----------|-----|
| SPA | ✅ Fast (tiny HTML) | ❌ Slow (waits for JS) | ❌ Slow (JS parse + execute) | ❌ High |
| SSR | ⚠️ Slower (server compute) | ✅ Fast (full HTML) | ⚠️ Delayed (hydration) | ⚠️ Medium |
| SSG | ✅✅ Fastest (CDN edge) | ✅ Fast (full HTML) | ✅ Good (minimal JS) | ✅ Low |
| ISR | ✅✅ Fastest (CDN, first hit = SSR) | ✅ Fast | ✅ Good | ✅ Low |

---

## Decision Flowchart

```
Is content personalized per user (auth, preferences, real-time)?
├── YES → Does SEO matter for this page?
│          ├── YES  → SSR
│          └── NO   → SPA (behind auth, no crawlers)
└── NO  → How often does content change?
           ├── Never / rarely    → SSG
           ├── Hourly / daily    → ISR
           └── Every request     → SSR
```

---

## Quick Use-Case Map

| Use case | Recommended |
|----------|-------------|
| Marketing / landing page | SSG |
| Blog, docs, portfolio | SSG |
| Large product catalog | ISR |
| News feed (fresh data) | SSR or ISR |
| Social feed / dashboard (per-user) | SSR |
| Admin panel / app behind login | SPA |
| E-commerce cart, checkout | SPA + SSG hybrid |
| Search results page | SSR |

---

## Key Principle

> "Consider server-side rendering or static rendering over a full rehydration approach." — web.dev

Prefer SSG first (cheapest, fastest). Add ISR when content needs freshness. Use SSR only when every request must be unique. Fall back to SPA for auth-gated, highly interactive experiences where SEO doesn't apply.

---

## Related Notes

- [[Web Rendering Patterns - Comparison]] — full tradeoff table
- [[React Reconciliation - Virtual DOM and Fiber]] — how React's fiber architecture handles SSR hydration
- [[React Component Composition - React Elements]] — how React elements relate to server vs client rendering
- [[React Re-renders Guide]] — client-side re-render behavior after hydration
