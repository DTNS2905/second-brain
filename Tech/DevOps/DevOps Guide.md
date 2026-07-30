---
tags:
  - devops
  - overview
  - ci-cd
  - docker
  - github-actions
created: 2026-07-17
source: https://dora.dev/
---

# DevOps Guide

> The parent index for DevOps notes in this vault — currently covering **Docker**, **CI/CD** (framework-agnostic), and **GitHub Actions**. Production-focused: real deploy patterns, security hardening, and observability, not tutorials.

---

## Subtopics

| Subtopic | Focus |
|----------|-------|
| [[Docker Guide]] | Containers, Dockerfile authoring, image optimization, Compose, networking, volumes, security, production considerations |
| [[CI-CD Guide]] | Trunk-based dev, pipeline patterns, deployment strategies (blue-green/canary/progressive delivery), testing, secrets, caching, supply-chain security, DORA metrics |
| [[GitHub Actions Guide]] | Workflow syntax, contexts, reusable workflows, matrix builds, caching, OIDC federation, self-hosted runners, security hardening, deployment environments |

---

## Mental Model

```
                            ┌─────────────────────┐
                            │   CI-CD principles  │  ← what & why
                            │  (framework-agnostic)│
                            └──────────┬──────────┘
                                       │ instantiated by
                        ┌──────────────┼──────────────┐
                        ▼              ▼              ▼
                ┌───────────┐   ┌──────────┐   ┌──────────┐
                │  Docker   │   │  GitHub  │   │  GitOps  │
                │  images   │   │  Actions │   │ (later)  │
                └───────────┘   └──────────┘   └──────────┘
                    build           run            deploy
```

- **[[CI-CD Guide]]** is the principles layer — trunk-based dev, progressive delivery, DORA metrics, SLSA/Sigstore.
- **[[Docker Guide]]** is the artifact layer — what CI/CD ships.
- **[[GitHub Actions Guide]]** is the concrete workflow engine expressing the principles.

Read the CI-CD guide first for the *why*; the GitHub Actions notes then read as the *how*.

---

## The 2026 DevOps Baseline (Cross-Cutting)

Pulled from all three subtopics:

| Practice | Where covered |
|----------|--------------|
| Trunk-based development, PRs merged within 24 h | [[CI-CD - Fundamentals]] |
| Small, digest-pinned base images with non-root `USER` | [[Docker - Security]] · [[Docker - Image Optimization]] |
| Multi-stage Dockerfiles + BuildKit cache mounts | [[Docker - Dockerfile Best Practices]] |
| Never `ARG`/`ENV` for secrets; use `--mount=type=secret` | [[Docker - Security]] |
| OIDC federation for cloud creds — no long-lived keys | [[CI-CD - Secrets Management]] · [[GitHub Actions - Secrets and OIDC]] |
| Progressive delivery (canary + auto rollback) | [[CI-CD - Deployment Strategies]] |
| Sigstore keyless signing + SLSA provenance | [[CI-CD - Security and Compliance]] |
| Pin GitHub Actions to full commit SHAs | [[GitHub Actions - Security Hardening]] |
| Restrict `GITHUB_TOKEN` to least privilege | [[GitHub Actions - Security Hardening]] |
| Environment protection rules for prod deploys | [[GitHub Actions - Deployment Environments and Approvals]] |
| Deploy markers on every dashboard | [[CI-CD - Observability and Rollback]] |

If your setup covers all eleven, you have a production-grade DevOps stack.

---

## Reading Order

1. **[[CI-CD - Fundamentals]]** — CI vs CD vs Continuous Deployment; trunk-based dev; DORA.
2. **[[Docker - Fundamentals]]** — images, containers, layers; the artifact model.
3. **[[Docker - Dockerfile Best Practices]]** + **[[Docker - Image Optimization]]** — how to build fast, small, secure images.
4. **[[CI-CD - Pipeline Design Patterns]]** + **[[GitHub Actions - Fundamentals]]** — the pipeline shape and its GitHub Actions expression.
5. **[[CI-CD - Deployment Strategies]]** + **[[GitHub Actions - Deployment Environments and Approvals]]** — how deploys actually go out.
6. **[[GitHub Actions - Security Hardening]]** + **[[CI-CD - Security and Compliance]]** + **[[Docker - Security]]** — the security triad; read together.
7. **[[CI-CD - Observability and Rollback]]** — closing the feedback loop.

---

## Related — Not Yet Covered

Areas that logically belong in DevOps but don't have notes yet. Candidates for future research passes:

- **Kubernetes** — the dominant orchestrator; would live under `Tech/DevOps/Kubernetes/`. Referenced throughout but not covered.
- **Terraform / Pulumi / OpenTofu** — infrastructure as code.
- **GitOps in depth** — Argo CD, Flux; only touched on in [[CI-CD - Deployment Strategies]].
- **Observability stack** — Prometheus, Grafana, OpenTelemetry, Loki, Tempo.
- **Service mesh** — Istio, Linkerd; canary traffic mechanics referenced but not detailed.
- **Platform engineering** — Backstage, Port, Humanitec; the "wrap CI/CD in golden paths" layer.
- **Cloud-specific compute** — AWS ECS/Fargate/EKS, GCP Cloud Run/GKE, Azure Container Apps/AKS.
- **Secrets management platforms in depth** — HashiCorp Vault, External Secrets Operator.

---

## Related Notes

- [[Docker Guide]] · [[CI-CD Guide]] · [[GitHub Actions Guide]] — the three subtopics under this parent
- [[Build Tools Foundations Guide]] — the layer beneath the CI pipeline (what your app is built with)
