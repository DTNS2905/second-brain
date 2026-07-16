---
tags:
  - build-tools
  - meta-frameworks
  - nuxt
  - sveltekit
  - tooling
  - frontend
created: 2026-07-16
source: https://nuxt.com/docs/guide/concepts/rendering
---

# Build Tools Meta-frameworks — Nuxt and SvelteKit

> The canonical meta-frameworks for Vue and Svelte. Both sit on Vite; both use adapters for deploy targets. Understanding their build pipelines shows what "Next.js for a different UI framework" looks like. Part of [[Build Tools Meta-frameworks Guide]].

---

## Nuxt 3 — overview

Nuxt is the meta-framework for Vue. It bundles routing, SSR, data-loading, and a universal server runtime into a single opinionated stack.

- **UI framework**: Vue 3
- **Bundler**: Vite (dev + build)
- **Runtime**: Nitro (universal server built on unenv + h3)
- **Router**: file-system routing from `pages/`
- **Rendering**: SSR + SSG + hybrid + edge

Unlike Next.js — which is React-specific and tightly coupled to Vercel's runtime — Nuxt separates the "UI framework layer" (Nuxt itself) from the "server layer" (Nitro). This split is why Nuxt runs cleanly on Node, Cloudflare Workers, Deno Deploy, or as static output with no config drama.

---

## Nitro — the universal server engine

Nitro is Nuxt's server runtime. It is not Nuxt-specific — it's a general-purpose universal Node/Edge/serverless framework that Nuxt happens to use.

- **Presets**: Node, Vercel, Cloudflare, Deno, Netlify, AWS Lambda, Bun, static, etc.
- **h3**: minimal HTTP framework (event-based, tree-shakeable)
- **unenv**: shim layer that makes Node APIs (`fs`, `crypto`, `stream`, etc.) work on edge runtimes

The build output is a single-file server bundle sized to the target platform. Cloudflare gets a Workers-shaped entry; Vercel gets an `output/functions/` shape; Node gets a plain `index.mjs` you can `node`.

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  nitro: {
    preset: 'cloudflare-pages',
  },
});
```

By separating framework (Nuxt) from server (Nitro), the same server engine can be used standalone or by other tools — Analog (Angular meta-framework) and others build on Nitro directly.

---

## Nuxt directory conventions

```
nuxt-app/
├── pages/          file-system routes
├── layouts/        Vue layout components
├── components/     auto-imported components
├── composables/    auto-imported composables (hooks)
├── middleware/     route middleware
├── plugins/        Vue plugins
├── server/         Nitro server routes (API + middleware)
│   ├── api/hello.ts
│   ├── middleware/
│   └── routes/
├── public/         static assets
├── assets/         processed assets
├── nuxt.config.ts
└── app.vue
```

Auto-import is a big Nuxt feature — no manual `import` needed for anything in `components/`, `composables/`, `utils/`. The Vite plugin scans these directories and injects imports at build time.

```vue
<!-- pages/index.vue -->
<script setup>
// No imports needed — useAsyncData is auto-imported
const { data } = await useAsyncData('posts', () => $fetch('/api/posts'));
</script>

<template>
  <PostList :posts="data" />
  <!-- <PostList> auto-imported from components/PostList.vue -->
</template>
```

---

## Nuxt build flow

1. **Dev**: Vite dev server drives both client and SSR. Nitro runs the dev server via h3 with HMR wired through Vite.
2. **`nuxt build`**: Vite build runs twice — one client bundle, one SSR bundle.
3. **Nitro packaging**: Nitro takes the SSR bundle + everything in `server/` and produces a single-file server at `.output/server/index.mjs`.
4. **Preset shaping**: Nitro applies the target preset (Node / Vercel / Cloudflare) to shape the entry file and folder structure for that platform.

```
.output/
├── public/          static assets (client bundle + `/public`)
├── server/
│   ├── index.mjs    the server entry
│   ├── chunks/
│   └── node_modules/
└── nitro.json
```

Result: `.output/` is portable — deploy it to any Nitro-supported platform without re-building.

---

## Nuxt SSR modes

Nuxt exposes rendering as a per-route knob, not a global choice.

- **`ssr: true`** (default) — server-rendered pages, hydrated on the client
- **`ssr: false`** — SPA mode; client-only, no server render
- **Hybrid rendering** — per-route via `routeRules`

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  routeRules: {
    '/':          { prerender: true },          // SSG
    '/blog/**':   { swr: 3600 },                // stale-while-revalidate
    '/admin/**':  { ssr: false },               // SPA
    '/api/**':    { cors: true, headers: { 'cache-control': 's-maxage=60' } },
    '/product/**':{ isr: true },                // ISR (Vercel)
  },
});
```

`swr` = stale-while-revalidate: serve cached HTML, revalidate in background. `isr` = incremental static regeneration on platforms that support it.

---

## Nuxt data fetching

Two auto-imported composables cover most cases:

```vue
<script setup>
// useFetch — thin wrapper over $fetch with SSR-aware caching
const { data, error, refresh } = await useFetch('/api/posts');

// useAsyncData — arbitrary async work, keyed for hydration
const { data } = await useAsyncData('user', () => db.users.findMe());
</script>
```

Both handle the SSR → client handoff: the server executes the fetch, serializes the payload into the HTML, and the client hydrates from that payload instead of re-fetching.

---

## Nuxt modules

Modules are Nuxt's extension system. A module is an npm package that hooks into the build and can register:

- Vite plugins
- Nitro plugins
- Auto-imports
- Components
- Runtime config
- Middleware
- Type augmentations

Ecosystem highlights:

- `@nuxt/content` — file-based CMS
- `@nuxt/image` — image optimization
- `@nuxt/ui` — component library
- `@pinia/nuxt` — state management
- `@nuxtjs/tailwindcss` — Tailwind integration
- `@nuxtjs/i18n` — internationalization

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  modules: [
    '@nuxt/content',
    '@nuxt/image',
    '@pinia/nuxt',
  ],
});
```

Modules can compose — one module can install another as a dependency. This is closer to Rails engines than to Next.js plugins.

---

## SvelteKit — overview

SvelteKit is the meta-framework for Svelte.

- **UI framework**: Svelte 5 (with runes)
- **Bundler**: Vite (dev + build)
- **Router**: file-system routing from `src/routes/`
- **Rendering**: SSR + SSG + hybrid via adapters
- **Compiler**: Svelte compiler (compiles reactive `.svelte` files to imperative JS)

SvelteKit is unusual in that its UI framework is a *compiler*, not a runtime. The `.svelte` file format compiles down to plain JS with fine-grained reactivity — there's no virtual DOM, no diffing, no reconciler. The build pipeline has to hand `.svelte` files to the Svelte compiler before Vite processes them (via `@sveltejs/vite-plugin-svelte`).

---

## SvelteKit directory conventions

```
src/
├── routes/
│   ├── +page.svelte          UI for /
│   ├── +page.ts              Universal load (server first, then client)
│   ├── +page.server.ts       Server-only load + form actions
│   ├── +layout.svelte        Nested layout
│   ├── +layout.server.ts     Layout-level server load
│   ├── +server.ts            Endpoint (resource route)
│   ├── +error.svelte         Error boundary
│   └── blog/
│       └── [slug]/
│           ├── +page.svelte
│           └── +page.server.ts
├── lib/                      $lib alias (import from '$lib/…')
│   └── server/               server-only, compile-time enforced
├── app.html                  root HTML template
├── hooks.server.ts           server middleware
└── hooks.client.ts           client hooks
```

The `+` prefix distinguishes framework files (routes, loads, actions) from regular files. A folder can contain non-`+` files — components, utilities — that won't be treated as routes.

`$lib/server/` is special: SvelteKit throws a build error if any client code imports from it, so server secrets stay server-side.

---

## SvelteKit load functions

`load` is SvelteKit's data-fetching primitive. Two variants:

```ts
// +page.server.ts — server-only, has access to secrets, cookies, DB
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ params, cookies }) => {
  const token = cookies.get('session');
  return { post: await db.posts.find(params.slug, token) };
};

export const actions: Actions = {
  save: async ({ request, params }) => {
    const data = await request.formData();
    await db.posts.update(params.slug, data);
    return { success: true };
  },
  delete: async ({ params }) => {
    await db.posts.delete(params.slug);
  },
};
```

```ts
// +page.ts — universal, runs on server first, then client on nav
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params }) => {
  const res = await fetch(`/api/posts/${params.slug}`);
  return { post: await res.json() };
};
```

Rules of thumb:

- `.server.ts` variant — server-only; secrets safe; runs on every request
- `.ts` variant — universal; runs on server for first hit, on client for subsequent navigations
- `+page.server.ts` `load` + `+page.ts` `load` can coexist — server load runs, then universal load receives its data via `data` param

Form actions replace the "API route" convention for form submissions — write a plain function, let SvelteKit handle progressive enhancement.

---

## SvelteKit adapters

Same model as Astro and React Router 7 — one framework, many deploy targets.

```ts
// svelte.config.js
import adapter from '@sveltejs/adapter-node';

export default {
  kit: {
    adapter: adapter({
      out: 'build',
      precompress: true,
    }),
  },
};
```

Available adapters:

| Adapter | Target |
|---------|--------|
| `adapter-node` | Long-running Node server |
| `adapter-vercel` | Vercel Functions / Edge Functions |
| `adapter-cloudflare` | Cloudflare Pages / Workers |
| `adapter-netlify` | Netlify Functions / Edge |
| `adapter-static` | Pure static (SSG) |
| `adapter-auto` | Auto-detects platform in CI |

The adapter runs after `vite build`. It receives SvelteKit's build artifacts and produces platform-shaped output — a Node entry, a Cloudflare Worker, a Vercel `functions/` layout, or a `static/` directory.

---

## SvelteKit build flow

1. Vite build produces client and server bundles, running each `.svelte` file through the Svelte compiler first
2. SvelteKit merges routes into a manifest (`.svelte-kit/output/`)
3. The adapter takes the raw output and shapes it for the target platform
4. Final output goes to the adapter's chosen directory (`build/`, `.vercel/`, etc.)

```
.svelte-kit/          intermediate framework output
build/                final adapter output (adapter-node)
```

---

## SvelteKit prerendering

SSG works via a `prerender` export or route config:

```ts
// +page.ts
export const prerender = true;
```

```ts
// +layout.ts
export const prerender = 'auto'; // prerender if possible, else SSR
```

Or in `svelte.config.js`:

```ts
kit: {
  prerender: {
    entries: ['*'],       // crawl and prerender everything reachable
    handleMissingId: 'warn',
  },
}
```

With `adapter-static`, this becomes SSG for the whole site.

---

## Common ground

| Concept | Nuxt | SvelteKit |
|---------|------|-----------|
| UI framework | Vue | Svelte |
| Bundler | Vite | Vite |
| Server runtime | Nitro | Adapter (per target) |
| File routing | `pages/` | `src/routes/` |
| Data loaders | Composables + `useAsyncData` | `+page.server.ts` load |
| Server routes | `server/api/*.ts` (h3) | `+server.ts` |
| Deploy targets | Nitro presets | Adapters |
| Static export | `nitro.preset: 'static'` | `adapter-static` |
| Streaming SSR | Yes | Yes |
| Form actions | Nitro API + `useFetch` | Native form actions |
| Auto-import | Yes (built-in) | No (explicit imports) |

Both frameworks land on the same shape: Vite for build, an adapter/preset layer for deploy target, file-system routing, and a server/universal data-loader split.

---

## Why they differ from Next

- **No RSC** — server components aren't a Vue/Svelte concept the same way. Vue has a `Server Component` proposal but nothing shipped; Svelte's compiler-based model already produces small enough output that the RSC problem is less pressing.
- **Adapter model** — cleaner separation of "framework" and "deploy target" than Next's Vercel-first design. Adapters are userland packages; you can write one.
- **Vite-native** — no Webpack legacy; smaller config surface. Nuxt 2 was Webpack + Vue 2; Nuxt 3 was a full rewrite on Vite + Vue 3.
- **Different reactivity** — Vue uses signals (`ref`, `reactive`); Svelte uses runes (`$state`, `$derived`). The compiler assumes reactive primitives Next/React don't have, so hydration and component boundaries look different.
- **Smaller runtime** — Svelte's compiled output is often smaller than the equivalent React app because there's no VDOM runtime shipped.

See [[Build Tools Meta-frameworks - RSC and the Bundler]] for why RSC is a React-specific concept.

---

## Cross-framework parallels

| Concept | Next.js | Nuxt | SvelteKit | Remix/RR7 |
|---------|---------|------|-----------|-----------|
| Data (server) | RSC / `fetch` | `useAsyncData` | `+page.server.ts` `load` | `loader` |
| Data (universal) | `use client` + `fetch` | `useFetch` | `+page.ts` `load` | `clientLoader` |
| Mutations | Server Actions | Nitro API routes | Form `actions` | `action` |
| API routes | `route.ts` | `server/api/*.ts` | `+server.ts` | Resource routes |
| Layouts | `layout.tsx` | `layouts/` | `+layout.svelte` | `_layout.tsx` |
| Streaming | RSC-native | Yes (Nitro) | Yes | `defer` |
| Middleware | `middleware.ts` | `server/middleware/` | `hooks.server.ts` | Route middleware |
| Env vars | `NEXT_PUBLIC_*` | `runtimeConfig` | `$env/static/*`, `$env/dynamic/*` | `loader` context |
| RSC | Yes | No (yet) | No | Being added |

---

## When to pick each

- **Nuxt** — you're on Vue. Rich module ecosystem, best-in-class DX for Vue teams, Nitro's deploy story is unmatched.
- **SvelteKit** — you're on Svelte. Smallest output, cleanest reactivity model, adapters for every platform.
- **Next.js** — you're on React and want RSC. Best Vercel integration, biggest ecosystem, RSC is production-ready.
- **Remix/RR7** — you're on React and prefer explicit loader/action data flow over the RSC model. Web-standards-first, better multi-runtime story than Next.

See [[Build Tools Meta-frameworks - Comparison and Decision Guide]] for a fuller decision matrix.

---

## Related

- [[Build Tools Vite - Architecture Overview]]
- [[Build Tools Vite - SSR and Environments]]
- [[Build Tools Meta-frameworks - Next.js Build Pipeline]]
- [[Build Tools Meta-frameworks - Comparison and Decision Guide]]
- [[Build Tools Meta-frameworks Guide]]
