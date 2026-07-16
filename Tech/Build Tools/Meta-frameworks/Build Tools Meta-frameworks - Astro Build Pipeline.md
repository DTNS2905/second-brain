---
tags:
  - build-tools
  - meta-frameworks
  - astro
  - islands
  - tooling
  - frontend
created: 2026-07-16
source: https://docs.astro.build/en/concepts/islands/
---

# Build Tools Meta-frameworks — Astro Build Pipeline

> Astro is Vite + a compiler for .astro components + the Islands architecture: zero-JS by default, hydrate only where you opt in. This note covers how the build produces that shape. Part of [[Build Tools Meta-frameworks Guide]].

---

## The Astro proposition

Ship HTML by default. Hydrate specific components — **Islands** — with a `client:*` directive. Use React, Vue, Svelte, or Solid as the island's UI framework — Astro treats them all as "renderers." The entire framework is optimized around this asymmetry: most of the page is static HTML shipped without a runtime, and only the interactive fragments carry JS.

The design axis is inverted from Next/Nuxt:

| Framework | Default | Opt-out |
|-----------|---------|---------|
| Next.js | Hydrated (full client React) | RSC / static export |
| Nuxt | Hydrated (full client Vue) | Nuxt-Island / SSG |
| Astro | Zero-JS static HTML | `client:*` on specific components |

Result: a blog homepage in Astro ships literally 0 bytes of JS unless you place an island on it.

---

## The build stack

- **Vite** — dev server and prod build. Astro is a Vite app; every plugin and integration is a Vite plugin under the hood
- **`.astro` compiler** — transforms `.astro` components into JS + HTML. Written in Go, ships as WASM
- **Framework renderers** — `@astrojs/react`, `@astrojs/vue`, `@astrojs/svelte`, `@astrojs/solid-js`. Each is a Vite plugin that registers a renderer for that framework's components
- **Adapters** — `@astrojs/node`, `@astrojs/vercel`, `@astrojs/cloudflare`, `@astrojs/deno` for deploy targets. They shape the SSR bundle to the target runtime's request/response model
- **Content Collections** — Zod-typed content, resolved at build time via `astro:content` virtual module

The compiler and Vite handle different halves: the compiler emits per-component render functions; Vite handles module graph, transforms for TS/JSX/CSS, and prod bundling via Rollup. See [[Build Tools Vite - Architecture Overview]].

---

## .astro components

```astro
---
// Component script (runs on server / at build)
import Card from './Card.astro';
const posts = await fetch('/api/posts').then(r => r.json());
---

<html>
  <body>
    <h1>Blog</h1>
    {posts.map(p => <Card title={p.title} />)}
  </body>
</html>
```

The `---` fence separates server logic from HTML template. Everything above the fence is executed **on the server or at build time**, never shipped to the client. Everything below is a JSX-like template that gets stringified to HTML.

The compiler produces:

- A JS module exporting a `render` function that produces HTML strings
- No client JS by default — the render output is HTML, not a DOM tree waiting for hydration
- A static import graph so Vite can crawl dependencies

```js
export async function render($$result, $$props) {
  const posts = await fetch('/api/posts').then(r => r.json());
  return $$render`
    <html><body>
      <h1>Blog</h1>
      ${posts.map(p => renderComponent($$result, 'Card', Card, { title: p.title }))}
    </body></html>
  `;
}
```

The whole file collapses to a template-tag call chain producing a string.

---

## Islands via `client:*` directives

```astro
---
import Counter from './Counter.tsx';
---

<Counter client:load />           <!-- hydrate immediately -->
<Counter client:idle />           <!-- hydrate on requestIdleCallback -->
<Counter client:visible />        <!-- hydrate on IntersectionObserver -->
<Counter client:media="(min-width: 800px)" /> <!-- hydrate at breakpoint -->
<Counter client:only="react" />   <!-- skip SSR entirely -->
```

Each directive is a **hydration strategy**:

| Directive | When | Use case |
|-----------|------|----------|
| `client:load` | Immediately after page load | Above-the-fold interactive UI |
| `client:idle` | `requestIdleCallback` fires | Low-priority interactivity |
| `client:visible` | Component enters viewport | Below-the-fold widgets, footers |
| `client:media` | CSS media query matches | Mobile-only or desktop-only islands |
| `client:only` | Never SSR, client-render only | Components that can't SSR (browser APIs) |

The bundler treats each `client:*` component as an **entry point in the client graph**. Its bundle is fetched only when the directive fires — no eager download of the full app.

✅ Correct — hydrate only the interactive part:

```astro
---
import ArticleBody from './ArticleBody.astro';
import CommentBox from './CommentBox.tsx';
---
<article>
  <ArticleBody />                 <!-- static HTML, 0 JS -->
  <CommentBox client:visible />   <!-- JS only when scrolled to -->
</article>
```

❌ Wrong — wrapping static content in a JSX island forces a full framework runtime for no reason:

```astro
---
import Everything from './Everything.tsx';
---
<Everything client:load />        <!-- ships the entire page as React -->
```

---

## Islands are entries

Astro's bundler adds each unique island component to `rollupOptions.input`. From Astro's perspective every `client:*` reference is a new **client entry point** — Vite can then code-split it, hash it, and produce a standalone chunk.

The result:

```
dist/
  _astro/
    Counter.abc123.js       (client bundle for Counter)
    Chart.def456.js         (client bundle for Chart)
    client.js               (shared hydration runtime, ~3 KB)
```

The shared `client.js` contains the tiny runtime that:

1. Reads the `astro-island` custom element on the page
2. Fetches the island's JS chunk lazily
3. Hydrates the specific DOM subtree with the framework's `hydrate` API

Each island's chunk imports the framework runtime (React DOM, Vue, etc.) — but only once per framework across the page thanks to Rollup deduplication.

---

## The compiler

`@astrojs/compiler` is written in Go, based on **parse5** (HTML) + a JSX-like AST. Emits:

- **Component render function** — the async function that produces HTML strings
- **Metadata** — static (build-time) vs dynamic (client) usage of each imported component
- **Hydration directives** — parsed from `client:*` attributes, forwarded to the runtime

```
.astro source  →  compiler (Go/WASM)  →  .ts module  →  Vite/esbuild  →  .js
```

The compiler is deliberately dumb about JS — it does not attempt to type-check or transform the frontmatter script beyond stripping the `---` fences. That's Vite's job. Compiler output is one virtual TS module per `.astro` file that Vite then transforms like any other TS.

The reason it's Go: parsing speed. Astro sites tend to have hundreds of pages, and cold-parsing them in JS was a startup-time bottleneck.

---

## Content Collections

```ts
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  schema: z.object({
    title: z.string(),
    pubDate: z.date(),
    tags: z.array(z.string()),
  }),
});

export const collections = { blog };
```

```astro
---
import { getCollection } from 'astro:content';
const posts = await getCollection('blog');
---
<ul>
  {posts.map(p => (
    <li><a href={`/blog/${p.slug}`}>{p.data.title}</a></li>
  ))}
</ul>
```

Content is validated at build time; type-safe queries in components. All static content is resolved during `astro build` — no fs reads at request time for static output.

The pipeline:

1. Astro scans `src/content/<collection>/` for `.md`, `.mdx`, or `.mdoc`
2. Runs frontmatter through the collection's Zod schema — build fails on type mismatch
3. Generates a `.astro/content.d.ts` with the collection's exact types
4. Exposes `astro:content` as a **virtual Vite module** that reads from an in-memory index

Because content is a virtual module, invalidating a single MD file triggers HMR only for the pages that import that collection — not a full reload.

---

## SSR vs SSG modes

- **Static** (`output: 'static'`) — default; every route pre-rendered at build. Output is pure HTML files, deployable to any CDN
- **Server** (`output: 'server'`) — everything SSR by default. Requires an adapter. Emits `dist/server/entry.mjs`
- **Hybrid** (`output: 'hybrid'`) — static default; opt-in SSR per route via `export const prerender = false`

```astro
---
// src/pages/api/live-price.astro
export const prerender = false;   // this route is SSR
const price = await getLivePrice();
---
{price}
```

Hybrid is the practical sweet spot: most of a marketing site is static, but a `/dashboard` or `/api/*` route can render per-request. Astro decides at build time which routes to pre-render and which to bundle into the server entry.

---

## Adapters

Framework abstraction for deploy target:

```ts
// astro.config.mjs
import cloudflare from '@astrojs/cloudflare';
export default { output: 'server', adapter: cloudflare() };
```

Adapters shape the SSR bundle for the target (Node, Cloudflare Workers, Vercel Edge, Deno). Each adapter provides:

- A **server entry** for the target's request format (`(req, res)` for Node, `(request) => Response` for Workers/Edge)
- **Build hooks** to emit the target's config (`vercel.json`, `_routes.json`, etc.)
- Optional **image service** and **runtime polyfill** shims

| Adapter | Runtime | Request model |
|---------|---------|---------------|
| `@astrojs/node` | Node.js | `(req, res)` — Express-like |
| `@astrojs/vercel` | Vercel Edge / Node | Fetch API `Request`/`Response` |
| `@astrojs/cloudflare` | Workers | Fetch API + Workers globals |
| `@astrojs/deno` | Deno Deploy | Fetch API |
| `@astrojs/netlify` | Netlify Functions / Edge | Fetch API |

The same Astro codebase can swap adapters without touching page code — the SSR contract is stable across them.

---

## Vite plugins in Astro

Astro integrations are typically **Vite plugin wrappers**:

```ts
// astro.config.mjs
import react from '@astrojs/react';
import svelte from '@astrojs/svelte';
export default { integrations: [react(), svelte()] };
```

Under the hood: `@vitejs/plugin-react` + Astro-specific glue that:

- Registers the framework as a **renderer** (server-render function + client hydrate function)
- Adds file extensions to Astro's resolver so `.tsx`, `.svelte`, `.vue` files are treated as island candidates
- Configures Vite's optimizeDeps to pre-bundle the framework runtime

The Astro integration API is a superset of Vite plugins — it can also hook into build lifecycle events (`astro:config:setup`, `astro:build:done`, etc.) that a bare Vite plugin cannot. See [[Build Tools Vite - Plugin API]].

---

## Zero-JS-by-default in practice

- A page with no islands ships **0 bytes of JS**
- A page with one island ships the island bundle + the shared client runtime (~3 KB)
- Astro strips out any unused framework runtime at build — if no React island is on a given route, no React runtime is loaded on that route

Per-route JS budget (typical blog post with one comment widget):

| Asset | Size (gzipped) |
|-------|----------------|
| HTML (article body) | ~5 KB |
| `client.js` (Astro runtime) | ~3 KB |
| `CommentBox.<hash>.js` | ~15 KB (React + component) |
| **Total client JS** | ~18 KB |

Compare to a naive Next.js equivalent that ships ~80 KB of framework baseline before any application code. The gap is Astro's core value proposition for content sites.

✅ Effective island usage:

```astro
<Hero />                            <!-- Astro, static -->
<ArticleBody />                     <!-- Astro, static -->
<Newsletter client:visible />       <!-- React, lazy -->
<Footer />                          <!-- Astro, static -->
```

❌ Anti-pattern — hydrating the whole page:

```astro
<Layout client:load>                <!-- ships the app as if it were an SPA -->
  <Everything />
</Layout>
```

---

## The .astro output shape

```
dist/
├── index.html                    (pre-rendered static pages)
├── blog/
│   └── post-1/index.html
├── _astro/
│   ├── Counter.abc123.js         (island bundles)
│   └── style.def456.css
└── server/                       (only if output != 'static')
    └── entry.mjs                 (adapter entry)
```

For static output, the entire `dist/` is deployable as a folder of files — any CDN, S3, or static host works. For server output, the adapter's runtime consumes `dist/server/entry.mjs` and serves requests through it.

Notable shape decisions:

- **`_astro/` prefix** — all hashed assets go here; makes CDN cache rules trivial (`_astro/*` is immutable, everything else is not)
- **Per-page HTML files** — static output is truly per-page HTML, not a client-side router shell
- **No `_next/` equivalent runtime** — the client runtime is a single small script, not a framework loader

---

## Related — where Astro fits

- **Better than Next** for content-first sites (blogs, docs, marketing). Zero-JS default is the killer feature; a Next.js blog ships an unnecessary React runtime on every page
- **Better than Nuxt** for framework-mixing. You can put a React island next to a Svelte island next to a Vue island on the same page — the other frameworks don't do that
- **Worse than Next** for heavily-interactive apps (Next's RSC serves that better — component-level server/client split with a first-class data flow). Astro Islands are page-first; RSC is component-first. See [[Build Tools Meta-frameworks - RSC and the Bundler]]
- **Comparable to Eleventy / Hugo** for pure SSG, but with a real component model and a Vite dev server instead of template DSLs

Decision heuristic:

| You want | Reach for |
|----------|-----------|
| Marketing site, blog, docs | Astro |
| Dashboard, app-shaped UI | Next / Remix |
| Vue-first content site | Nuxt (or Astro + `@astrojs/vue`) |
| Multi-framework migration | Astro |
| App with tight per-component streaming | Next RSC |

---

## Related

- [[Build Tools Vite - Architecture Overview]]
- [[Build Tools Vite - Plugin API]]
- [[Build Tools Meta-frameworks - RSC and the Bundler]] — different tradeoffs to Islands
- [[Build Tools Meta-frameworks - Comparison and Decision Guide]]
- [[Build Tools Meta-frameworks Guide]]
