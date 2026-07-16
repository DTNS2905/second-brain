---
tags:
  - build-tools
  - webpack
  - code-splitting
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/plugins/split-chunks-plugin/
---

# Build Tools Webpack — Code Splitting and SplitChunks

> Webpack's SplitChunks is the industry standard for automatic chunk optimization — heuristics for vendor extraction, shared modules, and dynamic imports. This note demystifies the config surface. Part of [[Build Tools Webpack Guide]].

---

## Three split modes

Webpack code-splits through three orthogonal mechanisms. Understanding which mechanism produces which chunk is the prerequisite to reading a bundle report.

1. **Entry-based** — multiple entries in config → multiple bundles. Static, declared at build time.
2. **Dynamic import** — `import()` in source → separate chunk automatically. Discovered from module graph.
3. **SplitChunks (automatic sharing)** — extract shared modules across chunks. Post-processing pass driven by heuristics.

The three combine: SplitChunks runs over the output of the first two, extracting shared code from the chunks they produced.

---

## Entry-based splitting

Declare each independent bundle in `entry`:

```js
entry: {
  main: './src/index.tsx',
  admin: './src/admin/index.tsx',
}
```

Two bundles produced: `main.js` + `admin.js`. If both import lodash, both include it (unless SplitChunks extracts it into a shared chunk).

Use entries for **truly independent HTML pages** — landing page vs. admin dashboard vs. embed widget. Do not use entries for lazy-loaded sub-features inside one SPA; that is what dynamic imports are for.

---

## Dynamic import splitting

Any `import()` expression in application code produces an async chunk:

```js
button.onclick = async () => {
  const { openEditor } = await import('./editor');
  openEditor();
};
```

Webpack emits `editor.<hash>.js` as an async chunk. Browser fetches on click. The parent chunk contains only the promise plumbing (a few hundred bytes) — the editor code is deferred until the user actually needs it.

Dynamic imports are the primary lever for lowering initial JS payload. Every route, every modal, every rarely-used panel is a candidate.

---

## Magic comments

Webpack reads specially-formatted comments inside `import()` to customize the emitted chunk:

```js
const mod = await import(
  /* webpackChunkName: "editor" */
  /* webpackPrefetch: true */
  /* webpackPreload: false */
  /* webpackMode: "lazy" */
  './editor'
);
```

- `webpackChunkName` — filename base (readable). Without it, chunks get numeric IDs like `247.chunk.js`.
- `webpackPrefetch: true` → `<link rel="prefetch">` injected into HTML. Browser fetches at idle.
- `webpackPreload: true` → `<link rel="preload">`. Browser fetches immediately alongside parent.
- `webpackMode`:
  - `"lazy"` (default) — separate async chunk per `import()` call
  - `"eager"` — no separate chunk; module inlined into parent, but still async in API
  - `"weak"` — resolve only if module was already loaded elsewhere; otherwise reject
  - `"lazy-once"` — one chunk shared by all matching template-string imports
- `webpackInclude` / `webpackExclude` — regex filters for template-string dynamic imports:

```js
import(`./locales/${lang}.json`,
  /* webpackInclude: /(en|fr|de)\.json$/ */
  /* webpackChunkName: "locale-[request]" */
);
```

Only `en`, `fr`, `de` JSON files ship — the rest are excluded from the bundle entirely.

---

## SplitChunks — the config surface

The full default (with all knobs made explicit):

```js
optimization: {
  splitChunks: {
    chunks: 'all',              // 'async' | 'initial' | 'all'
    minSize: 20000,             // 20KB — min chunk size to extract
    minChunks: 1,               // extract if used in ≥ 1 chunks
    maxAsyncRequests: 30,       // max parallel async fetches
    maxInitialRequests: 30,     // max parallel initial fetches
    enforceSizeThreshold: 50000,
    cacheGroups: {
      defaultVendors: {
        test: /[\\/]node_modules[\\/]/,
        priority: -10,
        reuseExistingChunk: true,
      },
      default: {
        minChunks: 2,
        priority: -20,
        reuseExistingChunk: true,
      },
    },
  },
}
```

Each knob:

- `minSize` — a candidate chunk must reach this size to be worth extracting. Smaller → more chunks, more HTTP overhead.
- `minChunks` — how many chunks a module must appear in before extraction. `1` means "any module in `node_modules`" for the vendors group; `2` means "shared between at least two chunks" for the default group.
- `maxAsyncRequests` — Webpack will refuse to split further if a route already loads this many parallel async chunks.
- `maxInitialRequests` — same cap for the initial page load.
- `enforceSizeThreshold` — above this size, other constraints (like `maxInitialRequests`) are ignored. Prevents monolithic chunks.
- `reuseExistingChunk` — if a module is already in another chunk, reference it rather than duplicating.

---

## chunks option

The single most consequential setting:

- `'all'` — split both async and initial chunks (recommended default)
- `'async'` — only async chunks (legacy default in older Webpack)
- `'initial'` — only initial (entry) chunks

`'all'` lets shared modules be extracted regardless of how they entered the graph. `'async'` will not extract a lib that both the entry and a lazy route use — the entry keeps its copy, the lazy chunk gets its own.

---

## cacheGroups — custom split rules

`cacheGroups` is where you override defaults with domain-specific rules:

```js
cacheGroups: {
  react: {
    test: /[\\/]node_modules[\\/](react|react-dom)[\\/]/,
    name: 'react-vendor',
    chunks: 'all',
    priority: 10,
  },
  ui: {
    test: /[\\/]src[\\/]components[\\/]ui[\\/]/,
    name: 'ui',
    minChunks: 2,
    chunks: 'all',
  },
}
```

`priority` breaks ties: higher priority wins when a module matches multiple groups. React matches both the custom `react` group (priority `10`) and `defaultVendors` (priority `-10`) — `react` wins because `10 > -10`.

Each group option:

- `test` — regex, function, or string matching module paths
- `name` — output chunk name; use `false` for auto-generated
- `chunks` — override the top-level `chunks` for this group
- `enforce: true` — ignore `minSize`/`minChunks` for this group (force extraction)
- `filename` — override output filename template

Common cacheGroup patterns worth knowing:

```js
cacheGroups: {
  framework: {
    test: /[\\/]node_modules[\\/](react|react-dom|scheduler)[\\/]/,
    name: 'framework',
    priority: 40,
    enforce: true,
  },
  lib: {
    test(module) {
      return module.size() > 160000 &&
             /node_modules[\\/]/.test(module.identifier());
    },
    name(module) {
      const hash = require('crypto').createHash('sha1');
      hash.update(module.identifier());
      return `lib-${hash.digest('hex').slice(0, 8)}`;
    },
    priority: 30,
    minChunks: 1,
    reuseExistingChunk: true,
  },
  commons: {
    name: 'commons',
    minChunks: 2,
    priority: 20,
  },
}
```

This mirrors Next.js's production heuristic: framework in its own chunk (rare to change), big libs each in their own chunk (better long-term caching), everything shared by 2+ pages in `commons`.

---

## runtimeChunk

Webpack embeds runtime code (module registry, chunk loader) in each entry chunk by default. Extract it:

```js
optimization: {
  runtimeChunk: 'single',        // one shared runtime.js
  // OR
  runtimeChunk: { name: 'runtime' },
  // OR
  runtimeChunk: 'multiple',      // per-entry: runtime~main.js, runtime~admin.js
}
```

Why: without a shared runtime chunk, adding a new module to any chunk changes the runtime code in that chunk → cache-busted despite same modules. With `runtimeChunk: 'single'`, only the tiny `runtime.js` is invalidated, and vendor chunks stay cached across deploys.

Inline it into HTML with `html-webpack-plugin` + `inline-manifest-webpack-plugin` to avoid the extra HTTP request.

---

## Chunk hashing

The single most common source of "why is my cache always busted" pain:

| Placeholder | What changes |
|-------------|--------------|
| `[hash]` | Every module in every chunk |
| `[chunkhash]` | Modules in this chunk (JS + related CSS via runtime) |
| `[contenthash]` | Just this file's content — **use this** |

```js
output: {
  filename: '[name].[contenthash].js',
  chunkFilename: '[name].[contenthash].chunk.js',
}
```

`[contenthash]` gives per-file granularity — a change to route A's chunk does not invalidate route B's cache. `[chunkhash]` couples JS and CSS extracted from the same chunk (a CSS-only change invalidates JS). `[hash]` invalidates everything on every build.

---

## Prefetch vs preload

Two `<link rel>` directives; wildly different semantics:

| Directive | When | Priority | Use |
|-----------|------|----------|-----|
| `preload` | Immediately | High | Current page |
| `prefetch` | Idle | Low | Next navigation |

Rule: `preload` chunks needed for THIS route. `prefetch` chunks likely needed for NEXT route.

Example:

```js
// Login form imports the dashboard route as prefetch —
// user will likely navigate there after logging in.
import(/* webpackPrefetch: true */ './routes/Dashboard');

// Font subset needed for above-the-fold text — preload.
import(/* webpackPreload: true */ './fonts/inter-subset');
```

Overuse of `preload` competes with the current page's own resources. Overuse of `prefetch` wastes bandwidth on things the user never navigates to.

---

## Route-based splitting (React example)

The canonical SPA pattern:

```tsx
const Editor = React.lazy(() =>
  import(/* webpackChunkName: "editor" */ './routes/Editor')
);

<Suspense fallback={<Spinner />}>
  <Routes>
    <Route path="/editor" element={<Editor />} />
  </Routes>
</Suspense>
```

Each route becomes its own chunk, fetched on navigation. Combine with `webpackPrefetch` on likely-next routes to eliminate perceived latency. Cross-link [[React Lifecycle - Suspense Lifecycle]] for how Suspense integrates with the async chunk fetch.

For dependent chunks (e.g. Editor also uses a rich-text lib), let SplitChunks extract the shared dependency into `commons`, so navigating between Editor and Preview reuses the parsed module.

---

## Debugging splits

The first tool: enable detailed stats output.

```
stats: 'detailed'
```

Or use `webpack-bundle-analyzer`:

```js
const { BundleAnalyzerPlugin } = require('webpack-bundle-analyzer');
plugins: [new BundleAnalyzerPlugin()]
```

This opens a treemap of every chunk and every module inside it — the fastest way to answer "why is this chunk so big" and "why is lodash in three chunks".

Common findings:

- **Duplicated deps** → tune cacheGroups. Usually a module is landing in a chunk that doesn't match `defaultVendors.test`; extract it explicitly.
- **Vendor chunk too large** → split further. Add cache groups for the biggest libs (React, moment, ChartJS) so long-term caching benefits per-lib.
- **Too many tiny chunks** → raise `minSize`. A 4KB chunk costs more in HTTP overhead than it saves.
- **`node_modules` inside a route chunk** → the lib is only used by that route; often correct, but check if it should be prefetched.
- **Duplicate `polyfills`** → check `chunks: 'all'` is set; `async`-only won't extract from initial.

---

## Common mistakes

```
❌ Using [hash] instead of [contenthash] → every build cache-busts
✅ [contenthash] for immutable outputs

❌ Not extracting runtime → module ID changes break vendor cache
✅ optimization.runtimeChunk: 'single'

❌ Too many cacheGroups → chunk explosion
✅ Start with defaults, tune only when you see a specific problem

❌ chunks: 'async' with a shared vendor lib on the initial page
✅ chunks: 'all' — extract regardless of how it entered the graph

❌ webpackPreload everywhere "for speed"
✅ preload only current-page critical; prefetch next-route candidates

❌ minSize: 0 to force splitting everything
✅ Keep 20KB default — many small chunks cost more in HTTP than they save

❌ Dynamic import inside a hot loop
✅ Import once at module top or use a memoized loader

❌ No webpackChunkName → unreadable numeric chunk IDs in prod
✅ Always name lazy chunks

❌ Route split without <Suspense> boundary
✅ Wrap React.lazy consumers in Suspense with a fallback
```

---

## Related

- [[Build Tools Bundlers - Chunking and Code Splitting]] — the concept
- [[Build Tools Webpack - Core Concepts]]
- [[Build Tools Webpack - Module Federation]]
- [[React Lifecycle - Suspense Lifecycle]]
- [[Build Tools Webpack Guide]]
