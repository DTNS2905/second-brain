---
tags:
  - build-tools
  - meta-frameworks
  - comparison
  - tooling
  - frontend
created: 2026-07-16
source: https://patterns.dev/
---

# Build Tools Meta-frameworks — Comparison and Decision Guide

> A decision matrix for picking a meta-framework in 2026 — by rendering mode, ecosystem, deploy target, RSC readiness, and edge-runtime support. Part of [[Build Tools Meta-frameworks Guide]].

---

## The at-a-glance matrix

| | Next.js | Remix/RR7 | Astro | Nuxt | SvelteKit | TanStack Start |
|---|---------|-----------|-------|------|-----------|----------------|
| UI framework | React | React | Any / mix | Vue | Svelte | React |
| Bundler | Webpack/Turbopack | Vite | Vite | Vite | Vite | Vite |
| RSC | ✅ (native) | 🟡 (adding) | ❌ (Islands) | ❌ | ❌ | ❌ |
| SSR streaming | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| SSG | ✅ | ✅ | ✅✅ (default) | ✅ | ✅ | ✅ |
| ISR | ✅ | 🟡 (via adapter) | 🟡 | ✅ (via routeRules) | 🟡 | 🟡 |
| Edge runtime | ✅ (per route) | ✅ | ✅ | ✅ (Nitro presets) | ✅ | ✅ |
| Router paradigm | File-system | File-system | File-system | File-system | File-system | Code-based |
| Data pattern | Server Components + fetch | loader / action | Component script | `useAsyncData` | `+page.server.ts` load | Route-based loaders |
| Deploy adapters | Vercel-first, others via next-start / OpenNext | Per-target adapters | Per-target adapters | Nitro presets | Per-target adapters | Per-target adapters |

The matrix is the whole point of this note — everything below is nuance layered on top of these rows. Read the column for the framework you're evaluating, then read the row for the constraint that matters most.

---

## Decision axes

Five axes cover ~90% of the decision. Rank them for your project, then filter the matrix.

- **UI framework** — locked in for the app's life. Migrating between React/Vue/Svelte after launch is a rewrite, not a refactor. Pick UI framework first, meta-framework second.
- **Interactivity level** — mostly static? mostly interactive? A docs site and a Figma-like app land on opposite ends of this spectrum, and the right tool differs.
- **Deploy target** — Vercel? Cloudflare? own Node server? Adapter maturity varies wildly. Some frameworks ship first-class support for a single host and treat others as second-class.
- **Team familiarity** — Next has the biggest ecosystem; smaller frameworks are simpler. If your team has zero Vue experience, Nuxt is a bigger jump than staying in React with Next.
- **RSC needed?** — only Next has it fully today. If you don't need RSC, you have far more options.

---

## When to pick Next.js

✅ You're on React and want RSC
✅ Enterprise / large team with React expertise
✅ Vercel deploy is fine or explicitly wanted
✅ You want the biggest ecosystem
❌ You want to escape Webpack's mental model
❌ You want minimal opinions and config

Next.js is the default choice when the answer to "what framework?" is genuinely unclear. Its ecosystem — hiring pool, third-party libraries, tutorials, deployment tooling — is larger than the next three combined. Cross-link [[Build Tools Meta-frameworks - Next.js Build Pipeline]].

The trade-off is opinion density: RSC, Server Actions, App Router, Route Handlers, Middleware, and Turbopack are all first-class abstractions you must learn. If you want a thin framework, look elsewhere.

---

## When to pick Remix / RR7

✅ You're on React and prefer explicit `loader` / `action` over RSC magic
✅ You already use React Router
✅ You value Web Fundamentals (forms, URLs, HTTP)
✅ You want multi-target deploys without Vercel lock-in
❌ RSC is a requirement today

Remix (now merged into React Router 7) is the anti-magic React framework. Data comes from `loader`, mutations go through `action`, and the transport is `<Form>` or `fetch`. No `use client` / `use server` split.

```tsx
export async function loader({ params }: LoaderFunctionArgs) {
  return json(await db.post.findUnique({ where: { id: params.id } }));
}

export default function Post() {
  const post = useLoaderData<typeof loader>();
  return <article>{post.body}</article>;
}
```

Cross-link [[Build Tools Meta-frameworks - Remix and React Router 7]] for build-pipeline detail.

---

## When to pick Astro

✅ Content-first site (blog, docs, marketing)
✅ Zero-JS-by-default is a priority
✅ Islands architecture matches your interactivity pattern
✅ You want to mix React + Vue + Svelte components
❌ Full-app SPA feel — Next/Remix serve that better

Astro is the only framework where "no JavaScript on this page" is the default, not a special mode. Ships zero JS unless a component is explicitly hydrated with `client:load`, `client:idle`, `client:visible`, or `client:media`.

```astro
---
const posts = await fetchPosts();
---
<html>
  <h1>Blog</h1>
  {posts.map((p) => <PostCard post={p} />)}
  <Search client:idle />
</html>
```

Cross-link [[Build Tools Meta-frameworks - Astro Build Pipeline]].

---

## When to pick Nuxt

You're on Vue. That's basically it. Vue devs choosing between frameworks would pick Nuxt every time.

Nuxt's Nitro server layer is arguably the most portable deploy layer in the meta-framework world — one build output with presets for Vercel, Netlify, Cloudflare Workers, Deno Deploy, Node, AWS Lambda, Firebase, and more. If deploy portability is the axis, Nitro is the state of the art.

Cross-link [[Build Tools Meta-frameworks - Nuxt and SvelteKit]].

---

## When to pick SvelteKit

You're on Svelte. Same story.

SvelteKit's `+page.server.ts` / `+page.ts` split is one of the cleanest server-vs-client data models in any framework — closer to Remix's philosophy than Next's, with the added benefit that Svelte's compile-time reactivity means shipped JS is significantly smaller than an equivalent React app.

---

## When to pick TanStack Start

✅ You value code-based routing over file-system
✅ You're already using TanStack Query / Router
✅ You want a smaller, less opinionated framework
❌ You want the mature ecosystem

TanStack Start is the newest entrant. Its code-based router is a genuine break from the file-system convention every other framework has settled on — routes are defined as objects with explicit `loader` / `component` / `errorComponent` fields. Type-safety is best-in-class because the router is code, not filenames.

```ts
export const Route = createFileRoute('/posts/$postId')({
  loader: async ({ params }) => fetchPost(params.postId),
  component: PostComponent,
});
```

Trade-off: ecosystem is small, plugin universe is thin, and RSC is not on the roadmap in the way it is for Next.

---

## RSC readiness

- **Full RSC support today**: Next.js
- **Adding RSC**: Remix/RR7, Waku (React-only RSC framework)
- **Different model (Islands)**: Astro — arguably a simpler-but-less-flexible alternative
- **Not RSC**: Nuxt, SvelteKit (they have their own server-component-like models)

If RSC is a hard requirement in 2026, Next is the only production-ready answer. Everything else is either "coming soon" (RR7, Waku) or a different model entirely (Islands, Server Components in Vue/Svelte are called that but behave differently).

Cross-link [[Build Tools Meta-frameworks - RSC and the Bundler]] for how RSC changes the build pipeline.

---

## Hosting adapter fit

| Target | Best fit |
|--------|----------|
| Vercel | Next.js |
| Cloudflare Workers | Astro, SvelteKit, Nuxt (Nitro) |
| Cloudflare Pages | Any Vite-based framework |
| Netlify | Any adapter-based framework |
| AWS Lambda | Any (via community adapters) |
| Node server (own hosting) | Any (with node adapter) |
| Static host (S3, GitHub Pages) | Astro (best), Next SSG, SvelteKit adapter-static |
| Deno Deploy | Fresh (Deno-native), any Nitro/adapter framework |
| Bun | Any (via Node adapter; some frameworks getting native Bun adapters) |

The pattern: **Next.js is Vercel-first**, **Vite-based frameworks are host-agnostic**. If you're locked to a specific host, work backwards from the adapter list — pick the framework with a first-party adapter for your target, not the framework with the biggest ecosystem.

Astro's static output is the smallest and simplest deployable — a folder of HTML + JS you can drop on any CDN. SvelteKit's `adapter-static` matches it. Next's SSG produces static files too, but the runtime-optional split is fuzzier.

---

## Edge-runtime support

- **Next.js** — edge-per-route (`export const runtime = 'edge'`)
- **Astro** — full edge (`adapter-cloudflare`, `adapter-vercel-edge`)
- **Nuxt** — Nitro presets for every edge runtime
- **SvelteKit** — adapters
- **Remix / RR7** — adapters
- All are viable on edge; the constraints are what deps you can use (no Node built-ins)

The edge constraint isn't the framework — it's your dependencies. Prisma, `fs`, `path`, `crypto` (partial), most ORMs — these break on Cloudflare Workers regardless of which meta-framework you picked. Framework choice affects **how granular** your edge decision is:

```ts
export const runtime = 'edge';
export default async function Page() {
  const data = await fetch('https://api.example.com/data').then(r => r.json());
  return <pre>{JSON.stringify(data)}</pre>;
}
```

Next's per-route edge is unique — every other framework is all-or-nothing at the deploy level. That matters when you want 90% Node routes + 10% edge routes in the same app (e.g., an auth middleware on edge, page rendering on Node).

---

## Framework decision flowchart

```
Q1: What UI framework?
  React  → Q2
  Vue    → Nuxt
  Svelte → SvelteKit
  Mix    → Astro

Q2 (React): How interactive is the app?
  Mostly static → Astro (React Islands)
  Mostly dynamic → Q3

Q3 (React, dynamic): RSC required?
  Yes → Next.js
  Prefer explicit data flow → Remix / RR7
  Small / code-based routing → TanStack Start
```

Notice how few questions it takes. In practice, most teams answer Q1 in seconds — the UI framework is a hiring/existing-codebase constraint. The real decision is Q2/Q3 for React teams.

For Vue and Svelte teams, the meta-framework choice is essentially made for you. That's not a limitation — it's a benefit. One canonical choice per ecosystem means less fragmentation, more shared tooling, deeper docs.

---

## Micro-frontend consideration

- **Module Federation** — Webpack-based; Next fits best
- **Different origin per app** — any framework, use iframes or the shell-app pattern
- **RSC boundaries** — Next-native way to split team ownership within an app

Cross-link [[Build Tools Webpack - Module Federation]].

Micro-frontends via Module Federation are historically a Webpack feature. Vite has plugins (`vite-plugin-federation`) but the ergonomics lag Webpack's native support. If micro-frontends are core to your architecture and you want Module Federation specifically, **Next.js with Webpack** (not Turbopack yet) is the safest pick.

The alternative — RSC boundaries as team split points — is Next-native. Each team owns a folder in `app/`, exports Server Components, and consumers `import` them like any other module. No runtime federation, but no build-time isolation either.

---

## Long-term migration paths

- Next → Turbopack (opt-in flag)
- Remix 2 → RR7 (codemod)
- Any → Rust bundler (all Vite-based will benefit from Rolldown; Next has Turbopack)
- Everyone → RSC when frameworks add it (or you pick Next now)

Meta-frameworks are moving in the same direction: Rust bundlers underneath, RSC-or-Islands on top, edge-first deploy. Picking the "wrong" framework in 2026 is less risky than in 2022 — the abstractions are converging.

That said: **framework migrations are expensive**. Even the Remix → RR7 codemod is weeks of work for a nontrivial app. Bundler migrations (Webpack → Turbopack, Vite → Rolldown) are cheaper because the bundler is behind the framework abstraction, but they still require testing every bundle-output edge case.

The stable bet in 2026: pick a Vite-based framework if you want portability, pick Next if you want the ecosystem, pick Astro if content is king. Everything else is nuance.

---

## Related

- [[Build Tools Meta-frameworks - Next.js Build Pipeline]]
- [[Build Tools Meta-frameworks - Remix and React Router 7]]
- [[Build Tools Meta-frameworks - Astro Build Pipeline]]
- [[Build Tools Meta-frameworks - Nuxt and SvelteKit]]
- [[Build Tools Meta-frameworks - RSC and the Bundler]]
- [[Build Tools Meta-frameworks Guide]]
