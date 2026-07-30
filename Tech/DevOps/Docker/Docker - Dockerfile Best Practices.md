---
tags:
  - devops
  - docker
  - dockerfile
  - buildkit
  - performance
created: 2026-07-17
source: https://docs.docker.com/build/building/best-practices/
---

# Docker - Dockerfile Best Practices

> Multi-stage builds, layer ordering, `.dockerignore`, and BuildKit cache mounts — the four levers that determine whether your image is 3 MB or 3 GB and whether your rebuild takes 2 seconds or 2 minutes. Back to [[Docker Guide]].

---

## Multi-Stage Builds (The Foundational Pattern)

Separate the **build stage** (compilers, dev deps, tests) from the **runtime stage** (only the artifact your app needs to run). BuildKit only rebuilds a shared stage once per invocation.

### ❌ Single-stage — ships build tooling

```dockerfile
FROM golang:1.23
WORKDIR /app
COPY . .
RUN go build -o server .
CMD ["./server"]
# Final image: ~800 MB. Ships the whole Go toolchain.
```

### ✅ Multi-stage — ships only the binary

```dockerfile
# ---- build stage ----
FROM golang:1.23 AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/server .

# ---- runtime stage ----
FROM gcr.io/distroless/static-debian12 AS runtime
COPY --from=build /out/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
# Final image: ~15 MB. Only the binary.
```

**Name stages with `AS <name>`** — `COPY --from=build` stays valid even if you reorder stages later. Reference by position (`COPY --from=0`) is fragile.

---

## Layer Ordering for Cache Reuse

Every instruction produces a layer whose content is hashed. **Any change invalidates every layer that follows.** Rule: expensive/stable steps early, frequently-changing steps late.

### ❌ Copies everything before installing deps — every source edit re-runs `npm ci`

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
CMD ["node", "server.js"]
```

### ✅ Copy manifests first, install, then copy source

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
CMD ["node", "server.js"]
```

Now `npm ci` only re-runs when `package.json` or `package-lock.json` changes — not on every source edit. This one reorder can cut CI build time by 90%.

---

## `.dockerignore` — Prune the Build Context

Everything not in `.dockerignore` gets shipped from your working directory to the daemon at the start of every build. A stray `node_modules/` or `.git/` can add hundreds of MB and slow every build.

```gitignore
# .dockerignore
.git
.github
node_modules
dist
build
coverage
.env*
*.log
.DS_Store
.vscode
.idea
Dockerfile.dev
docker-compose*.yml
README.md
```

Rules follow the same syntax as `.gitignore`. If a directory is copied into the image (via `COPY . .`) but you have a local `node_modules/` for editor tooling, without `.dockerignore` it gets baked in — silently overriding what `npm ci` produced inside the container.

---

## BuildKit Cache Mounts

Cache mounts (`RUN --mount=type=cache,...`) give a directory a **persistent cache location** that survives across builds without ending up in the image. Ideal for package-manager caches.

```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

FROM python:3.12-slim AS py
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

The cache lives on the builder, not in the image. Only new/changed packages get downloaded on subsequent builds. The `# syntax=` directive is required to opt in to Dockerfile v1 features.

---

## BuildKit Secret Mounts

Secrets injected at build time (private-repo tokens, package registry credentials) must **never** land in a layer. Use `--mount=type=secret`:

```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine
RUN --mount=type=secret,id=npm_token \
    npm config set //registry.npmjs.org/:_authToken=$(cat /run/secrets/npm_token) && \
    npm ci --omit=dev
```

Build with `docker build --secret id=npm_token,src=$HOME/.npmrc-token .`. The file is exposed only for the duration of that `RUN` step — no layer, no image history, no `docker inspect` leak.

See [[Docker - Security]] for why `ARG`/`ENV` for secrets is a hard "no".

---

## Instruction Cheatsheet

| Instruction | Creates Layer? | Notes |
|-------------|---------------|-------|
| `FROM` | — | Sets the base; can appear multiple times (multi-stage) |
| `RUN` | ✅ | Chain related commands with `&&` to avoid layer bloat |
| `COPY` | ✅ | Prefer `COPY` over `ADD`; `ADD` also does URL fetch + tar extract (surprising) |
| `ADD` | ✅ | Only for local tarball extraction or when you need auto-extract |
| `ENV` | metadata | Set at build time; visible at runtime |
| `ARG` | metadata | Build-only; **not** a secret channel (see above) |
| `WORKDIR` | metadata | Create + cd, in one step |
| `USER` | metadata | Switch to non-root (see [[Docker - Security]]) |
| `EXPOSE` | metadata | Documentation only — does not publish ports |
| `HEALTHCHECK` | metadata | Runtime health probe; Compose reads this |
| `ENTRYPOINT` / `CMD` | metadata | `ENTRYPOINT` = required, `CMD` = default args |

---

## Chain `RUN` Commands, Clean in the Same Layer

### ❌ apt cache lives in a layer forever

```dockerfile
RUN apt-get update
RUN apt-get install -y curl
RUN rm -rf /var/lib/apt/lists/*   # doesn't shrink earlier layers!
```

### ✅ single layer, no cache leftover

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*
```

Cleanup in a *later* layer doesn't recover space — the earlier layer still has the data. Clean up **in the same `RUN`** that created the mess.

---

## Summary

| Lever | Effect |
|-------|--------|
| Multi-stage | 10–100× smaller final image; build tooling never ships |
| Layer order (manifests before source) | Rebuilds skip dep install on source-only changes |
| `.dockerignore` | Faster context upload, prevents leaking secrets/host cruft |
| Cache mounts (`--mount=type=cache`) | Cross-build cache for package managers, without image bloat |
| Secret mounts (`--mount=type=secret`) | Build-time credentials without layer persistence |
| Chained `RUN` + cleanup | No orphaned caches in earlier layers |
| Named stages (`AS name`) | `COPY --from=name` survives reorders |

---

## Related Notes

- [[Docker - Fundamentals]] — why layers work the way they do
- [[Docker - Image Optimization]] — base-image choice compounds these gains
- [[Docker - Security]] — build-time and runtime secret handling
- [[GitHub Actions - Caching and Artifacts]] — how BuildKit cache exports plug into CI
