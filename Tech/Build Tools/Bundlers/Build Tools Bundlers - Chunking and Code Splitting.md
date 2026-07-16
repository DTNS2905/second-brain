---
tags:
  - build-tools
  - bundlers
  - chunking
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/guides/code-splitting/
---

# Build Tools Bundlers — Chunking and Code Splitting

> How bundlers decide what ships in which file — entry chunks, async chunks, vendor splits, and the caching strategy that ties them together. Part of [[Build Tools Bundlers Guide]].

---

## Three ways to split

Every modern bundler exposes the same three mechanisms; the difference is in defaults and configuration syntax.

1. **Entry-based** — you tell the bundler "these are separate top-level bundles" (multi-page apps, worker files, browser extension backgrounds).
2. **Dynamic import** — `import()` in source code creates an async chunk automatically. The bundler walks the graph, sees the split, and emits a separate file.
3. **Shared / vendor extraction** — bundler heuristics (Webpack) or manual config (Rollup/Vite) detect modules used by multiple chunks and extract them into their own file so they can be cached independently.

The three modes compose: a route entry does a dynamic import of a modal, and both share a vendor chunk containing React.

---

## Entry chunks

An entry is a starting point for graph traversal. Multiple entries → multiple top-level bundles, each with its own dependency graph.

```js
// Rollup config with multiple entries
{
  input: {
    main: 'src/index.ts',
    worker: 'src/worker.ts',
  },
  output: { dir: 'dist', format: 'esm' }
}
```

Use cases:

- **Multi-page apps** — `home.js`, `checkout.js`, `admin.js`; each HTML page loads only its own entry.
- **Web workers** — the worker file must be a standalone bundle the browser can `new Worker(url)`.
- **Service workers** — same reason.
- **Browser extensions** — `background.js`, `content.js`, `popup.js` each have distinct execution contexts.

Entries do not share code by default; if `main` and `worker` both import `lodash`, it appears in both bundles unless a shared chunk is configured.

---

## Async chunks via dynamic import

The `import()` expression is a standard ECMAScript feature that returns a promise. Every bundler treats it as a split point.

```js
// ✅ Rollup / Webpack / esbuild all treat this as a split point
button.onclick = async () => {
  const { openEditor } = await import('./editor');
  openEditor();
};
```

Bundler emits `editor-<hash>.js` as a separate chunk. Browser downloads it only when the user clicks. The parent chunk contains a tiny loader stub that fetches and evaluates the async chunk on demand.

Rules of thumb:

- Anything behind a user action (modal, editor, admin panel) → dynamic import
- Anything below the fold that isn't critical → dynamic import + `IntersectionObserver`
- Rarely-used utilities (PDF export, image cropper) → dynamic import
- Anything on the critical rendering path → static import (fewer waterfalls)

---

## Route-based splitting (React example)

Route-level splitting is the highest-value application of dynamic import — one chunk per route means users pay for only the routes they visit.

```jsx
// ✅ React.lazy + Suspense
const Editor = React.lazy(() => import('./routes/editor'));

<Suspense fallback={<Spinner />}>
  <Editor />
</Suspense>
```

`React.lazy` wraps a dynamic import so the component suspends while its chunk is loading. See [[React Lifecycle - Suspense Lifecycle]] for how Suspense integrates with the render cycle.

Cross-reference: modern frameworks (Next.js, Remix, TanStack Router) do route-based splitting automatically — you get one chunk per route file with no manual `React.lazy`.

---

## Webpack SplitChunks heuristics

`optimization.splitChunks` decides when to extract a shared module. Defaults (roughly):

- Module is in `node_modules`
- Module is used by ≥ 2 chunks
- Module ≥ 20 kB (before minification)
- Result: an extracted `vendors-<hash>.js` chunk

```js
// webpack.config.js
{
  optimization: {
    splitChunks: {
      chunks: 'all',
      minSize: 20000,
      maxAsyncRequests: 30,
      cacheGroups: {
        vendor: {
          test: /[\\/]node_modules[\\/]/,
          name: 'vendors',
          chunks: 'all',
        },
      },
    },
  },
}
```

`chunks: 'all'` means both sync (initial) and async (dynamic import) chunks are eligible for extraction. `cacheGroups` lets you override the heuristic — e.g., always put React in its own chunk. See [[Build Tools Webpack - Code Splitting and SplitChunks]] for the full option reference.

---

## Rollup manualChunks

Rollup has no auto-heuristic; you specify chunks explicitly. Vite inherits this from Rollup.

```js
// vite.config.ts
build: {
  rollupOptions: {
    output: {
      manualChunks: (id) => {
        if (id.includes('node_modules/react')) return 'react-vendor';
        if (id.includes('node_modules/lodash')) return 'lodash';
      },
    },
  },
}
```

The function receives each module ID; the returned string is the chunk name. Returning `undefined` lets Rollup decide. In practice you group large stable dependencies (React, RxJS, Three.js) into named vendor chunks and leave the rest to Rollup's auto-splitting on dynamic imports.

Caveat: Rollup may refuse a `manualChunks` grouping if it would create a circular dependency between chunks. When that happens, either widen the group (include more of the graph) or narrow it (extract fewer modules).

---

## Magic comments (Webpack)

Webpack extends `import()` with pragmas that influence chunk generation:

```js
const mod = await import(
  /* webpackChunkName: "editor" */
  /* webpackPrefetch: true */
  './editor'
);
```

- `webpackChunkName` — names the chunk (readable filenames instead of numeric IDs)
- `webpackPrefetch: true` — emits `<link rel="prefetch">` for idle-time fetch
- `webpackPreload: true` — emits `<link rel="preload">` for parallel fetch on the current navigation
- `webpackMode: "lazy" | "eager" | "weak"` — controls whether a chunk is created at all
- `webpackInclude` / `webpackExclude` — regex filters for dynamic imports with variable paths

Vite/Rollup do not support magic comments; they use plugin APIs or the `manualChunks` config for the same outcomes.

---

## Chunk hashing and caching

Hash types (Webpack terminology):

- `[hash]` — hash of the entire compilation (changes when any file changes; **avoid**)
- `[chunkhash]` — hash of this chunk only, based on module sources (Webpack)
- `[contenthash]` — hash of the chunk's final emitted content (Webpack; **the recommended choice**)

`contenthash` is stable across builds when the emitted bytes don't change — even if unrelated modules are added elsewhere. `chunkhash` can shift due to internal module ID changes.

```js
// webpack config for long-term caching
output: {
  filename: '[name].[contenthash].js',
  chunkFilename: '[name].[contenthash].js',
}
```

Vite / Rollup use content-hash by default in `[name].[hash].js` — no configuration needed.

---

## Long-term caching strategy

1. **Content-hash filenames** → immutable `Cache-Control: max-age=31536000, immutable`
2. **Split vendor deps into their own chunk** → app updates don't invalidate the vendor cache
3. **Extract the Webpack runtime** into `runtime.js` (see `optimization.runtimeChunk: 'single'`) so module IDs don't change between builds and downstream chunk hashes stay stable

```
✅ dist/vendors.a1b2c3.js       (invalidated only when node_modules changes)
✅ dist/main.d4e5f6.js          (invalidated on app code changes)
✅ dist/runtime.g7h8i9.js       (small; may change per build)
```

The HTML shell that references these files should **not** be cached long-term — it's the only mutable pointer to the current build. Serve `index.html` with `Cache-Control: no-cache` (revalidate on every request).

---

## Prefetch vs preload

| Directive        | When browser fetches | Priority                    |
| ---------------- | -------------------- | --------------------------- |
| `preload`        | Immediately          | High — for current page     |
| `prefetch`       | During idle time     | Low — for future navigation |
| `modulepreload`  | Immediately          | High — for ES modules       |

Rule of thumb: `preload` for chunks the current route needs (fonts, above-fold JS); `prefetch` for anticipated next-navigation chunks (route the user is likely to visit next).

`modulepreload` is the ES-module-aware variant — it also warms up the module's dependency graph, not just the file itself. Vite emits `modulepreload` automatically for statically discoverable async chunks.

Anti-pattern: preloading everything. Preload has a bandwidth cost that competes with the actual critical path; if you preload the whole app, nothing is prioritized.

---

## Module Federation (a mention)

A different mode of splitting: chunks live in *separate deployments*, loaded at runtime by URL. Team A ships `header@v3.js`, Team B ships `checkout@v7.js`, and the host app stitches them together at runtime. Shared dependencies (React) are negotiated between hosts and remotes to avoid duplication.

Trade-offs: runtime version-resolution complexity, network waterfalls between remotes, and versioning contracts between teams. Cross-link [[Build Tools Webpack - Module Federation]].

---

## Common mistakes

```
❌ Naming chunks with [hash] instead of [contenthash] → cache buster on every build
✅ Use [contenthash] for immutable outputs

❌ Splitting too aggressively → many tiny chunks, request overhead
✅ Group related modules; aim for chunks in the 30–200 KB range

❌ Splitting rarely-used code with preload → wasted bandwidth
✅ Use dynamic import + prefetch (or nothing) for rarely-used features

❌ Dynamic-importing a module that's also statically imported elsewhere → module still lands in the parent chunk
✅ Pick one; audit with the bundle visualizer

❌ manualChunks that creates circular dependencies between chunks → Rollup falls back or errors
✅ Widen the group until the cycle is inside one chunk
```

---

## Summary

| Mechanism            | Trigger                                    | Bundlers                     |
| -------------------- | ------------------------------------------ | ---------------------------- |
| Entry chunks         | Multiple `input` entries in config         | All                          |
| Async chunks         | `import()` in source                       | All                          |
| Auto shared/vendor   | `splitChunks` heuristics                   | Webpack                      |
| Manual shared/vendor | `manualChunks` in config                   | Rollup, Vite                 |
| Prefetch/preload     | Magic comments (Webpack) or plugin (Vite)  | Webpack (native), Vite (plugin) |
| Content hashing      | `[contenthash]` filename token             | All (default in Vite/Rollup) |
| Runtime chunk        | `optimization.runtimeChunk: 'single'`      | Webpack                      |

The three splitting modes + content-hash filenames + a stable vendor chunk = the entire long-term-caching story for a modern SPA.

---

## Related

- [[Build Tools Bundlers - Bundling Fundamentals]]
- [[Build Tools Webpack - Code Splitting and SplitChunks]] — Webpack's specifics
- [[Build Tools Vite - Production Build]] — Rollup manualChunks in Vite
- [[React Lifecycle - Suspense Lifecycle]] — React.lazy + Suspense
- [[Build Tools Bundlers Guide]]
