---
tags:
  - web
  - rendering-patterns
  - frontend
created: 2026-06-08
source: https://web.dev/articles/rendering-on-the-web
---

# Web Rendering Patterns - SSG

> Static Site Generation: HTML built once at deploy time, served from CDN edges globally. Part of [[Web Rendering Patterns Guide]].

---

## How It Works

```
Build time (CI/CD, not request time):
  ↓
Framework fetches all data
  ↓
Renders every page to a static .html file
  ↓
Files uploaded to CDN (globally distributed edge nodes)

User navigates to URL:
  ↓
Nearest CDN edge returns pre-built HTML instantly
  ↓
Browser displays content (FCP ✅, TTFB ✅✅)
  ↓
JS bundle hydrates if interactivity needed
```

No server compute at request time. Every visitor gets a pre-built file.

---

## SSG vs SSR: The Core Difference

| Aspect | SSG | SSR |
|--------|-----|-----|
| When HTML is built | Build time (once) | Request time (every visit) |
| Who builds it | Build server / CI | Live application server |
| Served from | CDN edge | Origin server |
| Content freshness | Stale until rebuild | Always fresh |
| Server cost | ✅ None at runtime | ❌ Scales with traffic |

---

## Performance Profile

| Metric | SSG behavior | Why |
|--------|-------------|-----|
| TTFB | ✅✅ Fastest | CDN edge responds; no server compute |
| FCP | ✅ Fast | Full HTML in first response |
| TTI | ✅ Good | Minimal JS needed; no mandatory hydration |
| TBT | ✅ Low | Less JS = less main thread blocking |
| SEO | ✅✅ Best | Pre-rendered, fast, crawlable |

---

## Next.js Implementation

```javascript
// pages/blog/[slug].js
export async function getStaticProps({ params }) {
  const post = await fetchPost(params.slug);   // runs at build time only

  return {
    props: { post }
  };
}

export async function getStaticPaths() {
  const posts = await fetchAllPosts();

  return {
    paths: posts.map(p => ({ params: { slug: p.slug } })),
    fallback: false   // 404 for unknown slugs
  };
}

export default function BlogPost({ post }) {
  return <Article post={post} />;
}
```

`getStaticProps` and `getStaticPaths` only run at build time — never on the server at runtime.

---

## Incremental Static Regeneration (ISR)

SSG limitation: content is stale until you redeploy. ISR solves this by **regenerating pages in the background** after a set interval, without a full rebuild.

```javascript
export async function getStaticProps() {
  const data = await fetchData();

  return {
    props: { data },
    revalidate: 3600   // regenerate this page at most once per hour
  };
}
```

**ISR request flow:**

```
First request after revalidation window expires:
  → Serve stale page immediately (user gets fast response)
  → Trigger background regeneration
  → Next request gets the fresh page

Requests during revalidation window:
  → Serve cached (fresh) page instantly — same speed as pure SSG
```

ISR first-hit-after-expiry behaves like SSR (TTFB slightly slower), but all subsequent hits are CDN-fast.

### On-demand ISR (Next.js)

```javascript
// pages/api/revalidate.js — call this from a CMS webhook
export default async function handler(req, res) {
  await res.revalidate('/blog/my-post');  // regenerate specific page now
  return res.json({ revalidated: true });
}
```

On-demand ISR is preferred over time-based — regenerate exactly when content changes, not on a timer.

---

## Staleness Trade-off

SSG is incompatible with data that must be fresh per-request:

```
✅ SSG appropriate:           ❌ SSG not appropriate:
  Blog post content              User's account page
  Product descriptions           Live stock prices
  Documentation                  Search results
  Team/about pages               Real-time scores
  Marketing pages                Personalized recommendations
```

For pages with mixed static + dynamic content, use **SSG + client-side fetch**:

```jsx
// Page shell is SSG (fast FCP), live data fetched client-side
export async function getStaticProps() {
  return { props: { productId: '123' } };  // static shell
}

export default function ProductPage({ productId }) {
  const { price } = useSWR(`/api/price/${productId}`);  // live price client-side

  return (
    <div>
      <StaticProductInfo />          {/* from SSG */}
      <LivePrice price={price} />    {/* from client fetch */}
    </div>
  );
}
```

---

## ✅ Good Use Cases

| Use case | Why SSG works |
|----------|--------------|
| Blogs, portfolios | Content rarely changes; fastest possible load |
| Marketing / landing pages | SEO + Core Web Vitals critical |
| Documentation sites | Static by nature (Docusaurus, Nextra) |
| E-commerce product pages | ISR handles price/stock freshness |
| Large catalogs | ISR scales to millions of pages without full rebuilds |

## ❌ Poor Use Cases

| Use case | Why SSG fails |
|----------|--------------|
| Per-user dashboards | Can't pre-render personalized content |
| Real-time data | Build-time snapshot is always stale |
| Unknown URL count | `getStaticPaths` can't enumerate infinite paths |
| Search results | Query-driven, unique per request |

---

## Frameworks

| Framework | SSG support |
|-----------|------------|
| Next.js | `getStaticProps` + `getStaticPaths`, ISR built-in |
| Gatsby | GraphQL-driven build-time data fetching |
| Astro | Zero-JS by default; HTML-first SSG |
| Eleventy (11ty) | Template-based SSG, no framework lock-in |
| Nuxt | `nuxt generate` for full static export |
| SvelteKit | `prerender = true` per route |

---

## Related Notes

- [[Web Rendering Patterns - SSR]] — per-request rendering when SSG is too stale
- [[Web Rendering Patterns - SPA]] — when content is fully dynamic and SEO doesn't apply
- [[Web Rendering Patterns - Comparison]] — full side-by-side + decision guide
- [[Web Rendering Patterns Guide]] — quick-reference decision flowchart
