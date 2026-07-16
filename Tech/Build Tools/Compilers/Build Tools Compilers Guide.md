---
tags:
  - build-tools
  - compilers
  - guide
  - tooling
  - frontend
created: 2026-07-16
source: https://swc.rs/docs/getting-started
---

# Build Tools Compilers Guide

> Compilers transform one file at a time — JSX → JS, TS → JS, ES2025 → ES2015, decorators → class fields. In modern pipelines the compiler is invoked by a bundler (per-file transform hook) or a dev server (per-request transform). This folder covers the four canonical compilers.

---

## Prereqs

- [[Build Tools Foundations - Bundlers vs Compilers]]
- [[Build Tools Foundations - AST and Transform Pipelines]]

---

## The four you meet in practice

| Compiler | Written in | Speed | Plugin ecosystem | Primary use |
|----------|-----------|-------|------------------|-------------|
| **Babel** | JS | Slow (mature) | Vast | Complex transforms; codemods; older stacks |
| **SWC** | Rust | 20× Babel | Growing (WASM plugins) | Next.js default; Vite via `unplugin-swc` |
| **esbuild (transform)** | Go | 100× Babel | Minimal | Dev transforms; simple pipelines |
| **TypeScript (`tsc`)** | JS | Slow | N/A (built-in) | Type-checking; declaration emit |

Modern React app in 2026:
- **Type-check**: `tsc --noEmit` (CI)
- **Transform**: esbuild (dev) → SWC (build, via `@vitejs/plugin-react-swc`) OR Babel (build, via `@vitejs/plugin-react`)
- **React Compiler** (memo optimization): `babel-plugin-react-compiler`, a Babel plugin

---

## Contents

- [[Build Tools Compilers - Babel Internals]] — parser, traverse, generator, preset ordering
- [[Build Tools Compilers - SWC Internals]] — Rust architecture, `.swcrc`, WASM plugins
- [[Build Tools Compilers - TypeScript as a Transpiler]] — tsc's role vs esbuild/SWC handling of TS
- [[Build Tools Compilers - JSX and React Transforms]] — classic vs automatic runtime, React Compiler, Fast Refresh transform

---

## Which does what for React

| Task | Tool |
|------|------|
| Strip `interface`, `type` | esbuild / SWC / Babel — all fine |
| Emit `.d.ts` declarations | `tsc` (only) |
| Type-check (semantic) | `tsc --noEmit` (only) |
| JSX transform | SWC / Babel / esbuild-transform |
| React Compiler auto-memo | `babel-plugin-react-compiler` (or SWC port if available) |
| Fast Refresh transform | `react-refresh/babel` / SWC equivalent via `@vitejs/plugin-react-swc` |

Ordering rule: **type-erase first, then transform semantics.** JSX is a syntactic transform independent of types.

---

## Related

- [[Build Tools Foundations - AST and Transform Pipelines]]
- [[Build Tools Bundlers Guide]]
- [[Build Tools Vite Guide]]
- [[Build Tools Foundations Guide]]
