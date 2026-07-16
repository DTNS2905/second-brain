---
tags:
  - build-tools
  - foundations
  - tooling
  - frontend
created: 2026-07-16
source: https://esbuild.github.io/faq/
---

# Build Tools Foundations — Bundlers vs Compilers

> A bundler walks a module graph and emits combined output. A compiler transforms one file at a time. Tools that do both (Vite, Next.js, esbuild) are pipelines composed of these two roles. Part of [[Build Tools Foundations Guide]].

---

## The one-sentence distinction

**Bundler = graph operation. Compiler = per-file operation.**

Everything else — dev servers, HMR, tree-shaking, code-splitting — is layered on top of these two primitives.

---

## Input/output signatures

| Role | Input | Output |
|------|-------|--------|
| Bundler | An entry file + a graph of imports | One or more chunks (JS files ± CSS, assets) |
| Compiler / transpiler | One source file | One transformed file |

If a tool's output count depends on how many `import` statements it followed, it's a bundler. If output count equals input count, it's a compiler.

---

## What a bundler actually does

The algorithm, in five steps:

1. Start at entry file(s).
2. Parse imports — statically for ESM `import` / CommonJS `require`, dynamically for `import()`.
3. Resolve each import to a file on disk — Node resolution + `package.json` `exports` conditions (`import`, `require`, `browser`, `default`).
4. Recurse into each resolved file. Build the graph.
5. Emit chunks based on split points (dynamic `import()`, multiple entries) and shared-module heuristics.

The graph is the whole point. Without it, there's no tree-shaking, no code-splitting, no single-file output.

See [[Build Tools Foundations - The Dependency Graph]] for how the walk is implemented and what invalidates it in watch mode.

---

## What a compiler actually does

Three phases: **parse → transform → generate.**

1. **Parse** source into an AST.
2. **Transform** the AST — strip types, lower syntax, apply plugins.
3. **Generate** output code (and usually a source map).

One file in, one file out. A compiler has no knowledge of imports beyond what's needed for the specific transform:

- JSX transform doesn't need import resolution — it rewrites `<Foo />` to `_jsx(Foo, ...)`, done.
- TypeScript **type-erasure** alone doesn't either — it deletes types syntactically.
- TypeScript **type-checking** does — it needs to load `.d.ts` files for imported modules to resolve types. But that's the checker, not the emitter.

See [[Build Tools Foundations - AST and Transform Pipelines]] for the parse/transform/generate loop in detail.

---

## Concrete examples

```bash
# ✅ Compiler: transforms one file, output has same "shape"
npx swc file.tsx --out-file file.js

# ✅ Bundler: walks graph from entry, outputs chunks
npx rollup src/index.ts -f esm -d dist
```

The SWC invocation never opens any file other than `file.tsx`. The Rollup invocation opens `src/index.ts`, then every file it imports, transitively.

---

## Tools that blur the line

The interesting cases — tools that expose both roles or embed one inside the other:

### esbuild

Has a `transform` API (compiler — string in, string out) **and** a `build` API (bundler — walks graph, emits files). Same binary, two roles, chosen by which entrypoint you call.

```js
// Compiler role
esbuild.transform(sourceString, { loader: 'tsx' });

// Bundler role
esbuild.build({ entryPoints: ['src/app.tsx'], bundle: true, outdir: 'dist' });
```

### TypeScript's `tsc`

Primarily a **type-checker + per-file transpiler**. Reads `foo.ts`, emits `foo.js`. With the deprecated `--outFile` it could concatenate for old script-tag setups, but that's not real bundling — no tree-shaking, no ESM chunking.

In modern pipelines: `tsc --noEmit` for type-check, and a bundler (esbuild/SWC/Rollup) for the actual transpile + graph work.

### Webpack

Nominally a bundler, but its **loaders** are per-file compilers plugged into the bundle pipeline. `babel-loader`, `swc-loader`, `ts-loader`, `css-loader` — each is a compiler; Webpack orchestrates them across the graph.

### Vite

A bundler (Rollup in prod) + a per-file compiler (esbuild/SWC via plugin) + a dev server. Different modes use different subsets — see the split table below.

---

## Common confusions

The single most useful section of this note. Get these right and 90% of build-tool confusion evaporates.

```
❌ "Babel bundles my app."
✅ Babel compiles files; a bundler (Webpack/Rollup/esbuild) combines them.
```

```
❌ "Webpack transpiles JSX."
✅ Webpack delegates JSX to a loader (typically babel-loader or swc-loader).
   Webpack itself is the bundler orchestrator.
```

```
❌ "TypeScript is a bundler."
✅ TypeScript is a type-checker + per-file transpiler. It emits .js from .ts
   one-for-one.
```

```
❌ "Vite is faster than Webpack because it's a better bundler."
✅ Vite is faster in *dev* because it doesn't bundle at all — it serves native
   ESM. In *build*, it uses Rollup (a bundler comparable to Webpack for
   output quality).
```

```
❌ "esbuild replaces Webpack."
✅ esbuild can play either role. In Vite, it plays the compiler role in dev
   and prod; Rollup still does prod bundling. Whether esbuild "replaces"
   Webpack depends on which role you're comparing.
```

```
❌ "SWC is faster than Babel because it bundles in Rust."
✅ SWC is a compiler, not a bundler. It's faster than Babel at the
   per-file transform. Bundling is a separate concern.
```

---

## Where each role sits in a modern React app

A typical Vite + React + TypeScript app splits the work like this:

| Job | Role | Tool |
|-----|------|------|
| Transform TSX to JS | Compiler | esbuild (dev), esbuild or SWC via `@vitejs/plugin-react` (dev + build) |
| Type-check | Compiler (type-only) | `tsc --noEmit` (usually in CI) |
| Walk import graph | Bundler | Rollup (Vite build) |
| Serve modules in dev | Dev server | Vite dev server (no bundling) |
| HMR | Dev server + client runtime | Vite HMR + `@vitejs/plugin-react` for Fast Refresh |
| Minify | Compiler (post-bundle) | esbuild or Terser |
| CSS handling | Compiler + bundler | PostCSS (per-file) + Rollup (graph) |

Notice: **no single tool does everything.** Even inside one framework, the roles are distinct — and they're chosen for what they're best at (esbuild is fast at transforms, Rollup produces cleaner chunks than esbuild-bundle).

---

## Why the distinction matters

When a build breaks, the fix depends on **which layer is misbehaving.**

- **"My JSX isn't transforming"** → compiler config. Check Babel presets, `tsconfig.jsx`, SWC config, plugin ordering.
- **"My tree-shaking isn't working"** → bundler + module-system issue. Check `sideEffects` in `package.json`, ESM vs CJS output, whether the bundler sees the exports as pure.
- **"A dev import is broken but the build works"** → dev server, not the bundler. In Vite this is often a `optimizeDeps` / pre-bundling problem.
- **"The bundle is huge"** → bundler config (chunking, split points) — the compiler doesn't know about size.
- **"Types aren't checked in the build"** → correct; bundlers strip types with a compiler, they don't run the type-checker. Add `tsc --noEmit` to CI.

Misdiagnosing wastes hours. Ask *"is this a per-file transform problem, or a graph problem?"* first.

---

## Summary

**Bundler walks the graph; compiler transforms a file.** Modern build tools are pipelines that stack both roles — knowing which role owns a given behavior is the fastest way to debug.

| | Bundler | Compiler |
|---|---------|----------|
| Operates on | Graph | Single file |
| Reads imports? | Yes (to resolve deps) | Only for syntax |
| Emits | Chunks | Transformed file |
| Example | Rollup, Webpack, esbuild-build | Babel, SWC, tsc, esbuild-transform |

---

## Related

- [[Build Tools Foundations - The Dependency Graph]] — how a bundler walks
- [[Build Tools Foundations - AST and Transform Pipelines]] — how a compiler transforms
- [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] — what both operate on
- [[Build Tools Foundations Guide]]
