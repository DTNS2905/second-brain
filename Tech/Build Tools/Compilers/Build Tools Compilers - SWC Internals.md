---
tags:
  - build-tools
  - compilers
  - swc
  - rust
  - tooling
  - frontend
created: 2026-07-16
source: https://swc.rs/docs/configuration/swcrc
---

# Build Tools Compilers — SWC Internals

> Rust-based drop-in for Babel. 20× faster on typical TS/JSX transforms. The default compiler in Next.js since v12, and increasingly in Vite via @vitejs/plugin-react-swc. Part of [[Build Tools Compilers Guide]].

---

## What SWC is

- Rust implementation of a JS/TS compiler (Speedy Web Compiler)
- Same three-phase shape as Babel: **parse → transform → generate**
- Not 1-to-1 API compatible with Babel; some Babel plugins have SWC ports, many don't
- Ships as a native binary + NAPI bindings for Node.js

The public surface is a single `.swcrc` config and a small `@swc/core` API. Everything the JS caller sees is a thin JSON-in / JSON-out wrapper around the Rust core.

---

## Speed factors

1. **Rust compilation** — no JS runtime overhead. The parser, transformer, and codegen run as compiled native code, not interpreted V8.
2. **Parallelism** — SWC parses multiple files across threads. Babel is single-threaded per file and single-threaded across files (unless the host tool orchestrates workers, which most don't).
3. **Native ASTs** — struct-based, cache-friendly memory layout. No dynamic-language overhead per node access.
4. **Sink/source data flow** — passes are chained via visitors on the same AST arena; minimal allocation between passes.

Typical benchmarks show **20× faster than Babel on medium projects** and up to **70× faster on parse-heavy workloads**. On a Next.js app of ~1500 modules, cold-start compile drops from ~15s (Babel) to ~700ms (SWC).

---

## `.swcrc` configuration

```json
{
  "jsc": {
    "parser": {
      "syntax": "typescript",
      "tsx": true,
      "decorators": true
    },
    "target": "es2022",
    "transform": {
      "react": {
        "runtime": "automatic",
        "development": false,
        "refresh": true
      }
    },
    "minify": {
      "compress": true,
      "mangle": true
    }
  },
  "module": {
    "type": "es6"
  },
  "sourceMaps": true
}
```

Everything nests under `jsc` (JavaScript compiler). `module` and `sourceMaps` are top-level because they're codegen concerns, not compiler concerns.

---

## Parser

Choose the syntax family up front — you cannot mix TS and Flow in one pass:

- `syntax: 'ecmascript'` with feature toggles (`jsx`, `numericSeparator`, `classPrivateProperties`, etc.)
- `syntax: 'typescript'` with `tsx: true` for TSX files

```json
{
  "jsc": {
    "parser": {
      "syntax": "typescript",
      "tsx": true,
      "decorators": true,
      "dynamicImport": true
    }
  }
}
```

Decorators, top-level await, class fields, private methods — all opt-in via parser flags. Unknown syntax fails hard instead of silently downgrading (unlike Babel's more permissive parser).

---

## Transforms

Built-in transforms cover the common React app needs without any plugin install:

| Transform | Config path | Purpose |
|-----------|-------------|---------|
| JSX (classic) | `jsc.transform.react.runtime: 'classic'` | Legacy `React.createElement` |
| JSX (automatic) | `jsc.transform.react.runtime: 'automatic'` | JSX 4 runtime, no React import needed |
| Fast Refresh | `jsc.transform.react.refresh: true` | HMR signatures for `react-refresh` |
| Constant elements | `jsc.transform.constModules` | Hoist static JSX outside render |
| Type erasure | Automatic under `syntax: 'typescript'` | Strip types |
| remove-prop-types | `jsc.transform.reactRemoveProperties` | Dev-only removal |

---

## Fast Refresh transform

```json
{ "jsc": { "transform": { "react": { "refresh": true } } } }
```

Inserts the `$RefreshSig$` and `$RefreshReg$` calls that the React Refresh runtime consumes at HMR time. Output shape is identical to `react-refresh/babel` — the runtime doesn't know which compiler produced it.

Only enable in dev builds; the extra calls bloat prod output. See [[Build Tools Dev Server and HMR - React Fast Refresh]] for how the runtime side works.

---

## SWC in Next.js

Since Next 12, SWC is the default compiler:

- **Replaces Babel entirely by default** — Next removes Babel from `node_modules` at install time for perf
- **Adding a `.babelrc` opts back in to Babel** — slower, useful only when you need a plugin SWC doesn't have
- **Next-specific SWC transforms** exposed through `next.config.js`:

```js
// next.config.js
module.exports = {
  compiler: {
    styledComponents: true,
    emotion: true,
    relay: { src: './', artifactDirectory: './__generated__' },
    removeConsole: { exclude: ['error'] },
    reactRemoveProperties: true
  }
};
```

Each of those is a native SWC pass compiled into Next's fork of `@swc/core`. See [[Build Tools Meta-frameworks - Next.js Build Pipeline]] for how Next drives SWC per-route.

---

## SWC in Vite

Two React plugin choices, pick one at project init:

| Plugin | Compiler | Trade-off |
|--------|----------|-----------|
| `@vitejs/plugin-react` | Babel | Slower dev + build, full plugin ecosystem |
| `@vitejs/plugin-react-swc` | SWC | Much faster, limited plugin surface |

```ts
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';

export default defineConfig({
  plugins: [react()]
});
```

Choose SWC unless you specifically need a Babel plugin — the most common blocker in 2026 is the React Compiler, which is still Babel-only.

---

## Plugin system — WASM plugins

SWC plugins are **compiled to WASM** and loaded by the host at runtime. This lets Rust-authored plugins run inside the JS-hosted SWC without shipping per-platform binaries.

```rust
use swc_core::ecma::ast::Program;
use swc_core::plugin::plugin_transform;

#[plugin_transform]
pub fn process(program: Program, _metadata: TransformPluginProgramMetadata) -> Program {
    // Walk the AST, apply transforms, return modified program
    program
}
```

Register in `.swcrc`:

```json
{
  "jsc": {
    "experimental": {
      "plugins": [
        ["@my-org/swc-plugin-thing", { "someOption": true }]
      ]
    }
  }
}
```

Currently **experimental** — the WASM ABI has broken between minor versions historically, so plugins pin exact SWC versions. Compare to Babel's JS-based plugin ecosystem which has thousands of plugins and a stable-ish visitor API since 2015.

---

## Babel-plugin gaps

SWC does **not** cover, as of 2026:

- ❌ **React Compiler** — Babel-only, SWC port on the roadmap but not landed
- ❌ **Emotion** (some patterns) — needs the dedicated Emotion SWC plugin
- ❌ **Any custom Babel plugin your team wrote** — port to WASM/Rust required
- ❌ **`babel-plugin-macros`** — no SWC equivalent, whole macro ecosystem is dead in SWC land
- ❌ **jscodeshift codemods** — Babel-AST-based; SWC has its own experimental codemod tool but no ecosystem

For projects heavily invested in `babel-plugin-macros` (e.g., preval, styled-components css-prop macros), migrating is a rewrite.

---

## Migrating a Babel config

Rough mapping for the common presets:

| Babel | SWC |
|-------|-----|
| `@babel/preset-typescript` | `jsc.parser: { syntax: 'typescript' }` |
| `@babel/preset-react` | `jsc.transform.react` |
| `@babel/preset-env` | `jsc.target: 'es2020'` (uses `.browserslistrc` in some setups) |
| `@babel/plugin-transform-runtime` | Handled automatically by SWC |
| `@babel/plugin-proposal-decorators` | `jsc.parser.decorators: true` |
| `babel-plugin-styled-components` | `jsc.experimental.plugins` or Next's `compiler.styledComponents` |
| Custom transform | Requires WASM plugin or rewrite |

Example: minimal Babel → SWC translation:

✅ SWC:
```json
{
  "jsc": {
    "parser": { "syntax": "typescript", "tsx": true },
    "target": "es2020",
    "transform": { "react": { "runtime": "automatic" } }
  }
}
```

❌ Babel equivalent (slower, more config):
```json
{
  "presets": [
    ["@babel/preset-env", { "targets": { "esmodules": true } }],
    "@babel/preset-typescript",
    ["@babel/preset-react", { "runtime": "automatic" }]
  ]
}
```

---

## SWC's other outputs

The SWC project is more than a Babel replacement — it ships a family of tools sharing the same Rust core:

- **`swc-minify`** — replaces Terser; 5–10× faster, similar output size
- **`swc-loader`** — Webpack loader; drop-in replacement for `babel-loader`
- **`@swc/register`** — Node.js require hook; replaces `@babel/register` for on-the-fly transpile
- **`@swc/wasm`** — browser + Deno build; runs SWC entirely in a WASM sandbox
- **`swc-node`** — direct Node.js runtime with TS support, competes with `ts-node` and `tsx`

Example Webpack config:

```js
// webpack.config.js
module.exports = {
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: {
          loader: 'swc-loader',
          options: {
            jsc: {
              parser: { syntax: 'typescript', tsx: true },
              target: 'es2020'
            }
          }
        }
      }
    ]
  }
};
```

---

## When to still use Babel

- ✅ **React Compiler** — until SWC ports it
- ✅ **Complex custom plugins your team maintains** — cost of WASM port may not be worth it
- ✅ **Codemods and jscodeshift work** — the tooling assumes Babel AST
- ✅ **`babel-plugin-macros` ecosystem** — no SWC equivalent
- ❌ **Plain TS/JSX transforms** — SWC is dramatically faster; no reason to stay on Babel

For most Next.js and Vite projects starting in 2026, SWC is the default and Babel is opt-in only when a specific plugin forces it.

---

## Related

- [[Build Tools Compilers - Babel Internals]]
- [[Build Tools Compilers - JSX and React Transforms]]
- [[Build Tools Meta-frameworks - Next.js Build Pipeline]]
- [[Build Tools Vite - Architecture Overview]]
- [[Build Tools Compilers Guide]]
