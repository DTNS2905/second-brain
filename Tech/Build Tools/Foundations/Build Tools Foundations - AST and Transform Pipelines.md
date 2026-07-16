---
tags:
  - build-tools
  - foundations
  - ast
  - tooling
  - frontend
created: 2026-07-16
source: https://babeljs.io/docs/plugins
---

# Build Tools Foundations — AST and Transform Pipelines

> Every compiler follows the same shape: parse to AST → transform via plugins → generate source. The AST is the shared interchange format; the visitor pattern is how plugins compose; ordering is what causes most bugs. Part of [[Build Tools Foundations Guide]].

---

## The universal shape

Every source-to-source compiler — Babel, SWC, esbuild, tsc, PostCSS — implements the same three-phase pipeline:

```
source code (string)
    ↓  parse
AST (tree of nodes)
    ↓  transform (visitor plugins)
AST' (transformed tree)
    ↓  generate
output code (string) [+ source map]
```

- **Parse** — lexer produces tokens; parser assembles them into a tree.
- **Transform** — plugins walk the tree, mutating or replacing nodes.
- **Generate** — printer serializes the tree back to source, emitting a source map alongside.

The AST is the shared interchange format. Once code is in AST form, any plugin that speaks that AST flavor can transform it — this is what makes Babel's plugin ecosystem possible.

Cross-link [[Build Tools Foundations - Bundlers vs Compilers]] — bundlers orchestrate this pipeline across many files; compilers implement it for one.

---

## AST — what a node looks like

An AST is a tree of typed nodes. Every node has a `type` field; the rest of the fields depend on the type. For the trivial program:

```js
const x = 1;
```

The (simplified) AST is:

```json
{
  "type": "VariableDeclaration",
  "kind": "const",
  "declarations": [{
    "type": "VariableDeclarator",
    "id": { "type": "Identifier", "name": "x" },
    "init": { "type": "Literal", "value": 1 }
  }]
}
```

Key observations:

- The shape is recursive — nodes contain nodes.
- Semantic information lives in fields (`kind: "const"`), not in string tokens.
- Whitespace, comments, and formatting are metadata attached to nodes, not part of the structural tree.

Babel and SWC use **ESTree-flavored** ASTs — a community spec that started as SpiderMonkey's Parser API. They diverge in minor details (field names, TypeScript node shapes, JSX handling), which is why plugins don't cross ecosystems.

**Reference tool:** [astexplorer.net](https://astexplorer.net) — paste code, pick a parser, see the AST live. Indispensable for plugin authoring.

---

## The visitor pattern

A plugin is a set of `NodeType → handler` mappings. The traversal engine walks the tree depth-first and calls the matching handler when it enters (and, optionally, exits) a node.

```js
// Babel plugin — rename all `foo` identifiers to `bar`
module.exports = () => ({
  visitor: {
    Identifier(path) {
      if (path.node.name === 'foo') path.node.name = 'bar';
    }
  }
});
```

`path` is a wrapper around the current node that carries:

- `path.node` — the node itself
- `path.parent` / `path.parentPath` — upward context
- `path.scope` — variable binding info
- Mutation helpers — `path.replaceWith(newNode)`, `path.remove()`, `path.insertBefore(node)`, `path.skip()`

You almost never touch nodes directly — you go through `path` so the traversal engine can track scope, re-visit replaced subtrees, and keep the tree consistent.

The visitor pattern is why plugins compose: two plugins can register handlers for the same node type, and the traversal engine merges them into a single pass. One walk of the tree, many transforms.

---

## Enter vs exit

Visitors can distinguish two phases:

```js
{
  visitor: {
    CallExpression: {
      enter(path) { /* runs before children are visited */ },
      exit(path)  { /* runs after children are visited */ }
    }
  }
}
```

- **enter** — top-down. You see the node before its children have been transformed. Good for early bailouts and structural rewrites.
- **exit** — bottom-up. You see the node after its children have been transformed. Good for aggregating child state or transforming a parent based on what its children became.

The bare-function shorthand `Identifier(path) {}` is `enter`. Use `exit` when your transform depends on child transforms already having run.

✅ Use `exit` for auto-memoization plugins that read the transformed function body.
❌ Don't use `enter` if you need to see child rewrites — you'll see the pre-transform shape.

---

## Plugin ordering

Order matters more than any other single decision in a compiler config. Rules of thumb:

- **Syntax first, semantic last.** Strip TypeScript types before you optimize runtime behavior — semantic passes shouldn't have to know about type syntax.
- **Innermost transforms first.** Decorators before class fields; class fields before class-to-function lowering. Each pass should assume the newer syntax has already been reduced away.
- **JSX before TS erasure** in the classic pipeline — so the JSX handler sees typed JSX. The automatic JSX runtime softens this because it doesn't inspect types.

**Babel's specific rules:**

- `plugins` run **before** `presets`
- `plugins` run in the order listed (first to last)
- `presets` run in **reverse** order (last to first)

```js
// babel.config.js
module.exports = {
  plugins: [
    'my-first-plugin',    // runs 1st
    'my-second-plugin',   // runs 2nd
  ],
  presets: [
    '@babel/preset-env',        // runs 4th (LAST)
    '@babel/preset-typescript'  // runs 3rd
  ]
};
```

The reversed preset order lets you write configs the way humans think: "this project is TypeScript, targeting these browsers" reads naturally as `[preset-env, preset-typescript]` even though TS must be erased before env-lowering runs.

---

## Two AST flavors: Babel vs SWC

Both are ESTree-adjacent, but the trees are not interchangeable:

| Dimension | Babel | SWC |
|-----------|-------|-----|
| Language | JS (self-hosted) | Rust |
| Node fields | ESTree with Babel extensions | ESTree with SWC extensions |
| Plugin API | JS `visitor` object | Rust `Fold`/`VisitMut` traits (WASM plugins experimental) |
| Speed | ~1x baseline | ~20–70x faster |
| TS support | Erasure only | Erasure only |

That difference in field names and node organization is why **Babel plugins don't run in SWC** and vice versa. SWC has ported (but not 1-to-1) many popular Babel plugins into its native Rust codebase — `@swc/plugin-styled-components`, its own `react-refresh`, etc.

Cross-link [[Build Tools Compilers - Babel Internals]], [[Build Tools Compilers - SWC Internals]].

---

## Source map propagation

Every transform must propagate a **source map** — a mapping from output positions back to input positions. Without it, stack traces, `console.log` locations, and debugger breakpoints point to compiled output instead of your source.

```
file.tsx  →  swc     →  file.js + file.js.map
                          ↓
                        bundler
                          ↓
                        bundle.js + bundle.js.map  (chained)
```

The bundler's source map is a **composition** of the per-file source maps. If any layer drops or corrupts its map, everything downstream degrades:

- Missing map → errors point to compiled positions.
- Stale map → breakpoints hit the wrong line.
- Broken chain → dev tools show generated JS instead of TSX.

Every AST-mutating step must return `{ code, map }`. In Babel, if you use `path.replaceWith(newNode)`, source location is copied from the replaced node automatically — but if you build a raw node with `t.callExpression(...)` and no `loc`, you'll lose that mapping.

Cross-link [[Build Tools Foundations - Source Maps]].

---

## Syntax vs semantic transforms

Two categories, with very different risk profiles:

- **Syntax transforms** rewrite one syntactic form into another that behaves identically. JSX → `_jsx()` calls, `const` → `var`, class fields → assignments in constructor, `??` → ternary. Safe, reversible, easy to test.
- **Semantic transforms** change what the code *does*. Auto-injecting polyfills, transforming `for-of` to raw iterator-protocol calls, auto-memoizing components. Riskier — bugs here silently change program meaning.

```js
// Syntax transform — JSX to function call
<Button primary>Click</Button>
// becomes
_jsx(Button, { primary: true, children: 'Click' });

// Semantic transform — auto-memoization (React Compiler)
function Row({ data }) {
  const sorted = data.sort();
  return <div>{sorted}</div>;
}
// becomes (conceptually)
function Row({ data }) {
  const $ = _cache(1);
  const sorted = $[0] !== data ? ($[0] = data, data.sort()) : $[1];
  return _jsx('div', { children: sorted });
}
```

Modern React work is almost all syntax — JSX transform, Fast Refresh insertions. **React Compiler is the notable semantic transform** — it changes runtime memoization behavior, not just syntactic form.

---

## Fast Refresh transform

`react-refresh/babel` (and its SWC equivalent, `@swc/plugin-react-refresh`) is a compile-time transform that inserts two things at the tail of each React module:

```js
// After transformation, roughly:
function Counter() { /* ... */ }

_c = Counter;
$RefreshReg$(_c, 'Counter');
var _c;

if (import.meta.hot) {
  import.meta.hot.accept();
  $RefreshSig$()(Counter, /* hook signature */);
}
```

- `$RefreshReg$` — registers the component with the HMR runtime so it can be looked up on reload.
- `$RefreshSig$` — captures a **signature** of the component's hooks; changes to the signature (adding a hook, changing hook order) trigger a full remount instead of a hot swap.

Runs during compilation only in dev mode — the transform is a no-op in production. Cross-link [[Build Tools Dev Server and HMR - React Fast Refresh]].

---

## Common pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Two plugins fighting over the same node | Non-deterministic output; works with cache, breaks on clean build | Explicit ordering; use `enter`/`exit` phases to split responsibilities |
| Plugin doesn't see JSX | JSX passes through untouched | Ensure JSX preset runs before TS preset — or switch to the automatic runtime |
| Source map missing from output | Errors point to compiled positions; DevTools shows generated JS | Enable `sourcemap: true` at every layer (compiler, bundler, minifier) |
| Custom AST manipulation doesn't propagate | Bundler emits stale source; changes seem to disappear | Return `{ code, map }` from every plugin; use `path.replaceWith` not raw node assignment |
| Missing `path.skip()` on replaced subtree | Infinite loop, stack overflow | Call `path.skip()` after replacing a node whose replacement matches the same visitor |
| Node built without `loc` field | Source map drops that region | Copy `loc` from a nearby node, or use `t.inherits(newNode, oldNode)` |
| Preset order reversed in head | TS types survive to preset-env | Remember: presets run **last-to-first**; put TypeScript **after** env in the array |

---

## Reference tooling

- **[astexplorer.net](https://astexplorer.net)** — paste code, pick a parser (Babel, SWC, acorn, TypeScript, Espree), see AST live. Also lets you write and test a plugin against the AST in the same page.
- **@babel/parser** — the parser used by Babel. Standalone-usable for tools that need JS parsing without a full compile pipeline.
- **swc_ecma_parser** — the parser used by SWC. Rust crate; bindings via `@swc/core`.
- **acorn** — the historic ESTree parser used by Rollup, Webpack, ESLint, and countless other tools. Small, fast, extensible via `acorn-*` plugins.
- **@babel/traverse** — the visitor engine used by Babel plugins. Usable standalone against any `@babel/parser` AST.
- **@babel/types** — node builders (`t.identifier('x')`, `t.callExpression(...)`) with runtime type-checking. Use these instead of hand-authoring node literals.

---

## Related

- [[Build Tools Foundations - Bundlers vs Compilers]] — compilers use the transform pipeline; bundlers orchestrate them
- [[Build Tools Foundations - Source Maps]] — how mappings propagate
- [[Build Tools Compilers - Babel Internals]]
- [[Build Tools Compilers - SWC Internals]]
- [[Build Tools Foundations Guide]]
