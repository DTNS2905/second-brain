---
tags:
  - build-tools
  - webpack
  - internals
  - tooling
  - frontend
created: 2026-07-16
source: https://webpack.js.org/api/compiler-hooks/
---

# Build Tools Webpack — Compiler and Compilation

> Webpack's architecture: a long-lived Compiler orchestrating per-run Compilations, with Tapable hooks everywhere for plugins to interpose. Understanding this shape lets you read and write plugins fluently. Part of [[Build Tools Webpack Guide]].

---

## The two-level architecture

Webpack splits its runtime into two distinct objects with different lifetimes:

- **Compiler** — created once per Webpack invocation. Lives for the duration of the process (watch mode: many compilations). Owns configuration, resolvers, the plugin registry, and the file system abstraction. It is the *conductor*.
- **Compilation** — one per run. Owns modules, chunks, assets, and stats for that build. It is *the build itself*, discarded and re-created on each rebuild in watch mode.

```
Compiler (long-lived)
  ├── config
  ├── resolvers
  ├── plugins (via hooks)
  └── produces → Compilation (per run)
                   ├── modules
                   ├── chunks
                   ├── assets
                   └── stats
```

A plugin's `apply(compiler)` runs once. Any per-build logic must be attached via `compiler.hooks.compilation` or `compiler.hooks.thisCompilation`, which fire each time a new Compilation is created.

---

## Tapable — the hook library

Webpack's plugin system is built on [Tapable](https://github.com/webpack/tapable). Every hook is one of the following types, each with different callback semantics:

| Hook type | Callback semantic |
|-----------|-------------------|
| `SyncHook` | Run all callbacks; no return |
| `SyncBailHook` | Stop on first non-undefined return |
| `SyncWaterfallHook` | Thread output of each into the next |
| `AsyncSeriesHook` | Callbacks run in order, async |
| `AsyncParallelHook` | Callbacks run in parallel |
| `AsyncSeriesWaterfallHook` | Async waterfall |
| `AsyncSeriesBailHook` | Async bail |

Which type a hook is determines *how* you tap it: `tap()` for sync, `tapAsync()` for callback-style async, `tapPromise()` for promise-returning async.

Plugin authoring pattern:

```js
class MyPlugin {
  apply(compiler) {
    compiler.hooks.compile.tap('MyPlugin', (params) => {
      // sync work
    });

    compiler.hooks.emit.tapAsync('MyPlugin', (compilation, cb) => {
      // async work
      cb();
    });

    compiler.hooks.done.tapPromise('MyPlugin', async (stats) => {
      // promise-based async
    });
  }
}
```

The first argument to `tap*` is the plugin name — used in stack traces, profiling, and stage ordering. Always use your class name.

❌ Wrong hook method:

```js
compiler.hooks.emit.tap('MyPlugin', (compilation) => {
  // emit is AsyncSeriesHook — sync tap is allowed but you can't await
});
```

✅ Match the hook type:

```js
compiler.hooks.emit.tapPromise('MyPlugin', async (compilation) => {
  await writeSideChannel(compilation);
});
```

---

## Compiler hooks (selected)

The Compiler exposes a large fixed set of hooks. The lifecycle roughly:

```
beforeRun          - before non-watch run
run                - non-watch run start
watchRun           - watch-mode run start
beforeCompile
compile            - a new Compilation is about to be created
thisCompilation    - Compilation about to be initialized (this build)
compilation        - Compilation created (also fires for child compilations)
make               - graph creation phase
afterCompile
emit               - about to write files
afterEmit
done               - build complete
watchClose         - watcher closed
```

Two crucial distinctions:

- `thisCompilation` fires **only** for the top-level Compilation, not for child compilations. Use it when a plugin should not recurse into HtmlWebpackPlugin's internal build, etc.
- `compilation` fires for **both** the main and child compilations. Use it when you want your plugin to apply everywhere.

- `run` vs `watchRun` — the former is a single build, the latter a rebuild triggered by file change. Watch mode never fires `run`.

---

## Compilation hooks (selected)

The Compilation object exposes even more hooks, covering the fine-grained build lifecycle:

```
buildModule        - a module is about to be built
succeedModule      - a module was built
finishModules      - all modules built
seal               - graph frozen; chunk graph next
optimize           - post-seal optimizations
optimizeChunks
afterOptimizeChunks
moduleAsset        - module has produced an asset
chunkAsset         - chunk has produced an asset
afterCodeGeneration
processAssets      - the modern place to modify assets
afterProcessAssets
```

The mental model: modules are built → the graph is sealed → chunks form → optimizations run → assets are emitted. Each transition is a hook.

Note that `optimize*` hooks fire after seal — you can rearrange chunks but not add modules.

---

## NormalModuleFactory

Modules aren't built directly by the Compilation; they're constructed by *factories*. `NormalModuleFactory` is responsible for creating `NormalModule` instances (i.e., `.js`/`.ts`/`.css` files — anything not a `ContextModule` or `ExternalModule`).

Key hooks:

```
beforeResolve
resolve
afterResolve
createModule
module
parser              - fires when parser needed
```

Access it from `compilation`:

```js
compiler.hooks.compilation.tap('MyPlugin', (compilation, { normalModuleFactory }) => {
  normalModuleFactory.hooks.parser.for('javascript/auto').tap('MyPlugin', (parser) => {
    parser.hooks.import.tap('MyPlugin', (statement, source) => {
      // observe every ES import in every JS file
    });
  });
});
```

The `.for(type)` pattern is a `HookMap` — a factory of hooks keyed by module type. Common types: `javascript/auto`, `javascript/esm`, `javascript/dynamic`, `json`, `webassembly/sync`.

---

## Module vs Chunk graph

Webpack maintains two related graphs. Do not conflate them:

- **Module graph** — one node per source file. Edges are dependencies (imports, requires, `import()` calls). Built during `make`.
- **Chunk graph** — one node per chunk (post-splitting). Edges represent chunk parent/child relationships (dynamic imports create chunk-to-chunk edges).

Chunks contain modules; modules belong to one or more chunks. A shared vendor module might live in a single `vendors` chunk referenced by every entry.

```
Module graph:              Chunk graph:
  entry.js                   main chunk
    → utils.js                 ├── entry.js
    → vendor/react              └── utils.js
  admin.js                   admin chunk
    → utils.js                 └── admin.js
    → vendor/react           vendors chunk (shared)
                               └── react
```

Cross-link `[[Build Tools Foundations - The Dependency Graph]]`.

---

## The sealing phase

Sealing is the pivotal moment in a build. Before seal, the module graph is mutable; after seal, it is frozen and only assets can change.

```
Modules built → graph complete → SEAL
  → chunks created (splitChunks)
  → optimizations run (tree shaking, side-effect analysis, minification)
  → code generation
  → assets emitted
```

After seal, modules can no longer be added. Plugins targeting graph mutation must run before seal — typically in `finishModules` or during `NormalModuleFactory` hooks. Plugins targeting output must run after seal — in `processAssets`.

❌ Adding a module during `processAssets`:

```js
compilation.hooks.processAssets.tap('MyPlugin', () => {
  compilation.addModule(new NormalModule(...)); // too late
});
```

✅ Add via `make` or `finishModules`:

```js
compilation.hooks.finishModules.tapAsync('MyPlugin', (modules, cb) => {
  compilation.addModule(newModule, cb);
});
```

---

## processAssets — the "modify output" hook

`processAssets` is the modern replacement for the older `emit` hook. It has an explicit **stage** parameter so plugins can order themselves relative to one another rather than relying on plugin registration order.

```js
const { Compilation } = require('webpack');

compilation.hooks.processAssets.tap(
  {
    name: 'MyPlugin',
    stage: Compilation.PROCESS_ASSETS_STAGE_OPTIMIZE_INLINE,
  },
  (assets) => {
    for (const name of Object.keys(assets)) {
      // mutate assets[name]
    }
  }
);
```

Stages (from earliest to latest):

- `ADDITIONAL` (add extra assets)
- `PRE_PROCESS`
- `DERIVED`
- `ADDITIONS`
- `OPTIMIZE`
- `OPTIMIZE_INLINE`
- `SUMMARIZE`
- `OPTIMIZE_HASH`
- `OPTIMIZE_TRANSFER`
- `ANALYSE` (read-only)
- `REPORT` (last)

Rules of thumb:

- Adding new files → `ADDITIONAL` or `ADDITIONS`
- Rewriting content (inlining CSS, source maps) → `OPTIMIZE_INLINE`
- Minification → `OPTIMIZE`
- Hashing (integrity attributes) → `OPTIMIZE_HASH`
- Compression (gzip/brotli) → `OPTIMIZE_TRANSFER`
- Read-only analysis (bundle stats) → `ANALYSE` or `REPORT`

The constant is exported from Webpack as `Compilation.PROCESS_ASSETS_STAGE_*`, and also available on the compilation instance as `compilation.PROCESS_ASSETS_STAGE_*`.

---

## Child compilations

Some plugins create sub-compilations (e.g., HtmlWebpackPlugin renders the HTML via a mini-compilation; MiniCssExtractPlugin extracts CSS via a child compilation). Child compilations inherit config but produce their own outputs and have their own module/chunk graph.

```js
const child = compilation.createChildCompiler(
  'my-child-compiler',
  { filename: 'child-[name].js' },
  [/* plugins */]
);

child.runAsChild((err, entries, childCompilation) => {
  // childCompilation.assets contains child outputs
});
```

Important: `thisCompilation` fires only for the top-level Compilation, but `compilation` fires for children too. If your plugin should be idempotent, tap `thisCompilation` to avoid accidentally recursing into HtmlWebpackPlugin's internal build.

---

## Loaders don't tap hooks

A common conceptual mistake: loaders are **not** plugins. Loaders are per-file functions invoked during module build. They receive source content, return transformed content, and have no access to compilation-lifecycle hooks.

```js
// loader.js
module.exports = function (source) {
  // no compiler, no compilation, no hooks
  return source.replace(/foo/g, 'bar');
};
```

If you need lifecycle access — e.g., "run once after all CSS modules are extracted" — write a plugin instead. Cross-link `[[Build Tools Webpack - Loaders vs Plugins]]`.

Loaders *do* receive a `LoaderContext` (`this` inside the loader function) with access to `this._compilation` and `this._compiler`, but reaching into these is a documented escape hatch, not a supported extension surface.

---

## Watching

In watch mode, the Compiler keeps a persistent instance and re-runs Compilations. Between compilations:

- The module cache is preserved for unchanged files
- Resolver caches persist
- The file system watcher tracks dependencies and produces a *changed files* list
- Plugins that keep state on the Compiler survive across builds; plugins that keep state on the Compilation are re-instantiated

```
compiler.watch(options, (err, stats) => { ... });
// vs
compiler.run((err, stats) => { ... });
```

`watchRun` fires at the start of each rebuild; `watchClose` fires when the watcher is torn down. Note that `run` does *not* fire in watch mode — this trips up plugins that use `run` as their "build starting" signal. Use `beforeCompile` or `compile` if you need something that fires for both.

---

## Plugin authoring — a full example

A plugin that emits a `build-info.json` alongside the bundle, containing the build timestamp and content hash:

```js
class BuildInfoPlugin {
  apply(compiler) {
    compiler.hooks.thisCompilation.tap('BuildInfoPlugin', (compilation) => {
      compilation.hooks.processAssets.tap(
        {
          name: 'BuildInfoPlugin',
          stage: compilation.PROCESS_ASSETS_STAGE_ADDITIONAL,
        },
        () => {
          const info = JSON.stringify({
            time: Date.now(),
            hash: compilation.hash,
          }, null, 2);
          compilation.emitAsset(
            'build-info.json',
            new webpack.sources.RawSource(info)
          );
        }
      );
    });
  }
}
```

Key observations:

- `thisCompilation` — we don't want the child compilations of HtmlWebpackPlugin to also emit `build-info.json`
- `PROCESS_ASSETS_STAGE_ADDITIONAL` — we are *adding* an asset, not modifying existing ones
- `compilation.emitAsset(name, source)` — the correct API for adding a new asset
- `webpack.sources.RawSource` — one of several source classes (`RawSource`, `OriginalSource`, `SourceMapSource`, `ConcatSource`) that Webpack understands

---

## Debugging plugins

Common approaches when a plugin misbehaves:

```
DEBUG=webpack:plugin webpack build
NODE_OPTIONS='--inspect-brk' webpack build   # attach debugger
stats: 'verbose'                             # detailed output
```

Additional techniques:

- `compilation.errors.push(new Error(...))` and `compilation.warnings.push(...)` surface plugin issues in the standard Webpack output
- Set `profile: true` on the config to get per-hook timing
- Use the `--progress` CLI flag to see which hooks are firing
- Log inside a `done` handler to see final stats: `compiler.hooks.done.tap(...)` receives a `Stats` object

❌ Throwing inside a hook silently kills the build:

```js
compilation.hooks.processAssets.tap('MyPlugin', () => {
  throw new Error('boom'); // hard to trace
});
```

✅ Push to `compilation.errors` for a clean stack trace and non-zero exit code:

```js
compilation.hooks.processAssets.tap('MyPlugin', () => {
  compilation.errors.push(new Error('MyPlugin: something went wrong'));
});
```

---

## Related

- [[Build Tools Webpack - Core Concepts]]
- [[Build Tools Webpack - Loaders vs Plugins]]
- [[Build Tools Bundlers - Rollup Internals]] — compare plugin surface
- [[Build Tools Webpack Guide]]
