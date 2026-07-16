---
tags:
  - build-tools
  - webpack
  - guide
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/concepts/
---

# Build Tools Webpack Guide

> Webpack is the incumbent — powering Next.js by default, thousands of enterprise apps, and Create React App (legacy). This folder covers its architecture (Compiler + Compilation + Tapable), the loader/plugin duality, and the migration paths (Rspack, Turbopack, Vite).

---

## Why Webpack still matters (2026)

- **Next.js default** — Turbopack is opt-in
- **Enterprise apps** with heavy custom loaders/plugins
- **Module Federation** — the mature runtime cross-app module sharing story
- **Ecosystem depth** — decades of loaders and plugins

For new apps: Vite. For migrating a Webpack app for speed: Rspack. For staying: it's fine.

---

## Contents

- [[Build Tools Webpack - Core Concepts]] — entry/output/loaders/plugins, modes, targets
- [[Build Tools Webpack - Compiler and Compilation]] — Tapable hooks, NormalModuleFactory, chunk graph, sealing
- [[Build Tools Webpack - Loaders vs Plugins]] — the distinction everyone confuses
- [[Build Tools Webpack - Code Splitting and SplitChunks]] — heuristics, hash variants, magic comments
- [[Build Tools Webpack - Module Federation]] — micro-frontends done at runtime
- [[Build Tools Webpack - HMR Internals]] — hot-update manifest + runtime
- [[Build Tools Webpack - Persistent Caching and Performance]] — filesystem cache, buildDependencies, migration

---

## The 30-second config

```js
// webpack.config.js
const path = require('path');

module.exports = {
  mode: 'production',
  entry: './src/index.tsx',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: '[name].[contenthash].js',
    clean: true,
  },
  module: {
    rules: [
      { test: /\.tsx?$/, use: 'swc-loader', exclude: /node_modules/ },
      { test: /\.css$/, use: ['style-loader', 'css-loader'] },
    ],
  },
  resolve: { extensions: ['.tsx', '.ts', '.js'] },
  plugins: [new HtmlWebpackPlugin({ template: './public/index.html' })],
};
```

---

## Reading order

1. [[Build Tools Webpack - Core Concepts]] — the config anatomy
2. [[Build Tools Webpack - Compiler and Compilation]] — internals
3. [[Build Tools Webpack - Loaders vs Plugins]] — the mental model
4. [[Build Tools Webpack - Code Splitting and SplitChunks]] — the optimization surface
5. [[Build Tools Webpack - HMR Internals]] — dev server + hot updates
6. [[Build Tools Webpack - Module Federation]] — for micro-frontend teams
7. [[Build Tools Webpack - Persistent Caching and Performance]] — speeding up big builds

---

## Migration outbound

- **Rspack** — Webpack-compatible, Rust-fast. See `[[Build Tools Bundlers - Turbopack and Rspack]]`.
- **Turbopack** — Next.js path.
- **Vite** — clean-slate rewrite; not compatible, but a good target for greenfield.

---

## Related

- [[Build Tools Bundlers - Rollup vs esbuild vs Webpack]]
- [[Build Tools Bundlers - Turbopack and Rspack]]
- [[Build Tools Dev Server and HMR Guide]]
- [[Build Tools Meta-frameworks - Next.js Build Pipeline]]
- [[Build Tools Foundations Guide]]
