---
tags:
  - build-tools
  - vite
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/why
---

# Build Tools Vite — Architecture Overview

> Vite's core design is two engines under one plugin API: native-ESM dev server + Rollup prod build, with esbuild as a shared transformer. Understanding this split is the key to reading its config and diagnosing its bugs. Part of [[Build Tools Vite Guide]].

---

## Two engines, one plugin API

Vite is not a single bundler. It is a **dev toolchain** that composes two very different engines behind a unified plugin surface:

- **Dev**: Vite's own HTTP server serves source files as native ES modules directly to the browser. There is no bundling step.
- **Build**: Vite hands the module graph to **Rollup**, which produces the production bundle.

Both engines accept the **same plugin format**: a Rollup-flavored plugin object (`name`, `resolveId`, `load`, `transform`, `generateBundle`, …) plus a handful of **Vite-only hooks** (`config`, `configResolved`, `configureServer`, `transformIndexHtml`, `handleHotUpdate`).

```
                   ┌───────────────────────────────┐
                   │      Vite plugin object       │
                   │  (Rollup hooks + Vite hooks)  │
                   └──────────────┬────────────────┘
                                  │
              ┌───────────────────┴────────────────────┐
              ▼                                        ▼
    ┌───────────────────┐                    ┌────────────────────┐
    │  Dev server       │                    │  Rollup            │
    │  (native ESM)     │                    │  (production)      │
    │  + esbuild xform  │                    │  + esbuild xform   │
    └───────────────────┘                    └────────────────────┘
```

The consequence: **one config file drives two very different execution paths**. If you don't know which engine is running, you cannot reason about a bug.

---

## Dev flow (step by step)

When you run `vite` (dev), the following happens for a fresh page load:

1. Browser requests `/` → Vite serves `index.html` from disk (with `transformIndexHtml` hooks applied).
2. The HTML contains `<script type="module" src="/src/main.tsx">` → the browser fetches that URL over HTTP.
3. Vite intercepts the request. It resolves `/src/main.tsx` on disk, then transforms it: **esbuild** strips TS + JSX in a few milliseconds.
4. Vite **rewrites bare imports** in the response so the browser can follow them:
   ```js
   // source
   import React from 'react'
   import App from './App'

   // what Vite ships to the browser
   import React from '/node_modules/.vite/deps/react.js?v=abc123'
   import App from '/src/App.tsx'
   ```
5. Browser follows each import and requests them one by one.
6. Vite repeats step 3-4 per file: transform → rewrite → respond.
7. Meanwhile a **WebSocket HMR channel** is opened. On file change Vite retransforms **only that single module** and pushes an update; the browser swaps the module in place.

Key property: **there is no bundle**. The browser walks the module graph itself, at HTTP speed.

See [[Build Tools Vite - Dev Server Architecture]] for the request lifecycle in more detail.

---

## Build flow (step by step)

When you run `vite build`, the picture flips:

1. Rollup is invoked with a Vite-projected config (Vite translates its own options + plugins into Rollup input options).
2. All Vite plugins are registered on Rollup, including any `apply: 'build'` variants.
3. For each file Rollup asks to load, **esbuild** transforms it (via `@vitejs/plugin-react-swc`, `@vitejs/plugin-react`, or Vite's built-in TS/JSX handling).
4. Rollup walks the graph from `input` entries, resolves every import, **tree-shakes** dead exports.
5. Rollup emits chunks (`dist/assets/*.js`), assets (`dist/assets/*.png`, hashed), and source maps.
6. Vite post-processes: extracts CSS into files, hashes asset filenames, rewrites URLs inside the emitted HTML.

Key property: **the dev server is completely absent**. Nothing that only lives in `configureServer` will run here.

See [[Build Tools Vite - Production Build]] for the full pipeline.

---

## The three "backends"

Vite's speed story rests on three cooperating tools:

| Backend | Role in dev | Role in build |
|---|---|---|
| **esbuild** | Pre-bundle deps (once) + per-file transform (each request) | Per-file transform via plugins |
| **Rollup** | Not used | Full bundle, tree-shake, code-split |
| **Vite dev server** | HTTP + module graph + HMR websocket | Not used |

None of these tools is optional; each covers a job the other two are bad at.

---

## Native ESM as the dev protocol

Vite's central bet: **the browser is a bundler**. If you tell it `<script type="module">`, it will fetch, parse, and instantiate the ES module graph itself.

That means the dev server's job shrinks dramatically:

- No entry-point bundling
- No dev-time code splitting (the browser does it via `import`)
- No dev-time chunking heuristic

Vite only has to answer three questions on every request:

1. Where is this file on disk? (resolve)
2. Can the browser parse it as-is? (transform: TS → JS, JSX → JS, `.vue` → JS…)
3. Are its imports valid URLs? (rewrite bare specifiers → `/node_modules/.vite/deps/...`)

Compare to Webpack dev: it must **build an in-memory bundle**, ship it, then rebuild on every change. Vite skips that entire step.

---

## esbuild's dual role

Newcomers assume "esbuild = the thing that makes Vite fast" and stop there. In fact esbuild plays **two** roles in Vite:

### 1. Dependency pre-bundling (once per install)

`node_modules` packages are shipped as many small files, often as CommonJS, often with hundreds of imports. If the browser had to fetch each one, dev startup would be as slow as Webpack.

Vite runs esbuild **once**, at first dev-server start, to pre-bundle each dep into a single ESM file cached under `node_modules/.vite/deps/`:

```
node_modules/react/           node_modules/.vite/deps/
├── index.js         ────▶    ├── react.js       (single ESM file)
├── cjs/*.js                  └── _metadata.json
└── (many files)
```

The cache is invalidated when `package.json` changes or `optimizeDeps` config changes. Cross-link `[[Build Tools Vite - Dependency Pre-Bundling]]`.

### 2. Per-request transform (every request in dev)

For **source** files (yours, not deps), Vite uses esbuild's transform API to strip TS types and compile JSX. This is the sub-millisecond step run inline in each HTTP response.

```js
// vite.config.ts — configure esbuild's inline transform
export default {
  esbuild: {
    jsxFactory: 'h',
    jsxFragment: 'Fragment',
    target: 'es2020',
  },
}
```

---

## Why not just use esbuild for everything

If esbuild is fast, why bring in Rollup at all?

- **esbuild's plugin API is limited.** No AST-level `transform` hook, no fine-grained `resolveId` chain, no `renderChunk`/`generateBundle`. Its plugin story is optimized for the transformer, not for extending the bundler.
- **Rollup's plugin API is deep.** Ten years of ecosystem — `@rollup/plugin-commonjs`, `@rollup/plugin-node-resolve`, `@rollup/plugin-alias`, dynamic-import-vars, virtual modules, code-splitting hooks, chunk-graph mutation.
- **Rollup's output is smaller.** Its tree-shaking + scope-hoisting produce cleaner ESM bundles than esbuild's.

So Vite uses **esbuild where speed matters** (per-file transforms, running literally thousands of times per session) and **Rollup where expressiveness matters** (the one prod build, where a percent-point of bundle size matters more than milliseconds).

```
                     Speed-critical        Expressiveness-critical
                     (many small ops)      (one big op)
                          │                        │
                          ▼                        ▼
                       esbuild                  Rollup
```

---

## Environment API (v5+)

Vite 5 introduced first-class **multi-environment builds**. Instead of a single module graph, Vite can maintain **several** — one per target runtime.

```ts
// vite.config.ts (Environment API)
export default {
  environments: {
    client: {
      build: { outDir: 'dist/client' },
    },
    ssr: {
      build: { outDir: 'dist/server', ssr: true },
      resolve: { conditions: ['node'] },
    },
    edge: {
      build: { outDir: 'dist/edge' },
      resolve: { conditions: ['workerd', 'edge-light'] },
    },
  },
}
```

Each environment has its **own** module graph, its **own** plugin pipeline (plugins can opt into `applyToEnvironment`), and its **own** resolve conditions. This is how frameworks like Nuxt, SvelteKit, and Astro implement SSR + edge + client from one Vite config. Cross-link `[[Build Tools Vite - SSR and Environments]]`.

---

## Rolldown — the future

The Vite team is building **Rolldown**, a **Rust rewrite of Rollup**, designed to be a drop-in replacement with Vite-friendly semantics.

Long term, the plan is:

- **Prod builds**: Rollup → Rolldown (10-30× faster).
- **Dev pre-bundle**: esbuild → Rolldown (same tool for dev + prod ⇒ no more "works in dev, breaks in build" edge cases from the two engines disagreeing).
- **Per-file transform**: likely stays on Oxc/esbuild for hot-path speed.

As of **2026**, Rolldown is in active development, ships as an opt-in (`rolldown-vite`), but is not the default in stable Vite. Once it is, the "two engines" story simplifies to "one Rust engine, two modes."

---

## Comparison mental model vs Webpack

|  | Webpack | Vite |
|---|---|---|
| Dev bundle | Yes (in-memory) | No (native ESM) |
| Dev startup | Slow (full bundle) | Instant |
| Prod bundle | Yes (Webpack) | Yes (Rollup) |
| Same tool for dev + prod | Yes | No (two engines) |
| Plugin API | Tapable (custom) | Rollup-flavored |
| HMR | Full-module patch via runtime | Native-ESM swap over ws |
| Dep handling | Inline in the graph | Pre-bundled to `.vite/deps` |

The most common source of confusion: **Vite is only "instant" in dev**. Prod build times are Rollup times, and are broadly comparable to Webpack. Rolldown is the answer, not esbuild.

---

## The single-config guarantee

A design goal of Vite is: **your plugin config runs identically in dev and build**. If you write:

```ts
// vite.config.ts
import react from '@vitejs/plugin-react'
import svgr from 'vite-plugin-svgr'

export default {
  plugins: [react(), svgr()],
}
```

… both plugins run in **both** engines. That means an SVG imported as a React component works in `vite dev` **and** in `vite build`, with no divergence.

Plugins can opt out per-engine when they need to:

```ts
{
  name: 'my-dev-only-plugin',
  apply: 'serve',   // only in dev
  configureServer(server) { /* … */ },
}

{
  name: 'my-build-only-plugin',
  apply: 'build',   // only in build
  generateBundle() { /* … */ },
}
```

By default plugins apply to both. This is what prevents the classic "works in dev, breaks in prod" Webpack-loader bugs — the transform pipeline is the same object in both engines.

---

## Common misconceptions

```
❌ "Vite is faster than Webpack because it uses esbuild."
✅ Vite is faster in DEV because it doesn't bundle at all.
   In BUILD it uses Rollup, comparable in speed to Webpack.
   esbuild helps with per-file transforms and dep pre-bundling only.

❌ "Vite is a bundler."
✅ Vite is a dev toolchain that composes esbuild + Rollup.
   In dev it doesn't bundle — the browser walks the ESM graph.
   Only `vite build` produces a bundle, and that step is Rollup.

❌ "My Vite plugin only works in dev."
✅ Check `apply`. Plugins run in BOTH engines by default.
   A plugin that only defines `configureServer` will silently do
   nothing in build — that's the plugin, not Vite.

❌ "Pre-bundling is the same as building."
✅ Pre-bundling only touches node_modules and only runs once per
   install. Your source is never pre-bundled; it's transformed
   per request.

❌ "Rolldown will replace esbuild."
✅ Rolldown replaces Rollup first. The per-file transform (the
   hot path) will likely stay on Oxc/esbuild for a long time.
```

---

## Related

- [[Build Tools Vite - Dev Server Architecture]]
- [[Build Tools Vite - Production Build]]
- [[Build Tools Vite - Dependency Pre-Bundling]]
- [[Build Tools Bundlers - Rollup Internals]]
- [[Build Tools Vite Guide]]
