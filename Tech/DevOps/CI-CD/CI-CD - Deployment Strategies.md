---
tags:
  - devops
  - ci-cd
  - deployment
  - progressive-delivery
  - argo-rollouts
  - flagger
created: 2026-07-17
source: https://argo-rollouts.readthedocs.io/en/stable/concepts/
---

# CI-CD - Deployment Strategies

> Big-bang deploys don't scale. The 2026 default is **progressive delivery** — blue-green or canary with automated promotion on metric health. Back to [[CI-CD Guide]].

---

## The Strategies

| Strategy | How it works | Best for |
|----------|-------------|----------|
| **Recreate** | Stop v1, start v2. Downtime. | Dev/CI, apps that can't run two versions concurrently |
| **Rolling** | Replace pods one (or N) at a time | Stateless services; the default `kubectl` behavior |
| **Blue-Green** | Deploy v2 alongside v1, flip traffic in one atomic switch | Fast rollback; DB-schema-compatible releases |
| **Canary** | Send a small % of traffic to v2, expand if healthy | High-risk changes; automated metric analysis |
| **Feature flags / dark launch** | v2 is deployed but disabled; flip a runtime flag | Decoupling deploy from release; per-user rollout |
| **Shadow / mirror** | Duplicate live traffic to v2; discard responses | Testing new code against prod traffic without impact |

---

## Vanilla Kubernetes Isn't Enough

Standard `Deployment` supports only `RollingUpdate` and `Recreate`. No traffic splitting, no metric-driven promotion, no active/preview services, no gated pause. For anything richer you use a **progressive delivery** controller.

---

## Argo Rollouts (Kubernetes Workload Replacement)

Argo Rollouts docs: *"a Kubernetes workload resource designed as a replacement for standard Deployments when advanced deployment capabilities are needed."*

- Drop-in replacement for `Deployment` (same PodSpec).
- First-class **blue-green** and **canary** strategies.
- Traffic control via ingress, service mesh (Istio, Linkerd, SMI, Ambassador, AWS ALB, Gloo, NGINX, Traefik), or plain Kubernetes services.
- **AnalysisTemplates** query metric providers (Prometheus, Datadog, New Relic, Wavefront, Kayenta, Graphite, InfluxDB, custom web/Job) to decide **promote** or **rollback**.

### Canary example (conceptual)

```yaml
spec:
  strategy:
    canary:
      steps:
        - setWeight: 5     # 5% traffic to v2
        - pause: {duration: 5m}
        - analysis:
            templates: [{templateName: success-rate}]
        - setWeight: 25
        - pause: {duration: 5m}
        - analysis:
            templates: [{templateName: success-rate}]
        - setWeight: 50
        - pause: {}         # wait for human "promote"
```

Failure in an `analysis` step triggers automatic rollback — the canary pods are removed and 100% of traffic returns to v1.

### Blue-Green

Two ReplicaSets, one active. Argo Rollouts flips the `activeService` selector after `previewService` passes analysis. Rollback is instant — just flip back.

---

## Flagger (CNCF Graduated, Flux CD)

Alternative to Argo Rollouts. Same idea (progressive delivery + metric analysis), different implementation footprint.

- Broad service-mesh matrix: **Istio, Linkerd, Kuma, Gateway API, Contour, Gloo, NGINX, Skipper, Traefik, Apache APISIX, Knative**.
- Metric providers: Prometheus, Datadog, CloudWatch, New Relic, Graphite, Dynatrace, InfluxDB, Google Cloud Monitoring.
- Built-in load tester (k6, nGrinder) and pre-rollout acceptance hooks (Helm tests, Bats, Concord).
- Progressive traffic shifting with session affinity.

Choose Flagger if you're on Flux CD or need broader mesh coverage; Argo Rollouts if you're on Argo CD. Both are CNCF-graduated and production-proven.

---

## Blue-Green in Detail

```
     ┌────────────┐         Router          ┌────────────┐
     │ v1 (blue)  │ ◀──── all traffic ────▶│  Router    │
     └────────────┘                         └────────────┘
     ┌────────────┐   deploy v2 here first,
     │ v2 (green) │   verify, then flip
     └────────────┘
```

Steps:
1. Deploy v2 to the "green" environment (idle capacity or ephemeral).
2. Smoke-test v2 with private traffic.
3. **Flip the router** to send 100% to v2.
4. Keep v1 running (idle) for N minutes/hours.
5. If problems appear, flip back — rollback in seconds.

Cost: 2× capacity during the overlap. Reward: near-instant rollback.

**Constraint**: the new version must be **schema-compatible** with the old — a running v1 and v2 must both be able to read/write the database. This forces expand-then-contract migrations (add nullable column → deploy code that reads new + old → backfill → deploy code that reads only new → drop old column).

---

## Canary in Detail

Route a small percentage of traffic to v2, expand if healthy:

```
Router ──▶ 95% v1
        └─▶ 5%  v2   ← observe metrics for N minutes
                     ↓ healthy?
        ┌─▶ 75% v1
        └─▶ 25% v2   ← observe, repeat
                     ↓
                    100% v2
```

**What you measure during canary:**
- HTTP/gRPC success rate (5xx count vs total).
- Latency (p95, p99).
- Business KPIs (checkout completion rate, error events).
- Custom SLIs from your instrumentation.

Flagger's built-in Prometheus templates cover HTTP/gRPC success rate and latency. Argo Rollouts' `AnalysisTemplate` lets you write arbitrary queries against any supported provider.

---

## Feature Flags (Deploy ≠ Release)

Deploy the code, but hide the new behavior behind a runtime flag. Release by flipping the flag — no redeploy, no rollback delay.

```
if (flags.isEnabled("new-checkout", user)) {
  return newCheckout(order);
}
return oldCheckout(order);
```

Providers: LaunchDarkly, Unleash (OSS), Split, Flagsmith, ConfigCat, GrowthBook. Or roll your own with a config file / DB row.

**Benefits:**
- Decouple deploy from release — deploy any time; release when ready.
- Rollback in milliseconds — flag off, no redeploy.
- Per-user rollout (5% of users, then 25%, then 100%).
- A/B testing on the same flag mechanism.

**Costs:**
- Every flag is a permanent branch in the code until removed. Delete flags aggressively.
- Testing surface multiplies — every combination of enabled flags is a code path.

**Rule**: flags are a tool for gradual rollout, not a permanent feature switchboard. If a flag has been at 100% for a month, delete both sides of the branch.

---

## Dark Launches / Shadow Traffic

Deploy v2 and send it a copy of live traffic; discard the responses. Verify v2 handles the load without exposing users. Then promote to real canary.

Enabled by service meshes (Istio `mirror`, Linkerd traffic split with mirroring). Especially useful for latency-sensitive or expensive-to-fix migrations (payment processors, ML inference stacks).

---

## GitOps: Where the Deploy Lives

Modern default: the deploy manifest is a file in a Git repo. A cluster controller (Argo CD or Flux) watches that repo and reconciles the cluster to match.

```
CI ──▶ builds & pushes image ─▶ opens PR to config repo ─▶ merge ─▶ ArgoCD/Flux syncs cluster
```

Benefits:
- Every deploy is a Git commit — full audit trail.
- Rollback = revert a Git commit.
- Cluster state converges to desired state automatically (self-heals if someone `kubectl edit`s live).
- CI credentials don't need cluster access — pull-based.

Argo Rollouts integrates with Argo CD; Flagger integrates with Flux CD. Both compose GitOps + progressive delivery naturally.

---

## Choosing a Strategy

| Situation | Reach for |
|-----------|-----------|
| Stateless service, low blast radius | Rolling (default) |
| High-risk migration, DB schema compatible | Blue-Green |
| Uncertain change, want automated rollback on real user impact | Canary + metric analysis |
| Need to release to a subset of users, or decouple deploy from release | Feature flags |
| Verifying v2 handles load before exposure | Shadow / mirror traffic |
| Regulated env — human must approve prod | CD + manual approval gate (see [[CI-CD - Pipeline Design Patterns]]) |

---

## Summary

| Strategy | Downtime | Rollback speed | Extra capacity | Metric-gated? |
|----------|---------|---------------|----------------|---------------|
| Recreate | Yes | Slow (redeploy) | None | No |
| Rolling | No | Slow (rolling back) | Minimal | No (default) |
| Blue-Green | No | Instant (flip) | 2× | Optional |
| Canary | No | Instant (drop canary) | Small | Yes (Rollouts/Flagger) |
| Feature flag | No | Milliseconds (flag off) | None (already deployed) | Optional |
| Shadow | No | N/A (no live traffic) | Depends on mirror ratio | N/A |

---

## Related Notes

- [[CI-CD - Fundamentals]] — CD vs. Continuous Deployment; the "always releasable" prerequisite
- [[CI-CD - Observability and Rollback]] — the metrics driving progressive delivery decisions
- [[Docker - Production Considerations]] — GitOps flow, immutable tags, registry choice
- [[GitHub Actions - Deployment Environments and Approvals]] — the gate mechanism in GitHub Actions
