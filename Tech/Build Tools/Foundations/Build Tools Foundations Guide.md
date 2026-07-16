---
tags:
  - build-tools
  - foundations
  - guide
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/why
---

# Build Tools Foundations Guide

> The shared theory every downstream tool assumes: what a bundler is, what a compiler is, how modules resolve, how ASTs get transformed, and why tree-shaking has preconditions. Read this before diving into any specific tool.

---

## Why this folder exists

Every JS build tool — Webpack, Vite, Rollup, esbuild, Babel, SWC, Turbopack, Next.js — is a composition of the same primitives: parse modules, resolve imports, transform code, walk a graph, emit output. Learning them tool-by-tool means re-learning the same primitives inside each one. This folder factors those primitives out. Every downstream tool note links back here.

---

## The four categories

Build tools fall into four roles. A given tool may play one role or several.

| Category | Job | Example tools |
|----------|-----|---------------|
| **Bundler** | Walk a module graph → emit combined output | Rollup, Webpack, esbuild, Parcel, Bun, Turbopack, Rspack |
| **Compiler / transpiler** | Transform one file at a time (syntax, type-erasure, JSX) | Babel, SWC, TypeScript, esbuild (transform mode) |
| **Dev server** | Serve modules on demand + HMR client/server | Vite dev server, Webpack Dev Server, Metro, Turbopack |
| **Meta-framework** | Wrap the above + router + rendering conventions | Next.js, Nuxt, SvelteKit, Astro, Remix (RR7), TanStack Start |

Tools that do more than one job (Vite = dev server + bundler + compiler orchestrator; Next.js = all four) are **pipelines** built from the primitives above.

See [[Build Tools Foundations - Bundlers vs Compilers]] for the sharpest distinction between the first two.

---

## Contents

### Concepts

- [[Build Tools Foundations - Bundlers vs Compilers]] — the mental-model lynchpin
- [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] — the module formats bundlers must reconcile
- [[Build Tools Foundations - The Dependency Graph]] — entry → modules → chunks
- [[Build Tools Foundations - AST and Transform Pipelines]] — parse → transform → generate
- [[Build Tools Foundations - Source Maps]] — how stack traces survive minification
- [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]] — preconditions and pitfalls

---

## Glossary

- **Module** — a file with its own scope, participates in the dependency graph.
- **Entry** — a module the bundler starts from when walking the graph.
- **Chunk** — a bundler output artifact; a group of modules that ship together.
- **Loader** (Webpack) — a per-file transform in a plugin chain.
- **Plugin** — a lifecycle-tapping extension (Webpack, Rollup, Vite).
- **AST** — Abstract Syntax Tree; a bundler/compiler's in-memory representation of source code.
- **HMR** — Hot Module Replacement; swap a module at runtime without reloading the page.
- **Tree shaking** — dead-code elimination on the ESM graph.
- **Code splitting** — emitting multiple chunks so the browser downloads only what's needed.

---

## Reading order

1. [[Build Tools Foundations - Bundlers vs Compilers]] — mental model first
2. [[Build Tools Foundations - Module Systems (ESM CJS UMD)]] — what tools operate on
3. [[Build Tools Foundations - The Dependency Graph]] — how the bundler walks
4. [[Build Tools Foundations - AST and Transform Pipelines]] — how compilers transform
5. [[Build Tools Foundations - Tree Shaking and Dead Code Elimination]] — the interaction of ESM + purity
6. [[Build Tools Foundations - Source Maps]] — the output that debuggers consume

After this folder, proceed to `[[Build Tools Bundlers Guide]]` and `[[Build Tools Compilers Guide]]`.

---

## Where each downstream folder builds on this

| Folder | Foundations concepts leaned on |
|--------|--------------------------------|
| Bundlers | Dependency graph, module systems, tree shaking |
| Compilers | AST + transforms, source maps |
| Vite | All six — Vite is the clearest composition of them |
| Webpack | Dependency graph, loaders (per-file transforms) + plugins (lifecycle taps) |
| Dev Server and HMR | Module graph, module boundaries |
| Meta-frameworks | All of the above, wrapped |
