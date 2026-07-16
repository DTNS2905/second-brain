---
tags:
  - build-tools
  - compilers
  - typescript
  - tooling
  - frontend
created: 2026-07-16
source: https://www.typescriptlang.org/docs/handbook/modules/reference.html
---

# Build Tools Compilers — TypeScript as a Transpiler

> tsc plays two roles that are often conflated: **type-checker** (semantic analysis) and **transpiler** (TS → JS emit). Modern pipelines split them — SWC/esbuild does the transpile, tsc does the type-check. Part of [[Build Tools Compilers Guide]].

---

## tsc's two jobs

| Job | Semantic knowledge required |
|-----|----------------------------|
| Type-checking | Yes (whole-program, cross-file inference) |
| Type-erasure emit | No (per-file syntactic transform) |

Because type-erasure doesn't require type info, faster tools (esbuild, SWC) can strip types without running the type-checker. That's why "TS in Vite" feels fast — the transpile is per-file esbuild; types are checked separately.

---

## The modern split: type-check ⊥ transpile

```
Editor / CI: tsc --noEmit          (type-check only)
Build:       esbuild / SWC          (transpile only)
```

This is the pattern Vite, Next.js, and Remix all use. `tsc --noEmit` runs in `check` scripts and CI; the bundler ignores type errors and just strips syntax.

---

## isolatedModules — the compat flag

Faster transpilers work **per file**. They can't see cross-file type info. Some TS features require cross-file knowledge to emit correctly:

- `export const enum` (must be inlined by tsc; can't be per-file)
- Ambient `namespace` merging
- Some `export type` vs `export` ambiguity

`"isolatedModules": true` in tsconfig makes tsc **error on constructs that per-file tools can't handle**. Result: your code becomes portable across tsc, SWC, esbuild.

```json
// tsconfig.json — required for esbuild/SWC compatibility
{ "compilerOptions": { "isolatedModules": true } }
```

---

## verbatimModuleSyntax

Replaces the older `importsNotUsedAsValues` + `preserveValueImports`. Enforces that:

- `import type` is emitted as no-op
- `import { X }` where X is a type-only import causes an error unless marked `import type`

```ts
// ✅ Explicit type-only import
import type { Config } from './config';

// ❌ Ambiguous — TS would emit either an import or a no-op depending on downstream use
import { Config } from './config';
```

---

## Emit modes

```
tsc                    → emits .js + .d.ts (default)
tsc --noEmit           → type-check only
tsc --emitDeclarationOnly → emit .d.ts only
tsc --isolatedDeclarations → require explicit types on exports (fastest .d.ts emit)
```

Modern library workflow:

```
src/*.ts → esbuild → dist/*.js
src/*.ts → tsc --emitDeclarationOnly → dist/*.d.ts
```

---

## isolatedDeclarations (TS 5.5+)

Requires exports to have explicit types (no inference across file boundaries). This lets ANY tool emit `.d.ts` files without running the full type-checker — enabling fast declaration bundling in esbuild / SWC.

```ts
// ❌ Return type inferred — fails isolatedDeclarations
export function greet(name: string) {
  return `Hi, ${name}`;
}

// ✅ Explicit return type
export function greet(name: string): string {
  return `Hi, ${name}`;
}
```

---

## Module resolution and moduleResolution

Options:

- `node` (classic, deprecated)
- `node10` (roughly Node 10 style)
- `node16` / `nodenext` — full Node ESM resolution with `exports` field
- `bundler` — matches what Vite / esbuild / Rollup do (no extension required; reads `exports`)

For app code with a bundler: `"moduleResolution": "bundler"`.
For library code: `"moduleResolution": "nodenext"`.

---

## Project references

Break a monorepo into referenced projects:

```json
// tsconfig.json
{
  "references": [
    { "path": "./packages/utils" },
    { "path": "./packages/app" }
  ],
  "files": []
}
```

`tsc --build` (or `tsc -b`) walks references and only rechecks changed projects — incremental type-checking.

---

## Declaration-only builds for libraries

```json
// package.json for a library
{
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.mjs",
      "require": "./dist/index.cjs"
    }
  },
  "scripts": {
    "build:js": "tsup src/index.ts --format esm,cjs",
    "build:dts": "tsc --emitDeclarationOnly --outDir dist"
  }
}
```

`tsup`, `unbuild`, `pkgroll` — all wrap this pattern.

---

## Type-check performance

Type-checking is the slow part. Techniques:

- Enable `skipLibCheck: true` — don't check dep types (usually safe)
- Use project references for monorepos
- Run type-check in a separate CI job so it doesn't block the build
- Consider TypeScript's built-in server mode + IDE for interactive checks

---

## Common patterns per stack

| Stack | Type-check | Transpile |
|-------|-----------|-----------|
| Vite + React | `tsc --noEmit` in CI or `vue-tsc` for Vue | esbuild (dev) / esbuild or SWC (build) |
| Next.js | `tsc --noEmit` (Next runs it in `next build`) | SWC |
| Remix | `tsc --noEmit` | esbuild |
| Library (Rollup) | `tsc --emitDeclarationOnly` | Rollup + `@rollup/plugin-typescript` or `esbuild` |

---

## Common misconceptions

```
❌ "SWC does type-checking."
✅ SWC only strips types. Semantic type-check requires tsc.

❌ "I don't need tsc if I use Vite."
✅ Vite doesn't type-check. Run `tsc --noEmit` in your test/CI script.

❌ "I have to use tsc to build."
✅ Nobody uses tsc for transpile in modern pipelines. Use esbuild/SWC for the .js, tsc for the .d.ts.
```

---

## Related

- [[Build Tools Compilers - SWC Internals]]
- [[Build Tools Compilers - Babel Internals]]
- [[Build Tools Foundations - Module Systems (ESM CJS UMD)]]
- [[Build Tools Bundlers - esbuild Internals]]
- [[Build Tools Compilers Guide]]
