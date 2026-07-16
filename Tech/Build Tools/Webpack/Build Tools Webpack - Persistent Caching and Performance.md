---
tags:
  - build-tools
  - webpack
  - performance
  - caching
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/configuration/cache/
---

# Build Tools Webpack — Persistent Caching and Performance

> Webpack 5's filesystem cache turns cold builds from minutes to seconds. Combined with parallel loaders and profiler stats, most Webpack apps can hit build times competitive with Vite. Part of [[Build Tools Webpack Guide]].

---

## Why builds are slow

Webpack's performance problems are rarely mysterious — they cluster around a handful of well-known causes. Ranked by real-world impact:

1. **Loaders re-parsing the same files every build** — Every cold start, Webpack asks each loader to transform every matched module. For a 5k-module TypeScript app running through Babel, this is 30–90 seconds of wasted work per build. Fixed by **persistent cache** (`cache: { type: 'filesystem' }`).
2. **Source-map generation** (`devtool` setting) — Full source maps (`source-map`, `nosources-source-map`) are extremely expensive. In dev, `eval-cheap-source-map` is 5–10× faster and still gives you line-accurate stack traces.
3. **Large `node_modules` transformed by default** — Without an `exclude`, Babel/SWC will happily run on every file inside `node_modules`, which is usually already-transpiled ES5 code. Fixed by `exclude: /node_modules/` on every JS/TS rule.
4. **Serial loader chains where parallel would work** — Loaders run one at a time per module, sequentially through the chain. For slow loaders (Babel-with-many-plugins, ts-loader), `thread-loader` runs the downstream work in a worker pool.
5. **Type-checking in the same process as bundling** — If `ts-loader` is doing type-checking, it blocks the main thread. Fixed by `ForkTsCheckerWebpackPlugin`, which runs `tsc --noEmit` in a separate process — bundle and type-check finish independently.

Cross-link `[[Build Tools Webpack - Loaders vs Plugins]]` for how loaders and plugins differ, and `[[Build Tools Webpack - Compiler and Compilation]]` for the Webpack lifecycle these hook into.

---

## Filesystem cache (Webpack 5)

The single biggest performance win in Webpack 5 is the filesystem cache. It's opt-in for production builds but transforms cold-start times:

```js
const path = require('path');

module.exports = {
  cache: {
    type: 'filesystem',
    cacheDirectory: path.resolve(__dirname, '.webpack-cache'),
    buildDependencies: {
      config: [__filename],
    },
  },
};
```

**How it works:** After the first build, Webpack writes serialized module snapshots to `.webpack-cache/`. On subsequent builds, unchanged modules are read from disk instead of being re-transformed.

**Result:** 5–20× faster warm builds. A 45-second cold build often drops to 3–5 seconds warm.

**Where to put the cache:**
- Local dev: `node_modules/.cache/webpack` (default) or a custom `.webpack-cache/` at repo root.
- CI: cache the directory between runs (GitHub Actions `actions/cache`, GitLab `cache:`). CI runs go from ~2min → ~15s once warm.

```js
cache: {
  type: 'filesystem',
  name: process.env.NODE_ENV,         // separate caches for dev/prod
  version: `${process.env.GIT_REV}`,  // bust on git rev change
}
```

The `name` option keeps dev and prod caches isolated — otherwise switching modes invalidates everything. The `version` option lets you nuke the cache on demand.

---

## buildDependencies

Persistent caching is only safe if Webpack knows what invalidates it. `buildDependencies` tells Webpack which files, when changed, must trigger a full cache rebuild:

```js
cache: {
  type: 'filesystem',
  buildDependencies: {
    config: [__filename],                 // webpack.config.js
    defaultWebpack: ['webpack/lib/'],     // webpack itself
    tsconfig: ['./tsconfig.json'],
    postcssConfig: ['./postcss.config.js'],
    babelConfig: ['./babel.config.js'],
  },
}
```

**Why this matters:** If you don't declare these, cache may serve stale results after config changes. You'll change `tsconfig.json`, restart the dev server, and see the *old* compiled output because Webpack didn't know that file affected the build.

Common gotcha — the config file itself must be in `buildDependencies.config`, or edits to `webpack.config.js` won't invalidate the cache. `[__filename]` is the safe default.

**Named cache groups:** The keys (`config`, `tsconfig`, etc.) are arbitrary labels for logging. Use whatever names you want.

---

## Memory cache (Webpack 5 dev default)

In dev, Webpack 5 defaults to `cache: { type: 'memory' }`. This is a purely in-process cache — it lives inside the running dev server and is discarded on restart.

```js
cache: {
  type: 'memory',
  maxGenerations: Infinity,   // never expire (default in dev)
}
```

**Two-tier caching:** In watch mode, both cache tiers play a role. The memory cache absorbs the hot loop — the current running Webpack process serves compiled modules from RAM. The filesystem cache absorbs restarts — kill the dev server and boot it back up, and the filesystem cache brings you back to warm speed in seconds.

**Persistent cache is opt-in for prod builds too** — Webpack won't create a `.webpack-cache/` directory unless you explicitly set `type: 'filesystem'`. This is intentional: on a fresh CI runner with no persistent disk, memory cache is the right default.

---

## thread-loader — parallel loaders

For slow synchronous loaders, `thread-loader` runs them in a worker pool:

```js
{
  test: /\.tsx?$/,
  exclude: /node_modules/,
  use: [
    {
      loader: 'thread-loader',
      options: { workers: 4, workerParallelJobs: 50 },
    },
    'swc-loader',
  ],
}
```

**How it works:** `thread-loader` forwards work to a pool of Node worker processes. Every loader listed *after* it in the chain runs in a worker. Everything *before* it runs on the main thread.

**Overhead:** ~50ms per task to serialize input, ship it across the process boundary, and receive output. This means **thread-loader is only worth it for slow loaders** — Babel with heavy plugin sets, ts-loader with `transpileOnly: false`, PostCSS with many plugins.

❌ **Don't** put thread-loader in front of already-fast tools:

```js
use: [
  { loader: 'thread-loader' },
  'swc-loader',                // already ~30ms per file — thread overhead is worse
]
```

✅ **Do** use it for slow ones:

```js
use: [
  { loader: 'thread-loader', options: { workers: 4 } },
  'babel-loader',              // with heavy plugin set — thread pays off
]
```

**Warmup:** `thread-loader.warmup({ workers: 4 }, ['babel-loader'])` at the top of the config pre-forks workers so the first build doesn't pay startup cost.

---

## swc-loader vs babel-loader

SWC is a Rust rewrite of Babel's transformation pipeline. Rough numbers: Babel ~100 files/s per core, SWC ~2000+ files/s per core. Swapping loaders is usually a one-line change:

```js
{
  test: /\.[jt]sx?$/,
  exclude: /node_modules/,
  use: 'swc-loader',
}
```

With options:

```js
{
  test: /\.[jt]sx?$/,
  exclude: /node_modules/,
  use: {
    loader: 'swc-loader',
    options: {
      jsc: {
        parser: { syntax: 'typescript', tsx: true },
        transform: { react: { runtime: 'automatic' } },
        target: 'es2020',
      },
    },
  },
}
```

**Rspack:** ships `builtin:swc-loader` — no npm install, no worker overhead, natively integrated. If migrating to Rspack, you get SWC for free.

**Migration checklist:**
- Move `.babelrc` → `.swcrc` (Babel plugins that have no SWC equivalent may block migration)
- Verify TypeScript decorators / experimental syntax you rely on is supported
- Drop `thread-loader` — SWC is already fast enough that thread overhead usually hurts

Cross-link `[[Build Tools Compilers - SWC Internals]]` for how SWC's Rust pipeline is structured.

---

## Fork the type-checker

The single biggest speed win in TypeScript projects is separating **transpile** and **type-check** into parallel processes:

```js
const ForkTsCheckerWebpackPlugin = require('fork-ts-checker-webpack-plugin');

module.exports = {
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        exclude: /node_modules/,
        use: {
          loader: 'ts-loader',
          options: { transpileOnly: true },   // no type-check here
        },
      },
    ],
  },
  plugins: [
    new ForkTsCheckerWebpackPlugin({
      typescript: {
        configFile: './tsconfig.json',
        diagnosticOptions: { semantic: true, syntactic: true },
      },
    }),
  ],
};
```

**How it works:** `ts-loader` in `transpileOnly` mode just strips types — it's ~5× faster than the full type-checking pipeline. In parallel, `ForkTsCheckerWebpackPlugin` runs `tsc --noEmit` in a separate process. Errors surface asynchronously in dev, and block the build in prod (via `async: false` when `mode === 'production'`).

**Works with any transpiler:** Use with `swc-loader` or `babel-loader` the same way — they don't type-check either, so you always need this plugin (or `tsc --watch` in a separate terminal) to catch type errors.

**Pro tip:** Also runs ESLint if you configure `eslint: { files: './src/**/*.{ts,tsx}' }`. One worker, two checks.

---

## externals

For dependencies provided at runtime (CDN globals, host apps, Node's built-ins), `externals` tells Webpack "don't bundle this, just reference it":

```js
externals: {
  react: 'React',              // pulled from window.React
  'react-dom': 'ReactDOM',
  jquery: 'jQuery',
}
```

Requests to `import 'react'` become `module.exports = React` — pointing at the global. Saves ~130KB of React from the bundle, cuts build time proportionally.

**For SSR / Node targets:** typically you want to externalize every `node_modules` dep:

```js
externalsType: 'commonjs',
externals: ['express', /^@my-org\//],
```

Or use `webpack-node-externals`:

```js
const nodeExternals = require('webpack-node-externals');

module.exports = {
  target: 'node',
  externals: [nodeExternals()],   // exclude everything in node_modules
};
```

For Node servers this can cut build time by 90% — you're only bundling your own code.

**Module Federation** — related pattern, different mechanism. See `[[Build Tools Webpack - Module Federation]]` for the runtime-shared-module story.

---

## optimization.moduleIds and chunkIds

Webpack assigns numeric IDs to every module and chunk. The strategy affects long-term browser caching:

```js
optimization: {
  moduleIds: 'deterministic',
  chunkIds: 'deterministic',
}
```

**Options:**

| Value | Behavior | Cache friendliness |
|-------|----------|-------------------|
| `natural` | Ordered by usage order | ❌ shifts on every change |
| `named` | Uses filename | ✅ but larger bundle |
| `deterministic` | Content-hashed short IDs | ✅ stable + compact |
| `size` | Optimized for smaller bundles | ❌ shifts on any change |

**Why `deterministic` wins:** IDs are derived from a hash of the module path. Adding a new module doesn't renumber the others → the vendor chunk hash stays stable → browsers keep their cached copy → repeat visits are instant.

This is now the default in production mode, but explicitly setting it makes intent obvious and works in dev too.

---

## stats and analysis

To diagnose performance, ask Webpack for detailed timings:

```js
stats: 'detailed'   // or 'errors-warnings', 'normal', 'verbose'
```

Or configure exactly what to log:

```js
module.exports = {
  // ...
  profile: true,
  stats: {
    modules: true,
    chunks: true,
    chunkModules: true,
    timings: true,
    builtAt: true,
    assets: true,
    performance: true,
  },
};
```

`profile: true` adds per-module timing to stats — you can see which modules took longest to build, resolve, or restore from cache.

**JSON output for offline analysis:**

```bash
webpack --profile --json > stats.json
```

Feed `stats.json` into:
- [**Webpack Analyse**](https://webpack.github.io/analyse/) — module dependency graph
- **`webpack-bundle-analyzer`** — visual treemap of the bundle
- **statoscope** — richer alternative with diffing across builds

**Bundle Analyzer:**

```js
const { BundleAnalyzerPlugin } = require('webpack-bundle-analyzer');

plugins: [
  new BundleAnalyzerPlugin({
    analyzerMode: 'static',       // writes report.html
    openAnalyzer: false,
  }),
]
```

Opens a treemap showing every module's contribution. Essential for spotting accidental duplicate deps and oversized libraries.

---

## The speed-measure plugin

`speed-measure-webpack-plugin` wraps your entire config to report per-loader + per-plugin timings:

```js
const SpeedMeasurePlugin = require('speed-measure-webpack-plugin');
const smp = new SpeedMeasurePlugin();

module.exports = smp.wrap({
  entry: './src/index.ts',
  module: { rules: [/* ... */] },
  plugins: [/* ... */],
});
```

Output looks like:

```
 SMP  ⏱
General output time took 12.3 secs

 SMP  ⏱  Plugins
ForkTsCheckerWebpackPlugin took 8.2 secs
BundleAnalyzerPlugin took 1.1 secs

 SMP  ⏱  Loaders
swc-loader took 2.4 secs
  module count = 412
css-loader took 0.8 secs
  module count = 61
```

Point of maximum insight — you can immediately see if a loader is dominating build time or a plugin is silently slow. Then optimize the biggest number.

**Caveat:** SMP wraps everything, which slightly distorts timings. Use it for diagnosis, disable it for production builds. Also incompatible with a few plugins (Mini CSS Extract) — check compatibility before permanent adoption.

---

## When to migrate off Webpack

You've tuned everything and it's still slow. Time to consider alternatives.

**Signals it's time:**
- Dev startup > 30s consistently
- HMR update > 3s (Vite/Turbopack are sub-100ms)
- Prod build > 5 min on a beefy CI runner
- You've already tuned caching, threads, SWC, forked the type-checker — and it's still slow

**Options, in decreasing overlap with your current setup:**

- **Rspack** — Webpack-compatible Rust replacement. Drop-in for most configs (loaders, plugins, config shape). 5–10× faster. Missing some niche plugins but the ecosystem is closing fast. This is the lowest-risk migration if your config is stable.
- **Turbopack** — Next.js's Rust bundler path. Only realistic if you're already on Next.js — otherwise it's a major migration since Turbopack is tied to Next's config surface.
- **Vite** — Clean-slate rewrite of config. Uses esbuild for dev + Rollup for prod. Excellent DX, but plugins are Rollup-shaped (not Webpack-shaped), so custom Webpack plugins need rewriting.

Cross-link `[[Build Tools Bundlers - Turbopack and Rspack]]` for the Rust migration story.

**Rough decision matrix:**

| Situation | Recommended |
|-----------|-------------|
| Large Webpack config, many custom plugins | **Rspack** (drop-in) |
| Already on Next.js | **Turbopack** (native fit) |
| Starting fresh, no Webpack legacy | **Vite** |
| Module Federation is critical | **Rspack** (best MF parity) |
| Need SSR + streaming | **Turbopack** or **Rspack** |

---

## Performance checklist

The default configuration to reach before considering migration:

```
✅ cache: { type: 'filesystem' }
✅ swc-loader (or babel-loader minimized to preset-env)
✅ exclude: /node_modules/ on all JS/TS loaders
✅ fork-ts-checker-webpack-plugin (parallel type-check)
✅ optimization.runtimeChunk: 'single' (better caching)
✅ optimization.splitChunks tuned to your app's shape
✅ devtool: 'eval-cheap-source-map' in dev
✅ mode: 'development' explicitly (skip prod defaults in dev)
❌ Avoid: source-map devtool in dev
❌ Avoid: babel-plugin-import in place of tree-shaking-friendly ESM libs
❌ Avoid: transforming node_modules unless required
```

A worked example combining all of the above:

```js
const path = require('path');
const ForkTsCheckerWebpackPlugin = require('fork-ts-checker-webpack-plugin');

module.exports = {
  mode: 'development',
  devtool: 'eval-cheap-source-map',
  cache: {
    type: 'filesystem',
    cacheDirectory: path.resolve(__dirname, '.webpack-cache'),
    buildDependencies: {
      config: [__filename],
      tsconfig: ['./tsconfig.json'],
    },
  },
  module: {
    rules: [
      {
        test: /\.[jt]sx?$/,
        exclude: /node_modules/,
        use: 'swc-loader',
      },
    ],
  },
  plugins: [
    new ForkTsCheckerWebpackPlugin({
      typescript: { configFile: './tsconfig.json' },
    }),
  ],
  optimization: {
    moduleIds: 'deterministic',
    chunkIds: 'deterministic',
    runtimeChunk: 'single',
    splitChunks: { chunks: 'all' },
  },
};
```

This config gets a mid-sized TypeScript app to sub-5-second warm builds and sub-100ms HMR — competitive with Vite for most workloads. If you get here and it's still slow, the bottleneck isn't Webpack — it's the total volume of your source, and no bundler swap will fix that alone. Cross-link `[[Build Tools Webpack - Code Splitting and SplitChunks]]` for splitting strategies that address that.

---

## Summary

| Optimization | Speed gain | Effort |
|--------------|-----------|--------|
| `cache: { type: 'filesystem' }` | 5–20× warm | Trivial |
| SWC over Babel | 10–20× transpile | Small |
| `ForkTsCheckerWebpackPlugin` | 2–5× TS builds | Small |
| `exclude: /node_modules/` | 2–3× | Trivial |
| `thread-loader` (slow loaders only) | 1.5–3× | Small |
| `externals` (SSR / CDN globals) | 3–10× SSR | Small |
| `deterministic` IDs | 0 build, big cache wins | Trivial |
| Migrate to Rspack | 5–10× | Medium |

---

## Related

- [[Build Tools Bundlers - Turbopack and Rspack]] — the Rust migration path
- [[Build Tools Compilers - SWC Internals]]
- [[Build Tools Foundations - Source Maps]]
- [[Build Tools Webpack - Compiler and Compilation]]
- [[Build Tools Webpack Guide]]
