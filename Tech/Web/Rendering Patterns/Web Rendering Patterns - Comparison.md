---
tags:
  - web
  - rendering-patterns
  - frontend
created: 2026-06-08
source: https://vercel.com/blog/how-to-choose-the-best-rendering-strategy-for-your-app
---

# Web Rendering Patterns - Comparison

> Full side-by-side tradeoffs, performance table, decision flowchart, and hybrid patterns for SPA / SSR / SSG / ISR. Part of [[Web Rendering Patterns Guide]].

---

## Full Comparison Table

| Aspect | SPA / CSR | SSR | SSG | ISR |
|--------|-----------|-----|-----|-----|
| HTML built | Browser (JS) | Server (per request) | Build server (once) | Build + background refresh |
| TTFB | ✅ Fast | ⚠️ Slower | ✅✅ Fastest | ✅✅ Fastest* |
| FCP / LCP | ❌ Slow | ✅ Fast | ✅ Fast | ✅ Fast |
| TTI | ❌ Slow | ⚠️ Delayed (hydration) | ✅ Good | ✅ Good |
| TBT | ❌ High | ⚠️ Medium | ✅ Low | ✅ Low |
| SEO | ❌ Poor | ✅ Good | ✅✅ Best | ✅✅ Best |
| Data freshness | ✅ Real-time | ✅ Real-time | ❌ Build-time | ⚠️ Periodic |
| Personalization | ✅ Full | ✅ Full | ❌ None | ❌ None** |
| Server cost | ✅ None | ❌ High (scales w/ traffic) | ✅ None | ✅ Minimal |
| Build time | ✅ Fast | ✅ Fast | ⚠️ Slow (large sites) | ⚠️ Medium |
| Caching | ⚠️ App shell only | ⚠️ Manual CDN cache | ✅ Full CDN | ✅ Full CDN |
| JS required | ✅ Yes (all rendering) | ⚠️ Yes (hydration) | ❌ Optional | ❌ Optional |

\* ISR first-hit-after-expiry equals SSR speed; all subsequent hits equal SSG speed.  
\*\* ISR can be combined with client-side fetch for user-specific data.

---

## Performance Metrics at a Glance

| Pattern | TTFB | FCP | TTI | TBT | INP |
|---------|------|-----|-----|-----|-----|
| SPA | 🟢 Fast | 🔴 Slow | 🔴 Slow | 🔴 High | 🟢 Fast (post-load) |
| SSR | 🟡 Medium | 🟢 Fast | 🟡 Delayed | 🟡 Medium | 🟢 Good |
| SSG | 🟢 Fastest | 🟢 Fast | 🟢 Good | 🟢 Low | 🟢 Good |
| ISR | 🟢 Fastest | 🟢 Fast | 🟢 Good | 🟢 Low | 🟢 Good |

---

## Decision Flowchart

```
START: What is this page?
│
├── Is content the same for every user (no personalization)?
│   ├── YES → Does content change?
│   │          ├── Never / rarely       → ✅ SSG
│   │          ├── Periodically (hours) → ✅ ISR
│   │          └── Every request        → ✅ SSR
│   │
│   └── NO (per-user content) → Does this page need SEO?
│                                ├── YES → ✅ SSR
│                                └── NO  → ✅ SPA
│
└── Is it purely interactive (app, dashboard, tool)?
    └── Behind auth, no public crawlers → ✅ SPA
```

---

## Industry Patterns

### E-Commerce

| Page | Pattern | Why |
|------|---------|-----|
| Homepage | SSG | Same for everyone; SEO critical |
| Category pages | ISR | Inventory changes; millions of variants |
| Product detail | ISR | Descriptions static; price/stock refreshed |
| Search results | SSR | Query-unique, must be fresh |
| Cart / Checkout | SPA | Auth-gated, highly interactive |
| User dashboard | SSR or SPA | Per-user, personalized |

### Content / Media Sites

| Page | Pattern | Why |
|------|---------|-----|
| Article / blog post | SSG | Static content; max SEO performance |
| Homepage (latest) | ISR (1hr) | Curated list updates occasionally |
| Breaking news | SSR | Must be seconds-fresh |
| Author profile | ISR | Rarely changes |

### SaaS / Apps

| Page | Pattern | Why |
|------|---------|-----|
| Marketing site | SSG | SEO, Core Web Vitals |
| Docs | SSG | Static, version-pinned |
| App (behind login) | SPA | Auth wall; no SEO needed |
| Public-facing reports | SSR or ISR | Shared data, SEO possible |

---

## Hybrid Patterns

### SSG Shell + Client-Side Data Fetch

Best of both worlds: fast initial load with real-time data where needed.

```jsx
// Shell is SSG (instant TTFB/FCP)
export async function getStaticProps() {
  return { props: { userId: null } };  // no user-specific data at build time
}

export default function ProductPage() {
  // Live/user data fetched client-side
  const { data: price } = useSWR('/api/live-price');
  const { data: cart } = useSWR('/api/cart');

  return (
    <>
      <StaticProductInfo />     {/* SSG — fast */}
      <LivePrice price={price} />   {/* CSR — fresh */}
      <AddToCart cart={cart} />     {/* CSR — interactive */}
    </>
  );
}
```

### Per-Route Strategy (Next.js)

Next.js lets each page use a different rendering strategy:

```
pages/
  index.js           → SSG  (marketing homepage)
  blog/[slug].js     → SSG + ISR  (blog posts)
  search.js          → SSR  (search results)
  dashboard.js       → SPA  (client-side only, behind auth)
  product/[id].js    → ISR  (product pages, revalidate: 3600)
```

### Partial Prerendering (PPR — experimental, Next.js)

Automatically prerender static sections, stream dynamic content through Suspense boundaries:

```jsx
// Static shell prerenders instantly; dynamic parts stream in
export default function Page() {
  return (
    <StaticShell>              {/* prerendered at build time */}
      <Suspense fallback={<Skeleton />}>
        <DynamicFeed />        {/* streamed per-request */}
      </Suspense>
    </StaticShell>
  );
}
```

Combines SSG speed with SSR freshness — the next evolution of hybrid rendering.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using SPA for a marketing site | Switch to SSG; FCP/SEO critical |
| Using SSR for a fully static blog | Switch to SSG; unnecessary server compute |
| SSG with no ISR for a product catalog | Add `revalidate` to keep prices/inventory fresh |
| Relying on SSR for personalization at massive scale | Cache shared SSR responses; use client-side for user-specific data |
| Hydrating an SSG page with heavy JS | Keep SSG pages minimal-JS; use SPA pattern for interactive parts |

---

## Related Notes

- [[Web Rendering Patterns - SPA]] — CSR deep dive
- [[Web Rendering Patterns - SSR]] — SSR + hydration deep dive
- [[Web Rendering Patterns - SSG]] — SSG + ISR deep dive
- [[Web Rendering Patterns Guide]] — quick decision flowchart
- [[React Reconciliation - Virtual DOM and Fiber]] — hydration mechanics in React
- [[React Re-renders Guide]] — what happens in the client after hydration
