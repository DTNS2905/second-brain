---
tags:
  - web
  - rendering-patterns
  - frontend
created: 2026-06-08
source: https://web.dev/articles/rendering-on-the-web
---

# Web Rendering Patterns - SSR

> Server-Side Rendering: full HTML built on the server per request, then hydrated on the client. Part of [[Web Rendering Patterns Guide]].

---

## How It Works

```
User navigates to URL
  ↓
Server receives request
  ↓
Server fetches data + renders full HTML (React/Vue/etc. runs on server)
  ↓
Server sends complete HTML to browser
  ↓
Browser displays content immediately (FCP achieved)
  ↓
Browser downloads JS bundle
  ↓
JS hydrates the HTML → page becomes fully interactive (TTI achieved)
```

The server does meaningful work on every request. The client gets usable HTML before any JS runs.

---

## Hydration: The Gap Between FCP and TTI

After the server sends HTML, the page *looks* interactive but isn't. Hydration is the process where client-side JS "wakes up" the static HTML by attaching event listeners and restoring component state.

```
[HTML arrives]     → user sees content (FCP ✅)
[JS downloads]     → ~100-500ms gap (page looks interactive but isn't)
[JS hydrates]      → buttons and links actually work (TTI ✅)
```

During this gap, clicks are silently ignored — a serious UX problem on slow mobile connections. This is called the **hydration mismatch window**.

```jsx
// React SSR: server renders this to HTML string
// Client then "rehydrates" it — attaches React's virtual DOM to the existing DOM
ReactDOM.hydrateRoot(document.getElementById('root'), <App />);
```

---

## Performance Profile

| Metric | SSR behavior | Why |
|--------|-------------|-----|
| TTFB | ⚠️ Slower | Server must fetch data + render before responding |
| FCP | ✅ Fast | Full HTML arrives; content visible immediately |
| TTI | ⚠️ Delayed | Depends on JS bundle size and hydration time |
| TBT | ⚠️ Medium | Hydration can block main thread briefly |
| SEO | ✅ Excellent | Crawlers get full content on first request |

---

## Streaming SSR (React 18+)

Traditional SSR sends the entire HTML at once — the server must wait for all data before responding. Streaming SSR sends HTML in **chunks** as each section is ready:

```jsx
// React 18 Suspense enables streaming
function Page() {
  return (
    <html>
      <body>
        <Header />                          {/* sent immediately */}
        <Suspense fallback={<Spinner />}>
          <SlowDataComponent />             {/* streamed when ready */}
        </Suspense>
      </body>
    </html>
  );
}
```

Benefits:
- TTFB is faster (browser starts rendering the shell sooner)
- FCP improves (above-the-fold content arrives first)
- Below-the-fold content streams in progressively

---

## Next.js Implementation

```javascript
// pages/dashboard.js — runs on server for every request
export async function getServerSideProps(context) {
  const { userId } = context.req.cookies;
  const data = await fetchUserData(userId);   // fresh per request

  return {
    props: { data }
  };
}

export default function Dashboard({ data }) {
  return <DashboardUI data={data} />;
}
```

The `context` object contains `req`, `res`, `query`, `params` — full access to request headers, cookies, and URL.

---

## Server Cost Trade-off

SSR requires a live server to handle every page request. Unlike SSG (static files on a CDN), SSR:
- Consumes server CPU on every page load
- Scales with traffic — more users = more server compute
- Increases hosting costs vs. static generation
- Needs caching strategy to avoid redundant renders

```
// Cache SSR responses where data is shared across users
Cache-Control: s-maxage=60, stale-while-revalidate   // 60s fresh, revalidate in background
```

---

## ✅ Good Use Cases

| Use case | Why SSR works |
|----------|--------------|
| Personalized pages | Data is per-user; can't be cached statically |
| Real-time data (news, stock, scores) | Must be fresh on every request |
| Search results | Query-dependent, unique per request |
| Social feeds | Per-user content + SEO requirements |
| Auth-gated but SEO-relevant pages | Fresh + crawlable |

## ❌ Poor Use Cases

| Use case | Why SSR is overkill |
|----------|---------------------|
| Static marketing pages | Same content for everyone → use SSG |
| Docs / blogs | Infrequent updates → use SSG or ISR |
| High-traffic pages with shared data | Server costs + latency → use ISR |
| Pure interaction-only UI (no SEO) | Auth-gated → use SPA |

---

## Frameworks

| Framework | SSR mechanism |
|-----------|--------------|
| Next.js | `getServerSideProps` (Pages Router), Server Components (App Router) |
| Remix | Loader functions; SSR by default |
| Nuxt | `asyncData` / `useFetch` with SSR mode |
| Angular Universal | `@nguniversal/express-engine` |
| SvelteKit | `load` functions with SSR by default |

---

## Related Notes

- [[Web Rendering Patterns - SPA]] — the FCP/SEO problem that SSR solves
- [[Web Rendering Patterns - SSG]] — avoids server compute by pre-building HTML
- [[Web Rendering Patterns - Comparison]] — full side-by-side tradeoffs
- [[React Reconciliation - Virtual DOM and Fiber]] — how React's fiber handles server rendering and hydration
