---
tags:
  - build-tools
  - bundlers
  - rollup
  - tooling
  - frontend
created: 2026-07-16
source: https://rollupjs.org/plugin-development/
---

# Build Tools Bundlers — Rollup Internals

> Rollup pioneered ESM-native bundling, hoisted-scope output, and the plugin API that Vite reuses. Understanding Rollup unlocks Vite. Part of [[Build Tools Bundlers Guide]].

---

## Why Rollup matters even in 2026

Rollup is not just legacy — it's the substrate underneath most of the modern web stack.

- **Vite** uses Rollup for production builds. Dev is esbuild + native ESM; `vite build` shells out to Rollup.
- **Nuxt, SvelteKit, Astro, Remix** all sit on top of Vite → transitively Rollup for their production outputs.
- **Library publishing** still overwhelmingly uses Rollup directly because of its **hoisted, readable output** and dual ESM/CJS support.

If you understand Rollup's hook model, you understand Vite's plugin API. If you understand Rollup's output shape, you understand why bundle diffs look the way they do.

---

## Build phases

Rollup's build is a fixed pipeline. Every plugin hook is wired into one of these phases:

1. **Options** — merge user config with plugin `options()` hooks. Plugins can rewrite the entire input config here.
2. **BuildStart** — plugins hook `buildStart()`. Side effects only (spawn watchers, warm caches).
3. **ResolveId** — for each `import`, plugins can resolve custom specifiers to an absolute id (or a virtual id).
4. **Load** — plugins can provide module contents given an id. This is how virtual modules materialize.
5. **Transform** — plugins mutate module code (TS → JS, MDX → JS, inject env, etc.).
6. **BuildEnd** — traversal complete; module graph ready. Plugins can inspect the graph.
7. **GenerateBundle / WriteBundle** — plugins can inspect / mutate the final chunk graph before/after write.

Each phase has enter/exit hooks. Hooks have execution semantics:

- **first** — plugins are called in order, the first non-nullish return wins. (`resolveId`, `load`)
- **sequential** — every plugin runs, in order, on the accumulated value. (`transform`)
- **parallel** — plugins run concurrently, results ignored / merged. (`buildStart`, `buildEnd`)

Getting this wrong is the #1 source of plugin bugs — a `transform` that returns non-null for files it doesn't own will block later plugins.

---

## Plugin hook shape

Every Rollup plugin is a factory returning an object with `name` plus any subset of the phase hooks:

```ts
import type { Plugin } from 'rollup';

const myPlugin = (): Plugin => ({
  name: 'my-plugin',
  resolveId(source, importer) {
    if (source === 'virtual:cfg') return '\0virtual:cfg';
    return null; // let others try
  },
  load(id) {
    if (id === '\0virtual:cfg') return 'export const cfg = {...};';
    return null;
  },
  transform(code, id) {
    if (!id.endsWith('.md')) return null;
    return { code: `export default ${JSON.stringify(code)};`, map: null };
  },
  generateBundle(_opts, bundle) {
    // inspect / write extra files
  },
});
```

The `null` return is load-bearing: it means "I don't own this, ask the next plugin." Returning a value short-circuits the first-wins hooks.

---

## The `\0` (virtual module) convention

Any resolved id starting with `\0` (a literal null byte) is treated as a **virtual module** — Rollup will not try to read it from disk. This is how plugins expose synthetic modules that don't correspond to a file.

```ts
resolveId(id) {
  if (id === 'virtual:env') return '\0virtual:env';
}
load(id) {
  if (id === '\0virtual:env') return `export default ${JSON.stringify(process.env)};`;
}
```

Consumers import the friendly name:

```js
import env from 'virtual:env';
```

Rollup rewrites the `\0`-prefixed id in bundle output so it's never leaked to users. Vite inherits this convention wholesale.

**❌ Wrong** — returning a fake path:
```ts
resolveId(id) {
  if (id === 'virtual:env') return '/fake/virtual-env.js'; // Rollup tries to read this file
}
```

**✅ Right** — prefix with `\0`:
```ts
resolveId(id) {
  if (id === 'virtual:env') return '\0virtual:env';
}
```

---

## Hoisted output

This is Rollup's differentiator and the reason it stayed relevant. When bundling a set of ESM modules, Rollup **inlines them into a single lexical scope** instead of wrapping each in a runtime module factory.

Rollup output (readable, hoisted):

```js
function foo() {}
function bar() {}
export { foo, bar };
```

Webpack output (wrapped in a runtime):

```js
var __webpack_modules__ = {
  "./foo.js": (module) => { module.exports = function foo() {}; },
  "./bar.js": (module) => { module.exports = function bar() {}; }
};
// runtime code...
var __webpack_require__ = (id) => { /* ... */ };
```

Consequences:

- **Rollup** — smaller output, no runtime overhead, debugger-friendly stack traces, but weaker CJS interop.
- **Webpack** — every module has an isolated scope, so CJS `module.exports` assignment and circular deps "just work" at the cost of always shipping a runtime.

For **libraries**, hoisted output is a big deal — your consumers see the source verbatim in DevTools. For **apps**, either shape is fine and the tradeoffs are elsewhere (HMR, code splitting).

---

## Tree shaking pipeline

Rollup's tree shaking is aggressive and static-only:

1. Parse all ESM imports statically (requires ESM — CJS is opaque).
2. Walk usage graph from `input` entries.
3. Mark every reachable export.
4. Drop unmarked exports and any code they alone reached.

For maximum aggressiveness, the module must declare it's safe:

```json
{
  "name": "my-lib",
  "sideEffects": false
}
```

Or per-file:

```json
{
  "sideEffects": ["**/*.css", "./src/polyfill.js"]
}
```

Without `sideEffects: false`, Rollup conservatively keeps top-level statements that might have side effects — even if you don't import their exports.

**❌ Anti-pattern** — barrel with side effects:
```js
// index.js
import './register-globals'; // side-effectful, kept
export * from './utils';
export * from './heavy';
```

**✅ Better** — pure re-exports:
```js
// index.js
export * from './utils';
export * from './heavy';
// side-effect init moved into an explicit setup() function callers opt into
```

See [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]] for the general theory.

---

## `output.manualChunks`

Rollup has **no auto-splitting heuristic** (unlike Webpack's `splitChunks`). You get manual control:

```js
// rollup.config.js
export default {
  input: 'src/index.ts',
  output: {
    dir: 'dist',
    format: 'esm',
    manualChunks: {
      'react-vendor': ['react', 'react-dom'],
      'utils': ['./src/utils/date', './src/utils/format'],
    },
  },
};
```

Or as a function for dynamic control:

```js
manualChunks(id) {
  if (id.includes('node_modules')) return 'vendor';
  if (id.includes('/src/routes/admin/')) return 'admin';
}
```

Vite's `build.rollupOptions.output.manualChunks` is a direct passthrough. This is the primary lever for controlling chunking in a Vite app.

**❌ Common mistake** — chunk that imports itself:
```js
manualChunks(id) {
  if (id.includes('lodash')) return 'lodash-vendor';
  return 'vendor'; // lodash callers also land here → circular chunk import
}
```

**✅ Right** — only carve out what's clearly separate:
```js
manualChunks(id) {
  if (id.includes('node_modules/react')) return 'react-vendor';
}
```

---

## Library mode

The canonical Rollup workflow: emit ESM + CJS + type declarations. Rollup handles this natively with a multi-config array:

```js
// rollup.config.js
import typescript from '@rollup/plugin-typescript';
import nodeResolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import dts from 'rollup-plugin-dts';

export default [
  {
    input: 'src/index.ts',
    output: [
      { file: 'dist/index.esm.js', format: 'esm' },
      { file: 'dist/index.cjs', format: 'cjs' },
    ],
    plugins: [typescript(), nodeResolve(), commonjs()],
  },
  {
    input: 'src/index.ts',
    output: { file: 'dist/index.d.ts', format: 'es' },
    plugins: [dts()],
  },
];
```

Paired with `package.json` conditional exports:

```json
{
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.esm.js",
      "require": "./dist/index.cjs"
    }
  }
}
```

For a Vite wrapper around the same idea, cross-link [[Build Tools Vite - Production Build]] — Vite's library mode is a thin sugar layer over exactly this config.

---

## Plugin authoring — a real example

An `env` plugin that surfaces environment variables as a virtual module:

```ts
// plugin-env.ts
import type { Plugin } from 'rollup';

export function envPlugin(env: Record<string, string>): Plugin {
  const VIRTUAL_ID = 'virtual:env';
  const RESOLVED = '\0' + VIRTUAL_ID;
  return {
    name: 'env-plugin',
    resolveId(id) {
      if (id === VIRTUAL_ID) return RESOLVED;
    },
    load(id) {
      if (id === RESOLVED) {
        return `export default ${JSON.stringify(env)};`;
      }
    },
  };
}
```

Usage in application code:

```js
import env from 'virtual:env';
console.log(env.API_URL);
```

Wired into config:

```js
// rollup.config.js
import { envPlugin } from './plugin-env';

export default {
  input: 'src/index.ts',
  output: { file: 'dist/bundle.js', format: 'esm' },
  plugins: [
    envPlugin({
      API_URL: process.env.API_URL ?? 'http://localhost:3000',
      NODE_ENV: process.env.NODE_ENV ?? 'development',
    }),
  ],
};
```

That's a full end-to-end plugin in ~15 lines. This is why every Vite/Nuxt/SvelteKit meta-framework leans on the pattern: it's small, composable, and cache-friendly.

---

## What Rollup deliberately doesn't do

- **No dev server** — Rollup is a build tool. Watch mode exists (`--watch`) but there's no HTTP layer.
- **No HMR** — build-time only. Vite adds HMR on top of Rollup's plugin API for dev, and drops it for the production build.
- **No advanced CJS handling** — needs `@rollup/plugin-commonjs` to consume CJS deps. This is deliberate: Rollup assumes ESM as the source of truth.
- **No auto chunk-split heuristics** — you must specify `manualChunks` if you want splitting. Webpack's `splitChunks` doesn't have an equivalent.
- **No asset pipeline** — no CSS, no image handling. Every non-JS asset requires a plugin.

The scope is intentional. Rollup does one thing: turn an ESM graph into an ESM (or CJS/UMD/IIFE) bundle.

---

## When to reach for Rollup directly (not via Vite)

Rollup direct is the right call when:

- **Publishing a library** — best output quality, dual ESM/CJS, no runtime wrapper.
- **Bundling a Node CLI** — `--format=cjs` for legacy Node, `--format=esm` for modern.
- **You need fine-grained emit control** — custom asset naming, manual chunk shapes, non-standard output formats.
- **Zero-dependency posture** — no dev-server bloat when all you want is a build.

For **apps**, use Vite (which invokes Rollup under the hood but gives you dev server, HMR, and sensible defaults for free).

| Use case | Tool |
|----------|------|
| Library (npm package) | Rollup direct |
| App with dev server + HMR | Vite (uses Rollup for build) |
| Node CLI, small | esbuild or tsup |
| Node CLI, complex output | Rollup direct |
| Meta-framework (Nuxt/SvelteKit/Astro) | Vite (transitively Rollup) |

---

## Summary

| Concept | Rollup behavior |
|--------|-----------------|
| Output shape | Hoisted single-scope, no runtime wrapper |
| Plugin API | Phase-based hooks (resolveId → load → transform → generateBundle) |
| Virtual modules | Ids prefixed with `\0` |
| Tree shaking | Static ESM analysis, honors `package.json#sideEffects` |
| Code splitting | Manual via `output.manualChunks`, no auto heuristic |
| CJS input | Requires `@rollup/plugin-commonjs` |
| Dev server / HMR | None — build only |
| Library workflow | Multi-config array, `rollup-plugin-dts` for `.d.ts` |
| Downstream users | Vite, Nuxt, SvelteKit, Astro, Remix |

Rollup is the quietly load-bearing piece of the modern JS build stack. Every plugin API you write for Vite is a Rollup plugin.

---

## Related

- [[Build Tools Bundlers - esbuild Internals]] — Rollup's fast cousin
- [[Build Tools Bundlers - Rollup vs esbuild vs Webpack]]
- [[Build Tools Vite - Plugin API]] — Vite's plugin API extends Rollup's
- [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]]
- [[Build Tools Bundlers Guide]]
