---
tags:
  - devops
  - github-actions
  - caching
  - artifacts
  - performance
created: 2026-07-17
source: https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows
---

# GitHub Actions - Caching and Artifacts

> **Caches** = ephemeral speed-up storage keyed by content hash. **Artifacts** = named outputs of a run, retrievable later. Different mechanisms; often used together. Back to [[GitHub Actions Guide]].

---

## `actions/cache` — The Primitive

```yaml
- uses: actions/cache@v4
  id: cache
  with:
    path: |
      ~/.npm
      **/node_modules
    key: node-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      node-${{ runner.os }}-
```

**On cache hit**: `path` is restored, `steps.cache.outputs.cache-hit == 'true'`.
**On miss**: `path` is empty on the runner; the action saves `path` under `key` at job end (only if the job succeeds).

`hashFiles(<glob>)` produces a SHA-256-of-hashes over matching files (see [[GitHub Actions - Workflow Syntax]]). Empty result if nothing matches.

### `key` vs `restore-keys`

- **`key`** — exact match. Save happens under this key on miss.
- **`restore-keys`** — ordered prefix-match fallbacks. Great for partial reuse:
  ```
  key:          node-linux-abc123     (lockfile hash)
  restore-keys: |
    node-linux-                        (fall back to any linux cache)
  ```
  If the primary key misses but a `restore-keys` prefix matches, the newest matching cache is restored, and a new cache with the exact `key` is saved at job end.

### Cache Scoping

- Caches are scoped per branch. A PR run can read caches from its **base branch** and from **`main`** (or the repo's default branch) as fallback.
- Base-branch caches are read-only from the PR; the PR can create its own branch-scoped cache.
- Caches for a branch are pruned when the branch is deleted.

### Size and Eviction

- **10 GB per repo total cache size** at the time of writing (verify current limit in the docs — may increase over time).
- **LRU eviction** past the cap.
- **7 days of no access → auto-eviction**. Caches unused for a week vanish.

### `actions/cache/save` and `restore` (split)

Since v4, you can split save and restore for more control:

```yaml
- uses: actions/cache/restore@v4
  id: r
  with:
    path: ~/.npm
    key: npm-${{ hashFiles('package-lock.json') }}

- if: steps.r.outputs.cache-hit != 'true'
  run: npm ci

- if: steps.r.outputs.cache-hit != 'true'
  uses: actions/cache/save@v4
  with:
    path: ~/.npm
    key: ${{ steps.r.outputs.cache-primary-key }}
```

Useful when you want to save mid-job or skip the save on failure.

---

## Built-In `setup-*` Caches

Many `setup-*` actions have a built-in cache — no separate `actions/cache` step needed:

```yaml
- uses: actions/setup-node@1d0ff469b7ec7b3cb9d8673fde0c81c44821de2a
  with:
    node-version: '22'
    cache: 'npm'                        # or 'yarn', 'pnpm'
    cache-dependency-path: '**/package-lock.json'

- uses: actions/setup-python@0b93645e9fea7318ecaed2b359399ac6875db9a2
  with:
    python-version: '3.12'
    cache: 'pip'
    cache-dependency-path: 'requirements*.txt'

- uses: actions/setup-java@3b6c050358614dd082e53cdbc55580431fc4e437
  with:
    distribution: 'temurin'
    java-version: '21'
    cache: 'maven'                      # or 'gradle'

- uses: actions/setup-go@41dfa10bad2bb2ae585af6ee5bb4d7d973ad74ed
  with:
    go-version: '1.23'
    cache: true                          # cache is on by default
    cache-dependency-path: 'go.sum'
```

These use `actions/cache` under the hood but pick the correct paths and hash the right dependency file. Prefer them over hand-rolled cache steps when applicable.

---

## Docker Layer Caching

Two options for BuildKit-driven Docker builds:

### Option A: `type=gha` (GitHub Actions cache backend)

```yaml
- uses: docker/setup-buildx-action@...
- uses: docker/build-push-action@...
  with:
    context: .
    push: true
    tags: ghcr.io/acme/api:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

- Uses the same 10 GB repo cache pool as `actions/cache`.
- Simple; no external storage.
- Watch the pool size — Docker layer caches can dominate quickly.

### Option B: `type=registry` (registry cache export)

```yaml
    cache-from: type=registry,ref=ghcr.io/acme/api:buildcache
    cache-to:   type=registry,ref=ghcr.io/acme/api:buildcache,mode=max
```

- Cache lives in the container registry — no runner cache pool consumption.
- Works across runners, workflows, and repos with registry access.
- Preferred for larger org-wide sharing.

`mode=max` exports cache for every stage (essential for multi-stage builds). See [[Docker - Image Optimization]].

---

## Artifacts — `upload-artifact` / `download-artifact` (v4)

Artifacts are **named outputs** of a run — build outputs, test reports, coverage, screenshots. Different from caches: not keyed, not restored automatically, persisted for retention window (default 90 days; configurable up to 400 for private repos).

### Upload

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: web-dist-${{ matrix.shard }}     # unique per invocation in v4
    path: dist/
    retention-days: 7
    if-no-files-found: error                # fail if nothing to upload
    compression-level: 6                     # 0..9, default 6
```

**v4 breaking change**: artifact names must be **unique within a workflow run**. In v3 you could upload multiple times to the same name to accumulate; v4 rejects the second upload. Use `${{ matrix.* }}` or `${{ github.job }}` to disambiguate.

### Download

```yaml
- uses: actions/download-artifact@v4
  with:
    pattern: 'web-dist-*'            # glob
    merge-multiple: true              # combine matched artifacts into one dir
    path: dist/                       # extraction root
```

Without `merge-multiple: true`, each artifact goes into its own subdirectory.

### Cross-Workflow / Cross-Run

Not the default. Enable with:

```yaml
- uses: actions/download-artifact@v4
  with:
    name: web-dist
    github-token: ${{ secrets.GITHUB_TOKEN }}
    repository: ${{ github.repository }}
    run-id: 12345678                  # explicit prior run
```

Requires `actions: read` on `GITHUB_TOKEN`. Useful for downstream release workflows consuming build artifacts from an earlier CI run.

---

## Cache vs Artifact — When to Use Which

| Need | Reach for |
|------|-----------|
| Skip re-installing deps on subsequent runs | Cache (`actions/cache` or `setup-*` cache) |
| Pass build output from one job to a later job in the same run | Artifact |
| Share build output with a downstream workflow (release job) | Artifact + `download-artifact` cross-run |
| Store test reports for the PR UI | Artifact |
| Persist Docker layers across builds | Cache (`type=gha` or `type=registry`) |
| Long-term storage of releases | Not artifacts — use Releases, S3, or a registry |

**Rough sizing**: caches are for MBs–GBs of "would recompute otherwise". Artifacts are for the small-to-medium payloads consumers actually need. Long-term durable storage belongs elsewhere (Releases, package registry, S3).

---

## Cache Hygiene Tips

- **Hash the lockfile**, not `package.json`. Package.json can change (comment, version bump) without dep changes; lockfile hashes are the authoritative "did anything real change".
- **Include OS/arch** in the cache key. A macOS `node_modules` doesn't work on Linux.
- **Include tool version** in the cache key when it matters (`node-${{ matrix.node }}-...`). Different Node versions have incompatible native modules.
- **Don't cache too broadly**. Caching `~/` restores stale system state. Cache only what you need.
- **Purge old caches manually** if you know a schema changed (`gh cache list`, `gh cache delete`).

---

## Summary

| Feature | Rule |
|---------|------|
| `actions/cache` | Ephemeral, per-branch, 10 GB per repo, 7-day inactive eviction |
| `key` + `restore-keys` | Exact match; prefix-match fallback |
| `hashFiles('lockfile')` | Canonical primary-key input |
| `setup-*` built-in cache | Prefer over hand-rolled `actions/cache` when available |
| Docker `type=gha` | Uses same cache pool; simple |
| Docker `type=registry` | Registry-backed; better for org-wide sharing |
| `upload-artifact@v4` | **Unique names required per run**; retention default 90d |
| `download-artifact@v4` | `pattern` + `merge-multiple` for shard aggregation |
| Cross-run download | Requires `actions: read`; specify `run-id` + `repository` |

---

## Related Notes

- [[GitHub Actions - Workflow Syntax]] — `hashFiles()`, expression fundamentals
- [[GitHub Actions - Matrix Builds and Job Strategies]] — per-shard artifacts and merge jobs
- [[CI-CD - Caching and Build Speed]] — the strategic case for caching
- [[Docker - Image Optimization]] — BuildKit registry cache export
