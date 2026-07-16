---
tags:
  - build-tools
  - vite
  - esbuild
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/dep-pre-bundling
---

# Build Tools Vite — Dependency Pre-Bundling

> Vite runs esbuild once at dev startup to convert node_modules into a small number of ESM files the dev server can serve efficiently. This is why "vite dev" is fast even for apps with thousands of dependencies. Part of [[Build Tools Vite Guide]].

---

## Why pre-bundle at all

Vite serves source files as native ESM to the browser — no bundling of app code in dev. But raw `node_modules` can't be served that way for two reasons:

1. **Many deps ship CJS.** React internally, most of `lodash`, older utility libraries, and a long tail of packages still publish CommonJS as their main entry. Browsers cannot `import` from a `module.exports =` file — the module resolver has no idea how to interpret it as ESM. Something has to convert `module.exports` into `export default` before the browser sees it.

2. **Some ESM deps ship thousand-file trees.** `lodash-es`, `date-fns`, `@mui/icons-material`, `rxjs/operators` — all correctly ESM, but each function lives in its own file. A single `import { debounce } from 'lodash-es'` walks the barrel file, which then imports 300+ sibling files. The browser fires off 300+ HTTP requests, each waiting for the previous to resolve to know what it needs next. Waterfall of doom.

Pre-bundling solves both by flattening each dep into a **single ESM file** that the dev server can hand back in one request.

```
❌ Without pre-bundle:
   import { debounce } from 'lodash-es'
   → browser fetches lodash-es/index.js
   → which imports ./debounce.js, ./throttle.js, ./curry.js, ...
   → 300+ requests before the module is usable

✅ With pre-bundle:
   import { debounce } from 'lodash-es'
   → rewritten to /node_modules/.vite/deps/lodash-es.js?v=abc123
   → one request, entire dep evaluated
```

---

## The workflow

The pre-bundle step runs at dev startup and is completely automatic:

1. First `vite dev` after `npm install` — Vite scans your entry HTML and JS/TS files for bare imports (`import x from 'pkg'`).
2. esbuild bundles each discovered dep into `node_modules/.vite/deps/<name>.js`. esbuild is the tool because it's ~10–100× faster than Rollup for this transform, which is critical since it blocks dev startup.
3. Vite rewrites every bare import in served source files:
   ```
   import React from 'react'
   →
   import React from '/node_modules/.vite/deps/react.js?v=abc123'
   ```
4. Cached until `package.json`, `pnpm-lock.yaml`, or Vite config changes. Subsequent `vite dev` invocations reuse the cache and are near-instant.

The `?v=abc123` query string is a hash of the resolved dep set — it lets the browser cache aggressively while still busting when deps change.

---

## The cache directory

Everything lives under `node_modules/.vite/deps/`:

```
node_modules/.vite/
├── deps/
│   ├── react.js
│   ├── react.js.map
│   ├── react-dom_client.js
│   ├── lodash-es.js
│   ├── chunk-ABC123.js       ← shared code between deps
│   ├── _metadata.json        ← version hash + dep list
│   └── package.json          ← { "type": "module" }
└── deps_temp_<timestamp>/    ← in-flight rebuild, atomically renamed
```

- One `.js` per pre-bundled dep, plus shared chunks when esbuild finds duplicated code across deps.
- `_metadata.json` stores the hash used in `?v=` query params. Vite compares this against a hash of the current lockfile + config to decide whether to reuse or rebuild.
- The bare `package.json` with `"type": "module"` forces Node/esbuild to treat every file in the directory as ESM.

The directory is safe to `rm -rf` — Vite will rebuild it on next start.

---

## Discovery vs static analysis

Vite tries to statically discover deps by scanning:

- `index.html` (and anything in `optimizeDeps.entries`)
- Every imported source file, recursively, following `import` and `import()` statements

Static analysis catches the common case. But it can miss deps that are:

- Dynamically imported with a computed specifier: `import(\`./locales/${lang}.js\`)`
- Imported only from a rarely-visited route (lazy route + `React.lazy`)
- Referenced through a re-export chain the scanner gives up on

When a missed dep is finally requested at runtime, Vite triggers a **secondary pre-bundle** during dev:

```
[vite] new dependencies optimized: some-lib, another-lib
[vite] optimized dependencies changed. reloading
```

The browser reloads because rewritten import URLs (with new `?v=` hashes) have to be re-fetched. This is annoying — you click into a route, the page half-loads, then reloads. To avoid it, pre-declare the deps in `optimizeDeps.include`.

---

## optimizeDeps.include / .exclude

Two escape hatches for when discovery gets it wrong.

```ts
// vite.config.ts
import { defineConfig } from 'vite'

export default defineConfig({
  optimizeDeps: {
    include: [
      'react',
      'react-dom/client',
      'my-monorepo-pkg',        // linked local dep, force pre-bundle
      'lazy-route-only-lib',    // avoid secondary bundle + reload
    ],
    exclude: [
      'some-heavy-esm-dep',     // already ESM + single-file, skip the work
      '@vite/env-only-thing',   // dep that misbehaves under esbuild
    ],
  },
})
```

- **`include`** — force these into the pre-bundle even if static analysis missed them. Common for deps only reached through dynamic imports.
- **`exclude`** — skip these entirely. Vite serves them straight from `node_modules` as-is. Use when the dep is already a single ESM file and pre-bundling adds no value, or when pre-bundling breaks the dep.

---

## Forcing re-optimize

The `--force` flag deletes the cache and rebuilds it:

```bash
vite dev --force
```

You almost never need this. Vite hashes the lockfile, `package.json`, and relevant config keys — if any change, the cache is invalidated automatically. `--force` is for the rare case where:

- You're editing a linked package's source directly and want the new code picked up
- Cache got corrupted (interrupted rebuild, disk full mid-write)
- You suspect a Vite bug in cache invalidation and want to rule it out

Alternatively: `rm -rf node_modules/.vite`.

---

## CJS → ESM interop

Pre-bundling also fixes the messy default-export interop between CJS and ESM. Bare CJS in the browser has no notion of `default`; esbuild wraps it so both interop patterns work.

**Case 1: single default export**

```js
// cjs-lib/index.js (CJS)
module.exports = function greet() { return 'hi' }
```

After pre-bundle, the wrapper exposes it as both default and namespace:

```js
// ✅ works
import greet from 'cjs-lib'

// ✅ also works
import * as greet from 'cjs-lib'
```

**Case 2: named exports object**

```js
// cjs-utils/index.js (CJS)
module.exports = {
  a: () => 1,
  b: () => 2,
}
```

The wrapper hoists each key to a named ESM export:

```js
// ✅ works
import { a, b } from 'cjs-utils'

// ✅ also works (whole object as default)
import utils from 'cjs-utils'
utils.a()
```

Without pre-bundle, named imports from a CJS dep would fail — the ESM spec requires exports to be statically analyzable, which `module.exports = {...}` isn't. esbuild does the analysis at bundle time and emits real `export` statements.

See [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] for the underlying model differences.

---

## Deep imports

Vite handles imports into subpaths of a dep, not just the main entry.

```js
// deep import into a subpath
import { debounce } from 'lodash-es/debounce'
```

Vite pre-bundles `lodash-es/debounce` as its own entry:

```
node_modules/.vite/deps/lodash-es_debounce.js
```

For libraries using the modern `exports` field with subpath patterns:

```json
{
  "name": "my-lib",
  "exports": {
    ".": "./index.js",
    "./features/*": "./src/features/*.js",
    "./package.json": "./package.json"
  }
}
```

Vite follows the `exports` map when resolving `import x from 'my-lib/features/foo'` and pre-bundles the mapped file. This means `exports`-gated deps Just Work — you don't need to configure anything special.

Deep imports that Vite hasn't seen before will trigger the secondary bundle described earlier; add them to `optimizeDeps.include` to preempt this.

---

## Linked packages (monorepos)

Linked deps (via `pnpm`, `yarn workspaces`, `npm link`) live outside your project's `node_modules` — usually up one or two directories in the monorepo root. Vite needs two things to handle them:

```ts
// vite.config.ts
export default defineConfig({
  optimizeDeps: {
    // pre-bundle react as it appears through the linked pkg
    include: ['@my/local-pkg > react'],
  },
  server: {
    fs: {
      allow: ['..'], // allow reading files outside project root
    },
  },
})
```

- The `'@my/local-pkg > react'` syntax says "pre-bundle the `react` that `@my/local-pkg` depends on." Useful when your app and a linked package have separate React copies — pre-bundling forces them into the same bundle to avoid the two-copies-of-React runtime error.
- `server.fs.allow: ['..']` opts out of Vite's default filesystem sandbox so it can serve files from the monorepo root.

By default Vite excludes linked deps from pre-bundling (so edits to the linked source hot-reload cleanly). Explicitly `include` them when you want the bundling behavior back.

---

## When pre-bundling breaks things

Pre-bundling is usually invisible, but it can trip on deps that do weird things:

```
❌ Dep uses require() conditionally at runtime
   e.g. `if (isServer) require('fs')`
   → esbuild sees the require() at bundle time and either bundles fs
     or errors. Runtime condition is gone.
✅ Add to optimizeDeps.exclude, let it serve as-is, and pair with an
   SSR/env guard.

❌ Dep expects Node globals in the browser (process, Buffer, global)
   → esbuild doesn't polyfill these.
✅ Add polyfills via optimizeDeps.esbuildOptions.plugins, or find a
   browser-native alternative.

❌ Dep imports a .css or .wasm file expecting the bundler to handle it
   → esbuild pre-bundle only outputs JS; non-JS assets are dropped or
     inlined incorrectly.
✅ Exclude the dep so Vite's dev server handles the asset request
   through its normal pipeline.

❌ Dep uses top-level await in a way esbuild refuses (older targets)
✅ Bump `optimizeDeps.esbuildOptions.target` to 'esnext'.
```

For the last case:

```ts
export default defineConfig({
  optimizeDeps: {
    esbuildOptions: {
      target: 'esnext',
      supported: {
        'top-level-await': true,
      },
    },
  },
})
```

---

## Prod build doesn't use pre-bundle

Pre-bundling is a **dev-only** step. `vite build` doesn't touch `node_modules/.vite/`:

- Prod build uses Rollup, which walks the full import graph and bundles everything (app code + deps) into optimized chunks.
- CJS deps are handled by `@rollup/plugin-commonjs`, which Vite invokes internally as part of its default plugin set.
- The output is not `deps/react.js` — it's the usual `assets/index-<hash>.js` chunks with deps inlined or code-split.

This split (esbuild in dev, Rollup in prod) is a deliberate design choice: esbuild optimizes for speed, Rollup optimizes for output quality (tree-shaking, chunking). See [[Build Tools Bundlers - esbuild Internals]] and [[Build Tools Vite - Architecture Overview]] for the full picture.

One consequence: a dep that works in dev but breaks in prod is often a pre-bundle vs Rollup difference. If you see this, try adding the dep to `optimizeDeps.exclude` and see if it also breaks in dev — that isolates the bundler.

---

## Config surface

Full `optimizeDeps` shape with defaults:

```ts
// vite.config.ts
export default defineConfig({
  optimizeDeps: {
    entries: ['index.html', 'src/*.html'], // files to scan for deps
    include: [],                            // force these into pre-bundle
    exclude: [],                            // skip pre-bundle for these
    force: false,                           // same as --force flag
    esbuildOptions: {},                     // pass-through to esbuild
    holdUntilCrawlEnd: true,                // wait for full scan before serving
    disabled: false,                        // 'build' | 'dev' | true | false
  },
  cacheDir: 'node_modules/.vite',           // where to write .vite/deps/
})
```

Key knobs:

| Option | Purpose |
|---|---|
| `entries` | Additional files to scan when discovering deps. Add SPA routes or non-HTML entries here. |
| `include` | Explicit list of deps to pre-bundle. Prevents secondary-bundle reloads. |
| `exclude` | Deps to skip. Vite serves them straight from disk. |
| `force` | Rebuild the cache on next start. Equivalent to `--force`. |
| `esbuildOptions` | Everything under this is forwarded to esbuild's `build()` API — target, plugins, define, loader, etc. |
| `holdUntilCrawlEnd` | Delay serving the first request until dep scan finishes. Reduces reloads at the cost of slightly slower first paint. |
| `disabled` | Turn off pre-bundling entirely. Almost never useful. |
| `cacheDir` | Where `.vite/deps/` lives. Change if `node_modules` is on a slow filesystem. |

For the interaction between pre-bundling and Vite's dev server, see [[Build Tools Vite - Dev Server Architecture]].

---

## Related

- [[Build Tools Bundlers - esbuild Internals]]
- [[Build Tools Foundations - Module Systems (ESM CJS UMD)]]
- [[Build Tools Vite - Dev Server Architecture]]
- [[Build Tools Vite - Architecture Overview]]
- [[Build Tools Vite Guide]]
