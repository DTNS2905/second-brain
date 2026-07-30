---
tags:
  - devops
  - docker
  - containers
  - fundamentals
created: 2026-07-17
source: https://docs.docker.com/get-started/overview/
---

# Docker - Fundamentals

> The mental model — images, containers, layers, the OCI stack, and the daemon/CLI split. Back to [[Docker Guide]].

---

## Images vs Containers

| | Image | Container |
|---|---|---|
| **Nature** | Immutable filesystem + metadata | A running (or stopped) process tree using the image |
| **Storage** | Layered, content-addressed by SHA256 | Writable layer on top of the image (copy-on-write) |
| **Created by** | `docker build` (or `docker commit`, rarely) | `docker run` (or `docker create` + `docker start`) |
| **Analogy** | A class | An instance |

You build an image *once* and can run *many* containers from it.

---

## Layers and the Union Filesystem

Each `RUN`, `COPY`, or `ADD` in a Dockerfile produces a **layer** — a diff of filesystem changes, content-addressed by its SHA256. Layers are stacked with a union filesystem (`overlay2` on Linux) so the container sees a single merged view.

- Layers are **immutable and shared** — two images that both `FROM node:22-alpine` share every alpine + node layer, downloaded once.
- The container's own writes go to a thin **writable layer** on top; it disappears when the container is removed.
- Only `RUN` / `COPY` / `ADD` create filesystem layers. `ENV`, `WORKDIR`, `LABEL`, `CMD`, `ENTRYPOINT`, `EXPOSE` are metadata-only — no new layer, no size cost.

This is why [[Docker - Dockerfile Best Practices|layer ordering]] matters: a change to any layer invalidates the cache for *every layer after it*, forcing a rebuild.

---

## OCI: The Open Standard

The **Open Container Initiative** defines two specs Docker implements:

| Spec | What it standardizes |
|------|---------------------|
| **Image spec** | The layered on-disk format, manifest JSON, config JSON |
| **Runtime spec** | How a container is launched from an unpacked image (`runc` reference implementation) |

Because Docker images are OCI images, they run under *any* OCI runtime — `containerd`, `CRI-O`, `podman`, `nerdctl`. Kubernetes uses `containerd` (or `CRI-O`), not the Docker daemon.

---

## The Docker Stack (What's Actually Running)

```
docker CLI ──HTTP──▶ dockerd (daemon) ──▶ containerd ──▶ runc ──▶ container process
                                              │
                                              └──▶ containerd-shim (keeps container alive if dockerd restarts)
```

- **`docker`** is a thin CLI that talks HTTP to `dockerd`.
- **`dockerd`** manages images, networks, volumes, and Compose.
- **`containerd`** is the actual container lifecycle manager (donated to CNCF).
- **`runc`** does the low-level Linux syscalls (`clone`, `unshare`, `pivot_root`) to create the isolated process.

Podman removes the daemon entirely — you go straight `podman → runc`.

---

## Isolation Primitives

Containers aren't VMs — they're just Linux processes with strategically applied kernel features:

| Feature | What it isolates |
|---------|------------------|
| **Namespaces** (`pid`, `net`, `mnt`, `uts`, `ipc`, `user`) | The process's view of the world (PIDs, network interfaces, mounts, hostname) |
| **cgroups** | Resource limits (CPU shares, memory, block I/O, PIDs) |
| **Capabilities** | Fine-grained root privileges (drop them — see [[Docker - Security]]) |
| **Seccomp / AppArmor / SELinux** | Syscall and MAC filtering (defense in depth) |

Same kernel as the host. No hypervisor. That's why containers start in milliseconds where VMs take seconds.

---

## Registries

An image lives in a **registry** between `docker push` and `docker pull`. A full image reference is:

```
registry.example.com/namespace/repo:tag@sha256:digest
```

- **Registry** — `docker.io` (default), `ghcr.io`, `<account>.dkr.ecr.<region>.amazonaws.com`, `gcr.io`, `<region>-docker.pkg.dev`.
- **Tag** — mutable pointer (e.g. `22-alpine`, `latest`). *Can be moved by the publisher.*
- **Digest** — immutable SHA256 of the manifest. *Same digest = same bytes, forever.*

`docker pull node:22-alpine` today and next month may return different bytes. `docker pull node@sha256:abc…` never will. See [[Docker - Production Considerations]] for tagging strategy.

---

## The Container Lifecycle

```
docker build ──▶ image
docker create ──▶ container (stopped)
docker start  ──▶ container (running)
docker stop   ──▶ container (stopped, filesystem preserved)
docker rm     ──▶ gone
```

`docker run` is `create + start` in one shot. `docker run --rm` also does `rm` on exit — the default for one-shot jobs.

---

## Summary

| Concept | Takeaway |
|---------|----------|
| Image | Immutable, layered, content-addressed. Built once, run many. |
| Container | A process (tree) in namespaces + cgroups on the host kernel. Not a VM. |
| Layer | Diff from one Dockerfile instruction. Cached, shared, order-sensitive. |
| OCI | The spec Docker implements. Portable across runtimes. |
| Registry | Where images live between build and deploy. Reference by digest for reproducibility. |
| Daemon | `dockerd → containerd → runc`. Docker CLI talks to `dockerd` over HTTP. |

---

## Related Notes

- [[Docker - Dockerfile Best Practices]] — how to author images that build fast and stay small
- [[Docker - Image Optimization]] — base image choice, layer sharing, digest pinning
- [[Docker - Production Considerations]] — registries, tags, and orchestrators in depth
