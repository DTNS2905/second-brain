---
tags:
  - devops
  - ci-cd
  - testing
  - test-pyramid
  - flaky-tests
created: 2026-07-17
source: https://martinfowler.com/bliki/TestPyramid.html
---

# CI-CD - Testing in Pipelines

> Fast, reliable, well-shaped tests turn CI from a bottleneck into a safety net. Slow or flaky ones do the opposite. Back to [[CI-CD Guide]].

---

## The Test Pyramid in CI

| Layer | Count | Speed | Cost | Where in pipeline |
|-------|-------|-------|------|-------------------|
| **Unit** | Thousands | Milliseconds | Cheap | Every PR, blocking |
| **Integration** | Hundreds | Seconds | Medium | Every PR, blocking |
| **E2E / UI** | Tens | Minutes | Expensive | Trunk after merge; smoke subset on PR |
| **Manual exploratory** | N/A | Human | Very expensive | Preview environments per PR |

**Anti-pattern**: an inverted pyramid — most tests are slow, brittle E2E. PRs take 40 minutes and flake every third run. Rewrite to push coverage down the pyramid.

Fowler's principle: *"unit tests give you fast feedback; higher-level tests give you confidence the pieces fit."* You need both — but you need a lot more of the first than the second.

---

## Fast PR Feedback (< 10 minutes)

The blocking PR suite is a budget, not a wish list. Target: **10 minutes end-to-end** from push to green.

**How to fit inside 10 minutes:**
- Ship only PR-relevant tests. Full E2E on trunk after merge.
- Shard (see below).
- Cache dependencies aggressively. See [[CI-CD - Caching and Build Speed]].
- Fail fast on the cheapest checks (lint → typecheck → unit → integration).
- Use path filters in monorepos — don't re-test unchanged packages.

Above 10 minutes, developers batch changes, PRs balloon, and review quality falls. Below 5 minutes, some teams see a productivity phase change: PRs become as small as commits.

---

## Sharding

Split a slow suite across N runners. Each shard runs 1/N of the tests; a final job aggregates coverage.

```yaml
# conceptual — every CI tool has a matrix/parallel keyword
jobs:
  test:
    strategy:
      matrix:
        shard: [1, 2, 3, 4, 5]
    steps:
      - run: pytest --shard=${{ matrix.shard }}/5
```

**Two sharding modes:**

- **Count-based** — `--shard 3/5`. Simple; tolerates flakes; may be uneven if some tests are much slower.
- **Timing-based** — record per-test runtimes, distribute to balance total time. Better wall-clock; needs a persistent timing store.

Tools that ship timing-based sharding: Jest (`--shard`), Playwright, Cypress (with Sorry Cypress or Cypress Cloud), pytest-split, Knapsack Pro, CircleCI's split-by-timings.

---

## Flaky Test Detection & Quarantine

A **flaky test** passes sometimes and fails sometimes on the same code. Flakes are worse than failures: they train the team to re-run without investigating, which kills trust in green.

### Detection

- **Retry once and flag** — if a test fails then passes on retry, log it as flaky.
- **Statistical detection** — if the same test fails > X% of runs across a rolling window, quarantine.
- **PR-triggered reruns** — some suites re-run failed tests once; a "green after retry" surfaces in a report.

Tools: Buildkite Test Analytics, CircleCI Test Insights, Datadog Test Optimization, Trunk.io Flaky Tests, Launchable, Spotify's Backstage plugin, Uber's SubmitQueue-style systems.

### Quarantine

Once flagged, move flaky tests to a **quarantine suite** that:
- Runs on every PR but does **not** block merge.
- Reports results to a dashboard the owning team monitors.
- Auto-deletes tests that stay green in quarantine for N runs (welcome back), or auto-files tickets when they keep flaking.

Quarantine is a first-response mechanism, not an archive. A test parked there for months has been forgotten.

---

## Root-Causing Flakes

Common causes (roughly ordered by prevalence):

| Cause | Fix |
|-------|-----|
| Time-of-day dependence | Freeze time; inject clock |
| Test order dependence | Isolate state; parallelize (exposes the coupling) |
| Async / race conditions | Prefer polling with timeout over `sleep` |
| Network calls to real services | Mock or use a hermetic double |
| Random seeds not fixed | Fix them in test setup |
| Filesystem clock or timezone | Set a fixed TZ in CI |
| Container/network startup timing | Healthchecks with retries (see [[Docker - Compose for Dev Environments]]) |

---

## Test Result Caching

Don't re-run tests that couldn't have been affected by the change.

**Approaches:**
- **Bazel / Nx / Turborepo** — content-hash inputs; if inputs unchanged, tests are cached green. Requires hermetic tests (no hidden inputs).
- **Test-impact analysis** — track which code paths a test exercises; run only tests whose paths intersect the change. Tools: Launchable, Testable, Playwright's `--only-changed`.

Caveat: test caching is only safe when your test *inputs* are complete. A test that reads `Date.now()` or an env var without declaring the dependency will produce a false-green cached result.

---

## Smoke vs Integration vs E2E Gates

Structure the deploy pipeline in graduated confidence gates:

| Gate | Runs against | Purpose |
|------|-------------|---------|
| **Unit / integration** | Isolated code | Correctness of the change |
| **Smoke** | Deployed staging | "Did the deploy work at all?" — 5–10 critical paths |
| **E2E full** | Deployed staging | Behavioral verification of user flows |
| **Canary metrics** | Live production canary | Real-user signal (5xx, latency, business KPI) |
| **Synthetic monitoring** | Prod, continuous | Steady-state health after full rollout |

Only the first two gate the deploy pipeline itself. E2E full and synthetic monitoring inform rollback decisions post-deploy, not deploy blocking.

---

## Contract Tests (Consumer-Driven)

For services with many consumers, **contract tests** verify the wire format each consumer depends on:

- Consumer's CI publishes a "pact" describing the requests it makes and responses it expects.
- Provider's CI runs each consumer's pact against a real provider instance; fails if the shape changed.

Tools: Pact, Spring Cloud Contract, ProtoBuf schema tests (buf), OpenAPI diff tools. Turns "we broke everyone downstream" from a runtime incident into a CI failure.

---

## PR Feedback Hygiene

- **Post test failures inline on the PR** — GitHub Actions annotations, GitLab test reports. Don't make developers click through to logs.
- **Report time-to-green trends** — a rising trendline is a canary for pipeline health.
- **Report flake rate publicly** — if it's ambient noise nobody sees, nobody fixes it.

---

## Summary

| Practice | Effect |
|----------|--------|
| Pyramid: many unit, few E2E | Fast, cheap, reliable feedback |
| PR budget < 10 min | Small PRs, tight review loops |
| Shard slow suites (timing-based) | 5–10× wall-clock reduction |
| Retry-and-flag + quarantine | Restores trust in green |
| Test caching (Bazel/Nx/Turborepo) | Skip work that can't be affected |
| Smoke → E2E → canary graduation | Different gates for different confidence levels |
| Contract tests | Cross-service breakage caught in CI, not prod |
| Public flake dashboard | Visibility drives fix rate |

---

## Related Notes

- [[CI-CD - Pipeline Design Patterns]] — sharding, PR vs trunk pipelines, fail-fast
- [[CI-CD - Caching and Build Speed]] — the other lever for making CI fast
- [[CI-CD - Deployment Strategies]] — canary + metrics is the ultimate integration test
- [[GitHub Actions - Matrix Builds and Job Strategies]] — GitHub's sharding mechanism
