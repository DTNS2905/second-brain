---
tags:
  - build-tools
  - bundlers
  - tooling
  - frontend
created: 2026-07-16
source: https://web.dev/articles/commonjs-larger-bundles
---

# Build Tools Bundlers — Bundling Fundamentals

> Why we bundle, when we don't need to, and what "bundling" actually does beyond string concatenation. Part of [[Build Tools Bundlers Guide]].

---

## What bundling produces

A bundler takes **one input module graph** and produces **one or more output chunks**. That output is not just concatenated source — it's the result of a pipeline:

- **Graph construction** — walk imports from entry points, resolve specifiers to files
- **Chunk splitting** — decide which modules ship together vs. lazy-load
- **Tree shaking** — drop exports/statements no chunk references
- **Minification** — rename identifiers, remove whitespace, fold constants
- **Asset handling** — hash, copy, and rewrite references to CSS, images, fonts
- **Source map composition** — merge maps across every transform in the chain

The wire artifact is a set of `.js`, `.css`, `.map`, and static asset files with content-hashed names, ready for a CDN.

---

## The historical arc

| Year | Tool | Contribution |
|------|------|--------------|
| Pre-2010 | `<script>` tags | Ordered, blocking, global scope. `LABjs` / `RequireJS` added async + AMD |
| 2011 | **Browserify** | Bundle Node-style CJS for browsers |
| 2014 | **Webpack** | Loaders, code splitting, HMR |
| 2015–17 | **Rollup** | ESM-first, hoisted output, real tree shaking |
| 2020 | **esbuild** | Written in Go, ~100× faster than JS bundlers |
| 2020–21 | **Vite** / **Snowpack** | Unbundled dev using native ESM |
| 2022+ | **Turbopack**, **Rspack** | Rust bundlers with incremental caching |

Each generation solved the pain point of the previous:

- Browserify → "I want npm packages in the browser"
- Webpack → "I want to split code and hot-reload"
- Rollup → "I want small library bundles with real tree shaking"
- esbuild → "Everything is too slow"
- Vite → "Why bundle in dev at all?"
- Turbopack/Rspack → "Rewrite Webpack in Rust for the incremental case"

---

## Why bundle at all (2026)

Native ESM works in every modern browser. HTTP/2 removed request-count penalties. So why do we still bundle for production?

- **Tree shaking** — requires whole-graph traversal; impossible per-file at runtime
- **Minification** — needs a single pass over the final output for global renaming
- **Code splitting decisions** — hand-managing chunk boundaries at scale is impractical
- **Asset handling** — CSS, SVG, images need hashing, copying, and reference rewriting
- **Cross-format compat** — CJS-only deps must be repackaged into ESM
- **Legacy browser fallbacks** — differential builds for older syntax targets

The reasons shifted. **In 2015 we bundled to reduce request count. In 2026 we bundle to shrink bytes and enable static analysis.**

---

## Why HTTP/2 changed the math

Under **HTTP/1.1**, each request had per-connection overhead: TCP handshake, TLS negotiation, head-of-line blocking, and a browser-imposed limit (~6) of parallel connections per origin. The mitigation was obvious: **bundle everything into one file**.

**HTTP/2** introduced multiplexing — many requests share one connection. **HTTP/3** (over QUIC) removed even TCP head-of-line blocking. Request count matters much less.

```
HTTP/1.1:  [conn]───req1───res1
                └──req2 (queued behind res1)
           → many small files = slow

HTTP/2:    [conn]═req1═════res1
                 ═req2═════res2   (multiplexed)
                 ═req3═════res3
           → many small files = fine
```

This is what made **unbundled dev servers** viable in the first place — the browser can request 200 modules over one connection without the old per-request tax.

---

## Unbundled dev

Vite's core insight: **in dev, don't bundle at all**. Serve modules over native ESM. The browser makes many requests; on `localhost` that's free. Transform each file only when it's requested, and only re-transform it when it changes.

```
Traditional (Webpack Dev Server):
  boot     → crawl entire graph → bundle everything → serve
  [edit]   → invalidate module  → re-bundle affected → HMR patch
  Startup: slow (bundle from scratch, seconds→minutes at scale)
  Update:  fast for small changes (persistent HMR)

Unbundled (Vite):
  boot     → start server, do nothing → wait for browser requests
  [edit]   → transform one file → HMR patch
  Startup: instant (no bundle)
  Update:  instant (single-file transform)
```

The tradeoff: cold page load in dev makes hundreds of requests. Fine on `localhost`, disastrous over slow networks. Vite pre-bundles `node_modules` deps with esbuild (into a few CJS→ESM files) so the request count is bounded.

See [[Build Tools Vite - Architecture Overview]] for the full mechanism.

---

## What still requires bundling in prod

Even with HTTP/3 everywhere, production still bundles. Reasons:

- **Tree shaking** — happens at build time, never at runtime
- **Minification** — smaller wire cost + faster parse
- **Long-term caching** — content-hashed chunk filenames for immutable caching
- **CSS extraction** — pull `import './x.css'` into standalone `.css` files
- **Legacy browser support** — polyfills, syntax downlevel, differential builds

**Dev vs. prod is not "bundle vs. no-bundle".** In Vite, dev uses raw ESM and prod uses Rollup. In Turbopack, both are bundled but dev is incremental. The choice is *when* to run the bundler and how much of the graph to touch per change.

---

## Bundle vs no-bundle decision matrix

| Scenario | Choice | Why |
|----------|--------|-----|
| Dev, small–medium app | **Unbundled** (Vite) | Instant startup, per-file HMR |
| Dev, huge app (>10k modules) | **Some pre-bundling** (Turbopack, or Vite with `warmup`) | Cold request storm dominates |
| Prod, browser app | **Bundle + code split** | Tree shake, minify, hash |
| Prod, Node CLI | **Optional** | Plain `.js` often ships fine; bundle only for single-file distributions |
| Prod, library | **Bundle** (Rollup) | Ship `.mjs` + `.cjs` outputs, preserve named exports |
| Serverless function | **Bundle** | Cold start cost scales with file count |

---

## The four layers of a bundler

Every bundler — Webpack, Rollup, esbuild, Turbopack — has the same four layers:

1. **Resolver** — turn `import 'lodash/get'` into `/node_modules/lodash/get.js` on disk. Handles `package.json` `exports`, conditions, extensions, aliases.
2. **Loader / transformer** — pick the right compiler per file type (`.ts` → tsc/swc, `.css` → postcss, `.svg` → asset). Emits JS + a source map.
3. **Graph walker** — recurse into `import`/`require` from entry points, detect cycles, propagate `sideEffects: false` from `package.json`.
4. **Emitter** — decide chunks, apply tree shaking, minify, write files and merged source maps.

```
entry.js
   │
   ▼
[Resolver] ──► path on disk
   │
   ▼
[Loader]   ──► JS + inline map
   │
   ▼
[Graph walker] ──► accumulate deps, mark side effects
   │
   ▼
[Emitter]  ──► chunks, tree-shake, minify, emit .js/.css/.map
```

Different bundlers differ in speed, language (JS/Go/Rust), plugin API, and defaults — but the pipeline shape is universal.

---

## Common misconceptions

```
❌ "Bundling is just concatenation."
✅ Bundling includes resolution, tree shaking, minification, asset pipeline, and chunking.

❌ "HTTP/2 means we don't need bundling anymore."
✅ HTTP/2 lets you ship many small chunks — but tree shaking, minification, and
   asset hashing still require a build-time bundler.

❌ "Bundling only matters in production."
✅ Dev servers (Webpack Dev Server) bundle; Vite doesn't. The dev-side choice
   dominates DX because it controls startup and HMR latency.

❌ "esbuild replaces Webpack."
✅ esbuild is fast but its plugin API and code-splitting are minimal. Vite uses
   esbuild for transforms and Rollup for prod bundling.

❌ "Tree shaking removes unused files."
✅ It removes unused *exports and statements*. Files are still traversed —
   what changes is which of their bindings end up in the output.
```

---

## Summary

Bundling is a **build-time activity** that produces artifacts optimized for network delivery and runtime execution. It's more than concatenation — it's resolution, graph walking, tree shaking, minification, asset hashing, and chunking, all wired through source maps.

It's **necessary in prod** for tree shaking, minification, and content-hashed chunking. It's **optional in dev** — Vite/Snowpack showed that unbundled dev is dramatically faster because HTTP/2 made per-request cost negligible on `localhost`.

The frontier since 2022 has been about doing the *same* bundling work faster (esbuild, Rspack, Turbopack via Rust/Go) and doing *less* of it per change (incremental graphs, persistent caches).

---

## Related

- [[Build Tools Bundlers - Chunking and Code Splitting]]
- [[Build Tools Vite - Architecture Overview]] — unbundled dev
- [[Build Tools Bundlers - Rollup vs esbuild vs Webpack]]
- [[Build Tools Foundations Guide]]
