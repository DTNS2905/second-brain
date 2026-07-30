---
tags:
  - devops
  - docker
  - optimization
  - security
  - supply-chain
created: 2026-07-17
source: https://docs.docker.com/build/building/best-practices/
---

# Docker - Image Optimization

> Pick the right base image, pin it by digest, and use BuildKit to compress the delta. Small images pull faster, expose less attack surface, and cost less to store. Back to [[Docker Guide]].

---

## Base Image Choice

| Base | Typical size | libc | Package manager | When to use |
|------|-------------|------|-----------------|-------------|
| **`scratch`** | 0 B | none | none | Static binaries (Go, Rust with musl target). Nothing to attack because nothing is there. |
| **`gcr.io/distroless/*`** | 2–30 MB | glibc | none | Compiled apps that need glibc (Java, Node, Python) but no shell. No `apt`, no `sh`. |
| **`alpine`** | ~6 MB | **musl** | `apk` | Small, familiar Linux env. Watch for musl vs glibc bugs (see below). |
| **`debian:*-slim`** | 30–80 MB | glibc | `apt` | Broad glibc compatibility, familiar Debian. Bigger CVE surface than Alpine. |
| **`ubuntu:*`** | 70–100 MB | glibc | `apt` | Only if you specifically need Ubuntu packages. |

Docker's own docs: *"A smaller base image not only offers portability and fast downloads, but also shrinks the size of your image and minimizes the number of vulnerabilities introduced through the dependencies."*

---

## Alpine vs Distroless vs Debian slim

**Alpine** — smallest general-purpose base. Uses **musl libc**, not glibc. This matters:
- Some prebuilt wheels/binaries (Python `manylinux`, some Node native modules) target glibc and won't work on musl without rebuilding.
- DNS resolution differs slightly (musl doesn't support all glibc resolver features).
- Time zone data is not included by default (`apk add tzdata`).

**Distroless** (`gcr.io/distroless/*`) — Google-maintained minimal images with **no shell, no package manager**. Just your runtime and a handful of libs.
- Great security surface (no `sh` = no interactive escape).
- Painful to debug (no `bash` for `docker exec -it`). Use the `:debug` variants during development.
- Requires an already-compiled binary — you can't `apt-get install` at runtime.

**Debian slim** — the safe default when Alpine breaks something.
- Larger, but broadest compatibility. Native modules "just work".
- Use `--no-install-recommends` and clean `apt` cache to trim.

**Rule of thumb**: try `distroless` for compiled languages (Go, Rust, static Node bundles). Fall back to `alpine` for scripting languages and CLI-heavy images. Fall back to `debian:*-slim` if either breaks.

---

## Pin Base Images by SHA256 Digest

Tags are mutable pointers — the publisher can move `node:22-alpine` to different bytes at any time. Digests are immutable.

### ❌ Reproducible only until upstream moves the tag

```dockerfile
FROM node:22-alpine
```

### ✅ Reproducible forever

```dockerfile
FROM node:22-alpine@sha256:9d70f6be...c8b3
```

Trade-off: you opt out of tag-based security patches. Automate digest updates via Docker Scout, Renovate, or Dependabot so you get a PR each time upstream ships a new patched build. Never pin and forget.

---

## Squash the Runtime Image

- **Multi-stage** — see [[Docker - Dockerfile Best Practices]]. Ship only artifacts, not the toolchain.
- **`--no-install-recommends`** — Debian/Ubuntu pull in optional deps by default.
- **`apk add --no-cache pkg`** — Alpine equivalent (no index update, no cache retention).
- **Clean up in the same `RUN`** — cleanup in a later layer doesn't shrink earlier ones.
- **Copy only what's needed** — `COPY dist/ /app/` beats `COPY . /app/`.
- **Skip package-manager metadata in runtime stage** — the runtime stage doesn't need `apt` or `npm`; a distroless final stage removes the temptation.

---

## Registry Cache Export

BuildKit can export its cache to a registry so CI runners share a warm cache. Without this, every fresh CI runner starts cold.

```bash
docker buildx build \
  --cache-from type=registry,ref=ghcr.io/acme/app:buildcache \
  --cache-to   type=registry,ref=ghcr.io/acme/app:buildcache,mode=max \
  --tag        ghcr.io/acme/app:$GIT_SHA \
  --push .
```

`mode=max` exports cache for every stage (not just the final one). See [[GitHub Actions - Caching and Artifacts]] for the CI-side wiring.

---

## Measure Before Optimizing

```bash
docker images                              # sizes at a glance
docker history <image>                     # per-layer size
docker buildx build --progress=plain .     # per-instruction time
dive <image>                               # interactive layer explorer
```

`dive` (a common third-party TUI) shows you which layer is fat and which files are dead weight. If the fat layer is `/var/lib/apt/lists/`, you forgot cleanup. If it's `node_modules/`, you copied dev deps.

---

## Multi-Arch Images

Production hardware is increasingly mixed (Intel/AMD + ARM64 for Graviton, Ampere, Apple Silicon). Build multi-arch with `buildx`:

```bash
docker buildx create --use --name mybuilder
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag ghcr.io/acme/app:$GIT_SHA \
  --push .
```

Both architectures live under one tag; the registry manifest list points at the right one per puller.

---

## Summary

| Lever | Payoff |
|-------|--------|
| Small base (Alpine / distroless) | 10–100× smaller than default; fewer CVEs |
| Digest pinning | Reproducible builds; supply-chain integrity |
| Multi-stage + `COPY --from=` | Runtime image never carries toolchain |
| Clean in the same `RUN` | Earlier-layer bloat can't be "fixed" later |
| `--no-install-recommends` / `--no-cache` | Trims dozens of MB of optional deps |
| Registry cache export (`buildx`) | CI runners share warm cache; fresh runners aren't cold |
| Multi-arch (`buildx --platform`) | One tag, both amd64 and arm64 |

---

## Related Notes

- [[Docker - Dockerfile Best Practices]] — layering rules that make optimization possible
- [[Docker - Security]] — smaller image = smaller attack surface
- [[Docker - Production Considerations]] — how tagging and digest strategy interact with deploys
- [[GitHub Actions - Caching and Artifacts]] — where registry cache export plugs in
