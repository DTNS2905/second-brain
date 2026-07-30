---
tags:
  - devops
  - github-actions
  - self-hosted-runners
  - kubernetes
  - actions-runner-controller
created: 2026-07-17
source: https://docs.github.com/en/actions/hosting-your-own-runners
---

# GitHub Actions - Self-hosted Runners

> Run jobs on machines you own. Cheaper at scale, required for internal network access or specialized hardware — but you now own security, capacity, and isolation. In 2026 the default self-hosted pattern is **Actions Runner Controller (ARC) on Kubernetes with ephemeral runners**. Back to [[GitHub Actions Guide]].

---

## Why (and Why Not) Self-hosted

**Reach for it when:**
- You need to reach internal networks / private endpoints CI otherwise can't.
- Specialized hardware — GPUs, huge RAM, ARM64 (if not using GitHub's ARM runners), macOS at scale.
- High minute burn — self-hosted amortizes below GitHub-hosted at ~5k minutes/month depending on region and machine size.
- Persistent state you can't recreate cheaply (huge language toolchains, base images pre-warmed).

**Skip when:**
- You'd otherwise ship long-lived runners with mutable state — a fresh VM per job is safer than a "just run it again" one.
- You don't have ops capacity — self-hosted requires runner-fleet management, autoscaling, security patching.
- You handle third-party PRs — untrusted code on self-hosted machines is a supply-chain nightmare (see Security below).

**Default recommendation for most teams**: use GitHub-hosted runners; graduate to self-hosted only when there's a concrete driver.

---

## Registration Basics

Runners register with GitHub and poll for jobs matching their labels:

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, x64, gpu]
```

Labels are a set — a runner offers many labels, jobs demand a subset. Custom labels (`gpu`, `high-mem`, `internal-net`) let you target specific pools.

Registration levels:
- **Repository-scoped** — one repo.
- **Organization-scoped** — any repo in the org (subject to runner groups).
- **Enterprise-scoped** — any org in the enterprise.

Organization scope + **runner groups** is the norm for anything larger than a single-repo hobby project.

---

## Runner Groups

Runner groups gate which repos can use which runners:

- Group `default` — the fallback.
- Custom groups — attach runners; configure which repos can access.
- Public-repo restrictions — critical: **do not allow public repos to schedule jobs on self-hosted runners** unless every workflow is trusted. A PR from a fork can execute arbitrary code.

Configure in Org → Settings → Actions → Runner groups.

---

## Ephemeral vs Persistent Runners

| | Persistent | Ephemeral |
|---|-----------|-----------|
| Lifecycle | Long-running; reuses OS between jobs | Fresh process per job; teardown after |
| State leakage | High — leftover files, env vars, background procs | None |
| Setup cost | Amortized across jobs | Every job pays |
| Security | Weak — a compromised job persists | Strong — process ends with the job |
| Recommended for | Never in 2026 | Always |

**Ephemeral runners are the modern default.** GitHub's own guidance and community best practice converge on: one job per runner, then the runner dies.

Configure `--ephemeral` on the runner binary, or use a controller (ARC) that spins fresh runners on demand.

---

## Actions Runner Controller (ARC) on Kubernetes

**ARC** — Kubernetes operator maintained by GitHub (formerly summerwind/actions-runner-controller, now the official `actions/actions-runner-controller`). Runs one **runner pod per job**, then terminates.

### Model

```
GitHub webhook (workflow_job queued) ──▶ ARC listener ──▶ scale RunnerScaleSet
                                                                │
                                                                ▼
                                                    Kubernetes creates pod
                                                                │
                                                                ▼
                                                    Runner registers, picks up the job
                                                                │
                                                                ▼
                                                    Job completes; pod terminates
```

### Setup outline

1. Install ARC via Helm chart (`actions-runner-controller/actions-runner-controller`).
2. Create a **GitHub App** with runner-registration permissions (or a PAT — App preferred).
3. Define a **`RunnerScaleSet`** (or the older `RunnerDeployment`) — specifies image, resources, labels, min/max replicas.
4. Set `runs-on: <scale-set-name>` in workflows.

Sample scale set (conceptual, Helm values):

```yaml
githubConfigUrl: https://github.com/acme
githubConfigSecret: github-app-secret
minRunners: 1
maxRunners: 50
runnerScaleSetName: k8s-linux-x64
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        resources:
          requests: { cpu: 1, memory: 2Gi }
          limits:   { cpu: 4, memory: 8Gi }
```

### Docker-in-Docker (DinD) Considerations

Runners inside pods that build Docker images need a way to run `docker build`. Options:
- **Docker-in-Docker sidecar** — a `dind` container beside the runner. Requires privileged; wide blast radius on compromise.
- **BuildKit / Buildx as a service** — a shared BuildKit daemon the runner talks to. Preferred; keeps the runner unprivileged.
- **Kaniko / Buildah** — daemonless builders that don't need privileged.

Don't run `--privileged` in ARC pods unless you understand the impact. See [[Docker - Security]].

### Autoscaling Model

ARC's `RunnerScaleSet` responds to GitHub's `workflow_job` webhooks — scale up on `queued`, scale down as pods exit. Contrast with the legacy horizontal pod autoscaler pattern (`RunnerDeployment` + HPA), which polled the GitHub API. Scale sets are the recommended 2026 approach.

---

## Larger GitHub-Hosted Runners

Before self-hosting, consider **larger runners** (paid tier):

- 4/8/16/32/64-vCPU Linux, macOS, Windows.
- More RAM, more disk.
- ARM64 options.
- **GPU** runners (Linux, NVIDIA T4 and larger).
- **Nested virtualization** on some SKUs.

Priced per minute, higher than base tier but far below "operate a Kubernetes runner fleet". Often the right first step when default runners are too small.

---

## Security Isolation

Self-hosted runners are a **first-class security surface**. Assume every job can:
- Read runner-local files.
- Reach any network the runner can reach.
- Persist changes if the runner isn't ephemeral.

Controls:

1. **Ephemeral runners.** Fresh pod/VM per job. Non-negotiable in 2026.
2. **No `pull_request` triggers on self-hosted runners for public repos.** Fork PRs can push arbitrary code.
3. **Runner groups** — pin repos to trusted runner pools; don't allow arbitrary repos to schedule.
4. **Least-privilege network policies.** Kubernetes NetworkPolicy or VPC security groups restricting egress.
5. **No cluster secrets in runner env.** Use OIDC federation to cloud, not baked-in credentials. See [[GitHub Actions - Secrets and OIDC]].
6. **Node isolation.** Dedicated nodepool for runners — don't schedule production workloads next to arbitrary CI jobs.
7. **StepSecurity Harden-Runner** — egress-policy sidecar that alerts / blocks unexpected outbound traffic during a job. Optional but useful for high-value repos.
8. **Read-only volumes and dropped capabilities** on the runner pod.
9. **Audit and rotate** GitHub App / PAT credentials the controller uses.
10. **Update runner images** promptly — CVEs land regularly.

---

## Cost Model (Rough)

- **Hosted default**: free minutes per plan (2000 Free / 3000 Team / 50000 Enterprise) + $0.008–0.016/min for Linux beyond.
- **Hosted larger**: ~2–8× base cost per minute, tiered by size.
- **Self-hosted**: cost of the underlying infra. On AWS EKS with spot nodes, cheap per minute if utilization is high (>50%).
- **Break-even**: usually somewhere between 5k–50k paid minutes/month depending on machine size and internal ops loading.

Don't forget the operational cost: someone owns runner upgrades, security patches, node draining, autoscaler tuning.

---

## Common Anti-Patterns

- ❌ Long-lived runners with `git clean` between jobs. State leaks; secrets from previous jobs may persist in `/tmp` or process memory.
- ❌ Same runner pool for `main` builds and fork PRs on a public repo. Fork jobs can steal from `main` jobs.
- ❌ Docker `--privileged` in ARC pods without threat modeling.
- ❌ Baking cloud creds into the runner image. Use OIDC.
- ❌ Runner nodes on the same subnet as production DBs, no network policy. A compromised job now has DB access.
- ❌ Skipping labels to "match anything" — you meant `runs-on: [self-hosted, linux]`, not `runs-on: self-hosted`.

---

## Summary

| Choice | Recommendation |
|--------|---------------|
| First option when hosted runners aren't enough | Larger hosted runners |
| Long-term self-hosted platform | ARC on Kubernetes with ephemeral scale sets |
| Runner lifetime | Ephemeral (one job per pod/VM) |
| Public repo PRs on self-hosted | Never (or strict runner group isolation) |
| DinD | Prefer BuildKit-as-a-service or daemonless builders |
| Credentials on runner | OIDC federation only; no static keys |
| Network posture | Least-privilege egress; dedicated nodepool |
| Monitoring | Pod-level metrics; StepSecurity Harden-Runner optional |

---

## Related Notes

- [[GitHub Actions - Security Hardening]] — the broader security context
- [[GitHub Actions - Secrets and OIDC]] — how to keep creds off runners
- [[Docker - Security]] — DinD, capabilities, non-root
- [[Docker - Production Considerations]] — Kubernetes as the runtime substrate
