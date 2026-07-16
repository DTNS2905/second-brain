---
tags:
  - build-tools
  - bundlers
  - rust
  - tooling
  - frontend
created: 2026-07-16
source: https://turbo.build/pack/docs
---

# Build Tools Bundlers — Turbopack and Rspack

> The Rust generation of bundlers. Turbopack (Vercel/Next.js) is built for incremental computation; Rspack (ByteDance) is a Webpack-compatible drop-in. Both promise Webpack's plugin ecosystem at esbuild-class speeds. Part of [[Build Tools Bundlers Guide]].

---

## Why Rust bundlers exist

The JS-based bundlers ([[Build Tools Webpack Guide|Webpack]], [[Build Tools Bundlers - Rollup Internals|Rollup]]) hit a ceiling: even with esbuild-like optimization, running JS-in-JS has garbage-collection and JIT overhead. Rust bundlers give:

- **Compiled speed** — no VM overhead, native machine code
- **Fine-grained memory control** — no GC pauses, arena allocation
- **True parallelism** — no GIL, no event-loop bottleneck; scale linearly with cores
- **Incremental caching primitives** — the Turbo engine models builds as a task graph with typed inputs/outputs

The pattern was established by [[Build Tools Bundlers - esbuild Internals|esbuild]] (Go, ~100× JS bundlers). Rust took it further by adding safety, richer type systems, and the ability to build long-lived incremental engines.

---

## Turbopack — Vercel's bet

Written for the Next.js dev/build loop. Built on the **Turbo engine** — a general incremental computation framework.

Key insight: model every build step as a "task" with typed inputs and cached outputs. When an input changes, only affected tasks re-run.

```
File → Parse task → Transform task → Chunk task → Emit task
           cached ↑        cached ↑     cached ↑
```

Result: rebuilds after a code change re-run only the affected tasks, not the whole graph. Contrast with Webpack, which rebuilds a large fraction of the module graph even for tiny edits.

```rust
#[turbo_tasks::function]
async fn parse(file: FileContent) -> Result<Ast> {
    // Result memoized by (file content hash) → Ast
    // If the file's bytes don't change, this never re-runs.
}
```

That memoization primitive is the whole trick. Everything above it — module resolution, transforms, chunking, HMR — is expressed as chained tasks.

---

## Turbopack status (2026)

- `next dev --turbo` → **stable**
- `next build --turbo` → beta / stable depending on Next version at time of reading; check Next docs
- Config parity with Webpack: **partial** — major loaders like `swc-loader` are built-in; obscure plugins may not be ported
- Migration path: **incremental** — Next abstracts most Webpack details, so switching to Turbopack usually means turning on a flag

```jsonc
// next.config.js — opt in to Turbopack for dev
{
  "experimental": {
    "turbo": {
      "rules": {
        "*.svg": ["@svgr/webpack"]
      }
    }
  }
}
```

Not usable outside Next.js today. Turbopack is not published as a general-purpose CLI the way esbuild or Rspack are.

---

## Rspack — the Webpack-compatible Rust bundler

Different philosophy from Turbopack: **be Webpack**, but faster.

- Same config shape (`rspack.config.js` mirrors `webpack.config.js`)
- Same loader API (mostly)
- Same plugin API (Tapable-flavored)
- Rust core → **5–10× faster** than Webpack on typical apps
- Persistent cache stored on disk between runs

Ideal for teams with heavy Webpack investment who want speed without rewriting configs.

```js
// rspack.config.js — looks exactly like webpack.config.js
module.exports = {
  entry: "./src/index.tsx",
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: {
          loader: "builtin:swc-loader",
          options: {
            jsc: { parser: { syntax: "typescript", tsx: true } }
          }
        }
      }
    ]
  },
  plugins: [
    new rspack.HtmlRspackPlugin({ template: "./index.html" })
  ]
};
```

`builtin:` loaders are Rust-native fast paths for the common cases (SWC, CSS, asset); custom JS loaders still work but drop back to a JS worker.

---

## Rspack ecosystem

Rspack seeded a family of tools sharing its Rust core:

- **Rsbuild** — opinionated app framework on top of Rspack (like CRA-but-Rust)
- **Rslib** — library-building framework (Rollup-flavored bundling, Rspack core)
- **Rspress** — Rust-native docs site generator
- **Rsdoctor** — bundle analyzer with build-time diagnostics

```js
// rsbuild.config.js — zero-config for common apps
import { defineConfig } from "@rsbuild/core";
import { pluginReact } from "@rsbuild/plugin-react";

export default defineConfig({
  plugins: [pluginReact()],
});
```

Rsbuild is the recommended entry point for most new Rspack users — you don't touch Rspack config unless you need to.

---

## Comparison

| Dimension | Turbopack | Rspack |
|-----------|-----------|--------|
| Author | Vercel | ByteDance |
| Language | Rust | Rust |
| API compatibility | New (own) | Webpack-compatible |
| Incremental caching | Task graph (Turbo engine) | Persistent cache (Webpack-style) |
| Primary consumer | Next.js | Migrating Webpack apps |
| Plugin ecosystem | Growing, tied to Next | Reusing Webpack ecosystem |
| Config file | `next.config.js` (Next) | `rspack.config.js` |
| Standalone CLI | ❌ (Next-only in practice) | ✅ |
| Module Federation | Limited | Yes (native support) |
| SWC integration | Built-in | Built-in |

---

## When to use Turbopack

✅ You're on Next.js and want the fastest dev loop
✅ You accept some Next-specific configuration
✅ Your Webpack customizations are minor (loaders Turbopack already knows)
❌ You have custom Webpack loaders that haven't been ported
❌ You're not on Next.js — Turbopack has no standalone story yet
❌ You depend on niche Webpack plugins (many aren't reimplemented)

---

## When to use Rspack

✅ Existing Webpack app; want speed without config rewrite
✅ Heavy custom loader / plugin investment
✅ You need Module Federation with specific versions
❌ You're starting fresh — pick [[Build Tools Vite - Architecture Overview|Vite]] instead (simpler mental model)
❌ You want the newest React / Next features first (that's Turbopack's turf)

---

## Migration example — Webpack → Rspack

Change dependencies:

```json
{
  "devDependencies": {
    "@rspack/core": "^0.7.0",
    "@rspack/cli": "^0.7.0"
  }
}
```

Rename `webpack.config.js` → `rspack.config.js` (or keep the name; Rspack reads either).

Change scripts:

```json
{
  "scripts": {
    "dev": "rspack serve",
    "build": "rspack build"
  }
}
```

Swap plugin imports where Rspack has a built-in equivalent:

```js
// Before
const HtmlWebpackPlugin = require("html-webpack-plugin");
// After
const { HtmlRspackPlugin } = require("@rspack/core");
```

Most configs work as-is. Rspack docs list the incompatibilities — typically obscure options on `optimization` or `resolve` that were rarely used.

---

## The Turbo engine (aside)

Turbopack's Turbo engine is a **general** incremental computation library — it can back other tools. Turborepo (Vercel's monorepo task runner) uses the same primitive: model each `pnpm build` per package as a task with typed inputs (source hash, dep outputs) and cached outputs.

```
Turbo engine
  ├── Turbopack   (bundler)
  ├── Turborepo   (monorepo task runner)
  └── … future    (any tool that wants memoized DAG execution)
```

The engine itself is the durable investment; the bundler is one application of it. Expect more Vercel tooling to sit on top of it over time.

---

## Common misconceptions

```
❌ "Turbopack replaces Webpack in Next.js immediately."
✅ It's an opt-in flag (--turbo). Webpack remains the default
   for the moment as of 2026.

❌ "Rspack is a Webpack plugin."
✅ Rspack is a separate Rust binary that speaks Webpack's
   config/plugin dialect.

❌ "Rust bundlers make Vite obsolete."
✅ Vite has its own Rust roadmap (Rolldown — Rollup rewrite
   in Rust). The community is converging on Rust cores;
   different tools remain for different opinions.

❌ "Turbopack and Rspack compete for the same users."
✅ They target different populations. Turbopack is coupled
   to Next.js; Rspack is for teams porting off Webpack.

❌ "Rust means zero JavaScript in the pipeline."
✅ Both fall back to JS workers for custom user loaders /
   plugins written in JS. The fast paths are Rust; the
   escape hatches are still JS.
```

---

## Rolldown (a mention)

Rolldown is the Vite team's ongoing Rust rewrite of [[Build Tools Bundlers - Rollup Internals|Rollup]]. Aims to be a drop-in Rollup replacement with Turbopack-class speed and Rspack-class compatibility, then ship inside Vite as the production bundler. As of 2026, in progress. Cross-link [[Build Tools Vite - Architecture Overview]] for how it fits into the Vite dev/prod split.

The picture in 2026:

| Tool | Rust core | Compat target |
|------|-----------|---------------|
| Turbopack | Turbo engine | Own API |
| Rspack | Rspack core | Webpack |
| Rolldown | Rolldown core | Rollup |
| Vite (prod) | Rolldown (soon) | Rollup |

Every major bundler is converging on a Rust core within the next couple of years.

---

## Summary

```
Vite    — best default for new React apps (unbundled dev,
          Rollup prod → Rolldown prod soon)
Next.js — full-stack apps with RSC; Webpack default,
          Turbopack opt-in and going stable
Rspack  — migrating a Webpack app without rewriting
esbuild — libraries, tools, transform-only pipelines
```

The old rule "pick a bundler" is becoming "pick a framework; the bundler comes with it." Turbopack ships with Next; Rolldown will ship with Vite; Rspack is for the case where you already have a Webpack config you can't afford to lose.

---

## Related

- [[Build Tools Bundlers - Rollup vs esbuild vs Webpack]]
- [[Build Tools Meta-frameworks - Next.js and Turbopack]]
- [[Build Tools Webpack Guide]]
- [[Build Tools Vite - Architecture Overview]]
- [[Build Tools Bundlers Guide]]
