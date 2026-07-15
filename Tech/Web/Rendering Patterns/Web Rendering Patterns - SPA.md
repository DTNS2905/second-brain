---
tags:
  - web
  - rendering-patterns
  - frontend
created: 2026-06-08
source: https://web.dev/articles/rendering-on-the-web
---

# Web Rendering Patterns - SPA

> Single Page Application / Client-Side Rendering: all HTML is built in the browser by JavaScript. Part of [[Web Rendering Patterns Guide]].

---

## How It Works

```
User navigates to URL
  ↓
Server responds with a minimal HTML shell (no content)
  ↓
Browser downloads the JavaScript bundle
  ↓
JS executes: fetches data, renders components, builds DOM
  ↓
Page becomes visible AND interactive simultaneously
```

The server never renders application HTML — it just delivers a JS payload.

---

## What the Server Sends

```html
<!DOCTYPE html>
<html>
  <head>
    <title>My App</title>
  </head>
  <body>
    <div id="root"></div>           <!-- empty shell -->
    <script src="/bundle.js"></script>
  </body>
</html>
```

Until `bundle.js` downloads, parses, and executes, the user sees a blank page or loading spinner.

---

## After JS Runs (React example)

```jsx
// React takes over the #root div and renders the full UI
ReactDOM.createRoot(document.getElementById('root')).render(<App />);
```

There is **no hydration** in a pure SPA — the client builds the entire DOM from scratch. Nothing was pre-rendered on the server.

---

## Performance Profile

| Metric | SPA behavior | Why |
|--------|-------------|-----|
| TTFB | ✅ Fast | Tiny HTML file; no server compute |
| FCP | ❌ Slow | User sees blank page until JS runs |
| TTI | ❌ Slow | JS must download + parse + execute first |
| TBT | ❌ High | Large JS bundles block the main thread |
| INP (after load) | ✅ Excellent | No page reloads; instant state transitions |

FCP and TTI converge in SPAs (both happen when JS finishes) — unlike SSR where FCP comes first but TTI lags behind hydration.

---

## SEO Implications

Search engine crawlers (Googlebot) can execute JavaScript, but:
- Content is **not available on initial page load** — crawlers may miss it or index it late
- ❌ Delayed indexing: Google must render the page in a second wave
- ❌ Social sharing previews (OG tags) fail if meta tags are injected by JS
- ❌ Core Web Vitals scores hurt rankings (slow FCP/LCP on mobile)

**Rule:** If the page needs to rank in search, don't use a pure SPA.

---

## ✅ Good Use Cases

| Use case | Why SPA works |
|----------|--------------|
| Admin dashboards | Behind auth, no public crawlers |
| Internal tools | No SEO requirement |
| Highly interactive UIs | Instant state transitions, no page reloads |
| Real-time features | WebSocket + client state management |
| Apps with complex client state | Redux/Zustand, no server round-trips |

## ❌ Poor Use Cases

| Use case | Why SPA fails |
|----------|--------------|
| Marketing / landing pages | SEO critical, slow FCP hurts conversions |
| Blogs, docs | Crawlability and fast FCP required |
| E-commerce product pages | SEO + fast LCP = revenue |
| Mobile-first content sites | Large JS bundles are slow on mobile |

---

## Mitigation Strategies for SPAs

When SPA is required but performance matters:

```
Code splitting      → ship only the JS needed for the current route
Lazy loading        → defer non-critical components with React.lazy()
App shell + cache   → service worker caches shell HTML for instant re-visits
Preconnect hints    → <link rel="preconnect"> speeds up API data fetching
```

---

## Frameworks

| Framework | Notes |
|-----------|-------|
| React + Vite | Modern SPA default; fast dev, tree-shaking |
| React + CRA | Legacy; largely replaced by Vite |
| Vue (vue-cli / Vite) | Same pattern as React SPA |
| Angular | Full SPA framework with built-in router |
| Svelte / SvelteKit (CSR mode) | Smaller bundles |

---

## Related Notes

- [[Web Rendering Patterns - SSR]] — adds server rendering to solve SPA's SEO/FCP problems
- [[Web Rendering Patterns - Comparison]] — full tradeoff matrix
- [[Web Rendering Patterns Guide]] — decision flowchart
- [[React Re-renders Guide]] — client-side re-render behavior inside SPAs
