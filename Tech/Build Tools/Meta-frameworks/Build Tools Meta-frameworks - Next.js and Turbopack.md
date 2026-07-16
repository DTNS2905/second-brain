---
tags:
  - build-tools
  - meta-frameworks
  - nextjs
  - turbopack
  - tooling
  - frontend
created: 2026-07-16
source: https://nextjs.org/docs/app/api-reference/turbopack
---

# Build Tools Meta-frameworks — Next.js and Turbopack

> Why Vercel wrote Turbopack (Webpack's ceiling), how it composes into Next.js, and what the migration story looks like as of 2026. Part of [[Build Tools Meta-frameworks Guide]].

---

## Why Vercel wrote Turbopack

Webpack has been Next's bundler since v1. It carried Next through the App Router rewrite, RSC, streaming, and every major Next milestone up to Next 13. Two hard limits pushed Vercel to build a replacement:

1. **JS-in-JS overhead** — Webpack itself is written in JavaScript. Large apps hit V8 GC pauses, JIT deoptimizations, and a single-threaded event loop. Once your dependency graph gets big enough, the bundler spends more time managing its own memory than doing useful work.
2. **Weak incremental model** — Webpack has a persistent file cache, but it's coarse-grained: it operates on modules and chunks, not on the individual transformations inside them. For Next's per-route rebuild pattern (change one server component, rebuild only the affected route), that granularity isn't fine enough.

Result: a Rust bundler built on a general-purpose incremental computation library (the Turbo engine). The bundler is one consumer of the engine, not the engine itself — which matters for how Vercel scales the toolchain across products.

---

## The Turbo engine

General-purpose incremental computation framework, written in Rust. Model:

- Every operation is a **task** with typed inputs and cached outputs
- Tasks form a **dependency graph** — a task's output feeds into other tasks' inputs
- On input change, the engine invalidates only the affected tasks and re-runs them

The key property: **cache identity is derived from typed inputs**, not from file mtimes or content hashes at the module level. If you re-run the same task with the same inputs, you get the same outputs — the engine skips the work entirely.

Turbopack is one application of the engine. Turborepo is another. Any tool that fits the "pure function of typed inputs" model can be layered on top.

```
┌────────────────────────────────────────────┐
│              Turbo Engine (Rust)           │
│  - typed task nodes                        │
│  - persistent + in-memory task cache       │
│  - parallel scheduler                      │
└────────────────────────────────────────────┘
        ▲                       ▲
        │                       │
   ┌────┴─────┐            ┌────┴─────┐
   │Turbopack │            │Turborepo │
   │ (bundler)│            │ (monorepo│
   └──────────┘            │  runner) │
                           └──────────┘
```

---

## What Turbopack replaces

| Concept | Webpack | Turbopack |
|---------|---------|-----------|
| Language | JS | Rust |
| Incremental model | Persistent file cache | Task graph (fine-grained) |
| Concurrency | Limited (V8 event loop) | True parallelism (Rust) |
| Plugin ecosystem | Vast | New (growing) |
| HMR | Chunked hot-update | Direct ESM replacement |
| Config | `webpack.config.js` | `next.config.js` → `experimental.turbo` |

The API compatibility surface is deliberately narrower than Webpack's. Turbopack does not implement `compilation.hooks.*`, does not expose the module graph as a mutable object, and does not run user code inside the bundler process. Everything user-facing is either declarative config or an isolated loader function.

---

## Enabling in Next.js

CLI flags:

```
next dev --turbo        # dev — stable
next build --turbo      # build — beta/stable depending on Next version
```

Or via config:

```js
// next.config.js
module.exports = {
  experimental: { turbo: { /* rules */ } },
};
```

In recent Next versions the flag is being promoted to the default — `next dev` picks Turbopack automatically unless you opt out. Check `next --help` in your installed version.

---

## Status matrix (as of 2026)

Check Next docs for current specifics — this moves fast:

- `next dev --turbo` — **stable** (default in recent Next)
- `next build --turbo` — **stable** (in recent Next; check version)
- Custom Webpack config (`webpack:` in `next.config.js`) — **not supported** in Turbopack; must migrate to rules
- Custom loaders — **rules** system with different shape
- Module Federation — **planned** / partial
- Custom source-map devtool modes — **partial**
- Persistent disk cache across runs — **shipping incrementally**

---

## Turbopack rules (loader-like)

```js
// next.config.js
module.exports = {
  experimental: {
    turbo: {
      rules: {
        '*.svg': {
          loaders: ['@svgr/webpack'],
          as: '*.js',
        },
      },
    },
  },
};
```

Rules match file globs to a chain of loaders and a target module type (`as`). Same shape as Webpack loaders in some cases — the `@svgr/webpack` example above is literally a Webpack loader — but the loader must be Turbopack-compatible.

Compatibility requirement: the loader must be a pure function of its input string plus options. Loaders that rely on Webpack-specific APIs (`this.emitFile`, `this.addDependency` in exotic ways, `compilation` access) won't work.

For loaders that Turbopack can't run natively, community shims exist for the common ones (`babel-loader`, `sass-loader`, `postcss-loader`, `@svgr/webpack`).

---

## Config parity gaps

Things you may lose migrating from Webpack:

- Custom Webpack plugins that tap into `compilation.hooks.*` — no equivalent
- `WebpackConfig.entry` customization — Next controls entries; Turbopack surfaces less of this
- Some `module.rules` patterns not yet supported (complex `oneOf`, chained resource queries)
- Custom source-map devtool modes — Turbopack picks the mode
- `resolve.alias` with function values — string-only in Turbopack

Framework abstracts most of this. If you never touched `webpack:` in `next.config.js`, migration is essentially flipping a flag. If your `next.config.js` has a 100-line `webpack:` block, budget real time for the port.

```js
// ❌ Webpack-only patterns that don't port directly
module.exports = {
  webpack: (config, { isServer }) => {
    config.plugins.push(new MyCustomPlugin());
    config.module.rules.push({
      test: /\.foo$/,
      use: [{ loader: 'foo-loader', options: { fn: (x) => x } }],
    });
    return config;
  },
};
```

```js
// ✅ Turbopack rule equivalent (for the loader case)
module.exports = {
  experimental: {
    turbo: {
      rules: {
        '*.foo': {
          loaders: [{ loader: 'foo-loader', options: { mode: 'compat' } }],
          as: '*.js',
        },
      },
    },
  },
};
```

Note: function-valued loader options must become static — the Turbopack task model requires serializable inputs so the cache key is stable.

---

## Fast Refresh in Turbopack

Built-in; no plugin needed. Uses the same `react-refresh` runtime but with Turbopack's own module replacement mechanism.

Where Webpack's HMR bundles a "hot-update chunk" and hands it to a runtime that patches the module registry, Turbopack updates the ESM module record directly. The wire format is smaller (usually one module per update rather than a chunk), and the client-side runtime is simpler.

Practical effect: single-file edits feel closer to instant than they do in Webpack HMR, because there's less work between "compiler sees the change" and "React re-renders the component tree".

Cross-link [[Build Tools Dev Server and HMR - React Fast Refresh]].

---

## Benchmarks — with caveats

Turbopack claims (Vercel):

- Dev startup: **4× faster** than Webpack in Next
- HMR: **10× faster** on medium apps
- Incremental builds: **5× faster**

In real-world Next apps:

- **Small app** (< 5k modules) — perceptible improvement, not life-changing. Webpack was already fine here.
- **Medium** (50k+ modules) — large improvement; dev feels near-instant, HMR is under 100ms consistently.
- **Large** (500k+ modules) — biggest win overall, but may still hit cache-warmup periods on cold starts. Warm HMR is where Turbopack shines.

As always: benchmark your own app. The published numbers are best-case on a specific hardware profile with a specific app shape. Yours differs.

---

## Rolldown, Rspack — parallel bets

The Rust-bundler space isn't one project:

- **Rolldown** — Vite team's Rollup rewrite in Rust; will ship as the default bundler inside Vite. Compatible with Rollup's plugin API.
- **Rspack** — Webpack-compatible Rust bundler from ByteDance; near drop-in for Webpack apps. Prioritizes migration cost over clean-slate design.
- **Turbopack** — Vercel's bundler, tied to Next. Prioritizes deep integration with the framework over ecosystem compatibility.

All three are Rust; different opinions on the tradeoff between API compatibility and clean-slate design:

| Bundler | Compat priority | Framework tie-in |
|---------|-----------------|------------------|
| Rspack | Webpack API compat | Standalone / any framework |
| Rolldown | Rollup API compat | Vite (default) |
| Turbopack | New API, framework-tuned | Next.js (primary) |

Cross-link [[Build Tools Bundlers - Turbopack and Rspack]].

---

## When Turbopack isn't the right choice yet

- ❌ Your Next app has heavy custom Webpack config with many plugins
- ❌ You depend on a specific Webpack plugin without a Turbopack equivalent (some analytics/instrumentation plugins fall here)
- ❌ Module Federation is critical to your setup and Turbopack support isn't ready
- ❌ You need a specific source-map mode Turbopack doesn't emit
- ✅ Otherwise, opt in — the speed wins usually justify the migration

The migration cost is front-loaded: a day to port config, then you're on the fast path forever.

---

## The migration path

1. Try `next dev --turbo` — if it works, ship dev on Turbopack immediately. Dev-only usage has zero prod risk.
2. Verify build with `next build --turbo` in CI on a branch. Compare output.
3. Compare bundle sizes (should be comparable ±10%). Investigate any large regression before shipping.
4. Ship prod on Turbopack when comfortable — usually a canary deploy first.
5. Keep Webpack config in `next.config.js` as a fallback in case you need to revert. Next accepts both `webpack:` and `experimental.turbo:` and picks based on the flag.

```
┌─────────────┐    ┌──────────────┐    ┌────────────────┐    ┌───────────┐
│ Dev turbo   │ →  │ CI build     │ →  │ Bundle diff    │ →  │ Prod turbo│
│ (local)     │    │ turbo branch │    │ vs main        │    │ (canary)  │
└─────────────┘    └──────────────┘    └────────────────┘    └───────────┘
```

Rollback is a flag flip, not a code change — that's the point of keeping the Webpack config path around.

---

## Turbopack's design philosophy

Vercel's stated goals:

- **Everything is a task with typed inputs** → deterministic, cacheable, reproducible
- **Never do work you've done before** → aggressive memoization at every layer
- **Parallelize by default** → Rust concurrency without JS's GIL-style constraints
- **Zero-config for typical Next apps** → declarative rules, no `webpack:` escape hatch expected

Different from Webpack's "plugin hooks for everything" philosophy. Webpack exposes almost every internal decision point to plugin authors, which is why the plugin ecosystem is vast — but also why the internal contract is impossible to change without breaking the world.

Turbopack is opinionated about the framework it serves. It ships without a rich plugin API on purpose: the surface stays small, the internals stay refactorable, and the common cases stay fast.

The tradeoff is real. If you loved Webpack's plugin ecosystem for exotic edge cases, Turbopack will feel restrictive. If you want a bundler that "just works" for Next apps and stays out of your way, Turbopack is the better shape.

---

## Related

- [[Build Tools Bundlers - Turbopack and Rspack]]
- [[Build Tools Meta-frameworks - Next.js Build Pipeline]]
- [[Build Tools Meta-frameworks - RSC and the Bundler]]
- [[Build Tools Webpack Guide]]
- [[Build Tools Meta-frameworks Guide]]
