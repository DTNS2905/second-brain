---
tags:
  - build-tools
  - meta-frameworks
  - nextjs
  - tooling
  - frontend
created: 2026-07-16
source: https://nextjs.org/docs
---

# Build Tools Meta-frameworks — Next.js Build Pipeline

> Next.js composes SWC (compiler) + Webpack (bundler by default, Turbopack opt-in) + a custom output shape (route/prerender manifests). This note walks the pipeline end-to-end. Part of [[Build Tools Meta-frameworks Guide]].

---

## The stack

Next.js is not a single tool — it's an orchestration layer that glues four moving parts together and adds routing conventions on top.

- **Compiler**: SWC (default since Next 12); Babel as opt-in for custom transforms
- **Bundler**: Webpack (default); Turbopack opt-in with `next dev --turbo`
- **Runtime**: Node (default); Edge (opt-in per route via `export const runtime = 'edge'`)
- **RSC support**: built-in in App Router

The pipeline reads source files, hands them to SWC for per-file transforms, feeds the transformed modules into Webpack's module graph, statically generates any pages that don't need per-request data, then emits a `.next/` output directory that the Next.js server (or a serverless adapter) can serve.

```
source files
   │
   ▼  per-file transform
  SWC ──► TS erased, JSX lowered, RSC markers preserved
   │
   ▼  module graph + code splitting
Webpack ──► server graph + client graph, chunks
   │
   ▼  invoke components for SSG/ISR
  SSG ──► prerendered HTML + RSC payloads
   │
   ▼
 .next/ (chunks, manifests, prerendered pages)
```

---

## next build phases

`next build` is a fixed sequence — understanding the order is the fastest path to debugging why a build fails or emits the wrong shape.

1. **Compile** — SWC transforms per file (TS erase + JSX + Fast Refresh transform if dev)
2. **Collect page data** — walks `app/` and `pages/` for route entries, generates the route manifest
3. **Bundle** — Webpack builds one bundle per route (or per RSC boundary)
4. **Static generation** — pre-renders SSG/ISR pages by invoking components
5. **Emit** — writes `.next/` with chunks, manifests, prerendered HTML, `standalone/` if enabled

### Phase 1 — Compile

SWC processes every `.ts`, `.tsx`, `.js`, `.jsx` file it encounters. This is a per-file pass with no cross-file awareness — no dead-code elimination happens here, just syntax lowering. See [[Build Tools Compilers - SWC Internals]].

### Phase 2 — Collect page data

Next walks `app/` and `pages/` looking for route conventions:

- `page.tsx` / `page.js` (App Router leaf)
- `layout.tsx` (App Router layout)
- `route.ts` (App Router route handler)
- `pages/**/*.tsx` (Pages Router)
- `middleware.ts` (edge middleware)

Each match becomes an entry in the route manifest.

### Phase 3 — Bundle

Webpack traces imports from each entry, builds two module graphs (server + client, post-RSC), and code-splits.

### Phase 4 — Static generation

For every route marked as SSG or ISR, Next imports the compiled component and renders it to HTML. If a route uses `generateStaticParams`, all variants are generated. This phase is the slowest for large marketing sites.

### Phase 5 — Emit

Everything gets written to `.next/`. If `output: 'standalone'` is set, a self-contained folder is also produced.

---

## Output shape (.next/)

```
.next/
├── server/                    Node bundle (server components, API routes, middleware)
│   ├── app/                   compiled app router chunks
│   ├── pages/                 compiled pages router chunks
│   └── chunks/
├── static/                    client bundle (hashed)
│   ├── chunks/
│   └── css/
├── build-manifest.json        client entrypoints
├── prerender-manifest.json    SSG/ISR route metadata
├── routes-manifest.json       all route entries
└── standalone/                (if output: 'standalone') minimal Node app
```

Two top-level folders matter most:

- `server/` — everything the Node runtime executes: RSC modules, route handlers, middleware
- `static/` — everything the browser downloads: JS chunks, CSS, hashed for immutable caching

The `*-manifest.json` files are the glue: they map URLs → chunks, mark which routes are static/dynamic, and describe the prerender state so a serverless host knows what to do at request time.

---

## SWC's role

SWC replaced Babel in Next 12. It's a per-file transform pass — no module graph awareness, no bundling. Handles:

- TypeScript erasure
- JSX transform
- React Refresh injection (dev)
- Custom Next transforms (`styled-components`, `emotion`, `relay`, `remove-console`, `remove-imports`)
- RSC directive analysis (`'use client'` / `'use server'` markers passed to bundler)

The RSC directive analysis is worth calling out — SWC doesn't decide server vs client on its own, it just annotates each module with what directive it saw, and Webpack's Next plugin uses those annotations to route the module into the right graph.

Configured via `next.config.js`:

```js
module.exports = {
  compiler: {
    styledComponents: true,
    removeConsole: { exclude: ['error'] },
  },
};
```

Compare with the escape hatch — a `.babelrc` in the project root disables SWC entirely and Next falls back to Babel. Almost always slower.

```js
✅ // Fast path — SWC
module.exports = { compiler: { styledComponents: true } };

❌ // Slow path — disables SWC, uses Babel
// .babelrc present in project root
```

---

## Webpack's role

Webpack takes SWC's transformed modules and assembles the module graph, does code splitting, produces chunks. Two graphs post-RSC:

- **Server graph** — React server components + boundaries
- **Client graph** — client components + islands

The Next.js Webpack plugin injects a custom loader that reads the RSC directive markers SWC left behind and enforces the boundary — a server component importing a client component becomes an entry point in the client graph, and vice versa is forbidden.

Cross-link [[Build Tools Meta-frameworks - RSC and the Bundler]].

### Split points

Webpack generates chunks at:

- Every route (`app/foo/page.tsx` → separate chunk)
- Every dynamic `import()`
- Every RSC client-boundary crossing
- Shared modules that appear in 2+ routes → `chunks/framework-*.js`, `chunks/main-*.js`

---

## App Router vs Pages Router — build differences

Both routers can coexist in the same project — the build pipeline handles them in parallel and emits both into `.next/server/`.

| Aspect | Pages Router (`pages/`) | App Router (`app/`) |
|--------|-------------------------|---------------------|
| Convention | `pages/foo.tsx` → `/foo` | `app/foo/page.tsx` → `/foo` |
| Data fetching | `getServerSideProps` / `getStaticProps` | RSC + `fetch` in components |
| Layouts | HOC / `_app.tsx` | Nested `layout.tsx` |
| Loading UI | Manual | `loading.tsx` (Suspense boundary) |
| Error UI | `_error.tsx` | `error.tsx` (per segment) |
| Streaming | Limited | First-class |
| RSC | No | Yes (default) |

### What changes at build time

- **Pages Router** — one bundle per page. `getStaticProps` runs at build; `getServerSideProps` is skipped (runs per request).
- **App Router** — one bundle per RSC boundary. Static generation invokes the server component tree; anything without dynamic APIs (`headers()`, `cookies()`, `noStore()`) is prerendered.

### Coexistence

If both `pages/foo.tsx` and `app/foo/page.tsx` exist, App Router wins and build emits a warning. Otherwise they route independently.

---

## Route entry manifest

Every route Next discovers ends up in `routes-manifest.json`. The Next.js server (or a serverless adapter like Vercel's) reads this file at cold start to decide how to handle each incoming URL.

```json
// routes-manifest.json (simplified)
{
  "version": 4,
  "staticRoutes": [{ "page": "/about", "regex": "..." }],
  "dynamicRoutes": [{ "page": "/blog/[slug]", "regex": "..." }],
  "dataRoutes": [...],
  "rewrites": [...]
}
```

Companion manifests:

- `prerender-manifest.json` — SSG/ISR-specific: revalidation intervals, fallback modes, prerendered variants
- `build-manifest.json` — client entrypoints: for each route, which chunks the browser needs
- `app-build-manifest.json` — App Router variant of the above
- `middleware-manifest.json` — edge middleware matchers + compiled bundle refs

---

## Middleware

Special build target. Runs on the edge:

```ts
// middleware.ts
export function middleware(request: NextRequest) { … }
export const config = { matcher: '/dashboard/:path*' };
```

Bundled separately with `target: 'webworker'`, no Node built-ins.

### Build implications

- No `fs`, `path`, `child_process`, or any Node-only module — Webpack errors at build if you import them
- Bundle size limit (~1MB compressed) enforced at build
- Emitted to `.next/server/middleware.js` with its own manifest

```js
✅ // Fetch works — Web APIs only
export function middleware(request) { return fetch('...'); }

❌ // Build error — Node builtin
import fs from 'fs';
export function middleware(request) { fs.readFileSync('...'); }
```

---

## API routes

Server-only, bundled into the Node graph. Since Next 13.4, function-like route handlers replace the old `pages/api/*.ts` (still supported):

```ts
// app/api/hello/route.ts
export async function GET(request: Request) { return Response.json({ ok: true }); }
```

### Runtime opt-in

Add `export const runtime = 'edge'` and the handler moves to the middleware-style build target — same bundle constraints (no Node built-ins).

```ts
// app/api/hello/route.ts
export const runtime = 'edge';
export async function GET() { return Response.json({ ok: true }); }
```

### Old vs new

```
❌ pages/api/hello.ts        — default export, req/res style
✅ app/api/hello/route.ts    — named exports per HTTP verb
```

Both are supported. New code should prefer route handlers — they're closer to the platform (`Request` / `Response`) and integrate with RSC caching.

---

## Custom webpack config

```js
// next.config.js
module.exports = {
  webpack: (config, { isServer, dev }) => {
    // mutate config.module.rules, config.plugins, etc.
    return config;
  },
};
```

Escape hatch; break it and Next builds may fail. Prefer built-in options.

### Common patterns

```js
module.exports = {
  webpack: (config, { isServer }) => {
    if (!isServer) {
      config.resolve.fallback = { fs: false, path: false };
    }
    return config;
  },
};
```

The `webpack` callback runs **four times** in a full build: server + client × dev + prod. Guard with `isServer` / `dev` accordingly. Turbopack ignores this callback entirely — migration path uses `experimental.turbo` rules instead.

---

## Output modes

The `output` field in `next.config.js` picks the emit target:

- **Default** — server-required output. Assumes a Node process (or serverless adapter) will serve it.
- **`output: 'standalone'`** — self-contained folder (`server.js`) for minimal Docker images. Copies only the traced dependencies into `.next/standalone/`. Cuts image size from ~1GB to ~50MB in typical projects.
- **`output: 'export'`** — pure static export (like SSG-only mode; loses many features). No API routes, no middleware, no ISR, no on-demand revalidation, no image optimization (unless configured externally).

```js
✅ // Docker deployment — minimal image
module.exports = { output: 'standalone' };

✅ // Static hosting (CDN, GitHub Pages)
module.exports = { output: 'export' };

❌ // Combining incompatibles
module.exports = { output: 'export' };
// then using API routes → build error
```

---

## Where each concept lives

| Concept | File |
|---------|------|
| Compiler config | `next.config.js` → `compiler` |
| Webpack config | `next.config.js` → `webpack` |
| Turbopack rules | `next.config.js` → `experimental.turbo` |
| Route manifest | `.next/routes-manifest.json` |
| Prerender manifest | `.next/prerender-manifest.json` |

When something breaks, check the manifests first — they reflect what Next.js *thinks* your app looks like after phases 1–2, before bundling. If a route is missing from `routes-manifest.json`, the file naming convention is off; if it's static when it should be dynamic, some dynamic API isn't being detected.

---

## Common misconceptions

```
❌ "next build outputs a static site."
✅ Only with output: 'export'. Default is server-required.

❌ "SWC replaces Webpack in Next."
✅ SWC replaced Babel. Webpack is still the bundler.

❌ "Every Next 13 app is App Router."
✅ Pages Router is still supported; both routers can coexist in the same app.
```

More that come up in review:

```
❌ "Turbopack is production-ready for builds."
✅ next dev --turbo is stable; next build --turbo is still experimental in most SDK versions.

❌ "Middleware is a Node function."
✅ Middleware runs on the edge runtime — no Node built-ins, ~1MB bundle limit.

❌ "API routes and route handlers are different runtimes."
✅ Both default to Node. Both can opt into edge with `export const runtime = 'edge'`.

❌ "RSC boundaries are drawn by the framework at runtime."
✅ Boundaries are static — SWC annotates directives, Webpack splits graphs at build.
```

---

## Summary

| Phase | Tool | Input | Output |
|-------|------|-------|--------|
| Compile | SWC | source files | transformed modules |
| Collect | Next | `app/` + `pages/` | route entries |
| Bundle | Webpack | modules + entries | chunks (server + client) |
| Prerender | Next | server components | static HTML + RSC payload |
| Emit | Next | everything above | `.next/` output |

The pipeline is deterministic: same source in, same `.next/` out. When debugging, work outward from the manifests — they're the source of truth for what Next thinks it built.

---

## Related

- [[Build Tools Meta-frameworks - Next.js and Turbopack]]
- [[Build Tools Meta-frameworks - RSC and the Bundler]]
- [[Build Tools Compilers - SWC Internals]]
- [[Build Tools Webpack Guide]]
- [[Build Tools Meta-frameworks Guide]]
