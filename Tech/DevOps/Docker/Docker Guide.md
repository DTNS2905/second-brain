---
tags:
  - devops
  - docker
  - containers
created: 2026-07-17
source: https://docs.docker.com/
---

# Docker Guide

> **Docker** — the reference implementation of OCI containers. Package once, run anywhere Linux (or WSL2/HyperKit). These notes target production practice in **2026**, based on official Docker docs, CNCF guidance, and 2026 engineering blogs. Part of [[DevOps Guide]].

---

## Contents

| Note | Covers |
|------|--------|
| [[Docker - Fundamentals]] | Images vs containers, layers, OCI, the daemon/CLI split, registries |
| [[Docker - Dockerfile Best Practices]] | Multi-stage builds, layer ordering, `.dockerignore`, BuildKit cache mounts |
| [[Docker - Image Optimization]] | Base image choice (Alpine / Debian slim / distroless), size reduction, digest pinning |
| [[Docker - Compose for Dev Environments]] | Services, healthchecks, `depends_on` conditions, profiles, secrets |
| [[Docker - Networking]] | `bridge` / `host` / `overlay` drivers, port publishing, container-to-container DNS |
| [[Docker - Volumes and Persistence]] | Bind mounts vs named volumes vs tmpfs, backup patterns, `volumes-from` deprecation |
| [[Docker - Security]] | Non-root `USER`, dropped capabilities, read-only FS, BuildKit secret mounts, scanners |
| [[Docker - Production Considerations]] | Registries (ECR/GCR/GHCR/Docker Hub), tagging strategies, orchestration landscape |

---

## Vocabulary

| Term | Meaning |
|------|---------|
| **Image** | An immutable, layered filesystem + metadata (entrypoint, env, ports). Built from a `Dockerfile`. |
| **Container** | A running (or stopped) instance of an image — a process tree in isolated namespaces. |
| **Layer** | A read-only diff produced by a single `RUN` / `COPY` / `ADD` instruction. Content-addressed by SHA256. |
| **BuildKit** | The modern build backend (default since Docker Engine 23.0, Feb 2023). Parallel DAG solver, checksum-tracked cache, secret mounts, cache export. |
| **Registry** | A store for images. Docker Hub, GHCR, ECR, GCR, Harbor, etc. |
| **Compose** | A YAML-driven local orchestrator for multi-container dev stacks. Not for production. |
| **OCI** | The Open Container Initiative — the spec that defines image and runtime formats. Docker images are OCI images. |
| **runc / containerd** | The low-level runtime and daemon Docker uses under the hood. Kubernetes talks to containerd directly. |

---

## Mental Model

```
Dockerfile ──(docker build)──▶ Image ──(docker push)──▶ Registry
                                 │
                                 └──(docker run)──▶ Container (process in namespaces)
```

A **Dockerfile** is a recipe. An **image** is the frozen filesystem it produces. A **container** is one running instance of that image. The registry is where images live between build and deploy. See [[Docker - Fundamentals]].

---

## The 2026 Baseline (do these on every project)

1. **Multi-stage Dockerfiles** — never ship build tooling. → [[Docker - Dockerfile Best Practices]]
2. **BuildKit + `.dockerignore` + cache mounts** — every build should hit warm caches when only source changes.
3. **Small base image** — Alpine or distroless unless you have a glibc/CGO reason for Debian slim. → [[Docker - Image Optimization]]
4. **`USER` non-root** — no service runs as root. → [[Docker - Security]]
5. **Pin base images by digest** in production Dockerfiles (`FROM alpine:3.21@sha256:…`).
6. **Never** put secrets in `ARG` or `ENV`. Use `RUN --mount=type=secret,…` at build time; use runtime secret managers (or Docker/Compose secrets) at run time.
7. **Immutable tags in production** — deploy `image:git-sha`, not `image:latest`. → [[Docker - Production Considerations]]
8. **Scan images** (Trivy / Grype / Docker Scout / Snyk) in CI before push.

---

## When Docker Is / Isn't the Right Tool

**Reach for it when:**
- You need reproducible runtime environments across dev / CI / prod.
- Your team ships services that need to be portable across cloud providers.
- You want to standardize local dev with Compose.

**Skip it when:**
- You only ship a single binary to a fixed VM and dependencies are trivial (native Go/Rust with no system libs).
- You're on a serverless platform (Vercel, Cloudflare Workers, Lambda) that has its own packaging model.

---

## Related — Not Yet Covered

- **Kubernetes** — the dominant orchestrator; would live under `Tech/DevOps/Kubernetes/`.
- **Podman / nerdctl** — daemonless / containerd-native alternatives with mostly Docker-compatible CLIs.
- **Terraform / Pulumi** — infrastructure-as-code for the platform Docker runs on.

---

## Related Notes

- [[DevOps Guide]] — parent index
- [[CI-CD Guide]] — where Docker images are built and shipped from
- [[GitHub Actions Guide]] — `docker/build-push-action`, layer caching, registry auth via OIDC
