---
tags:
  - build-tools
  - bundlers
  - esbuild
  - tooling
  - frontend
created: 2026-07-16
source: https://esbuild.github.io/architecture/
---

# Build Tools Bundlers — esbuild Internals

> Written in Go, 10–100× faster than JS bundlers. Trades plugin API expressiveness for raw speed. In modern React apps, esbuild is usually the transformer inside Vite, not the primary bundler. Part of [[Build Tools Bundlers Guide]].

---

## Why esbuild is fast

Five compounding decisions, not one silver bullet:

1. **Go language** — compiled to native, no JS runtime overhead, no GC pauses on the JS heap, and cheap goroutines instead of worker-thread boundaries.
2. **Parallel parsing** — every module is parsed on its own goroutine. On an 8-core machine, parsing scales roughly 8×.
3. **Single-pass architecture** — parse, transform, and emit share the same in-memory representation. No serialize/deserialize between phases.
4. **No AST persistence between phases** — most passes fuse into one traversal, so intermediate ASTs are freed early and cache locality stays high.
5. **Inline everything hot** — no reflection, no generic containers where a struct suffices, no visitor abstractions layered above the AST.

The point isn't any single optimization — it's that JS bundlers pay the cost of *all five* inversions (interpreted, single-threaded-ish, multi-pass, AST-heavy, generic-abstracted).

---

## Two modes: transform and build

- **Transform** — one file → one output. Like Babel or SWC. Used by Vite's dev server per-request.
- **Build** — entry graph → bundled output. Full bundler mode with resolve + link.

```bash
# Transform mode
esbuild file.tsx --loader=tsx --format=esm

# Build mode
esbuild src/index.ts --bundle --outfile=dist/bundle.js --format=esm
```

The transform mode is the interesting one for framework authors — it's what lets Vite treat esbuild as "a very fast Babel" during dev without ever entering bundle mode.

---

## What esbuild does natively

- TypeScript → JS (type-erase, no semantic checks)
- JSX → JS
- Minification (whitespace, identifier, and dead-code)
- Tree shaking (aggressive; ESM required for real DCE)
- Source maps
- CommonJS → ESM interop
- CSS bundling (with limitations vs PostCSS)
- JSON / text / binary / dataurl imports

All of this is built into the Go binary — no plugins required for the common path.

---

## What esbuild deliberately doesn't do

- **Advanced code splitting** — supports `import()` but chunking heuristics are limited compared to Webpack/Rollup
- **Full plugin AST access** — plugins get resolve/load hooks, not transform-AST hooks
- **CSS Modules with variable interpolation** — basic support only
- **HMR** — bundle mode is one-shot
- **Type-checking** — you still need `tsc --noEmit`

The omissions are the design. Each one is a place where a JS bundler pays for expressiveness — esbuild refuses that trade.

---

## Plugin API — resolve and load only

```js
const myPlugin = {
  name: 'my-plugin',
  setup(build) {
    build.onResolve({ filter: /^virtual:/ }, (args) => {
      return { path: args.path, namespace: 'virtual' };
    });
    build.onLoad({ filter: /.*/, namespace: 'virtual' }, (args) => {
      return { contents: `export default 'hello'`, loader: 'js' };
    });
  },
};
```

No `transform` hook — if you want per-file transforms, use `onLoad` to intercept and return transformed code. Notably restrictive compared to Rollup or Babel, but the constraint is what enables the speed: plugins can never force esbuild to re-enter its parser mid-pipeline.

✅ Virtual modules, custom resolvers, source rewrites at the string level
❌ AST-level transforms mid-pipeline (do it yourself in `onLoad` and hand back a string)

---

## Loaders — file type → interpreter

```js
esbuild.build({
  entryPoints: ['index.tsx'],
  bundle: true,
  loader: {
    '.png': 'file',
    '.svg': 'dataurl',
    '.txt': 'text',
    '.md': 'text',
  },
});
```

Built-in loaders: `js`, `jsx`, `ts`, `tsx`, `css`, `json`, `text`, `base64`, `file`, `dataurl`, `binary`, `default`.

Loaders are the primitive that plugins compose with — an `onLoad` callback returns `{ contents, loader }` and esbuild takes it from there.

---

## Concurrency architecture

esbuild parses modules in parallel goroutines, then joins them into a single graph. The linker is single-threaded but very fast because it's Go operating on flat arrays — no HashMap indirection where an array index will do.

```
     ┌── parse (goroutine)──┐
entry┼── parse (goroutine)──┼── link (single) → emit (parallel) → files
     └── parse (goroutine)──┘
```

Result: near-linear scaling with core count for parse-heavy workloads. Linker time dominates only on very large graphs.

---

## esbuild inside Vite (pre-bundle mode)

Vite uses esbuild to **pre-bundle** dependencies from `node_modules` — a one-time step that turns CJS or thousand-file-ESM libraries into a single ESM file the dev server can serve.

```
node_modules/react/            → esbuild pre-bundle → .vite/deps/react.js
node_modules/react-dom/client/ → esbuild pre-bundle → .vite/deps/react-dom_client.js
```

Why: browsers can't efficiently import 700 small ESM files over HTTP/2 without waterfalls. Pre-bundling collapses each dep to one file, and CJS deps get an ESM wrapper in the process. See [[Build Tools Vite - Dependency Pre-Bundling]].

Vite uses Rollup — not esbuild — for the production bundle, because output quality matters more there than speed.

---

## Output quality

Good, not Rollup-best. esbuild wraps modules in small IIFE wrappers (not as hoisted as Rollup, not as machined as Webpack). The output is smaller than Webpack's default and larger than Rollup's after scope hoisting.

Fine for apps. Libraries usually prefer Rollup because its scope-hoisted output is what npm consumers expect, and it minifies better when the input is already flat.

---

## When to use esbuild standalone

✅ CLI tools — quick bundle to a single JS file
✅ Library builds where you don't need Rollup's output quality
✅ Dev-only transforms (Vite's per-request transform)
✅ Build tools written on top (Bun, Vite pre-bundle)

❌ Complex React apps needing HMR + code-splitting sophistication → use Vite (which uses esbuild + Rollup)
❌ Publishing a library where output quality matters → use Rollup
❌ Migrating from Webpack with heavy plugin usage → use Rspack (Webpack API + Rust speed)

The rule of thumb: if the bundler is the *product*, use esbuild directly. If the bundler is *infrastructure for a framework*, esbuild is usually a component, not the whole thing.

---

## API surfaces

| Interface | Where to use |
|-----------|-------------|
| CLI (`esbuild file.tsx --bundle`) | Ad-hoc builds |
| JS API (`esbuild.build()`, `esbuild.transform()`) | Build scripts, custom pipelines |
| Go API | Embedding in Go tools |
| Deno / WASM | Deno-native workflows |

The JS API is the one framework authors actually reach for — it spawns a long-lived Go child process and pipes work over stdin/stdout, so repeated `transform()` calls amortize startup cost.

---

## Benchmarks with caveats

esbuild's own benchmark (bundling 10 copies of Three.js) shows a ~100× speedup over Webpack in cold builds. Real-world speedups on medium apps are more like 5–20× vs Webpack + Terser. On small apps, the difference is imperceptible — parse time is dwarfed by node startup either way.

The number that matters isn't the ratio; it's *whether the build fits inside a coffee refill*. esbuild almost always does.

---

## Related

- [[Build Tools Bundlers - Rollup Internals]] — the plugin API comparison
- [[Build Tools Bundlers - Rollup vs esbuild vs Webpack]]
- [[Build Tools Vite - Dependency Pre-Bundling]] — esbuild's role in Vite dev
- [[Build Tools Foundations - AST and Transform Pipelines]]
- [[Build Tools Bundlers Guide]]
