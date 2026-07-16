---
tags:
  - build-tools
  - foundations
  - dependency-graph
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/concepts/dependency-graph/
---

# Build Tools Foundations — The Dependency Graph

> Every bundler is a graph traversal from entries to leaves, with resolution rules deciding where imports point, and heuristics deciding what ships in which chunk. Part of [[Build Tools Foundations Guide]].

---

## The mental model

A bundler is essentially a fixed-point traversal: it starts at the entry, parses each file to discover imports, resolves each specifier to a concrete path, and recurses. When no new modules are discovered, it emits chunks.

```
entry → parse → find imports → resolve each → recurse
                                      ↓
                                 (loop until fixed point)
                                      ↓
                                 emit chunks
```

Everything else — tree shaking, code splitting, HMR — is built on top of this graph.

---

## Nodes and edges

Nodes are modules (files). Edges are imports.

- **Static ESM imports** (`import x from 'y'`) — known before execution. The bundler discovers them by parsing the AST.
- **Dynamic imports** (`import('./x')`) — create a special edge marking a **split point**. The referenced subgraph becomes a separate chunk fetched at runtime.
- **CommonJS `require`** — statically analyzable when the argument is a string literal; otherwise the bundler falls back to including everything reachable.

Example graph for a small React app:

```
src/index.tsx
  ├── react
  ├── react-dom/client
  └── ./App.tsx
        ├── react
        ├── ./Header.tsx
        │     └── ./logo.svg  (asset edge)
        └── ./routes.tsx
              └── import('./Settings.tsx')  (async split edge)
```

`react` appears twice but is deduplicated — the graph is keyed by resolved module identity, not by import site.

---

## Node resolution algorithm (the resolver)

Every `import x from 'lib'` goes through resolution. This is the single most consequential subsystem in a bundler, and the source of nearly every "cannot find module" error.

1. If the specifier starts with `./` or `../` — **relative** resolution against the importer file.
2. If it starts with `/` — **absolute** path (against project root or config-defined root).
3. Otherwise (bare specifier like `react`) — walk up `node_modules` looking for a matching package.
4. Inside the matching package: consult `package.json#exports` (modern) or `main`/`module`/`browser` (legacy).
5. Apply **conditions**: `types` (TypeScript), `browser` (browser builds), `node`, `import` (ESM importer), `require` (CJS importer), `default`.

| Step | Specifier example | Where it lands |
|------|-------------------|----------------|
| Relative | `./Header` | `./Header.tsx`, `./Header/index.tsx`, `./Header.ts`, ... (extension list applies) |
| Absolute | `/src/lib/x` | `<root>/src/lib/x.*` |
| Bare | `react` | `./node_modules/react` → `package.json#exports["."]` |
| Subpath | `react/jsx-runtime` | `./node_modules/react` → `exports["./jsx-runtime"]` |
| Aliased | `@/components/X` | Config-defined alias → resolved as relative or absolute |

See [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] for how ESM and CJS differ at this layer.

---

## Conditional exports and how bundlers pick

`package.json#exports` is a small conditional language for saying "which file to serve depending on who's asking."

```json
{
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "browser": "./dist/browser.js",
      "worker": "./dist/worker.js",
      "import": "./dist/esm.js",
      "require": "./dist/cjs.cjs",
      "default": "./dist/esm.js"
    }
  }
}
```

Resolution walks the object top-to-bottom and picks the first key that matches the active conditions. Order in the JSON matters — `default` must always be last.

| Consumer | Active conditions (typical) | Lands on |
|----------|-----------------------------|----------|
| Vite / Webpack (browser) | `browser`, `import`, `default` | `./dist/browser.js` |
| Node ESM | `node`, `import`, `default` | `./dist/esm.js` |
| Node CJS | `node`, `require`, `default` | `./dist/cjs.cjs` |
| `tsc` | `types`, `import`, `default` | `./dist/index.d.ts` |
| Cloudflare Workers | `worker`, `import`, `default` | `./dist/worker.js` |
| Deno | `deno`, `import`, `default` | `./dist/esm.js` |

Framework runtimes can define custom conditions (`edge`, `react-server`) that library authors opt into.

---

## `sideEffects` field — the tree-shaking hint

`package.json#sideEffects: false` tells bundlers: "no module in this package has side effects at import time. Feel free to drop unused imports."

```json
{
  "name": "lodash-es",
  "sideEffects": false
}
```

Fine-grained variant — list the files that _do_ have side effects:

```json
{ "sideEffects": ["./src/polyfill.js", "*.css"] }
```

Without this hint, bundlers must assume every import may have observable effects — registering globals, patching prototypes, mutating a module-level store, running `console.log`. That defeats tree shaking entirely.

- ✅ Library authored as pure ESM with no top-level side effects → `sideEffects: false`
- ✅ CSS side effects declared explicitly → `sideEffects: ["*.css"]`
- ❌ Missing field on a modular lib → consumer bundles the whole thing

See [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]] for how `sideEffects` is consumed during elimination.

---

## Circular dependencies

A module graph is not a tree — it can contain cycles. `a.js → b.js → a.js`.

Bundlers handle cycles fine at **emit time** — each module carries an initialized/uninitialized state, and the runtime lazily fills exports. At **runtime**, cycles bite:

```js
// ❌ Circular — `foo` is undefined at read time
// a.js
import { foo } from './b.js';
export const bar = foo + 1;   // foo not defined yet

// b.js
import { bar } from './a.js';
export const foo = 1;
```

The first module to execute reads the other's exports before they're initialized. In ESM you get `undefined` (live bindings resolve later); in CJS you get whatever was on the exports object at the moment of `require`.

Fixes:

- ✅ Extract the shared symbols into a third module both sides import from
- ✅ Delay the read — put it inside a function so it runs after both modules have initialized
- ❌ Rearrange import order hoping it "just works" — fragile and reintroduces at any refactor

---

## Virtual modules

Some plugins expose modules that don't exist on disk. The plugin intercepts resolution and provides the source in-memory. This is how environment injection, route manifests, and content collections work.

Common examples:

- `import.meta.env` (Vite) — a virtual object baked at build time
- `virtual:routes` — synthesized route manifest
- `astro:content` — content collections
- `vite-plugin-pages` — file-system routing entry

```js
// Vite plugin implementing a virtual module
{
  name: 'virt-routes',
  resolveId(id) {
    if (id === 'virtual:routes') return '\0virtual:routes';
  },
  load(id) {
    if (id === '\0virtual:routes') return generateRouteManifest();
  },
}
```

The `\0` prefix is a Rollup convention marking the ID as synthetic — it signals to other plugins "don't try to read this from disk."

---

## Assets as graph nodes

Modern bundlers treat non-JS files as first-class modules. `import logo from './logo.svg'` creates an edge to the SVG; the loader emits it as a hashed asset and replaces the import with the resulting URL.

```js
import logo from './logo.svg';
// After build: logo === '/assets/logo.a3f2b1c.svg'
```

Different query suffixes change treatment:

```js
import url from './logo.svg?url';       // returns the URL string
import inline from './logo.svg?inline'; // returns a base64 data URL
import raw from './logo.svg?raw';       // returns the file contents as text
```

| Suffix | Result | Use case |
|--------|--------|----------|
| (none) | Default handler — usually URL, sometimes component | Standard `<img src={logo}>` |
| `?url` | Explicit URL string | Force URL even when default is component |
| `?inline` | base64 data URL | Tiny assets, avoid extra request |
| `?raw` | File contents as string | Read shader/SQL/text at build time |
| `?worker` | Worker constructor | Web Workers |

Because assets are graph nodes, they participate in code splitting and hashing — an SVG only imported by a lazy route ships in that route's chunk.

---

## Where meta-frameworks inject entries

Meta-frameworks (Next.js, Nuxt, SvelteKit, Remix) synthesize entry files from file-system routing. You don't write the entry — the framework generates it at build time from your `pages/` or `app/` directory.

Concretely, the framework:

1. Scans the routing directory to build a route table
2. Generates a virtual entry that imports each route lazily (`import('./app/blog/page.tsx')`)
3. Feeds that virtual entry to the underlying bundler (Turbopack, Webpack, Vite, Rollup)
4. The bundler's dependency graph starts from that synthesized entry

This is why `pages/foo.tsx` "just works" without any manual `import` — the framework's virtual entry pulls it in.

Cross-link [[Build Tools Meta-frameworks Guide]].

---

## Summary of resolution steps

```
import 'x' from 'y'
  │
  ├─ Relative (./ ../) → resolve against importer path
  ├─ Absolute (/)      → resolve against project root or config
  └─ Bare (y)          → node_modules walk
                          → find package.json
                          → apply exports + conditions
                          → land on target file
  → parse target
  → repeat
```

Every bundler — Webpack, Vite, esbuild, Rollup, Turbopack, Bun, Rspack — implements this same loop. The differences are in speed (native vs JS parsers), which conditions they set by default, and how aggressively they cache the resolved graph across builds.

---

## Related

- [[Build Tools Foundations - Bundlers vs Compilers]]
- [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] — conditions and exports in detail
- [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]] — how `sideEffects` gets used
- [[Build Tools Foundations - AST and Transform Pipelines]] — what the parser produces
- [[Build Tools Foundations Guide]]
