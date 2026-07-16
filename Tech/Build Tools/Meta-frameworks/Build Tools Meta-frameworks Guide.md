---
tags:
  - build-tools
  - meta-frameworks
  - guide
  - tooling
  - frontend
created: 2026-07-16
source: https://nextjs.org/docs
---

# Build Tools Meta-frameworks Guide

> A meta-framework is an opinionated wrapper around a bundler + router + rendering strategy + deployment adapter. This folder covers how the industry-standard React and non-React meta-frameworks compose the primitives from the rest of the Build Tools folder.

---

## What a meta-framework provides beyond a bundler

- **File-system routing** — auto-generated route manifest from `pages/` or `app/`
- **Rendering modes** — SSR, SSG, ISR, streaming, RSC — orchestrated at request time
- **Data-fetching contracts** — loaders, actions, server components
- **Build outputs for a specific deploy target** — Node server, static bundle, edge worker
- **Dev server tuned for framework primitives** — auto-import types, route hot-reload

---

## Landscape (2026)

| Framework | Bundler | Compiler | Rendering | Notes |
|-----------|---------|----------|-----------|-------|
| **Next.js** | Webpack (default) + Turbopack (opt-in) | SWC | RSC + SSR + SSG + ISR + streaming | The React default in enterprise |
| **Remix (RR7)** | Vite (via plugin) | esbuild | SSR + streaming | Merged into React Router 7 |
| **TanStack Start** | Vite | esbuild | SSR + streaming | New; router-first design |
| **Astro** | Vite | esbuild + `.astro` compiler | Islands + partial hydration | Zero-JS-by-default; React usable as an island |
| **Nuxt 3** | Vite + Nitro | esbuild | SSR + SSG + hybrid; Vue | Vue's Next equivalent |
| **SvelteKit** | Vite | esbuild + Svelte compiler | SSR + SSG + hybrid; Svelte | Svelte's canonical framework |
| **Qwik City** | Vite | esbuild + Qwik compiler | Resumability | Different rendering paradigm |

---

## Bundler-choice matrix

| Framework | Dev bundler | Prod bundler |
|-----------|-------------|--------------|
| Next.js | Webpack (or Turbopack) | same |
| Remix / RR7 | Vite | Rollup (via Vite) |
| Astro | Vite | Rollup (via Vite) |
| Nuxt 3 | Vite | Rollup (via Vite) |
| SvelteKit | Vite | Rollup (via Vite) |

Every non-Next React meta-framework is a Vite plugin. Next is the outlier.

---

## Contents

- [[Build Tools Meta-frameworks - Next.js Build Pipeline]] — SWC + Webpack, `next build` phases, App vs Pages Router
- [[Build Tools Meta-frameworks - Next.js and Turbopack]] — why Vercel rewrote the bundler; migration story
- [[Build Tools Meta-frameworks - RSC and the Bundler]] — two module graphs, `'use client'`/`'use server'` as build markers
- [[Build Tools Meta-frameworks - Astro Build Pipeline]] — Vite + `.astro` compiler + Islands
- [[Build Tools Meta-frameworks - Remix and React Router 7]] — Vite plugin + route modules + loaders
- [[Build Tools Meta-frameworks - Nuxt and SvelteKit]] — the non-React canonical frameworks
- [[Build Tools Meta-frameworks - Comparison and Decision Guide]] — pick the right one

---

## Reading order

1. [[Build Tools Meta-frameworks - Next.js Build Pipeline]]
2. [[Build Tools Meta-frameworks - RSC and the Bundler]] — foundational for modern Next
3. [[Build Tools Meta-frameworks - Next.js and Turbopack]]
4. [[Build Tools Meta-frameworks - Astro Build Pipeline]]
5. [[Build Tools Meta-frameworks - Remix and React Router 7]]
6. [[Build Tools Meta-frameworks - Nuxt and SvelteKit]]
7. [[Build Tools Meta-frameworks - Comparison and Decision Guide]]

---

## Related

- [[Build Tools Vite Guide]] — the shared substrate for most meta-frameworks
- [[Build Tools Webpack Guide]] — Next.js's default
- [[Build Tools Bundlers - Turbopack and Rspack]]
- [[Build Tools Dev Server and HMR Guide]]
- [[Build Tools Foundations Guide]]
