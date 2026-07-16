---
tags:
  - build-tools
  - webpack
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/concepts/
---

# Build Tools Webpack — Core Concepts

> The seven concepts every Webpack config uses: entry, output, module (loaders), resolve, plugins, mode, target. Get these right and everything else clicks. Part of [[Build Tools Webpack Guide]].

---

## The seven concepts

Every Webpack config — no matter how large — is built from the same handful of top-level keys. Learn what each one owns and the rest of the surface area becomes navigation, not memorization.

| Concept | What it means |
|---------|--------------|
| entry | Where the graph traversal starts |
| output | Where files are written |
| module.rules (loaders) | Per-file transforms |
| plugins | Compilation-lifecycle taps |
| resolve | How imports become file paths |
| mode | 'development' / 'production' / 'none' |
| target | 'web' / 'node' / 'webworker' / etc. |

Everything else in `webpack.config.js` — `devtool`, `optimization`, `cache`, `devServer`, `experiments` — is a refinement of one of these seven.

---

## entry

`entry` tells Webpack where to begin dependency graph traversal. Every `import`/`require` reachable from an entry becomes part of that entry's bundle.

```js
// Single string
entry: './src/index.tsx',

// Named entries → multiple bundles
entry: {
  main: './src/index.tsx',
  admin: './src/admin/index.tsx',
  worker: './src/worker.ts',
},

// Descriptor form
entry: {
  main: {
    import: './src/index.tsx',
    dependOn: 'shared',
  },
  shared: ['react', 'react-dom'],
},
```

Key points:

- The string form is shorthand for `{ main: './src/index.tsx' }`.
- Named entries produce one bundle per key — useful for MPAs, admin bundles, or splitting a worker script.
- `dependOn` lets an entry declare that another entry already contains its deps — the referenced entry must be loaded first at runtime, but the duplicated modules are stripped.
- Prefer `dependOn` over listing shared deps as an array entry when possible — arrays get bundled into every dependent, `dependOn` deduplicates.

---

## output

`output` controls where the emitted files land and how they're named. Naming templates drive both cache behavior and CDN wiring.

```js
output: {
  path: path.resolve(__dirname, 'dist'),
  filename: '[name].[contenthash].js',
  chunkFilename: '[name].[contenthash].chunk.js',
  assetModuleFilename: 'assets/[name].[contenthash][ext]',
  publicPath: '/',
  clean: true,          // wipe dist on build
  library: { type: 'umd', name: 'MyLib' },  // for library builds
}
```

Filename tokens:

- `[name]` — the entry or chunk name
- `[contenthash]` — hash of the emitted content; changes only when output content changes → best for long-term caching
- `[chunkhash]` — hash of the chunk (less precise than contenthash)
- `[hash]` — hash of the whole compilation (invalidates everything)
- `[ext]` — original extension, for Asset Modules

`publicPath` is the runtime prefix used to construct URLs for lazy chunks and assets. Set it to `'/'` for root-hosted apps, a CDN URL for CDN-hosted, or `'auto'` to derive it from the script's own URL.

`clean: true` (webpack 5+) replaces the old CleanWebpackPlugin.

For library builds, `output.library` determines the module format (`umd`, `commonjs2`, `module`, `window`, etc.).

---

## module.rules (loaders)

Loaders are per-file transforms. A rule matches files by `test` (regex), `include`/`exclude`, or `resource*` filters, then runs a chain of loaders that convert the source into JavaScript Webpack can add to the graph.

```js
module: {
  rules: [
    {
      test: /\.tsx?$/,
      exclude: /node_modules/,
      use: 'swc-loader',
    },
    {
      test: /\.css$/,
      use: ['style-loader', 'css-loader', 'postcss-loader'],
    },
    {
      test: /\.(png|svg|jpg)$/,
      type: 'asset',        // built-in asset modules (webpack 5+)
    },
  ],
}
```

Loader chain runs **right to left, bottom to top**. So CSS is processed: postcss → css → style.

Rule shape reference:

- `test` — regex (or array) of paths to match
- `include` / `exclude` — narrow matches; strongly prefer `include` for perf
- `use` — string, object, or array of loader descriptors
- `type` — one of `javascript/auto`, `javascript/esm`, `json`, `asset`, `asset/resource`, `asset/inline`, `asset/source`
- `oneOf` — first-match-wins list of sub-rules; skips the rest once a match is found
- `sideEffects` — override the module's `sideEffects` claim for tree-shaking

Asset Modules replace the old `file-loader` / `url-loader` / `raw-loader` trio:

| `type` | Emits file? | Behavior |
|--------|-------------|----------|
| `asset/resource` | Yes | Import returns URL (replaces `file-loader`) |
| `asset/inline` | No | Import returns data URI (replaces `url-loader`) |
| `asset/source` | No | Import returns raw source string (replaces `raw-loader`) |
| `asset` | Depends | Chooses `resource` or `inline` by size heuristic (default 8kB) |

Cross-link [[Build Tools Webpack - Loaders vs Plugins]].

---

## plugins

Plugins tap into the compilation lifecycle. Where loaders transform files, plugins operate on the whole build — emitting HTML, extracting CSS, injecting env vars, analyzing bundles.

```js
plugins: [
  new HtmlWebpackPlugin({ template: './public/index.html' }),
  new MiniCssExtractPlugin({ filename: '[name].[contenthash].css' }),
  new webpack.DefinePlugin({ 'process.env.NODE_ENV': JSON.stringify('production') }),
],
```

Common plugins:

- `HtmlWebpackPlugin` — generates an HTML file with `<script>`/`<link>` tags injected for every emitted asset
- `MiniCssExtractPlugin` — pulls CSS out of the JS bundle into `.css` files (used with its `loader` in `module.rules` instead of `style-loader`)
- `DefinePlugin` — compile-time constant replacement (values must be JSON strings, hence `JSON.stringify`)
- `ProvidePlugin` — auto-imports a module wherever a global identifier is referenced
- `CopyWebpackPlugin` — copies static files into `output.path`
- `BundleAnalyzerPlugin` — treemap of the bundle for size auditing

Plugins receive the `compiler` object and register callbacks on its hooks (via `tapable`). This is why they're much more powerful than loaders — loaders can only see one file at a time.

Cross-link [[Build Tools Webpack - Loaders vs Plugins]].

---

## resolve

`resolve` controls how import specifiers become file paths.

```js
resolve: {
  extensions: ['.tsx', '.ts', '.js', '.jsx'],
  alias: {
    '@': path.resolve(__dirname, 'src'),
  },
  mainFields: ['browser', 'module', 'main'],
  conditionNames: ['import', 'require', 'default'],
  modules: ['node_modules'],
  symlinks: true,
}
```

Field reference:

- `extensions` — extensions tried when the import has none. Order matters (first match wins) — put TS before JS if both may exist.
- `alias` — path prefixes for cleaner imports. `@/components/Foo` resolves to `<projectRoot>/src/components/Foo`.
- `mainFields` — which `package.json` fields to pick when a package has no explicit `exports`. For `web` target: `['browser', 'module', 'main']`; for `node`: `['module', 'main']`.
- `conditionNames` — which conditional exports to honor from `package.json#exports`. `import` for ESM consumers, `require` for CJS, `browser`, `worker`, custom conditions like `development`.
- `modules` — directories to search for bare specifiers (`import x from 'foo'`).
- `symlinks` — if `false`, symlinked packages resolve to their real path (breaks `pnpm` deduplication if you're not careful).

Also useful:

- `resolve.fallback` — polyfills for missing Node core modules (webpack 5 removed the auto-polyfill)
- `resolve.plugins` — inject custom resolvers (e.g., `tsconfig-paths-webpack-plugin`)

---

## mode

`mode` applies sensible defaults for `optimization`, `devtool`, `plugins`, and `process.env.NODE_ENV`:

| Mode | Defaults |
|------|----------|
| `'development'` | `devtool: 'eval'`, no minify, HMR enabled, verbose stats |
| `'production'` | `devtool: 'source-map'` (or off), minify + tree-shake, small stats |
| `'none'` | No defaults |

Set via `--mode` CLI or env var:

```bash
webpack --mode=production
webpack --mode=development
```

In production mode Webpack sets:

- `optimization.minimize: true` (with `TerserPlugin`)
- `optimization.usedExports: true` (tree-shaking marks unused exports)
- `optimization.concatenateModules: true` (scope hoisting)
- `optimization.nodeEnv: 'production'` (baked into `process.env.NODE_ENV`)

In development mode:

- `optimization.namedModules: true` (readable module ids)
- `optimization.namedChunks: true` (readable chunk ids)
- `devtool: 'eval'`
- Debug-friendly output, no minification

---

## target

`target` tells Webpack the runtime environment so it can pick the right globals, module system, and polyfills.

- `'web'` — default; browser globals available
- `'node'` — Node.js; `require()` for externals, `__dirname`/`__filename` untouched
- `'webworker'` — Web Worker; no DOM
- `'browserslist'` — reads `.browserslistrc` to configure everything else
- `['web', 'es2020']` — combine

Effects of target:

- Which core modules are treated as externals (Node builtins on `'node'`, none on `'web'`)
- Which `resolve.mainFields` are consulted
- The runtime chunk's global (`self` on web, `global` on node, `globalThis` on browserslist)
- Whether async chunks are emitted as script tags, `require`, or `importScripts`

For SSR builds you'll typically have two configs — one `target: 'web'` for the client, one `target: 'node'` for the server.

---

## devtool (source maps)

Modes range from fast+cheap to slow+full:

| Mode | Speed | Fidelity | Use |
|------|-------|----------|-----|
| `'eval'` | ✅✅ | Line only | Dev tight loop |
| `'eval-cheap-source-map'` | ✅ | Lines | Dev |
| `'source-map'` | Slow | Full | Prod default |
| `'hidden-source-map'` | Slow | Full | Prod + Sentry |

Modifier prefixes:

- `eval-` — sources stored via `eval()` inline; rebuild is very fast
- `cheap-` — line mappings only, no columns
- `inline-` — map appended as data URI in the bundle
- `hidden-` — map emitted but no `//# sourceMappingURL` comment (upload to Sentry manually)
- `nosources-` — map without source contents (protects source from download)

Cross-link [[Build Tools Foundations - Source Maps]].

---

## Multiple config files

Real projects almost never live in one `webpack.config.js`. The idiomatic split is common / dev / prod, merged at load time.

```js
// webpack.common.js — shared
// webpack.dev.js — extends common with dev-only
// webpack.prod.js — extends common with prod-only

// Merge using webpack-merge
const { merge } = require('webpack-merge');
module.exports = merge(common, { mode: 'production' });
```

Alternatives:

- Export a function `(env, argv) => config` — read `argv.mode` and branch inline
- Export an array of configs — Webpack builds each in parallel (client + server SSR pair)
- Use `env` via CLI: `webpack --env production --env target=web`

`webpack-merge` handles the tricky cases — deduping loaders, appending plugins, concatenating rule arrays — better than a naive spread.

---

## webpack v4 → v5 major changes

- `Node.js polyfills` no longer auto-injected (`fs`, `crypto`, etc.) — use `resolve.fallback` or drop the dep
- Asset Modules built-in (`type: 'asset'`) replaces `file-loader`/`url-loader`
- Persistent caching (`cache.type: 'filesystem'`) — second builds are dramatically faster
- Better tree-shaking with `sideEffects` field — top-level `package.json#sideEffects: false` lets Webpack skip whole files
- Module Federation stabilized — cross-app runtime imports
- Named chunk ids by default (`optimization.chunkIds: 'named'` in dev, `'deterministic'` in prod)
- Automatic public path via `output.publicPath: 'auto'`
- Top-level await support in modules

Migration friction usually comes from removed polyfills (`process`, `Buffer`, `crypto`) and from loaders that assumed webpack 4 loader API — pin versions carefully.

---

## Config gotchas

```
❌ Forgetting exclude: /node_modules/ on a loader → transforms all deps (slow)
✅ Always exclude node_modules for JS/TS loaders

❌ Setting devtool: 'source-map' in dev → slow rebuild
✅ Use 'eval-cheap-source-map' or 'eval-source-map' in dev

❌ Not setting mode → treated as 'production' but with a warning
✅ Always set mode explicitly
```

More traps:

```
❌ Using [hash] in output.filename → any file change busts every cache entry
✅ Use [contenthash] for content-addressed cache-busting

❌ Chaining loaders in wrong order (['css-loader', 'style-loader'] for CSS)
✅ Remember: right-to-left. ['style-loader', 'css-loader', 'postcss-loader']

❌ Using DefinePlugin without JSON.stringify → raw identifier substitution
✅ new DefinePlugin({ 'process.env.NODE_ENV': JSON.stringify('production') })

❌ publicPath: '' in a lazy-loaded SPA on a subpath → 404 on chunk fetch
✅ Set publicPath to the deploy prefix, or use 'auto'
```

---

## Related

- [[Build Tools Webpack - Compiler and Compilation]] — the internals underneath these concepts
- [[Build Tools Webpack - Loaders vs Plugins]]
- [[Build Tools Webpack - Code Splitting and SplitChunks]]
- [[Build Tools Foundations - Source Maps]]
- [[Build Tools Webpack Guide]]
