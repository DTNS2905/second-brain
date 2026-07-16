---
tags:
  - build-tools
  - compilers
  - babel
  - tooling
  - frontend
created: 2026-07-16
source: https://babeljs.io/docs/plugins
---

# Build Tools Compilers — Babel Internals

> Babel's three-phase pipeline (parser → traverse → generator), its preset/plugin ordering rules, and why it's still the compiler you reach for when you need custom AST transforms. Part of [[Build Tools Compilers Guide]].

---

## The three packages

Babel is not a monolith — it's a small orchestrator (`@babel/core`) coordinating three focused packages, each of which can be used standalone.

- `@babel/parser` — source → AST (fork of Acorn, ESTree-compatible with Babel extensions)
- `@babel/traverse` — visitor-based AST walker with mutation helpers and scope tracking
- `@babel/generator` — AST → source (+ source map)

`@babel/core` orchestrates them and loads configs/plugins. Every transform Babel performs passes through this pipeline:

```
source  ─►  parser  ─►  AST  ─►  traverse (plugins mutate)  ─►  AST'  ─►  generator  ─►  source' + map
```

See [[Build Tools Foundations - AST and Transform Pipelines]] for the general shape of this pipeline.

---

## Parse phase

```js
import { parse } from '@babel/parser';

const ast = parse(source, {
  sourceType: 'module',
  plugins: ['jsx', 'typescript', 'decorators-legacy'],
});
```

Parser plugins are **syntax parsers** (enable JSX, TS, decorators, `import assertions`, etc.). They are distinct from Babel plugins (transform plugins) — they don't transform anything, they only teach the parser to accept new syntax.

Options worth knowing:

| Option | Effect |
|--------|--------|
| `sourceType: 'module'` | Enables `import`/`export`, strict mode |
| `sourceType: 'unambiguous'` | Auto-detect module vs script |
| `allowReturnOutsideFunction` | Useful for REPL-like transforms |
| `errorRecovery: true` | Return partial AST with `.errors` instead of throwing |
| `attachComment: false` | Faster if you don't need comments (e.g., production build) |

The AST format is documented in the Babel AST spec (`@babel/types` package). Every node has a `type` and, depending on type, typed child fields.

---

## Visitor pattern (traverse)

Plugins are just objects with a `visitor` field. Babel walks the AST depth-first; when the walker enters or exits a node whose type matches a visitor key, your handler runs.

```js
module.exports = ({ types: t }) => ({
  name: 'add-header',
  visitor: {
    Program: {
      enter(path) {
        path.unshiftContainer('body', t.expressionStatement(t.stringLiteral('use strict')));
      },
    },
  },
});
```

`path` is not the node — it's a wrapper carrying context (parent, scope, siblings, remove/replace methods). This is what makes Babel plugins composable.

Key `path` API:

| Member | Purpose |
|--------|---------|
| `.node` | The underlying AST node |
| `.parent` / `.parentPath` | Immediate parent node / path |
| `.replaceWith(newNode)` | Swap this node for another |
| `.remove()` | Delete this node |
| `.get('childName')` | Navigate to a child `path` |
| `.scope` | Lexical scope (variable bindings, references) |
| `.hub` | File-level context (options, comments, filename) |
| `.traverse(subVisitor)` | Walk this subtree with a nested visitor |
| `.skip()` | Don't descend into this node's children |

The `scope` object is what makes rename/inline safe:

```js
Identifier(path) {
  const binding = path.scope.getBinding(path.node.name);
  if (!binding) return;               // undeclared reference
  if (binding.references > 1) return; // referenced elsewhere — don't inline
  // safe to transform
}
```

---

## Generator phase

Produces code + source map. The generator is intentionally boring — it walks the AST and prints tokens. Configuration is limited to formatting concerns.

```js
import generate from '@babel/generator';

const { code, map } = generate(ast, {
  compact: false,
  retainLines: false,
  minified: false,
  jsescOption: { minimal: true },
  sourceMaps: true,
}, source);
```

| Option | Effect |
|--------|--------|
| `compact` | No whitespace between tokens |
| `retainLines` | Preserve original line numbers (useful for stack traces without a source map) |
| `minified` | Shorthand for compact + no comments |
| `jsescOption` | Controls how strings are escaped (Unicode preservation) |
| `sourceMaps` | Emit a v3 source map alongside code |

Babel does not minify — that's Terser/SWC's job. Babel's `minified: true` only skips whitespace, not identifier mangling or dead-code elimination.

---

## Plugin ordering rules

The single most confusing thing about Babel. Three rules, memorize them:

1. **Plugins run before presets.**
2. **Plugins run in order** (top-down, as written).
3. **Presets run in reverse order** (last-defined runs first).

```js
// babel.config.js
module.exports = {
  plugins: [
    'p1',   // 1st
    'p2',   // 2nd
  ],
  presets: [
    '@babel/preset-env',        // 4th (runs last)
    '@babel/preset-typescript', // 3rd
  ],
};
```

**Why the reversed preset order?** Presets are defined intuitively "high-level to low-level" — you write `preset-env` first because it's the "main" thing, then `preset-typescript` as a supplement. But you want low-level to run first (TypeScript erasure before ES2015 lowering, otherwise `preset-env` would choke on `interface` syntax). Reversing the array makes both the writing order and the execution order feel natural.

This ordering also applies per-visitor: within a single AST walk, plugins/presets are merged into one master visitor, and for each node type, handlers run in the resolved order.

---

## @babel/preset-env

The "compile to the browsers I care about" preset. It reads a `browserslist` config and enables only the syntax + polyfill transforms needed for those targets.

```
# .browserslistrc
> 0.5%
last 2 versions
not dead
```

```js
// babel.config.js
{
  presets: [
    ['@babel/preset-env', {
      targets: '> 0.5%, last 2 versions, not dead',
      useBuiltIns: 'usage',
      corejs: 3,
      modules: false,  // leave ESM alone — let the bundler handle it
    }],
  ],
}
```

| Option | Effect |
|--------|--------|
| `targets` | Browserslist query — the compile target |
| `modules` | `'auto' \| 'cjs' \| 'amd' \| false` — set to `false` for tree-shaking bundlers |
| `useBuiltIns` | `'usage'` injects only the polyfills each file uses; `'entry'` requires a manual import; `false` skips polyfilling |
| `corejs` | Version of core-js providing polyfills (usually 3) |
| `debug: true` | Prints which plugins were included based on targets |

**Without a targets config, preset-env defaults to ES5**, producing dramatically larger output than modern targets need. Always set targets explicitly.

---

## @babel/preset-react

Handles JSX. Three runtime modes:

- `runtime: 'classic'` — the old default. JSX → `React.createElement(…)`. Requires `React` in scope in every file.
- `runtime: 'automatic'` — modern (React 17+, released 2020). JSX → `_jsx(…)` imported from `react/jsx-runtime`. **No React import needed.**
- `development: true` — adds `__source` (filename/line) and `__self` for better DevTools messages and hook warnings.

```js
{
  presets: [
    ['@babel/preset-react', {
      runtime: 'automatic',
      development: process.env.NODE_ENV !== 'production',
      importSource: 'react',  // or 'preact', '@emotion/react', etc.
    }],
  ],
}
```

`importSource` is what lets Preact, Emotion, and Nano JSX hijack the JSX transform to import from their own runtime module. See [[Build Tools Compilers - JSX and React Transforms]] for a full walk-through.

---

## @babel/preset-typescript

Erases TypeScript syntax. Does **NOT type-check**.

```js
{ presets: ['@babel/preset-typescript'] }
```

Use `tsc --noEmit` (or the IDE) for type checking. This is deliberate: fast builds require decoupling emit from type-checking. The build pipeline erases; a separate `tsc` pass catches errors.

Because Babel doesn't understand types, a few TypeScript features it can't handle:

- `const enum` → falls back to a regular enum unless `optimizeConstEnums` is set
- Namespace merging across files
- Emit-metadata for decorators (needs `@babel/plugin-proposal-decorators` + a metadata plugin)

Cross-link [[Build Tools Compilers - TypeScript as a Transpiler]] for the fuller comparison against `tsc`.

---

## @babel/runtime + helpers

When Babel lowers syntax, it may need runtime helpers — small functions like `_extends`, `_asyncToGenerator`, `_toConsumableArray`, `_classCallCheck`. Two approaches:

**Inline** (default) — helpers are copied into every file that needs them. Simple but bloats the bundle when many files use the same helper.

**`@babel/plugin-transform-runtime` + `@babel/runtime`** — helpers are imported from a shared package. One copy total, deduplicated by the bundler.

```js
{
  plugins: [
    ['@babel/plugin-transform-runtime', {
      corejs: 3,          // also polyfill core-js from the runtime
      helpers: true,      // share helpers (default)
      regenerator: true,  // share the generator runtime
    }],
  ],
}
```

Adds `@babel/runtime-corejs3` as a runtime dependency of your app. Essential for libraries — a library that inlines helpers forces its consumers to ship the helper N times, once per bundled dep.

---

## Authoring a plugin

A plugin is a factory returning `{ name, visitor }`. This one renames all `foo` identifiers to `bar` — except property names in member expressions:

```js
// Rename all `foo` variables to `bar`
module.exports = () => ({
  name: 'rename-foo-to-bar',
  visitor: {
    Identifier(path) {
      if (path.node.name === 'foo' && !path.parentPath.isMemberExpression({ property: path.node })) {
        path.node.name = 'bar';
      }
    },
  },
});
```

The `path.parentPath.isMemberExpression({ property: path.node })` check is the kind of nuance that's easy to miss on a first pass — without it, `obj.foo` becomes `obj.bar`, breaking property access.

A more realistic transform — strip `console.log` calls in production:

```js
module.exports = () => ({
  name: 'strip-console-log',
  visitor: {
    CallExpression(path) {
      const callee = path.get('callee');
      if (
        callee.isMemberExpression() &&
        callee.get('object').isIdentifier({ name: 'console' }) &&
        callee.get('property').isIdentifier({ name: 'log' })
      ) {
        path.remove();
      }
    },
  },
});
```

Reference: Jamie Kyle's "Babel Plugin Handbook" (github.com/jamiebuilds/babel-handbook) — still the definitive guide despite predating a few API additions.

---

## Config file resolution

Babel looks for config files in two flavors, with different scoping rules:

| File | Scope | When to use |
|------|-------|-------------|
| `babel.config.json` / `babel.config.js` | **Project-wide** (applies to `node_modules`) | Monorepos; when you need to transform a specific dep |
| `.babelrc.json` / `.babelrc.js` | **File-relative** (per subtree, closest wins) | Apps where each package configures itself |

**Rule of thumb:** use `babel.config.js` for monorepos or when transforming deps. `.babelrc` won't apply to files in `node_modules` even if you enable `babelrcRoots`.

```js
// babel.config.js — needed to transform an ESM-only dep in node_modules
module.exports = {
  presets: [['@babel/preset-env', { targets: { node: 'current' } }]],
  overrides: [
    {
      test: /node_modules\/some-esm-only-pkg/,
      presets: [['@babel/preset-env', { targets: { node: 'current' } }]],
    },
  ],
};
```

The `overrides` field lets one config file describe different transforms for different subtrees — invaluable for monorepos where an `apps/web` package targets browsers and `apps/api` targets Node.

---

## Why Babel is still relevant

SWC (Rust) and esbuild (Go) have largely replaced Babel for TS/JSX transforms in modern React apps — they're 20–70× faster on the same work. But Babel keeps returning for specific reasons:

- **React Compiler** (`babel-plugin-react-compiler`) — the auto-memoization pass ships as a Babel plugin, at least through 2026
- **Codemods** — jscodeshift is Babel-adjacent; ecosystem tools like `@codeshift/cli`, `putout`, and most Storybook/MDX transforms use Babel
- **Complex custom transforms** — SWC's plugin API is WASM-based and less mature; Babel plugins are JS, easier to author, and can reuse the vast `@babel/*` ecosystem
- **i18n extraction** — Lingui, FormatJS, and similar tools ship as Babel plugins
- **Emotion / styled-components** — display-name and label plugins are Babel-only for now

For most modern React apps: SWC replaces Babel for the TS/JSX transform, but Babel returns when you need a specific plugin. See [[Build Tools Compilers - SWC Internals]] for the Rust side.

---

## Common pitfalls

```
❌ No `targets` in preset-env → outputs ES5, 3× larger bundle
✅ Set browserslist or `targets` explicitly

❌ Preset ordering confusion: `presets: ['@babel/preset-env', '@babel/preset-typescript']`
   — reads left-to-right but env runs LAST (reversed)
✅ Order is fine — last runs first, so TS erasure happens before ES lowering

❌ `include`/`exclude` not set → Babel transforms node_modules (slow)
✅ Exclude node_modules unless you specifically need to transpile a dep

❌ Using `.babelrc` in a monorepo and wondering why deps aren't transformed
✅ Use `babel.config.js` — it's project-wide

❌ `modules: 'commonjs'` in preset-env + a bundler → kills tree-shaking
✅ `modules: false` — let webpack/Rollup/Vite handle module output

❌ Inline helpers in a library (default) → every consumer ships helpers N times
✅ Use `@babel/plugin-transform-runtime` for libraries

❌ Expecting `preset-typescript` to catch type errors
✅ It erases only — run `tsc --noEmit` separately

❌ Mutating `path.node` fields directly and losing sibling paths
✅ Use `path.replaceWith` / `path.replaceWithMultiple` so Babel updates path state
```

---

## Related

- [[Build Tools Foundations - AST and Transform Pipelines]]
- [[Build Tools Compilers - SWC Internals]] — the Rust replacement
- [[Build Tools Compilers - JSX and React Transforms]]
- [[Build Tools Compilers - TypeScript as a Transpiler]]
- [[Build Tools Compilers Guide]]
