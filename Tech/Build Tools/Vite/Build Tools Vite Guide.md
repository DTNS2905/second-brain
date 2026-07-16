---
tags:
  - build-tools
  - vite
  - guide
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/
---

# Build Tools Vite Guide

> Vite is not a bundler. It's a **dual-architecture** dev toolchain: native-ESM dev server + Rollup production build, composed via a unified Rollup-flavored plugin API. Understanding Vite means understanding the split between its two engines.

---

## Prereqs

- [[Build Tools Foundations - Bundlers vs Compilers]]
- [[Build Tools Bundlers - Rollup Internals]] (Vite's prod backend)
- [[Build Tools Bundlers - esbuild Internals]] (Vite's transformer)

---

## The one-diagram mental model

```
┌─────────────────────────────────────────────────────────────┐
│ DEV                                                          │
│   Browser → HTTP → Vite dev server (Connect middleware)     │
│                       ↓                                       │
│                   Module graph                                │
│                       ↓                                       │
│                   Per-request transform (esbuild + plugins)   │
│                       ↓ ESM                                   │
│                   Serve to browser                            │
│                                                               │
│   Deps pre-bundled once by esbuild (.vite/deps/*)             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ BUILD                                                        │
│   Source → Rollup (with the same plugin config as dev)      │
│                       ↓                                       │
│                   Chunks + assets + source maps               │
│                       ↓                                       │
│                   dist/                                       │
└─────────────────────────────────────────────────────────────┘
```

Same plugin config runs in both engines — this is Vite's core design constraint.

---

## Contents

- [[Build Tools Vite - Architecture Overview]] — the dual engines in detail
- [[Build Tools Vite - Dev Server Architecture]] — Connect middleware, module graph, per-request transform
- [[Build Tools Vite - Dependency Pre-Bundling]] — esbuild's role in dev
- [[Build Tools Vite - HMR API]] — `import.meta.hot`, module boundaries, Fast Refresh
- [[Build Tools Vite - Plugin API]] — Rollup hooks + Vite-only hooks
- [[Build Tools Vite - Production Build]] — Rollup config projection
- [[Build Tools Vite - CSS and Asset Handling]] — CSS modules, PostCSS, ?raw ?url ?inline
- [[Build Tools Vite - SSR and Environments]] — `ssrLoadModule`, Environment API
- [[Build Tools Vite - Config Reference]] — the config file in detail

---

## Config skeleton

```ts
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';

export default defineConfig({
  plugins: [react()],
  server: { port: 3000 },
  build: { sourcemap: true, target: 'es2020' },
  resolve: { alias: { '@': '/src' } },
});
```

---

## Reading order

1. [[Build Tools Vite - Architecture Overview]] — the mental model
2. [[Build Tools Vite - Dev Server Architecture]] — how dev works
3. [[Build Tools Vite - Dependency Pre-Bundling]] — the esbuild step
4. [[Build Tools Vite - HMR API]] — how updates propagate
5. [[Build Tools Vite - Plugin API]] — extend or debug
6. [[Build Tools Vite - Production Build]] — the Rollup engine
7. [[Build Tools Vite - CSS and Asset Handling]] — non-JS pipelines
8. [[Build Tools Vite - SSR and Environments]] — server-side + edge
9. [[Build Tools Vite - Config Reference]] — reference

---

## Related

- [[Build Tools Bundlers - Rollup Internals]]
- [[Build Tools Bundlers - esbuild Internals]]
- [[Build Tools Dev Server and HMR Guide]]
- [[Build Tools Meta-frameworks Guide]] — Nuxt, SvelteKit, Astro, Remix all sit on Vite
- [[Build Tools Foundations Guide]]
