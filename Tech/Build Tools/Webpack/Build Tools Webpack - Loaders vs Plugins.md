---
tags:
  - build-tools
  - webpack
  - loaders
  - plugins
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/concepts/loaders/
---

# Build Tools Webpack — Loaders vs Plugins

> The distinction everyone confuses. Loaders transform one file at a time; plugins tap into the compilation lifecycle. Getting the mental model right unlocks the whole ecosystem. Part of [[Build Tools Webpack Guide]].

---

## The one-sentence distinction

**Loader** = per-file transform. A pure function `(source) => transformed` that runs during module resolution, once per matched file.

**Plugin** = lifecycle-tapping compilation extension. A class with `apply(compiler)` that subscribes to hooks fired by the [[Build Tools Webpack - Compiler and Compilation|Compiler and Compilation]] objects.

If your work is *"take this file, produce another file's contents"* → loader. If your work is *"do something when the build reaches state X"* (emit assets, generate HTML, analyze the graph, inject globals) → plugin.

---

## Loader signature

A loader is a function that receives source text (or a Buffer for binary files) and returns the transformed source.

```js
// A loader is a function: (source) => transformed
module.exports = function (source) {
  const result = source.replace(/foo/g, 'bar');
  return result;
};
```

Async version — call `this.async()` to defer:

```js
module.exports = function (source) {
  const callback = this.async();
  doAsync(source, (err, result) => callback(err, result));
};
```

`this` (inside the loader) exposes the **Loader Context**:

- `this.resourcePath` — absolute path of the file being loaded
- `this.resourceQuery` — the `?query` portion of the request
- `this.emitFile(name, content)` — emit an additional file into the output
- `this.addDependency(file)` — mark another file as a dependency so the loader re-runs when it changes
- `this.getOptions()` — the loader's own options block
- `this.cacheable(true)` — mark the result as cacheable (default true)
- `this.async()` — switch to async mode; returns a callback

Binary loaders opt in with `module.exports.raw = true` to receive a `Buffer` instead of a string.

---

## Plugin signature

A plugin is a class (or object) with an `apply(compiler)` method. Inside, tap into hooks exposed by the compiler and its compilation.

```js
class MyPlugin {
  apply(compiler) {
    compiler.hooks.done.tap('MyPlugin', (stats) => {
      console.log('build done in', stats.endTime - stats.startTime, 'ms');
    });
  }
}
```

Hook flavors:

- `.tap(name, fn)` — synchronous
- `.tapAsync(name, (arg, cb) => …)` — node-style callback
- `.tapPromise(name, async (arg) => …)` — promise-returning

Common entry points on `compiler.hooks`: `beforeRun`, `run`, `compile`, `thisCompilation`, `compilation`, `make`, `emit`, `afterEmit`, `done`. Deeper work happens on `compilation.hooks` — see [[Build Tools Webpack - Compiler and Compilation]] for the full lifecycle map.

---

## When to use which

| Job | Choice |
|-----|--------|
| Transform TS to JS | Loader (`swc-loader`, `babel-loader`) |
| Turn SVG into a React component | Loader (`@svgr/webpack`) |
| Compile Sass to CSS | Loader (`sass-loader`) |
| Extract CSS into separate files | Plugin (`MiniCssExtractPlugin`) |
| Generate HTML with `<script>` tags | Plugin (`HtmlWebpackPlugin`) |
| Inject env vars via `process.env.X` replacement | Plugin (`DefinePlugin`) |
| Emit a build-info file | Plugin |
| Analyze the bundle | Plugin (`BundleAnalyzerPlugin`) |
| Copy static assets to output | Plugin (`CopyWebpackPlugin`) |

Rule of thumb: if you can answer *"what does one file become?"* → loader. If you need to know about **many** modules, or about the **outputs**, or need to emit files that don't correspond to a source module → plugin.

---

## Loader chain — right-to-left, bottom-to-top

```js
{
  test: /\.scss$/,
  use: ['style-loader', 'css-loader', 'sass-loader'],
}
```

Execution order: `sass-loader` → `css-loader` → `style-loader`.

Reason: each loader receives the previous loader's output. Sass compiles to CSS; `css-loader` parses it into a JS module (resolving `@import`, `url()`); `style-loader` wraps that module so importing it injects a `<style>` tag at runtime.

Two-phase execution:

1. **Pitch phase** — left-to-right. Each loader's `pitch` method (if defined) fires. A pitching loader can short-circuit the chain by returning a value.
2. **Normal phase** — right-to-left. Each loader's default export runs, receiving the previous loader's output.

Mental model: pitching is a "descent"; normal loaders are the "ascent" back up. `style-loader` uses pitching to inline its runtime and skip re-processing CSS on the way back up.

---

## Loader configuration

```js
{
  test: /\.tsx?$/,
  exclude: /node_modules/,
  use: [
    {
      loader: 'swc-loader',
      options: {
        jsc: {
          transform: { react: { runtime: 'automatic', refresh: true } },
          parser: { syntax: 'typescript', tsx: true },
        },
      },
    },
  ],
}
```

`use` can be:

- a string — `'babel-loader'`
- an object — `{ loader, options }`
- an array — a chain, applied right-to-left

Options are passed to the loader via `this.getOptions()` (validated against a schema if the loader ships one).

---

## Rule matching

Fields for narrowing which files a rule applies to:

- `test` — regex against the absolute path of the resource
- `include` — regex/string; only match if the path is inside
- `exclude` — regex/string; skip if the path is inside
- `resourceQuery` — match against the `?query` portion of the request
- `issuer` — match if the *importer* matches (useful for "apply this loader only when imported from src/")
- `oneOf` — pick the **first** matching sub-rule (mutually exclusive rules; unlike top-level rules, which are all applied)

```js
{
  test: /\.svg$/,
  oneOf: [
    { resourceQuery: /react/, use: '@svgr/webpack' },
    { type: 'asset/resource' },   // fallback
  ],
}
```

With that config: `import Icon from './x.svg?react'` gives you a React component; `import url from './x.svg'` gives you the emitted URL.

Also useful: `resource`, `descriptionData` (match against `package.json` fields), and negated versions like `not`, `and`, `or` for composite conditions.

---

## Inline loaders and the ! syntax

Loaders can be specified inline on an import, overriding config:

```js
import x from '!!raw-loader!./file.txt';
```

Prefixes control which configured loaders are still applied:

- `!!` — disable **all** normal, pre, and post loaders configured for this file
- `-!` — disable pre and normal loaders (post loaders still run)
- `!` — disable normal loaders only (pre + post still run)
- (no prefix) — inline loaders are prepended to the configured chain

Modern preference: use `resourceQuery` in config instead of inline loaders — cleaner, keeps the pipeline discoverable, and doesn't leak build-tool syntax into application code.

---

## enforce: 'pre' | 'post'

```js
{
  test: /\.js$/,
  enforce: 'pre',
  use: 'eslint-loader',
}
```

`pre` runs before non-enforced loaders. `post` runs after. Useful for:

- **Linting** — `enforce: 'pre'` so lint sees the original source before Babel/SWC rewrites it
- **Source-map processing** — `source-map-loader` as `enforce: 'pre'` to pick up upstream maps
- **Coverage instrumentation** — `enforce: 'post'` to wrap already-transformed code

Ordering across enforce buckets: `pre` → normal → inline → `post` (but each bucket still processes right-to-left within itself).

---

## Common loader packages

| Loader | Purpose |
|--------|---------|
| `babel-loader` | Babel transforms |
| `swc-loader` | SWC transforms |
| `ts-loader` | tsc-based TS transforms |
| `css-loader` | Parse CSS into JS modules |
| `style-loader` | Inject CSS into `<style>` tags |
| `sass-loader`, `less-loader` | Preprocessor pipelines |
| `postcss-loader` | PostCSS transforms |
| `file-loader` (legacy) | Emit files with hash |
| `url-loader` (legacy) | Inline as data URL below threshold |
| `@svgr/webpack` | SVG → React component |
| `raw-loader` | Import as string |

Note: `file-loader` / `url-loader` / `raw-loader` are legacy in Webpack 5 — use **asset modules** (`type: 'asset'`) instead. Cross-link [[Build Tools Compilers - Babel Internals]] for how `babel-loader` bridges Webpack's per-file model into Babel's AST pipeline.

---

## Common plugin packages

| Plugin | Purpose |
|--------|---------|
| `HtmlWebpackPlugin` | Generate HTML with script tags |
| `MiniCssExtractPlugin` | Extract CSS to files |
| `DefinePlugin` (built-in) | Static replace of identifiers |
| `ProvidePlugin` (built-in) | Auto-import when identifier used |
| `CopyWebpackPlugin` | Copy static files |
| `BundleAnalyzerPlugin` | Visualize bundle |
| `ForkTsCheckerWebpackPlugin` | Run tsc in parallel |
| `DllPlugin` (legacy) | Pre-built vendor DLL |
| `ModuleFederationPlugin` (built-in) | Runtime module sharing |

Notice: several **plugins ship a companion loader** — `MiniCssExtractPlugin.loader` replaces `style-loader` in the chain; `HtmlWebpackPlugin` has no loader because its work is purely emission. This is the clearest signal of the split: transformation on the way in (loader), lifecycle work on the way out (plugin).

---

## Asset Modules — the built-in replacement

Webpack 5 built-in, no loaders needed:

```js
{
  test: /\.png$/,
  type: 'asset',              // auto: asset/inline if < 8KB, else asset/resource
}
{
  test: /\.svg$/,
  type: 'asset/source',       // as raw string
}
```

Types:

- `asset/resource` — emit file, return URL (replaces `file-loader`)
- `asset/inline` — inline as data URL (replaces `url-loader`)
- `asset/source` — inline as string (replaces `raw-loader`)
- `asset` (default) — auto-pick between resource and inline based on `parser.dataUrlCondition.maxSize` (default 8 KiB)

Configure the emitted filename with `output.assetModuleFilename` or per-rule `generator.filename`. Prefer asset modules over the legacy loaders in any Webpack 5+ project — faster, no extra deps, integrated with the module graph.

---

## Common mistakes

```
❌ "I need a plugin to transform TS"
✅ Use a loader — plugins don't see per-file source

❌ "I need a loader to extract CSS to a file"
✅ MiniCssExtractPlugin handles emit (a lifecycle event); its loader replaces style-loader

❌ Loader chain in wrong order
✅ Remember: right-to-left. sass-loader FIRST (compiles .scss → css)
```

More subtle ones:

- **Confusing `include` and `test`** — `test` narrows *what kind of file*, `include` narrows *where it lives*. Use both together for tight rules.
- **Forgetting `this.addDependency`** — if your loader reads an external file (a config, a `.env`, a partial), watch-mode won't invalidate on changes to it unless you declare the dependency.
- **Mutating options inside the loader** — options are shared across invocations. Clone before mutating, or you'll get race conditions in parallel builds.
- **Plugin that reads `compilation.assets` too early** — modifications made after `emit` are ignored. Tap `compilation.hooks.processAssets` with the right `stage` instead.

---

## Related

- [[Build Tools Webpack - Core Concepts]]
- [[Build Tools Webpack - Compiler and Compilation]]
- [[Build Tools Foundations - AST and Transform Pipelines]]
- [[Build Tools Compilers - Babel Internals]]
- [[Build Tools Webpack Guide]]
