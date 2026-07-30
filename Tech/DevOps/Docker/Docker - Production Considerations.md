---
tags:
  - devops
  - docker
  - production
  - registry
  - orchestration
created: 2026-07-17
source: https://docs.docker.com/
---

# Docker - Production Considerations

> What changes between `docker run` on a laptop and shipping to production: **registry choice, tagging strategy, and orchestrator**. Back to [[Docker Guide]].

---

## Registry Choice

| Registry | Pros | Cons | Best for |
|----------|------|------|----------|
| **Docker Hub** | Ubiquitous, free public repos | Rate limits (100–200 pulls/6h anonymous, higher when logged in), no fine-grained IAM | Public images only |
| **GHCR** (`ghcr.io`) | Free for public repos, seamless GitHub Actions OIDC, GitHub-native permissions | GitHub-centric | Anyone already on GitHub |
| **ECR** (AWS) | Cheap egress inside AWS, IAM integration, immutable-tag policy | AWS-only IAM makes external CI harder | AWS workloads |
| **Artifact Registry / GCR** (GCP) | Cheap intra-GCP egress, IAM integration | GCP-only IAM | GCP workloads |
| **Azure ACR** | Same story on Azure | Azure-only IAM | Azure workloads |
| **Harbor** (self-hosted) | Full control, replication, scanning, RBAC | You run it | Air-gapped or heavy-regulation shops |
| **Cloudsmith / JFrog / Quay** | Multi-format, mature UI | Commercial | Larger orgs with multi-format artifact needs |

**Rate limits matter**: unauthenticated `docker pull` from Docker Hub is the classic CI outage. Mirror `docker.io` through your own registry or authenticate CI pulls.

---

## Tagging Strategy

Tags are mutable — a policy question, not a technical one. The three strategies you'll see:

### 1. Immutable Git SHA (production-grade)

```
ghcr.io/acme/api:git-a1b2c3d
```

- **Immutable** — the same tag always points at the same bytes.
- **Traceable** — you know exactly what commit shipped.
- Deploy manifests reference `:git-sha`, not `:latest`.
- Combine with digest pinning for full supply-chain integrity.

### 2. Semver (for libraries and public tools)

```
ghcr.io/acme/cli:v1.4.2
ghcr.io/acme/cli:v1.4
ghcr.io/acme/cli:v1
ghcr.io/acme/cli:latest
```

Multiple mutable tags — `v1` moves when you release `v1.5.0`, `v1.5` moves when you release `v1.5.1`. Fine for consumers who opt into looseness.

### 3. `:latest` (don't, in production)

`:latest` is a **default tag**, not a stable pointer. It means "whichever image was pushed most recently". Prod deploys pointing at `:latest`:
- Different pods on the same deploy pull different bytes if a push happens mid-rollout.
- Rollback is guesswork.
- Autoscaling brings up new pods with newer bytes than the ones that were serving.

**Rule**: production references `:git-sha` or a digest. `:latest` is fine for dev.

---

## Immutable Tags at the Registry

Most registries can enforce **tag immutability** (ECR: `IMMUTABLE`, GHCR: repo setting, Harbor: retention rules). Turn it on for prod repos — a push with an existing tag fails. Combined with `:git-sha` tagging, it's impossible to accidentally overwrite a released version.

---

## Orchestration Landscape (2026)

You need something to deploy, scale, and heal containers across hosts. The realistic options:

| Orchestrator | Model | Sweet spot |
|--------------|-------|------------|
| **Kubernetes** | Declarative, YAML, controllers | The default at every scale in 2026; huge ecosystem. |
| **AWS ECS** | Managed, task/service model, tight AWS integration | Small–medium AWS shops that want less operational surface than EKS. |
| **AWS Fargate** | Serverless containers (ECS or EKS runtime) | No node management; per-second billing. |
| **GCP Cloud Run** | Serverless; scales to zero | Request-driven services with idle periods. |
| **Nomad** (HashiCorp) | Simpler than K8s; unified scheduler for containers + VMs + batch | Ops-lean teams; mixed workloads. |
| **Docker Swarm** | Native Docker orchestration | Deprecated for new work; still runs but Docker Inc. de-emphasizes it. |

**Rough decision matrix:**

- One or two services, small team, on AWS → **Fargate** or **App Runner**.
- Ten+ services, multi-team, any cloud → **Kubernetes** (EKS/GKE/AKS or self-managed).
- Mixed containers + VMs + batch, small ops team → **Nomad**.
- Purely event-driven, spiky traffic → **Cloud Run** / **Lambda container images**.
- You inherited it → **ECS** is a fine place to stay.

**Compose is not on this list.** Compose is dev/CI tooling. Don't run production traffic on `docker compose up` on a single VM — no scheduling, no healing across nodes, no rolling updates worth the name.

---

## From Compose to Orchestrator

- **Compose Bridge** (Docker's tool) converts `compose.yaml` to Kubernetes manifests.
- **Kompose** (CNCF) — the older/simpler alternative; same idea.

Both give you a starting point, not a finished production config. Real production adds: HorizontalPodAutoscaler, PodDisruptionBudgets, resource requests/limits, NetworkPolicies, ServiceMonitors, Ingress, etc. Compose has no equivalent for any of these.

---

## CI-to-Registry-to-Cluster (The Standard Flow)

```
git push ─▶ CI builds ─▶ docker push ghcr.io/acme/api:git-$SHA ─▶ update deploy manifest ─▶ kubectl apply / ArgoCD sync
```

Two variants for the "update deploy manifest" step:

- **Push-based**: the CI job runs `kubectl set image` or `helm upgrade`. Fast, direct, tightly coupled to CI credentials.
- **Pull-based (GitOps)**: CI writes the new tag into a Git repo that ArgoCD / Flux watches. Cluster pulls itself. Auditable, easier to reason about, standard in 2026.

See [[CI-CD - Deployment Strategies]] and [[GitHub Actions - Deployment Environments and Approvals]].

---

## What You Still Own (Even On Managed Kubernetes)

The cloud gives you the control plane. You own:

- **Base image hygiene** — pinning, scanning, patching.
- **Resource requests/limits** — nothing else stops one bad service from OOMing others.
- **NetworkPolicies** — the default is "everything can talk to everything".
- **PodSecurityStandards / OPA / Kyverno** — enforce non-root, drop caps, no `hostPath`.
- **Secrets** — External Secrets Operator + a real vault, not raw K8s Secrets.
- **Observability** — Prometheus, OpenTelemetry, log aggregation.

The container ecosystem's job is to give you well-shaped defaults. Production is the discipline of not undoing them.

---

## Summary

| Decision | 2026 default |
|----------|--------------|
| Registry | GHCR if on GitHub; cloud-native registry (ECR/GAR/ACR) inside a cloud; Harbor if air-gapped |
| Production tag | `git-<sha>` (immutable) + optional digest pin |
| Never in prod | `:latest`, unauthenticated Docker Hub pulls |
| Orchestrator | Kubernetes if scale/multi-team; managed serverless (Fargate, Cloud Run) if not |
| Deploy model | GitOps (ArgoCD/Flux) pulling from a manifest repo, over push-based `kubectl` |
| Rate limit gotcha | Mirror or authenticate Docker Hub pulls; don't rely on anonymous |
| Immutable tags at registry | Turn on for prod repos |

---

## Related Notes

- [[Docker - Image Optimization]] — digest pinning; where prod-ready images come from
- [[Docker - Security]] — what "prod-ready image" actually means
- [[CI-CD - Deployment Strategies]] — blue-green, canary, rolling in the orchestrator layer
- [[GitHub Actions - Deployment Environments and Approvals]] — protection rules around prod deploys
- [[DevOps Guide]] — parent index
