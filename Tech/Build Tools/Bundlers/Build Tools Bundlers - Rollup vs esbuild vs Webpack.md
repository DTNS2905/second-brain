---
tags:
  - build-tools
  - bundlers
  - tooling
  - frontend
created: 2026-07-16
source: https://bundlers.tooling.report/
---

# Build Tools Bundlers — Rollup vs esbuild vs Webpack

> A decision matrix for choosing between the three canonical bundlers based on speed, output quality, plugin depth, and code-splitting sophistication. Part of [[Build Tools Bundlers Guide]].

---

## The at-a-glance table

| Dimension | Rollup | esbuild | Webpack |
|-----------|--------|---------|---------|
| Language | JS | Go | JS |
| Speed (cold) | Moderate | Fastest (~100×) | Slowest |
| Speed (incremental) | Moderate | Fast (no incremental cache; whole rebuild is fast) | Fast (persistent cache) |
| Output quality (readable) | Best (hoisted) | Good | OK (wrapped) |
| Tree shaking | Aggressive | Aggressive | Requires config |
| Code splitting sophistication | Manual (`manualChunks`) | Basic | Full (`splitChunks` heuristics) |
| Plugin API depth | Deep (transform + graph) | Shallow (resolve + load only) | Deepest (Tapable hooks everywhere) |
| HMR | No | No | Yes (dev server) |
| Ecosystem | Vite, Nuxt, SvelteKit | Vite (as transformer), Bun | Next.js (default), CRA (legacy) |

The three tools optimize for different points on the same Pareto frontier: speed, output quality, and plugin expressiveness. None dominates the others across all axes.

---

## Speed vs plugin depth — the fundamental tradeoff

- esbuild pays for speed by restricting the plugin API (no AST-transform hook)
- Rollup and Webpack pay for expressiveness with speed
- You cannot have both — Rspack and Turbopack try (Rust + rich plugin API) but at 2026 both are still catching up on plugin ecosystem

The core reason: an AST transform hook forces the bundler to expose parsed nodes to JS-land plugins, which means shipping a JS runtime into a Go/Rust bundler and paying the FFI cost. esbuild's design deliberately keeps plugins at the file boundary (`onResolve`, `onLoad`) — plugins receive strings, not ASTs.

See [[Build Tools Bundlers - esbuild Internals]] for why the Go implementation forces this shape.

---

## Output quality — what "hoisted" means

Rollup:

```js
function foo() { return 1; }
function bar() { return foo() + 1; }
export { bar };
```

Two source modules become one lexical scope. No wrapping IIFE, no runtime, no `__webpack_require__`. This is called scope hoisting or "flat bundling".

Webpack:

```js
var __webpack_modules__ = {
  "./foo.js": (m) => { m.exports = () => 1; },
  "./bar.js": (m, _, __webpack_require__) => {
    var foo = __webpack_require__("./foo.js");
    m.exports = () => foo() + 1;
  },
};
// + module loader runtime
```

Each module is wrapped in its own IIFE and connected via a runtime module registry. Webpack does support `ModuleConcatenationPlugin` (a scope-hoisting mode), but bailouts are common when any module uses dynamic exports or CJS.

esbuild:

```js
var require_foo = () => 1;
var require_bar = () => require_foo() + 1;
export { require_bar };
```

In between — wrapper minimal, but not fully hoisted. Each module becomes a function that memoizes its exports.

For libraries, hoisted output is preferable — consumers may re-bundle, and hoisted output tree-shakes better in the consumer's bundler. See [[Build Tools Bundlers - Rollup Internals]] for how the graph flattening works.

---

## Plugin API — expressiveness comparison

| Hook | Rollup | esbuild | Webpack |
|------|--------|---------|---------|
| Resolve module | `resolveId` | `onResolve` | Resolver plugin |
| Load module | `load` | `onLoad` | Loader (per-file) |
| Transform code (AST-aware) | `transform` | ❌ (must inline via onLoad) | Loader chain |
| Post-emit / manifest | `generateBundle` | `metafile` | `emit` hook |
| Custom compilation phase | Limited | Very limited | Tapable everywhere |

### What each shape enables

Rollup's `transform` hook receives the module code post-load and can return code + sourcemap. Because it's called after loading and before graph construction, Rollup plugins can rewrite imports and the graph tracker picks up the changes. This is why `@rollup/plugin-babel`, `@rollup/plugin-typescript`, and Vite's whole SFC compiler live in `transform`.

esbuild's `onLoad` returns raw contents. If you need to transform, you must return already-transformed code — the bundler will not call you a second time on the transformed output, so plugin chaining is manual.

Webpack's Tapable hook system exposes ~20 phases (`beforeCompile`, `compile`, `thisCompilation`, `finishModules`, `optimizeChunks`, `afterEmit`, ...). Module Federation, `HtmlWebpackPlugin`, and `DefinePlugin` all exploit different phases.

---

## Code splitting — depth comparison

- **Rollup**: manual (`manualChunks`); no auto vendor detection. You write a function `(id) => 'vendor'` for shared code.
- **esbuild**: `import()` → chunk, but no auto vendor split, no runtime chunks. Splitting is opt-in via `splitting: true` and only works for ESM output.
- **Webpack**: full `optimization.splitChunks` heuristics (minSize, cacheGroups, priority), magic comments (`/* webpackChunkName */`), runtime chunk, and Module Federation for cross-app sharing.

For most apps, Webpack's automatic splitting produces a better waterfall out of the box. For fine-grained control, Rollup's `manualChunks` gives you the whole graph and lets you write the strategy explicitly. esbuild sits at the "just works for basic cases" end.

See [[Build Tools Bundlers - Chunking and Code Splitting]] for the algorithms behind each.

---

## Ecosystem placement

```
Rollup:
  - Vite (prod backend)
  - Nuxt / SvelteKit / Astro (all sit on Vite)
  - Library authors' first choice

esbuild:
  - Vite (transformer + pre-bundle)
  - Bun (bundler backend)
  - CLI tools (bundling Node scripts)

Webpack:
  - Next.js (default, opt-in Turbopack)
  - React Native (Metro is spiritually similar; not Webpack)
  - Legacy CRA apps
  - Enterprise apps with heavy custom loaders/plugins
```

The overlap is heavy: Vite uses both esbuild and Rollup, so choosing Vite means you get both without picking. Next.js uses Webpack today; Turbopack is opt-in and Rust-based.

---

## Decision matrix by task

| Task | Recommended |
|------|------------|
| Publish a library | Rollup |
| Modern React app (dev + prod) | Vite (Rollup for prod, esbuild for dev) |
| Next.js app | Webpack (or Turbopack opt-in) |
| Bundle a Node CLI | esbuild |
| Migrate from Webpack for speed | Rspack (Webpack-compatible, Rust) |
| Zero-config prototype | Parcel or Vite |

For libraries, Rollup remains the default because:
- Hoisted output re-bundles cleanly in consumers
- Preserves ESM semantics (named exports, live bindings)
- `output.preserveModules` gives per-file output for cherry-picking

For apps, Vite dominates because it hides the Rollup/esbuild split from you — dev uses esbuild (fast), prod uses Rollup (good output).

---

## The "which does what in Vite" mental model

Vite is not a bundler — it composes esbuild and Rollup:

- **Dev**: esbuild (pre-bundle deps) + Vite's own dev server (no bundling — serves modules directly over HTTP with on-demand transforms)
- **Prod**: Rollup (via Vite's config projection — Vite's plugin API is a superset of Rollup's)

```
┌──────────────────── Vite ────────────────────┐
│                                              │
│  Dev:                                        │
│    esbuild ──> pre-bundled node_modules      │
│    Vite server ──> transforms user code      │
│                                              │
│  Prod:                                       │
│    Rollup ──> bundles everything             │
│    esbuild ──> minifies                      │
│                                              │
└──────────────────────────────────────────────┘
```

Cross-link [[Build Tools Vite - Architecture Overview]].

The consequence: your Vite plugin is really a Rollup plugin (with a few Vite-specific hooks like `configureServer`). If you learn Rollup's plugin API, you know Vite's.

---

## Common misconceptions

```
❌ "esbuild is always faster than Webpack, so use it."
✅ esbuild has less plugin coverage. For a complex app, migrating from
   Webpack to esbuild directly may lose features. Use Vite (esbuild + Rollup)
   or Rspack instead.

❌ "Rollup is only for libraries."
✅ Rollup is Vite's prod backend for every app that uses Vite — including
   Nuxt, Astro, SvelteKit apps. Millions of production apps ship Rollup output.

❌ "Webpack is deprecated."
✅ Webpack is still Next.js's default. It's slower but has unmatched plugin
   depth (Module Federation, mature loaders). Rspack is the drop-in Rust
   successor, not a replacement of Webpack's ideas.

❌ "esbuild can replace Babel."
✅ esbuild handles TS syntax stripping and modern JS lowering, but not
   custom Babel plugins (JSX pragmas, styled-components, macros). If your
   toolchain has bespoke Babel plugins, you can't just swap.

❌ "Tree shaking is a bundler feature."
✅ Tree shaking requires ESM-authored code and correct `sideEffects` in
   package.json. All three bundlers tree-shake — but only if the input allows.
```

---

## Speed benchmarks with caveats

Micro-benchmarks (bundling Three.js × 10) show esbuild ~100× vs Webpack. Real-world React apps:

- **Cold build**: esbuild ~5–20× faster than Webpack
- **Incremental (Vite/Webpack HMR)**: comparable (both are fast in the inner loop)
- **Prod build (Vite = Rollup + esbuild vs Webpack + Terser)**: Vite typically 2–5× faster

Don't switch tools purely for speed unless your dev loop is the bottleneck. The dev-loop bottleneck is often not the bundler — it's TypeScript type-checking, ESLint, or test runners. Profile before migrating.

| Scenario | Webpack | Vite | esbuild alone |
|----------|---------|------|---------------|
| 100-module app cold | ~15s | ~3s | ~0.5s |
| HMR update (single file) | ~200ms | ~50ms | N/A (no HMR) |
| Prod build, 500 modules | ~60s | ~20s | ~2s (but fewer features) |

Numbers are illustrative — YMMV wildly with plugin count.

---

## The 2026 recommendation

- **Apps**: Vite (default) or Next.js (if you want RSC + full-stack)
- **Libraries**: Rollup (via `vite build --lib` or directly)
- **CLI tools**: esbuild
- **Existing Webpack app you don't want to migrate**: stick with Webpack, consider Rspack for a drop-in speed upgrade

The industry has consolidated around Vite for greenfield apps and Rollup for libraries. Webpack remains dominant only where Next.js is dominant (and even there, Turbopack is coming). esbuild rarely appears as a standalone user-facing choice — it's the fast engine inside larger tools.

For net-new work in 2026, the honest default is:

```
Vite for apps.
Rollup for libraries.
Reach for Webpack only when Next.js already reached for you.
```

See [[Build Tools Bundlers - Turbopack and Rspack]] for what comes after this generation.

---

## Related

- [[Build Tools Bundlers - Rollup Internals]]
- [[Build Tools Bundlers - esbuild Internals]]
- [[Build Tools Webpack Guide]]
- [[Build Tools Bundlers - Turbopack and Rspack]]
- [[Build Tools Vite - Architecture Overview]]
- [[Build Tools Bundlers Guide]]
