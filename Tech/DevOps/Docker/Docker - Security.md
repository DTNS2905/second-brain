---
tags:
  - devops
  - docker
  - security
  - hardening
  - secrets
created: 2026-07-17
source: https://docs.docker.com/engine/security/
---

# Docker - Security

> Containers share the host kernel — a compromise doesn't stop at the container boundary by default. Non-root `USER`, dropped capabilities, read-only FS, BuildKit secret mounts, and image scanning form the 2026 baseline. Back to [[Docker Guide]].

---

## Non-Root `USER` — The Single Highest-Value Change

Docker docs: *"If a service can run without privileges, use USER to change to a non-root user."*

```dockerfile
FROM node:22-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --chown=app:app package*.json ./
RUN npm ci --omit=dev
COPY --chown=app:app . .
USER app
CMD ["node", "server.js"]
```

Why it matters: a container process running as UID 0 that escapes its namespace (through a kernel bug, misconfigured mount, or shared socket) starts as **root on the host**. A non-root UID keeps the blast radius bounded even if isolation fails.

**Randomized UIDs (OpenShift model)**: use a high, arbitrary UID (e.g. `10001`) that doesn't map to any real host account. Linux enforces file permissions by numeric UID — no `/etc/passwd` entry required. Just make sure `WORKDIR` and any writable paths are `chown`ed to it.

**Avoid `sudo`**: Docker docs flag it as having *"unpredictable TTY and signal-forwarding behavior."* If you need to elevate at build time, do it as `USER root` and switch back with `USER app`.

---

## Drop Capabilities

Linux capabilities split root's power into ~40 fine-grained bits (`CAP_NET_BIND_SERVICE`, `CAP_SYS_ADMIN`, `CAP_SYS_PTRACE`, …). By default, containers get a reduced set — but "reduced" still includes several dangerous ones.

```bash
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE nginx
```

- **`--cap-drop ALL`** — start from nothing.
- **`--cap-add <NAME>`** — add back only what your app needs.

Common minimal capabilities:
- Web server binding to port 80/443: `NET_BIND_SERVICE`.
- No capabilities at all: most Go/Rust services on high ports.

Compose equivalent:

```yaml
services:
  api:
    cap_drop: ["ALL"]
    cap_add: ["NET_BIND_SERVICE"]
```

---

## Never Run `--privileged`

`docker run --privileged` disables *all* security features — capabilities, seccomp, AppArmor, device restrictions. The container gets full access to the host's devices and kernel interfaces.

Reserved for very narrow cases (docker-in-docker for CI, some hardware-facing workloads). Any general-purpose service running `--privileged` is a bug.

---

## Read-Only Root Filesystem

```bash
docker run --read-only --tmpfs /tmp myapp:latest
```

Or in Compose:

```yaml
services:
  api:
    read_only: true
    tmpfs:
      - /tmp
      - /run
```

Combined with a non-root `USER`, this makes it much harder for an exploit to persist — an attacker can't drop a binary anywhere writable. Apps that need writable paths get explicit `tmpfs` or a named volume; everything else is immutable.

---

## Seccomp, AppArmor, SELinux (Defense in Depth)

| Mechanism | What it does | Docker's default |
|-----------|-------------|------------------|
| **Seccomp** | Filters syscalls | Docker ships a default profile blocking ~50 dangerous syscalls (out of ~330) |
| **AppArmor** | MAC policy (Debian/Ubuntu) | Uses `docker-default` policy on hosts where installed |
| **SELinux** | MAC policy (RHEL/CentOS/Fedora) | Requires `--security-opt label=…` opt-in |

These are usually invisible — the defaults work — but a real production host should keep the defaults enabled and layer additional policies for high-value services. Kubernetes SecurityContext lets you pin `seccompProfile: RuntimeDefault` explicitly.

Layering non-root USER + dropped capabilities + seccomp + AppArmor is the standard hardening stack (Sysdig, CIS Docker Benchmark, NSA/CISA Kubernetes Hardening Guidance).

---

## Secrets — Never in `ARG` or `ENV`

Docker's own build check `SecretsUsedInArgOrEnv` fails a build that does this. Reason: **`ARG` values are written into the image history**, and **`ENV` values are runtime-visible via `docker inspect`** and persist in layers.

### ❌ Persisted in image forever

```dockerfile
ARG NPM_TOKEN
RUN npm config set //registry.npmjs.org/:_authToken=$NPM_TOKEN && npm ci
```

`docker history` shows the `ARG` value. Anyone who pulls the image can read it.

### ✅ BuildKit secret mount — never persisted

```dockerfile
# syntax=docker/dockerfile:1
RUN --mount=type=secret,id=npm_token \
    npm config set //registry.npmjs.org/:_authToken=$(cat /run/secrets/npm_token) && \
    npm ci --omit=dev
```

```bash
docker build --secret id=npm_token,src=$HOME/.npmrc-token .
```

The secret is mounted at `/run/secrets/npm_token` **only for the duration of that `RUN` step**. No layer, no history, no metadata leak.

**Runtime secrets** — use a real secrets manager (AWS Secrets Manager, GCP Secret Manager, HashiCorp Vault, Kubernetes Secrets), or mount them via Compose secrets / Kubernetes projected volumes. Never bake them into images. See [[CI-CD - Secrets Management]].

---

## Pin Base Images by Digest

Tags move. Digests don't. Pin bases to `@sha256:…` so a compromised upstream tag can't silently poison your next rebuild — and automate the digest updates via Docker Scout / Renovate / Dependabot so you get PRs for patched builds. See [[Docker - Image Optimization]].

---

## Image Vulnerability Scanning

Scan every image in CI before it ships. Common tools:

| Tool | Notes |
|------|-------|
| **Trivy** (Aqua Security) | Open source, fast, wide DB coverage (OS + language). De-facto default in 2026. |
| **Grype** (Anchore) | Open source. Pairs with Syft for SBOM generation. |
| **Docker Scout** | Docker's own; deeply integrated with Docker Hub, does digest-update PRs. |
| **Snyk** | Commercial; strong on language ecosystems (npm, PyPI, Maven). |

Typical CI wiring:

```yaml
- uses: aquasecurity/trivy-action@0.28.0
  with:
    image-ref: ghcr.io/acme/api:${{ github.sha }}
    severity: HIGH,CRITICAL
    exit-code: 1
    ignore-unfixed: true
```

`ignore-unfixed: true` avoids paging on CVEs with no upstream patch (which you can't fix by rebuilding). See [[GitHub Actions - Security Hardening]].

---

## Signing and Provenance (Supply Chain)

- **Sigstore / cosign** — sign images with keyless OIDC; verify at pull time.
- **SBOM** — Software Bill of Materials. Generate with Syft, attach to the image, and let scanners consume it.
- **Provenance attestations** — BuildKit can emit SLSA-format attestations describing how an image was built.

These matter for regulated environments (FedRAMP, PCI, DORA), and are becoming table stakes for anyone shipping images others depend on.

---

## Summary

| Control | Effect |
|---------|--------|
| Non-root `USER` (randomized UID) | A namespace escape doesn't land as host root |
| `--cap-drop ALL` + narrow `--cap-add` | Fine-grained privilege minimization |
| Never `--privileged` | Keeps seccomp/apparmor/capabilities in play |
| `--read-only` + explicit `tmpfs` | Attacker can't persist a payload anywhere writable |
| Default seccomp + AppArmor/SELinux | Defense in depth against unknown kernel bugs |
| BuildKit `--mount=type=secret` | Build-time secrets never touch layers or history |
| Digest-pinned bases | Supply-chain integrity; automate the update cycle |
| Trivy / Grype / Docker Scout in CI | Block known-vulnerable images before deploy |
| Sigstore / cosign + SBOM | Verifiable provenance up the chain |

---

## Related Notes

- [[Docker - Dockerfile Best Practices]] — secret mounts and BuildKit basics
- [[Docker - Image Optimization]] — digest pinning and small bases (smaller attack surface)
- [[Docker - Volumes and Persistence]] — read-only bind + tmpfs pattern
- [[CI-CD - Secrets Management]] — runtime secrets, vaults, OIDC federation
- [[CI-CD - Security and Compliance]] — SAST/DAST/SBOM in the pipeline
- [[GitHub Actions - Security Hardening]] — SHA-pinned actions, GITHUB_TOKEN permissions
