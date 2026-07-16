---
tags:
  - build-tools
  - meta-frameworks
  - remix
  - react-router
  - tooling
  - frontend
created: 2026-07-16
source: https://reactrouter.com/start/framework/installation
---

# Build Tools Meta-frameworks — Remix and React Router 7

> Remix merged into React Router 7 (2024) — now the same tool. Vite plugin, route modules with loaders and actions, server/client bundle split. This note covers the build shape. Part of [[Build Tools Meta-frameworks Guide]].

---

## The merge

In late 2024, Remix + React Router merged. React Router 7 is Remix — same team, same primitives, same Vite plugin. Two operating modes:

- **Library mode** — RR7 as a client-side router (drop-in for RR6 apps)
- **Framework mode** — RR7 as a full-stack framework (drop-in for Remix apps)

This note focuses on framework mode.

The practical implication: there is no "Remix 3" — the Remix package moved into `react-router` and `@react-router/*` scopes. Existing Remix 2 apps get a codemod; new apps use `create-react-router`.

---

## The Vite plugin architecture

```ts
// vite.config.ts
import { defineConfig } from 'vite';
import { reactRouter } from '@react-router/dev/vite';

export default defineConfig({
  plugins: [reactRouter()],
});
```

The plugin:

- Discovers routes from `app/routes/*` (file-system routing)
- Injects server + client entries
- Handles `loader` / `action` code-splitting
- Emits both bundles

Under the hood, `reactRouter()` is a Vite plugin that hooks into `configResolved`, `resolveId`, `load`, and `transform`. It uses Vite's built-in SSR pipeline (`environments.ssr`) to build the server bundle in parallel with the client bundle. Cross-link [[Build Tools Vite - SSR and Environments]].

Config lives in `react-router.config.ts` at the project root:

```ts
// react-router.config.ts
import type { Config } from '@react-router/dev/config';

export default {
  ssr: true,              // default; false → SPA mode (client-only build)
  prerender: ['/', '/about'],
  future: { unstable_optimizeDeps: true },
} satisfies Config;
```

---

## Route modules

Every file in `app/routes/*` is a route module. Exports:

```ts
// app/routes/posts.$id.tsx
export async function loader({ params }: LoaderFunctionArgs) {
  return json(await db.posts.find(params.id));
}

export async function action({ request, params }: ActionFunctionArgs) {
  const form = await request.formData();
  await db.posts.update(params.id, form.get('title'));
  return redirect(`/posts/${params.id}`);
}

export function meta() { return [{ title: 'Post' }]; }

export default function Post() {
  const post = useLoaderData<typeof loader>();
  return <article>{post.title}</article>;
}
```

The Vite plugin splits this file:

- `loader` and `action` go to the **server** bundle
- `default` and `meta` go to the **client** bundle (and are also SSR-rendered on the server)

Additional named exports the plugin knows about:

| Export | Runs on | Purpose |
|--------|---------|---------|
| `loader` | Server | Fetch data before render |
| `clientLoader` | Client | Client-side data fetch (skips server on navigation) |
| `action` | Server | Handle mutation from `<Form>` |
| `clientAction` | Client | Client-side mutation |
| `default` | Both | The route component |
| `meta` | Both | `<title>`, meta tags |
| `links` | Both | `<link rel>` tags (preload, stylesheet) |
| `headers` | Server | HTTP response headers |
| `handle` | Both | Arbitrary metadata for parent routes |
| `shouldRevalidate` | Client | Skip loader on some transitions |
| `ErrorBoundary` | Both | Route-scoped error UI |
| `HydrateFallback` | Client | Shown while `clientLoader` runs on first render |

---

## Server / client bundle split

Similar to RSC but different mechanism:

- The plugin analyzes named exports at build time
- Named exports like `loader`, `action`, `headers` → server-only
- Default export → both bundles (SSR + hydrate)
- Client-only code goes in `entry.client.tsx`; server-only in `entry.server.tsx`

The mechanism is essentially **named-export tree-shaking driven by convention**:

```
[route module source]
        │
        ├─► server bundle: keep loader, action, headers, default, ErrorBoundary
        │
        └─► client bundle: keep default, meta, links, ErrorBoundary,
                            HydrateFallback, clientLoader, clientAction
                            (strip loader, action, headers)
```

This is why importing a server-only module (like `node:fs`) at the top of a route file works — the plugin strips the imports along with the exports that referenced them, so they never reach the client bundle.

✅ **Correct** — server-only import used only in `loader`:

```ts
import { readFile } from 'node:fs/promises';

export async function loader() {
  return json({ content: await readFile('data.json', 'utf8') });
}

export default function Page() {
  const { content } = useLoaderData<typeof loader>();
  return <pre>{content}</pre>;
}
```

❌ **Wrong** — server-only import used in the default export:

```ts
import { readFile } from 'node:fs/promises';

export default function Page() {
  // readFile is undefined in the browser bundle — build error or runtime crash
  readFile('data.json', 'utf8').then(console.log);
  return null;
}
```

For values that must be server-only but need to be reached from other server code, use a `.server.ts` file suffix — the plugin errors if any client code imports it.

---

## File-system routing conventions

```
app/routes/
  _index.tsx                  → /
  about.tsx                   → /about
  posts.$id.tsx               → /posts/:id
  posts.$id.edit.tsx          → /posts/:id/edit
  _layout.tsx                 → wraps children
  $.tsx                       → catch-all
```

Segment separator is `.`; dollar-prefixed segments are dynamic; underscore-prefixed are pathless (layouts).

More conventions:

- `_index.tsx` — matches the parent's index (no additional segment)
- `posts_.$id.tsx` (trailing `_`) — opts out of the parent layout
- `($lang).about.tsx` — optional segment (parens)
- Escape a literal `.` in a URL with `[.]` (e.g. `sitemap[.]xml.tsx` → `/sitemap.xml`)

For those who dislike the flat convention, `routes.ts` allows explicit programmatic routing:

```ts
// app/routes.ts
import { type RouteConfig, route, index, layout } from '@react-router/dev/routes';

export default [
  index('routes/home.tsx'),
  layout('routes/_layout.tsx', [
    route('about', 'routes/about.tsx'),
    route('posts/:id', 'routes/post.tsx'),
  ]),
] satisfies RouteConfig;
```

---

## Data loaders and revalidation

- Loader runs on the server on initial navigation → SSR render
- Loader runs on the server on subsequent client navigations → fetch, hydrate new data
- Actions can trigger loader revalidation automatically

Client never sees `loader` code — it's in the server bundle only.

The client's `<Link>` performs a `fetch()` to the server, which re-runs the loader and returns JSON. The default is:

1. User clicks `<Link to="/posts/2">`
2. Client fetches `/posts/2?_data=routes/posts.$id`
3. Server runs the loader, returns JSON
4. Client swaps the route component with new `useLoaderData()`

After an action succeeds, React Router automatically revalidates all loaders in the matched route tree — so the UI reflects the new state without extra code.

`shouldRevalidate` lets a route opt out:

```ts
export function shouldRevalidate({ currentUrl, nextUrl, formAction }) {
  // Only revalidate if the search params changed
  return currentUrl.search !== nextUrl.search;
}
```

---

## Resource routes

Route files without a default export are "resource routes" — endpoints, not pages:

```ts
// app/routes/api.posts.ts
export async function loader() { return json(await db.posts.list()); }
export async function action({ request }: ActionFunctionArgs) {
  const body = await request.json();
  return json(await db.posts.create(body));
}
```

Requesting `/api/posts` invokes loader/action; no HTML page is rendered.

Use cases:

- REST-ish JSON endpoints for external clients
- File downloads (return a `Response` with a `Content-Disposition` header)
- Webhooks (return `new Response(null, { status: 204 })`)
- OG image generation
- RSS/Atom feeds, `robots.txt`, `sitemap.xml`

Because they use the same route table, they benefit from the same server bundle, tree-shaking, and adapter targeting as page routes.

---

## Deployment adapters

RR7 targets multiple runtimes via adapters similar to Astro's:

- `@react-router/node` — Node runtime (Express, Fastify)
- `@react-router/vercel` — Vercel functions
- `@react-router/cloudflare` — Cloudflare Workers
- `@react-router/dev serve` — dev server + a bundled minimal server for local prod

Adapters shape the server bundle for the target runtime.

The adapter's job is to convert the platform's native request object into a standard `Request` and call the RR7 request handler:

```ts
// server.js (Node adapter, Express)
import { createRequestHandler } from '@react-router/express';
import express from 'express';

const app = express();
app.use(express.static('build/client'));
app.all('*', createRequestHandler({
  build: () => import('./build/server/index.js'),
}));
app.listen(3000);
```

For Cloudflare Workers, the entry uses `fetch` directly:

```ts
import { createRequestHandler } from '@react-router/cloudflare';
import * as build from './build/server';

const handler = createRequestHandler(build);
export default { fetch: handler };
```

The build output is adapter-agnostic in shape (same `build/server/index.js`) — only the wrapping entry differs.

---

## Streaming and defer

```ts
export async function loader() {
  return defer({
    user: await getUser(),           // await → included in initial payload
    comments: getCommentsSlowly(),   // promise → streams in
  });
}

export default function Page() {
  const { user, comments } = useLoaderData();
  return (
    <>
      <h1>{user.name}</h1>
      <Suspense fallback={<Spinner />}>
        <Await resolve={comments}>{cs => <Comments comments={cs} />}</Await>
      </Suspense>
    </>
  );
}
```

Uses React 18 streaming SSR. Cross-link [[React Lifecycle - Suspense Lifecycle]].

The transport is a single chunked HTTP response — the initial HTML flushes with `<Spinner />`, then when `getCommentsSlowly()` resolves the server serializes the promise result inline as a `<script>` block that resolves the client-side promise. No extra fetch round-trips.

`defer` composes cleanly with `Suspense` — one loader can return many streaming values, and each `<Await>` boundary hydrates independently.

---

## RSC in RR7

RSC support is being added to RR7 (as of 2026). Check `react-router.com/rsc` for current status. The Vite plugin handles the two-graph model; loaders become an "escape hatch" for non-RSC data flow.

The mental model:

- `"use server"` and `"use client"` directives work the same as in Next.js
- `loader` still exists — useful for reading query params, headers, and cases where you want data at the route level rather than the component level
- Route modules can now `export default` an RSC-tree; the plugin builds three graphs (client, SSR, RSC)

Cross-link [[Build Tools Meta-frameworks - RSC and the Bundler]] for how the three-graph model works.

---

## Build output

```
build/
├── client/                Client bundle (Vite Rollup output)
│   ├── assets/
│   ├── entry.client-<hash>.js
│   └── routes/<route-chunks>
└── server/                Server bundle (Vite SSR output)
    ├── index.js           adapter-specific entry
    └── routes/<route-chunks>
```

The client bundle is what the browser downloads. Each route becomes a separate chunk so that navigating to `/about` only fetches the `about` chunk — plus any shared vendor chunks Vite factored out.

The server bundle is a single JS file (or one per route, depending on `serverBundles` config) that the adapter imports at runtime. It contains every route's `loader`, `action`, and `default` export — the default export is needed for SSR rendering.

`serverBundles` config lets you split the server bundle by route tree — useful when different route subtrees should deploy to different runtimes (e.g. `/admin/*` on Node, `/*` on the edge):

```ts
export default {
  serverBundles: ({ branch }) => {
    return branch.some(r => r.id.startsWith('routes/admin'))
      ? 'admin' : 'main';
  },
} satisfies Config;
```

---

## Comparison to Next.js

| | Remix / RR7 | Next.js |
|---|-------------|---------|
| Bundler | Vite | Webpack / Turbopack |
| Data | `loader` / `action` | RSC + `fetch` in components / Server Actions |
| Routing | File-system, `.` separators | File-system, `/` folders |
| Deploy | Adapter model | Vercel-first, works elsewhere |
| RSC | Being added | First-class |
| Streaming | `defer` + `<Await>` | Built into RSC |

Philosophical difference: Next.js pushes data-fetching into components (RSC), so the mental unit is the component. RR7 keeps data-fetching at the route level (loaders), so the mental unit is the route. Both hit the same use cases, but code organization differs.

Cross-link [[Build Tools Meta-frameworks - Next.js Build Pipeline]] and [[Build Tools Meta-frameworks - Next.js and Turbopack]] for the Next.js side of the comparison.

---

## Migration story

- **From Remix 2**: `npx create-react-router@latest` codemod
  - Renames imports: `@remix-run/react` → `react-router`, `@remix-run/node` → `@react-router/node`, etc.
  - Updates `vite.config.ts` to use `reactRouter()` instead of `vitePlugin` from `@remix-run/dev`
  - Moves config from `remix.config.js` (or the `remix` key in `vite.config.ts`) to `react-router.config.ts`
- **From RR6 (library)**: framework mode is opt-in; keep using library mode indefinitely
  - Library mode still ships (`import { BrowserRouter } from 'react-router'`)
  - Adopt framework mode incrementally by adding the Vite plugin — no rewrite required upfront
- **From Next**: significant rewrite — different data model
  - RSC-heavy Next apps don't have a mechanical migration path
  - Pages Router apps map more directly (getServerSideProps → loader, API routes → resource routes)

---

## Related

- [[Build Tools Vite - SSR and Environments]] — RR7 uses Vite's SSR pipeline
- [[Build Tools Vite - Plugin API]]
- [[Build Tools Meta-frameworks - Next.js Build Pipeline]] — comparison
- [[Build Tools Meta-frameworks - RSC and the Bundler]]
- [[Build Tools Meta-frameworks Guide]]
