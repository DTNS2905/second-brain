---
tags:
  - build-tools
  - foundations
  - esm
  - tooling
  - frontend
created: 2026-07-16
source: https://nodejs.org/api/esm.html
---

# Build Tools Foundations — Module Systems (ESM, CJS, UMD)

> ESM vs CommonJS vs UMD vs AMD — what bundlers must reconcile, why tree-shaking depends on ESM, and how package.json exports resolve the dual-package hazard. Part of [[Build Tools Foundations Guide]].

---

## The four formats

| Format | Origin | Syntax | Static/dynamic |
|--------|--------|--------|----------------|
| CommonJS (CJS) | Node.js | `require()`, `module.exports` | Dynamic (runtime) |
| ESM | ES2015 | `import`, `export` | Static (parse time) |
| UMD | Universal (browser + Node) | Function wrapper detecting env | Dynamic |
| AMD | RequireJS | `define()` callback | Dynamic |

In 2026, AMD is dead outside legacy corporate codebases. UMD is on life support (still emitted by some libs). ESM is the target; CJS is the backward-compatibility burden every bundler still has to carry.

The whole modern toolchain — Vite, Rollup, esbuild, Webpack 5, Turbopack, Bun — pivots on one fact: **ESM is the only format a static analyzer can reason about**. Everything else in this note follows from that.

---

## Static vs dynamic imports (the tree-shaking gate)

ESM imports are **statically analyzable**: `import { x } from 'lib'` tells the bundler which names are used before any code runs. The graph of "which module needs which export" is fully known at build time. This is the precondition for tree-shaking.

CJS `require()` is **dynamic**: `const lib = require('lib'); lib[computeKey()]` can only be resolved at runtime. A bundler can't prove which exports are unused → conservative default: keep everything.

```js
// ✅ ESM — tree-shakable
import { debounce } from 'lodash-es';

// ❌ CJS — not tree-shakable (bundlers ship all of lodash)
const { debounce } = require('lodash');
```

The `lodash` vs `lodash-es` split is the canonical example: same library, ~70KB vs ~2KB after tree-shaking, because one ships CJS and one ships ESM.

Cross-link [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]] for how bundlers actually eliminate the dead branches.

---

## File extensions and package.json#type

Node resolves module format via:

| Signal | Format |
|--------|--------|
| `.mjs` | ESM |
| `.cjs` | CommonJS |
| `.js` in package with `"type": "module"` | ESM |
| `.js` in package with `"type": "commonjs"` (or absent) | CommonJS |

Bundlers respect this in dep resolution. If a package declares `"type": "module"` and ships `.js` files, those files are parsed as ESM even inside `node_modules`.

Practical implication: adding `"type": "module"` to a package.json is a **breaking change** for any consumer that was relying on `require()`ing your `.js` files. Ship a major version bump.

---

## package.json#exports (conditional exports)

The modern replacement for `main`/`module`/`browser` fields. Lets a package expose different files for different consumers — the resolver picks the first matching condition.

```json
{
  "name": "my-lib",
  "type": "module",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "browser": "./dist/browser.js",
      "import": "./dist/esm/index.js",
      "require": "./dist/cjs/index.cjs",
      "default": "./dist/esm/index.js"
    },
    "./utils": "./dist/utils.js"
  }
}
```

Key conditions: `types`, `browser`, `node`, `import`, `require`, `default`. **Order matters — first match wins.** Put `types` first (TypeScript expects it), then narrower conditions before broader ones.

The `exports` field also acts as an **encapsulation boundary**: paths not listed are unimportable. `import 'my-lib/internal'` fails unless `./internal` (or a matching pattern) is in `exports`. This is stricter than the pre-`exports` world where any file inside a package was reachable.

Pattern-based subpaths:

```json
{
  "exports": {
    "./features/*": "./dist/features/*.js"
  }
}
```

Then `import x from 'my-lib/features/foo'` resolves to `./dist/features/foo.js`.

---

## Import maps and #imports

`package.json#imports` — internal alias for `#subpath` imports:

```json
{
  "imports": {
    "#config": "./src/config.node.js",
    "#config/browser": "./src/config.browser.js"
  }
}
```

Then `import cfg from '#config'` works inside the package. Bundlers (Vite, Webpack, esbuild) support this natively. It's the standards-based replacement for arbitrary path aliases in `tsconfig.json` — with the advantage that Node itself understands `#name`.

Browser `<script type="importmap">` is the DOM-side analog: a JSON blob remapping bare specifiers to URLs. Used natively in no-build setups (Deno, Astro islands, some Rails/Django flows).

---

## The dual-package hazard

A package that ships both ESM and CJS builds risks being loaded **twice** — once by an ESM importer, once by a CJS importer. Two copies means two module scopes: `instanceof` checks break, singletons duplicate, module-level state diverges.

```
❌ instanceof fails across dual copies
const a = new lib.Foo();
b.isFoo(a);  // false — b's Foo is from CJS copy, a's from ESM copy
```

This is not a bug in Node — it's the inevitable outcome of two module systems each maintaining their own cache. The ESM loader has one `Foo` class; the CJS loader has a different `Foo` class. They are structurally identical but referentially distinct.

Mitigations:

- **Ship ESM-only** — most impactful. Consumers using CJS pay a runtime cost (async `import()`) but no dual-copy. This is where the ecosystem is heading (`chalk` v5, `node-fetch` v3, `execa` v6+ are ESM-only).
- **Externalize hot classes** — don't ship classes both consumers might `instanceof`. Move them to a peer dependency that resolves to a single copy.
- **Use runtime singletons** — attach shared state to `globalThis`:

```js
const KEY = Symbol.for('my-lib.singleton');
globalThis[KEY] ??= createSingleton();
export default globalThis[KEY];
```

`Symbol.for` uses the cross-realm registry, so both copies of the module see the same symbol → same singleton.

See Andrea Giammarchi's writings + [Node docs on dual-package hazard](https://nodejs.org/api/packages.html#dual-package-hazard) for depth.

---

## __esModule interop

Legacy: to make `import x from 'cjs-lib'` work when the CJS module has `module.exports = { default: x }`, tools set `Object.defineProperty(exports, '__esModule', { value: true })` on the compiled output. This flag tells a downstream compiler "treat this as if it were an ES module — the default export is at `.default`".

Modern ESM implementations (Node native ESM) handle this differently: `import x from 'cjs-lib'` returns `module.exports` **directly**. Different tools implement different interop policies, hence the "why does my default import not match my expectations?" bug.

```js
// CJS module
module.exports = { name: 'lib', helper: () => {} };

// ESM importer — depends on tool policy
import lib from './lib.cjs';
// Node: lib is the whole { name, helper } object
// Webpack esModuleInterop: lib is same or synthesized differently
// TypeScript esModuleInterop: lib is the whole object; requires `import * as lib` otherwise
```

The `esModuleInterop` flag in `tsconfig.json` was added specifically to paper over this. With it on, TypeScript emits helper wrappers that check `__esModule` at runtime. With it off, you must write `import * as lib from 'cjs-lib'` for every CJS import.

Rule of thumb: **turn `esModuleInterop` on**, treat it as non-negotiable in any new project, and stop thinking about `__esModule` unless you're authoring a compiler.

---

## Dynamic import

`import('./module')` returns a Promise. Static analyzers can identify the target (if the path is a literal or template with an unambiguous prefix), so bundlers can create a chunk for it.

```js
// ✅ Split point — bundler emits a separate chunk
const { heavy } = await import('./heavy.js');

// ✅ Dynamic path — bundler can still emit chunks per possible file
const { widget } = await import(`./widgets/${name}.js`);

// ❌ Fully dynamic — bundler can't analyze; bundles the entire dir or errors
const { thing } = await import(name);
```

The middle case is a Webpack/Vite feature called **glob-driven code splitting**: given a template literal with a known prefix, the bundler enumerates matching files at build time and emits one chunk per match. Vite exposes this explicitly via `import.meta.glob`.

Dynamic import is also the **CJS-from-ESM escape hatch**: `import()` works in CJS files too, and returns a Promise regardless. It's the only way to load ESM-only packages from a legacy CJS codebase.

Cross-link [[Build Tools Bundlers - Chunking and Code Splitting]] for the chunking mechanics.

---

## UMD, and why you can ignore it in new code

UMD (Universal Module Definition) is a wrapper pattern from the ~2013 era. It's the code you see with:

```js
(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define(['dep'], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('dep'));
  } else {
    root.myLib = factory(root.dep);
  }
}(typeof self !== 'undefined' ? self : this, function (dep) {
  // library body
}));
```

It exists so a library can be dropped in a `<script>` tag, `require`'d in Node, or `define`'d under AMD.

In 2026: ship ESM. UMD is only worth publishing if you need `<script>` tag consumers, and even then a plain IIFE build (`format: 'iife'` in Rollup) is more common — it's smaller and simpler than UMD's env-sniffing wrapper.

If you're consuming a UMD-only library: import it in ESM as if it were CJS. Bundlers detect the `module.exports = ...` at the end of the wrapper and treat it as CJS.

---

## Summary table

| Format | Static? | Tree-shakable? | Modern use |
|--------|---------|----------------|------------|
| ESM | Yes | Yes | ✅ Default target |
| CJS | No | No | Legacy consumers, Node scripts |
| UMD | No | No | Legacy `<script>` consumers |
| AMD | No | No | Effectively dead |

---

## Related

- [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]] — why static ESM matters
- [[Build Tools Foundations - The Dependency Graph]] — how imports feed graph construction
- [[Build Tools Foundations - Bundlers vs Compilers]]
- [[Build Tools Foundations Guide]]
