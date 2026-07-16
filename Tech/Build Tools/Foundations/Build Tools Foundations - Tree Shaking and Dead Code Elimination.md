---
tags:
  - build-tools
  - foundations
  - tree-shaking
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/guides/tree-shaking/
---

# Build Tools Foundations — Tree Shaking and Dead Code Elimination

> Tree shaking is mark-and-sweep on the ESM graph. It only works when imports are statically analyzable AND modules are provably side-effect-free. Both preconditions fail more often than you'd think. Part of [[Build Tools Foundations Guide]].

---

## What tree shaking is

A dead-code elimination pass that walks the ESM export graph from the entry point, marks every export that's actually imported (transitively), and drops the unmarked ones from the final bundle.

The name comes from the mental model: hold the module graph by its entry, shake it, and everything not firmly attached falls off.

```js
// lib.js
export const used = () => 1;
export const unused = () => 2;

// entry.js
import { used } from './lib';
console.log(used());

// bundle (after tree shaking)
const used = () => 1;
console.log(used());
// `unused` is gone
```

Tree shaking is a **build-time** optimization. It's distinct from runtime DCE (branch elimination, constant folding) which minifiers do separately.

---

## The two preconditions

Tree shaking is fragile. It requires **both** of these to hold — miss either, and the bundler falls back to "keep everything."

### 1. Static ESM

`import { x } from 'lib'` must be statically parseable at build time. The bundler needs to know, without executing anything, exactly which bindings flow between modules.

- ✅ `import { x } from 'lib'`
- ✅ `export { x }`
- ❌ `const x = require('lib').x` — CJS is dynamic
- ❌ `import(name)` where `name` is a variable — dynamic import path

See [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] for why CJS can't be statically analyzed.

### 2. Provably side-effect-free

The bundler must know that dropping an unused import won't skip a needed side effect — a registration call, a prototype patch, a store dispatch, a CSS injection.

By default, the bundler assumes **every module has side effects**. Even if you don't use the export, loading the module might do something important, so it stays.

```js
// side-effect.js — assumed to have side effects, even if unused
window.__MY_LIB__ = true;
export const helper = () => {};

// entry.js
import { helper } from './side-effect';
// If `helper` is unused, can the bundler drop the module?
// Default answer: NO. The `window.__MY_LIB__ = true` might matter.
```

You unlock aggressive dropping by declaring modules pure via `sideEffects` or `/*#__PURE__*/`.

---

## sideEffects field — the contract

In `package.json`:

```json
{ "sideEffects": false }
```

This tells bundlers: "no file in this package has import-time side effects — you can drop unused imports from any of them."

Fine-grained form — list the files that *do* have side effects:

```json
{
  "sideEffects": [
    "*.css",
    "*.scss",
    "./src/polyfill.js",
    "./src/register-*.js"
  ]
}
```

Now CSS imports and the polyfill/registration files are preserved; everything else is fair game.

**Missing `sideEffects` field → bundlers assume the worst → keep everything.**

```json
// ❌ No sideEffects field — tree shaking hobbled
{
  "name": "my-lib",
  "main": "./dist/index.js",
  "module": "./dist/index.mjs"
}

// ✅ Explicit — bundler can drop unused exports
{
  "name": "my-lib",
  "main": "./dist/index.cjs",
  "module": "./dist/index.mjs",
  "sideEffects": false
}
```

Set this in your **app's** `package.json` too — the app is a module the bundler walks, and its own barrels are subject to the same rules.

---

## The /*#__PURE__*/ annotation

Marks a call expression as side-effect-free. If the return value is unused, drop the whole call.

```js
// ✅ Even if the bundler can't prove createInstance() is pure,
// this annotation says it is
const client = /*#__PURE__*/ createInstance({ apiKey: 'x' });
```

Used inside compiled output — Preact's `h()` calls, React's `_jsx()` in some configurations, Rollup's own output — so unused component instantiations get dropped even when the factory function isn't provably pure.

```js
// input
import { Component } from './Component';
const el = <Component prop="x" />;

// compiled output with /*#__PURE__*/
const el = /*#__PURE__*/ _jsx(Component, { prop: "x" });
// If `el` is never used, the whole _jsx call disappears
```

Without the annotation, minifiers must assume `_jsx()` might mutate globals or throw, so they keep it.

---

## Why CJS breaks tree shaking

CJS builds the export object **at runtime**. `module.exports = { … }` is an assignment statement, not a declaration — the bundler can't reason about which fields will be read without executing the code.

```js
// ❌ CJS lib — tree shaking impossible
// node_modules/lib/index.cjs
module.exports = { a, b, c, d };

// consumer
const { a } = require('lib');
// b, c, d still bundled — the whole exports object is kept
```

```js
// ✅ ESM lib — tree shakable
// node_modules/lib/index.js
export { a, b, c, d };

// consumer
import { a } from 'lib';
// b, c, d dropped if sideEffects: false
```

This is why `lodash` doesn't tree-shake (CJS) but `lodash-es` does (ESM).

```js
// ❌ Pulls in ~70KB — the whole lodash CJS module object
import { debounce } from 'lodash';

// ✅ Pulls in ~2KB — only `debounce` and its dependencies
import { debounce } from 'lodash-es';

// ❌ Also fine but relies on package-level tree shaking
//    working — usually does with lodash-es
import debounce from 'lodash/debounce';
```

Modern libraries publish **dual packages** with `exports` field routing consumers to ESM when their bundler supports it. See [[Build Tools Foundations - Module Systems (ESM CJS UMD)]].

---

## Barrel file traps

A "barrel" is a re-export file that gathers modules into a single import surface:

```js
// src/utils/index.ts
export * from './date';
export * from './string';
export * from './network';
export * from './crypto';
```

Consumers write `import { formatDate } from '@/utils'` instead of `import { formatDate } from '@/utils/date'`.

**The problem:** with `sideEffects: true` (the default for your app if not set), a barrel forces the bundler to *load* every re-exported file just to check for side effects — negating tree shaking.

```js
// entry.ts
import { formatDate } from '@/utils';
// Bundler must load date.ts, string.ts, network.ts, crypto.ts
// to check if any have side effects, even though only
// formatDate is used
```

Even with `sideEffects: false`, resolution of `export *` requires walking every file to build the export map. It works, but slows down builds significantly.

**Fixes:**

- ✅ Set `"sideEffects": false` in your app's `package.json`
- ✅ Import directly: `import { formatDate } from '@/utils/date'` — bypass the barrel
- ✅ Framework-level: Next.js's `optimizePackageImports` config rewrites barrel imports automatically
- ❌ `export * from './everything'` in perf-critical libraries — prefer explicit named re-exports

```js
// ❌ Anti-pattern for large barrels
export * from './date';
export * from './string';

// ✅ Explicit — bundler sees the exact export surface without loading files
export { formatDate, parseDate } from './date';
export { camelCase, kebabCase } from './string';
```

---

## Aggressiveness across bundlers

| Bundler | Tree-shake level |
|---------|------------------|
| Rollup | Aggressive — pioneered the technique. Best output for libraries. |
| esbuild | Aggressive. Fast + effective. |
| Webpack | Requires `optimization.usedExports: true` (default in `production` mode) + `sideEffects` fields. |
| Vite | Uses Rollup in prod → aggressive by default. |
| Parcel | Enabled by default. |
| Turbopack | Aggressive; similar to Rollup. |
| SWC (bundler mode, experimental) | Aggressive. |

Webpack lags because it evolved from a CJS-first world — it has to be conservative to avoid breaking existing projects. Rollup was ESM-first and shipped tree shaking as a headline feature from day one.

---

## What tree shaking does NOT catch

- **Runtime dead code** — `if (false) { … }` may or may not be eliminated. Terser/SWC-minify handle it via DCE, not tree shaking.
- **Reachable but unused values** — `const x = compute(); use(y);` may keep `compute()` if it's not marked pure.
- **Side-effect imports** — `import './setup'` is kept unconditionally (unless `sideEffects` config says otherwise).
- **Dynamic imports** — the graph is walked, but dynamic paths can't be shaken.
- **`import * as ns from 'lib'`** — the entire namespace is preserved because any field could be accessed dynamically.

```js
// ❌ Namespace import — keeps everything
import * as _ from 'lodash-es';
_.debounce(fn);
// All ~200 lodash functions included

// ✅ Named import — only what's used
import { debounce } from 'lodash-es';
debounce(fn);
```

---

## Verifying that tree shaking worked

You can't trust the config — verify with a bundle analyzer.

- **Webpack**: `webpack-bundle-analyzer`
- **Vite / Rollup**: `rollup-plugin-visualizer`
- **esbuild**: `esbuild --metafile=meta.json` + `esbuild-visualizer`
- **Next.js**: `@next/bundle-analyzer` (wraps webpack-bundle-analyzer)

Look for suspicious modules — big libs like `moment`, `lodash`, or your own barrels showing more code than you expected. If you see `date-fns` at 200KB, you're pulling in the CJS build. If you see `lodash` (not `lodash-es`), same story.

Sanity check: change a single named import and see if the bundle size moves in the direction you expect.

---

## Practical checklist

```
✅ Publish libraries with "type": "module" (or dual ESM/CJS with correct exports)
✅ Set "sideEffects": false unless you have registration/polyfill files
✅ Import from named exports, not default-plus-destructure
✅ Avoid barrels in performance-critical code paths, or opt into framework barrel optimization
✅ Use lodash-es, date-fns, ramda-adjunct — all ESM + tree-shakable
❌ Don't rely on tree shaking to drop non-ESM code
❌ Don't use `import * as everything from 'lib'` — it keeps everything
```

---

## Related

- [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] — the ESM precondition
- [[Build Tools Foundations - The Dependency Graph]] — how `sideEffects` gets consumed
- [[Build Tools Bundlers - Rollup Internals]] — the reference implementation
- [[Build Tools Bundlers - Rollup vs esbuild vs Webpack]] — aggressiveness comparison
- [[Build Tools Foundations Guide]]
