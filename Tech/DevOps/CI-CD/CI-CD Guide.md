---
tags:
  - devops
  - ci-cd
  - deployment
  - trunk-based-development
created: 2026-07-17
source: https://martinfowler.com/articles/continuousIntegration.html
---

# CI-CD Guide

> **Continuous Integration** — every developer commits to trunk at least daily; a green build gate on every push. **Continuous Delivery** — the codebase is always releasable. **Continuous Deployment** — every green build ships automatically. These notes are framework-agnostic; for the GitHub Actions expression of the same ideas, see [[GitHub Actions Guide]]. Part of [[DevOps Guide]].

---

## Contents

| Note | Covers |
|------|--------|
| [[CI-CD - Fundamentals]] | CI vs CD vs Continuous Deployment; trunk-based development; DORA capabilities; broken-build discipline |
| [[CI-CD - Pipeline Design Patterns]] | Stages, gates, sequential vs parallel jobs, fan-out/fan-in, monorepo triggers, merge queues |
| [[CI-CD - Deployment Strategies]] | Blue-green, canary, rolling, feature flags, dark launches, Argo Rollouts, Flagger |
| [[CI-CD - Testing in Pipelines]] | Test pyramid in CI, sharding, flaky tests, quarantine, PR feedback loops |
| [[CI-CD - Secrets Management]] | Vaults, OIDC federation to cloud, ephemeral credentials, rotation |
| [[CI-CD - Caching and Build Speed]] | Dependency caches, artifact reuse, remote caching (Bazel/Turborepo/Nx), cache keys |
| [[CI-CD - Security and Compliance]] | SAST, DAST, SBOM, dependency scanning, SLSA levels, Sigstore/cosign |
| [[CI-CD - Observability and Rollback]] | Deploy markers, DORA metrics, automated rollback triggers, SLO-based reversion |

---

## Vocabulary

| Term | Meaning |
|------|---------|
| **CI** | Every commit gets built and tested against trunk. Broken builds block. |
| **CD (Continuous Delivery)** | Trunk is always deployable. A human clicks "deploy" to release. |
| **Continuous Deployment** | Every green trunk build auto-deploys to production. |
| **Trunk-Based Development (TBD)** | All devs commit to trunk at least once every 24 hours. Short-lived branches only for review + CI. |
| **Pipeline** | The DAG of build/test/deploy stages that runs on each change. |
| **Stage / Job / Step** | Rough hierarchy: a *stage* groups *jobs*; a *job* runs a sequence of *steps* on one runner. |
| **Runner / Agent / Executor** | The machine (or container) that executes a job. GitHub calls them "runners", GitLab "runners", Jenkins "agents". |
| **Artifact** | A build output (binary, image, tarball, coverage report) passed between jobs or stored for release. |
| **Gate** | A predicate that must pass before the pipeline proceeds — tests green, approval given, canary healthy. |
| **DORA** | DevOps Research & Assessment — the four (now five) metrics that predict elite delivery performance. |
| **Progressive delivery** | Shipping in graduated exposure — canary → 10% → 50% → 100% — with automated rollback. |

---

## The Three Cs

```
Continuous Integration ──▶ Continuous Delivery ──▶ Continuous Deployment
   (green trunk)             (always releasable)         (auto-release)
```

You can practice CI without CD (some regulated shops must not auto-deploy). You cannot practice CD without CI — you can't release what isn't verified. Continuous Deployment is the endpoint most teams don't reach and don't need. Continuous *Delivery* is the goal.

---

## The 2026 Baseline

1. **Trunk-based development, PRs merged within 24 hours.** Long-lived feature branches are the root of most CI pain. → [[CI-CD - Fundamentals]]
2. **Self-testing code.** Fowler: *"instituting CI without self-testing code won't work."*
3. **Green trunk is the team's top priority.** Revert first; forward-fix only if a revert is genuinely worse. → [[CI-CD - Fundamentals]]
4. **Fast PR feedback (< 10 min).** Split slow stages behind trunk gates; keep the PR-blocking suite lean. → [[CI-CD - Testing in Pipelines]]
5. **OIDC federation for cloud credentials.** No long-lived AWS access keys in CI secrets. → [[CI-CD - Secrets Management]]
6. **Progressive delivery, not big-bang deploys.** Canary or blue-green with automated rollback. → [[CI-CD - Deployment Strategies]]
7. **Sign and attest every artifact.** Sigstore/cosign; SLSA v1.0 Build track L2+. → [[CI-CD - Security and Compliance]]
8. **Deploy markers on your dashboards.** Every rollout is a candidate cause for the next incident. → [[CI-CD - Observability and Rollback]]

---

## Anti-Pattern: The Slow Serial Pipeline

```
lint ──▶ typecheck ──▶ unit ──▶ integration ──▶ e2e ──▶ deploy    (30–60 min)
```

Every step waits for the previous. A change to a comment triggers a 45-minute cycle. Compare with:

```
             ┌──▶ lint ──────┐
             ├──▶ typecheck ─┤
build ─┬────▶┼──▶ unit (shard 1..N in parallel)
       │     ├──▶ integration
       │     └──▶ e2e (only on trunk after merge)
       │
       └────▶ image build + push (parallel with tests)
                    │
                    └──▶ deploy (once all tests green)
```

Fan-out early, fan-in late. Only join at the deploy gate. See [[CI-CD - Pipeline Design Patterns]].

---

## Mental Model: The Pipeline as a Value Stream

Every stage exists to answer one question. If it doesn't move the artifact closer to production or provide actionable feedback, cut it.

```
"Does it compile?" ──▶ "Does it work?" ──▶ "Is it safe?" ──▶ "Ship it."
     (build)              (test)             (scan/sign)      (deploy)
```

DORA's four metrics — **deployment frequency**, **lead time for changes**, **change failure rate**, **failed-deployment recovery time** — measure whether your pipeline actually delivers this value quickly and safely. The fifth (**reliability**) was added in 2021 and tracks operational health downstream. See [[CI-CD - Observability and Rollback]].

---

## Related — Not Yet Covered

- **GitOps** (ArgoCD / Flux) — pull-based deploy; briefly referenced in [[CI-CD - Deployment Strategies]].
- **Platform engineering** — internal developer platforms (Backstage, Port, Humanitec) that wrap CI/CD in golden paths.
- **Feature-flag management** in depth (LaunchDarkly, Unleash, Split) — mentioned but not deep.

---

## Related Notes

- [[DevOps Guide]] — parent index
- [[Docker Guide]] — the artifact CI produces
- [[GitHub Actions Guide]] — the concrete workflow engine for the ideas in these notes
