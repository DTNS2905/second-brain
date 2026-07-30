---
tags:
  - devops
  - ci-cd
  - observability
  - rollback
  - dora
  - slo
created: 2026-07-17
source: https://dora.dev/guides/dora-metrics/
---

# CI-CD - Observability and Rollback

> A deploy that ships without a metric to confirm it worked is a coin flip. This note is about closing the loop: **deploy markers + SLO-based signals + automated rollback**. Back to [[CI-CD Guide]].

---

## The Feedback Loop

```
code merged ──▶ deploy ──▶ marker on dashboard ──▶ metrics observed ──┐
                                                                       │
                     ┌─── all-clear: continue ────────────────────────┘
                     │
                     └─── SLO breach or error spike: automated rollback + page
```

Without the marker, "when did this start breaking?" is a manual archaeology dig through git logs. With it, the answer is one glance at Grafana.

---

## Deploy Markers on Every Dashboard

**Deploy markers** are timestamped annotations on your metric visualizations. When something regresses, the marker tells you which deploy is a candidate cause.

**How to emit:**

- **Datadog** — `POST /api/v1/events` with the deploy details; or the Continuous Delivery Deployment feature auto-detects.
- **Grafana** — the annotations API, or Grafana Loki/Tempo integrations.
- **Sentry** — release tracking via `sentry-cli releases new/finalize`.
- **Honeycomb** — `honeycomb markers create`.

Put the git SHA, environment, deployer identity, and the service name in every marker. Correlate with error rate, latency, and business KPIs.

Emit the marker **as the last step of the deploy job** — never before the deploy completes.

---

## SLIs and SLOs

A **Service Level Indicator** is a quantity you measure. A **Service Level Objective** is the threshold you commit to.

| Common SLI | Typical SLO |
|-----------|-------------|
| Successful requests / total requests | 99.9% over 30 days |
| p95 latency | < 300 ms over 24 hours |
| Job success rate | > 99% over 7 days |
| Data freshness (ETL) | < 15 min lag, 99% of the time |
| Availability | 99.95% monthly |

The gap between actual and target is your **error budget**. Every deploy consumes budget if it degrades an SLI; automated rollback triggers when the budget-burn rate exceeds a threshold.

Google's SRE Book is the canonical reference. Datadog, Nobl9, Sloth, and OpenSLO codify it in tooling.

---

## Automated Rollback Triggers

Rollback should not require a human at 3am if a machine can decide. Triggers:

- **Error rate spike** — canary's 5xx rate > baseline + 2σ over 5 min → rollback.
- **Latency degradation** — p95 > 1.5× baseline sustained → rollback.
- **SLO burn rate** — burning 30-day budget at 14.4× (5% consumed in 1 hour) → rollback.
- **Deploy healthcheck failure** — new pods don't reach healthy in N minutes → rollback.

Progressive delivery controllers automate this:

- **Argo Rollouts** — `AnalysisTemplate` queries Prometheus / Datadog / New Relic; failed analysis triggers automatic canary abort.
- **Flagger** — built-in Prometheus templates for request-success-rate and request-duration; automated promotion/rollback per canary step.

See [[CI-CD - Deployment Strategies]] for the strategy layer these tools implement.

---

## Datadog Deploy Tracking (Concrete Example)

Datadog Continuous Delivery ties deploys to their downstream impact:

- **Auto-detected deploys** — Datadog observes registry pushes / k8s manifest updates and records them.
- **Change overlays** — every timeseries gets clickable annotations for recent deploys.
- **Rollback detection** — Datadog identifies when a deploy is reverted; correlates with the incident that prompted it.
- **Deployment success/failure metrics** — feed DORA dashboards directly.

Similar patterns in Grafana Cloud (Application Observability), Honeycomb (Query Assistant + Markers), New Relic (Change Tracking).

---

## DORA Metrics — Instrumentation

The four core metrics require joining CI/CD data with incident data:

| Metric | Sources needed |
|--------|---------------|
| **Deployment frequency** | Deploy events per service per day |
| **Lead time for changes** | PR merged-at → deploy-to-prod timestamp |
| **Change failure rate** | Deploys / incidents-caused-by-a-deploy |
| **Failed deployment recovery time** | Incident-start → resolution timestamp |
| **Reliability** (5th, 2021+) | SLO attainment |

**Tools that automate this:**
- **Sleuth** — pulls from GitHub / GitLab / Jira / PagerDuty and computes DORA metrics per service.
- **LinearB** — engineering-velocity + DORA.
- **Faros AI, Waydev, Jellyfish, LogRocket Galileo** — competing offerings.
- **CNCF DevLake** — open-source alternative.

Or roll your own with a scheduled job that queries CI, incident tracking, and version-control APIs.

**Don't turn these into stack-rank metrics.** DORA is a leading indicator of team health, not a productivity score. Elite teams *emerge* these metrics from disciplined practice; teams that target the metrics directly usually just game them.

---

## Incident Correlation

When something breaks, the first question is: "what changed?" A well-instrumented deploy pipeline should surface:

- Last deploy timestamp (per service) and git SHA.
- Which PRs are in that deploy (compare vs previous).
- Config changes (LaunchDarkly flag flips, feature toggles).
- Dependency changes (Renovate/Dependabot merges).

Tools that link all these:
- **LaunchDarkly Insights** — flag flips as first-class events on your dashboards.
- **PagerDuty Change Events** — deploys and flag flips ingested for correlation.
- **Datadog Watchdog** — auto-detects anomalies and correlates with recent deploys.

Half of good incident response is knowing what changed. The other half is knowing how to change it back — which is what fast, safe rollback (blue-green / feature-flag / canary) gives you.

---

## Post-Deploy Verification

The deploy pipeline shouldn't return "green" the moment `kubectl apply` succeeds. Add explicit post-deploy verification:

1. **Smoke tests** against the new environment — 5–10 critical paths.
2. **Synthetic monitoring** — external probes hitting user-facing endpoints.
3. **Metric-based bake time** — 5–15 minutes of watching key SLIs before considering the deploy complete.
4. **Business KPI check** — checkout success rate, funnel conversion, whatever measures user impact.

Automate all four; page on failure of any.

---

## Rollback Discipline

- **Rollback is a normal outcome, not a failure.** Track rollback rate; a rising trend is a signal.
- **Rollback should be as fast as rollforward.** If rolling back takes an hour, you deploy less often; deploy less often, and each deploy carries more change; more change means bigger regressions.
- **Test rollback in staging.** Not just the mechanism — the schema-compat contract that makes rollback possible.
- **Feature flags are a rollback mechanism**, not an alternative to real deploys. If a flag flip resolves 90% of incidents, invest in flag hygiene: naming, ownership, expiry.

---

## Change Failure Rate — What Counts

Not every incident is a change-failure. Definition: an incident caused by (or exposed by) a change made through the CI/CD pipeline. That means:

- ✅ New code shipped, error rate spiked → change failure.
- ✅ Config change, latency degraded → change failure.
- ✅ Dep bump introduced a regression → change failure.
- ❌ Third-party API outage → not a change failure.
- ❌ Traffic spike from a marketing campaign → not a change failure.

Elite teams sit at 0–15%. If you're above 30%, focus on smaller PRs, better testing, or faster canary windows — not on hiding failures.

---

## Summary

| Practice | Effect |
|----------|--------|
| Deploy markers on every dashboard | "What changed?" becomes a one-glance question |
| SLIs + SLOs + error budgets | Objective definition of "the deploy is healthy" |
| Argo Rollouts / Flagger `AnalysisTemplate` | Automated rollback on metric breach |
| DORA metrics instrumented (Sleuth / DevLake) | Objective team health signal |
| Bake time before "deploy complete" | Regressions caught before pipeline reports green |
| Feature flags as fast rollback | Milliseconds instead of minutes |
| Change events (LaunchDarkly / PagerDuty) | Incident correlation across code, config, deps |
| Practice rollback | Rollback is only fast if you've done it recently |

---

## Related Notes

- [[CI-CD - Fundamentals]] — DORA metrics and elite-team benchmarks
- [[CI-CD - Deployment Strategies]] — canary + metric analysis; feature flags as rollback
- [[CI-CD - Testing in Pipelines]] — smoke tests and synthetic monitoring
- [[GitHub Actions - Deployment Environments and Approvals]] — gates and post-deploy verification hooks
