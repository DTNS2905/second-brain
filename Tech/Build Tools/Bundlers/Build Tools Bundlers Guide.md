---
tags:
  - build-tools
  - bundlers
  - guide
  - tooling
  - frontend
created: 2026-07-16
source: https://bundlers.tooling.report/
---

# Build Tools Bundlers Guide

> Bundling is more than concatenation — it's dependency resolution + graph traversal + chunking + tree-shaking + asset handling. This folder covers the theory and the tools that live in the "pure bundler" niche (Rollup, esbuild). Webpack and Vite have their own folders.

---

## Prereqs

- [[Build Tools Foundations - Bundlers vs Compilers]] — the mental model
- [[Build Tools Foundations - The Dependency Graph]] — how a bundler walks
- [[Build Tools Foundations - Module Systems (ESM CJS UMD)]]

---

## Tool landscape (2026)

| Tool | Written in | Speed | Output quality | Primary use |
|------|-----------|-------|----------------|-------------|
| **Rollup** | JS | Moderate | Best (hoisted, readable) | Libraries; Vite's prod backend |
| **esbuild** | Go | Fastest | Good but limited | Dev transforms; small bundlers |
| **Webpack** | JS | Slow (mature) | Full-featured | Apps with heavy plugin needs |
| **Parcel** | JS/Rust | Fast (Rust core) | Zero-config apps | Rapid prototyping |
| **Bun bundler** | Zig | Very fast | Growing | Bun-based apps |
| **Turbopack** | Rust | Very fast, incremental | Improving | Next.js apps |
| **Rspack** | Rust | Very fast | Webpack-compatible | Webpack migration path |

Cross-link: `[[Build Tools Bundlers - Rollup vs esbuild vs Webpack]]` for the comparison.

---

## Contents

- [[Build Tools Bundlers - Bundling Fundamentals]] — why bundle, what still needs bundling
- [[Build Tools Bundlers - Chunking and Code Splitting]] — how output chunks are decided
- [[Build Tools Bundlers - Rollup Internals]] — hooks, phases, why libraries choose Rollup
- [[Build Tools Bundlers - esbuild Internals]] — Go concurrency, constrained plugin API
- [[Build Tools Bundlers - Rollup vs esbuild vs Webpack]] — decision matrix
- [[Build Tools Bundlers - Turbopack and Rspack]] — the Rust generation

---

## When to reach for which

| Job | Tool |
|-----|------|
| Publishing a library | Rollup (best output quality) |
| Bundling a CLI tool | esbuild (fastest, good enough) |
| Large app with many plugins | Webpack, or Vite (Rollup in prod) |
| Next.js app | Webpack (default) or Turbopack (opt-in) |
| Prototyping | Vite (dev) or Parcel |
| Migrating from Webpack for speed | Rspack |

---

## Related

- [[Build Tools Vite Guide]] — Rollup + esbuild composed into an app dev/prod pipeline
- [[Build Tools Webpack Guide]] — the incumbent
- [[Build Tools Meta-frameworks Guide]]
- [[Build Tools Foundations Guide]]
