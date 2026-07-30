---
tags:
  - devops
  - ci-cd
  - caching
  - performance
  - monorepo
created: 2026-07-17
source: https://docs.bazel.build/versions/main/remote-caching.html
---

# CI-CD - Caching and Build Speed

> Uncached CI is slow, expensive, and non-deterministic. Every warm-cache job saves developer wait time — the highest-leverage tuning in the pipeline. Back to [[CI-CD Guide]].

---

## Three Kinds of Caching

| Kind | Cached artifact | Where it lives |
|------|----------------|---------------|
| **Dependency cache** | `node_modules`, `~/.m2`, `~/.cargo`, pip wheels | CI-provided cache (S3/GCS/blob) or self-hosted |
| **Build artifact reuse** | Compiled binaries, transpiled JS, generated code | Per-pipeline artifact store or remote build cache |
| **Remote build cache** | Content-addressed build outputs shared across users and CI | Bazel Remote Cache, Turborepo Remote Cache, Nx Cloud |

Each unlocks a different level of speedup. Combine all three on large monorepos.

---

## Dependency Caching

Every CI runner starts empty. Without caching, every job re-downloads all deps.

### Cache key discipline

The cache key is the *contract*. Get it wrong and you get either:
- Stale caches (dep changed but key didn't) → mysterious CI failures.
- Cache misses on every run (key too specific) → no benefit.

**Rule**: hash the lock file, not the version file.

- ✅ `key: node-${{ hashFiles('package-lock.json') }}` — invalidates when the lockfile changes.
- ❌ `key: node-${{ hashFiles('package.json') }}` — misses when a `caret-ranged` dep gets a new patch.
- ❌ `key: node-latest` — same key forever; poisoned cache lives forever.

**Restore keys / fallback keys**: most CI systems support layered keys. Try exact match, fall back to prefix match. On miss, save the exact key after install so the next run hits.

### `npm ci` and friends

Package managers already do reproducible installs from a lockfile if you use the right command:

- npm: `npm ci` (not `npm install`).
- yarn: `yarn install --frozen-lockfile`.
- pnpm: `pnpm install --frozen-lockfile`.
- pip: `pip install -r requirements.txt` with pinned versions or `pip-tools`.
- poetry: `poetry install --sync`.

Combine `npm ci` with cache of `~/.npm` — you download less, and install is deterministic.

---

## Docker Layer Caching in CI

Every fresh CI runner starts with an empty Docker cache — every build re-executes every layer. Fix with BuildKit registry cache export:

```bash
docker buildx build \
  --cache-from type=registry,ref=ghcr.io/acme/app:buildcache \
  --cache-to   type=registry,ref=ghcr.io/acme/app:buildcache,mode=max \
  --push --tag ghcr.io/acme/app:$GIT_SHA .
```

- `mode=max` — export cache for *every stage*, not just the final one. Essential for multi-stage builds.
- Warm cache typically cuts a 4-minute image build to 30-90 seconds.

See [[Docker - Image Optimization]] and [[GitHub Actions - Caching and Artifacts]].

---

## Artifact Reuse Across Jobs

If job A builds an artifact and jobs B, C, D consume it, don't rebuild it three times. Publish once, consume many:

```
build ──▶ artifact ──┬─▶ integration tests
                     ├─▶ e2e tests
                     └─▶ security scan
```

Every CI tool has an "artifact" primitive (GitHub `actions/upload-artifact` + `download-artifact`, GitLab `artifacts:`, CircleCI `persist_to_workspace`). Retention is short (days/weeks); use registries or S3 for durable storage.

---

## Remote Build Cache (Monorepo Superpower)

**The idea**: content-hash the inputs of every build/test task; if the hash matches a cached result, skip execution and reuse the output — across every developer and every CI runner.

### Bazel Remote Cache

Bazel's original model. Every action (compile, test, package) is hermetic — its inputs are fully declared. Bazel hashes inputs, checks the remote cache, downloads outputs on hit, executes and uploads on miss.

- HTTP or gRPC (`REAPI`) backend.
- Backends: `bazel-remote`, Buildbarn, EngFlow, BuildBuddy, Google Cloud Build, self-hosted S3.
- Hit rate on a mature Bazel monorepo: 80–95% for incremental changes.

### Turborepo Remote Cache

The JS-monorepo equivalent, popular for Next.js / Turbo-based repos. Managed by Vercel by default; self-host with `turbo-remote-cache` or Mercari's implementation.

Content-hashes each task's inputs (source files, deps, env vars). A CI job that touched only the `web` app skips test runs for `api`, `auth`, `billing`, etc.

### Nx Cloud

Nx's equivalent, with additional features like distributed task execution (send tasks to remote agents automatically) and affected-only builds based on a project graph.

### When it pays off

- Monorepos with > ~10 packages / apps.
- Slow test/build tasks (multi-second minimum).
- Multiple contributors — shared cache means one dev's warm run helps everyone.

Small single-app repos don't benefit — the metadata overhead cancels the savings.

---

## Cache Invalidation

The eternal problem. Two failure modes:

### Silent staleness

The cache is served even though inputs changed but the key didn't detect it. Symptom: "works on my machine after `rm -rf node_modules`", CI fails intermittently.

Fix: include *all* inputs in the hash. Lock file **and** OS/arch **and** language version **and** relevant env vars.

### Cache-key thrash

Every run misses. Symptom: cache size grows unboundedly, no speedup.

Fix: consider a lockfile-only key (not `package.json`), and use restore-key fallback so a near-miss still helps.

**Rule of thumb**: a healthy cache has a hit rate above 80% on typical PR runs and above 95% on rebuild-same-commit.

---

## Cache Hygiene

- **Size limits**: caches grow. Most CI systems auto-evict LRU past a size cap. Know your cap.
- **Scope**: per-branch caches vs. shared. Shared caches maximize hit rate but risk poisoning across branches.
- **Purging**: automate purge on lockfile-manager version bumps or major OS updates.
- **Cost**: remote caches are billed by egress + storage. A cold-cache CI job saves N minutes but might cost more egress than it saves.

---

## Compiler and Tool Caches

Beyond dependencies:

- **`ccache` / `sccache`** — compiler wrappers that cache C/C++/Rust object files across builds.
- **TypeScript incremental build** (`--incremental`) — persists a `.tsbuildinfo` file; only re-typecheck changed files. Cache this file.
- **Jest cache** (`--cache`) — per-file transform + haste cache. Cache the Jest cache dir.
- **Cypress / Playwright browser downloads** — cache `~/.cache/Cypress` / `~/.cache/ms-playwright`. Downloads are hundreds of MB.

Each one saves 10–60 seconds. In aggregate they turn a 5-minute setup into 30 seconds.

---

## Distributed Test Execution

When you can't shard further (already at 20 parallel runners), send individual tasks to remote workers:

- **Nx Cloud DTE** — Nx sends tasks to workers on Nx Cloud infrastructure.
- **Bazel remote execution** — build actions run on remote workers, not just cached.
- **Distributed Playwright** (via Buildkite, Cypress Cloud) — spread a suite across dozens of workers.

Not always cheaper than one big runner; measure per-suite.

---

## Summary

| Lever | Typical speedup |
|-------|----------------|
| Dependency cache (correct key) | 30–120 s per job |
| Docker layer cache from registry | 3–5× on image builds |
| Artifact reuse across jobs | Eliminates duplicate work |
| Remote build cache (Bazel/Turborepo/Nx) | 5–20× on incremental monorepo changes |
| Compiler caches (`sccache`, TS incremental) | 30–60 s per job |
| Browser download cache (Cypress/Playwright) | 30–90 s per job |
| Distributed test execution | Additional 2–5× when sharding maxed out |

---

## Related Notes

- [[CI-CD - Pipeline Design Patterns]] — the other lever for making CI fast
- [[CI-CD - Testing in Pipelines]] — sharding, test caching
- [[Docker - Image Optimization]] — BuildKit registry cache export
- [[Docker - Dockerfile Best Practices]] — layer ordering that makes caching effective
- [[GitHub Actions - Caching and Artifacts]] — GitHub's `actions/cache` mechanism
