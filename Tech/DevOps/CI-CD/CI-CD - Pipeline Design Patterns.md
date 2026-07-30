---
tags:
  - devops
  - ci-cd
  - pipeline
  - design-patterns
created: 2026-07-17
source: https://martinfowler.com/articles/continuousIntegration.html
---

# CI-CD - Pipeline Design Patterns

> How to structure stages, jobs, and gates so the pipeline is fast, predictable, and easy to debug when it breaks. Back to [[CI-CD Guide]].

---

## The Shape of a Good Pipeline

```
                    ┌─▶ lint
                    ├─▶ typecheck
build & install ────┼─▶ unit tests (sharded)
   (once, cached)   ├─▶ security scan (SAST, deps)
                    └─▶ image build (parallel with tests)
                              │
                              ▼
                       integration tests
                              │
                              ▼
                        deploy to staging
                              │
                              ▼
                          e2e / smoke
                              │
                              ▼
                        canary → prod
```

**Fan out early, fan in late.** Everything that can run in parallel should. The pipeline's wall-clock is set by the *longest single chain*, not the sum of stages.

---

## Stage / Job / Step Vocabulary

Every CI tool uses these words slightly differently, but roughly:

| Level | What it is | Runs on |
|-------|-----------|---------|
| **Stage** | A logical phase (build, test, deploy) | Multiple jobs — often in parallel |
| **Job** | A unit that runs on a single runner | Multiple sequential steps |
| **Step** | A shell command or reusable action | One runner |

GitHub Actions: workflow → job → step. GitLab: pipeline → stage → job → script. Jenkins: pipeline → stage → step. The mental model is the same.

---

## Parallel vs Sequential

**Rule**: parallelize by default. Serialize only when there's a real dependency.

### ❌ Everything sequential

```yaml
# Wall clock = sum of all
stages: [install, lint, typecheck, unit, integration, build-image, deploy]
```

Even trivial fast stages add latency because each waits for the previous. A 90-second image build behind a 30-second install → 2 minutes before tests even start.

### ✅ Fan out after build

```yaml
stages:
  - build           # install deps, produce shared artifact
  - verify          # lint, typecheck, unit, security in parallel
  - integration     # needs the built artifact
  - deploy
```

Wall clock = `build + max(verify) + integration + deploy`, not the sum. Typically 40–60% faster on real repos.

---

## Fan-Out / Fan-In

**Fan-out** — one upstream job produces work for many downstream jobs.

**Fan-in** — many upstream jobs contribute to one downstream job.

The classic use: shard a slow test suite across N runners, then aggregate coverage.

```
              ┌─▶ unit shard 1 ─┐
              ├─▶ unit shard 2 ─┤
build ────────┼─▶ unit shard 3 ─┼────▶ coverage aggregate ──▶ report
              ├─▶ unit shard 4 ─┤
              └─▶ unit shard 5 ─┘
```

10-minute suite → ~2 minutes on 5 shards, coverage merged at the end. See [[CI-CD - Testing in Pipelines]] for sharding mechanics.

---

## Gates

A **gate** blocks the pipeline until a condition holds. Common gates:

| Gate | Blocks on |
|------|-----------|
| CI green | All tests + scans pass |
| Approval | A human clicks "approve" on the deploy |
| Canary healthy | Metrics analysis for the canary window |
| Manual promotion | Explicit "promote to prod" trigger |
| Business hours | No deploys after 5pm Friday, etc. |
| Environment lock | Only one deploy in-flight per environment |

Gates are how you get **Continuous Delivery without Continuous Deployment** — everything's ready to ship; a human just says when.

---

## PR Pipeline vs Trunk Pipeline

**Don't run the same pipeline on PRs and trunk.** They have different jobs.

| PR pipeline | Trunk pipeline |
|-------------|---------------|
| Fast feedback (< 10 min) | Comprehensive |
| Unit + typecheck + lint + fast integration | + slow integration, e2e, security scans, image push, deploy |
| Runs on every commit to the PR | Runs once after merge |
| Blocks the PR | Blocks the deploy pipeline |

If PR feedback takes 30 minutes, developers batch changes, PRs get large, review quality drops. Fowler again: fast feedback is the whole point.

---

## Monorepo Path Filters

In a monorepo, don't rebuild every service on every commit. Trigger jobs based on which paths changed:

```yaml
# conceptual — every CI tool has an equivalent
jobs:
  api-build:
    triggers:
      paths: ["services/api/**", "packages/shared/**"]
  web-build:
    triggers:
      paths: ["apps/web/**", "packages/shared/**"]
```

Combined with a **project graph** (Nx, Turborepo, Bazel) you can go further — rebuild and retest only the packages whose *transitive* dependencies changed. Massive wins on large repos. See [[CI-CD - Caching and Build Speed]].

---

## When to Split the Pipeline

One pipeline is fine until it grows two properties:

1. **Different failure modes require different owners.** Frontend deploy failure vs. DB migration failure. Split.
2. **Different cadences.** Docs publish, security scans, and app deploys don't run on the same trigger. Split.

Split by:

- **Repository** — separate apps in separate repos, one pipeline each.
- **Environment** — one pipeline builds + tests + pushes; a second one deploys, gated on the artifact.
- **Purpose** — a nightly full-security-scan pipeline separate from the PR pipeline.

**Don't split too eagerly.** Two pipelines that need to coordinate (deploy artifact from A, verified by pipeline B) are more painful than one longer pipeline.

---

## Merge Queue Interaction

Merge queues change the pipeline shape:

```
PR passes CI ──▶ enters queue ──▶ queue runs "PR + latest trunk" ──▶ merge if green
```

The queue's CI job is often *smaller* than the PR CI job — just the fast blocking tests, because the PR already ran the full suite. Full trunk-side verification runs *after* merge.

---

## Fail Fast

The order of jobs within a stage matters when *any* failure kills the stage:

- Cheap checks first: lint (seconds), typecheck (tens of seconds).
- Then unit tests (minutes).
- Then integration / e2e (many minutes).

If typecheck fails, you don't want to wait 20 minutes for e2e to also fail. Configure the pipeline to cancel outstanding work when a required job fails (`fail-fast: true` in GitHub Actions matrix; equivalent in GitLab / CircleCI).

---

## Ephemeral Environments per PR

Every PR gets its own throwaway environment (a namespace in a k8s cluster, a preview URL from Vercel, a Compose stack in a runner). Reviewers get a working link, not just green checks. Tear down on PR close.

Enables:
- Real user-facing testing before merge.
- Cross-team review with a URL, not a build log.
- E2E tests running against a real, isolated stack.

Cost: environment sprawl and non-trivial infra. Managed by tools like Vercel Preview Deployments, Netlify Deploy Previews, Coder Envbox, Uffizzi, or hand-rolled with k8s namespaces + ArgoCD.

---

## Summary

| Pattern | Payoff |
|---------|--------|
| Fan out after `build`, fan in at `deploy` | Wall-clock = longest chain, not sum |
| Shard slow suites | 5–10× faster tests without infra rearchitecture |
| Separate PR pipeline from trunk pipeline | Fast feedback on PRs; full rigor after merge |
| Monorepo path filters + project graph | Rebuild only what actually changed |
| Fail-fast within a stage | Don't wait 20 min for e2e to confirm typecheck already broke |
| Merge queue | Prevents "each PR passed individually, but merging both fails" |
| Ephemeral preview environments | Real-world PR review before merge |

---

## Related Notes

- [[CI-CD - Fundamentals]] — trunk-based dev, merge queues, self-testing code
- [[CI-CD - Testing in Pipelines]] — sharding, flaky tests, test pyramid
- [[CI-CD - Caching and Build Speed]] — the other half of "make it fast"
- [[GitHub Actions - Matrix Builds and Job Strategies]] — the concrete parallel-job mechanism
