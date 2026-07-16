---
tags:
  - build-tools
  - dev-server
  - hmr
  - guide
  - tooling
  - frontend
created: 2026-07-16
source: https://vitejs.dev/guide/api-hmr
---

# Build Tools Dev Server and HMR Guide

> Hot Module Replacement (HMR) is the state-preserving cousin of live-reload. This folder covers the protocol common to all bundlers, the per-tool implementations (Vite, Webpack), and React Fast Refresh — the runtime that makes hot-editing components possible.

---

## HMR vs live-reload

| Reload strategy | State preserved | Speed | Setup |
|----------------|-----------------|-------|-------|
| Full reload (F5) | No | Slow | Trivial |
| Live-reload | No | Faster (no manual) | Auto |
| HMR (module swap) | Yes (usually) | Fastest | Requires `accept` boundary or framework runtime |

---

## Contents

- [[Build Tools Dev Server and HMR - HMR Protocol Fundamentals]] — the three-part protocol every bundler implements
- [[Build Tools Dev Server and HMR - Vite HMR Protocol]] — Vite's WebSocket messages + module graph propagation
- [[Build Tools Dev Server and HMR - Webpack HMR Protocol]] — Webpack's hot-update manifest + module.hot API
- [[Build Tools Dev Server and HMR - React Fast Refresh]] — what it preserves, rules for reliability, failure modes

---

## Tool comparison

| Tool | Transport | Client API | React Fast Refresh |
|------|-----------|------------|--------------------|
| Vite | WebSocket | `import.meta.hot` | `@vitejs/plugin-react[-swc]` |
| Webpack | WebSocket (`webpack-dev-server`) or SSE | `module.hot` | `react-refresh-webpack-plugin` |
| Turbopack | WebSocket | Similar to Vite | Built-in |
| Metro (RN) | WebSocket | Metro-specific | `react-refresh` transform |
| Parcel | WebSocket | `module.hot` (Webpack-compatible) | Built-in |

---

## Framework HMR runtimes

- **React**: React Refresh (`react-refresh` npm package + Babel/SWC plugin)
- **Vue**: Vue HMR API (baked into `vue-loader`, `@vitejs/plugin-vue`)
- **Svelte**: Svelte HMR (via `svelte-hmr`, `@sveltejs/vite-plugin-svelte`)
- **Solid**: Solid Refresh

---

## Related

- [[Build Tools Vite - HMR API]]
- [[Build Tools Vite - Dev Server Architecture]]
- [[Build Tools Webpack - HMR Internals]]
- [[Build Tools Foundations Guide]]
