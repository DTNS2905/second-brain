---
tags:
  - devops
  - docker
  - volumes
  - persistence
created: 2026-07-17
source: https://docs.docker.com/storage/
---

# Docker - Volumes and Persistence

> Container filesystems are ephemeral. Anything you need after `docker rm` must live outside the container — in a volume, a bind mount, or `tmpfs`. Back to [[Docker Guide]].

---

## Three Storage Mechanisms

| Kind | Location | Managed by Docker? | Best for |
|------|----------|-------------------|----------|
| **Named volume** | `/var/lib/docker/volumes/<name>/_data` | ✅ Yes | Production data (DBs, uploads) — portable, tooled |
| **Bind mount** | Any host path | ❌ No — just a path | Dev live-reload, injecting configs, mounting host tools |
| **`tmpfs`** | RAM (host memory) | ✅ Yes | Secrets, ephemeral caches, PID files |

The default when you `docker run` without specifying storage is a **container-writable layer** that dies with the container. Never store data there.

---

## Named Volumes (Production Default)

```bash
docker volume create pg-data
docker run -d --name db \
  -v pg-data:/var/lib/postgresql/data \
  postgres:16-alpine
```

Or with the more explicit `--mount` syntax (recommended in scripts because it fails loudly on typos):

```bash
docker run -d --name db \
  --mount type=volume,source=pg-data,target=/var/lib/postgresql/data \
  postgres:16-alpine
```

**Why prefer volumes over bind mounts for data:**
- Path is opaque — the app doesn't care where on the host the bytes live.
- Portable across hosts when combined with a volume driver (NFS, EFS, Ceph).
- `docker volume ls` / `inspect` / `prune` — first-class management.
- No UID/GID surprises. Bind mounts inherit the host user's ownership; named volumes are initialized from the image path's owner on first use.
- Compose auto-creates them from the top-level `volumes:` block.

---

## Bind Mounts (Dev Convenience)

A bind mount grafts a host path into the container:

```bash
docker run --rm -it \
  -v "$(pwd)":/app \
  -w /app \
  node:22-alpine \
  npm test
```

**Use for:**
- Live-reload during dev — edit on host, see changes instantly.
- Injecting per-environment config files at runtime.
- CI: mounting the workspace into a builder container.

**Watch out for:**
- **UID mismatch** — files written by a container running as `root` end up `root`-owned on the host, breaking editors. Solve with `USER $UID:$GID` at runtime.
- **Docker Desktop performance** — bind mounts on macOS/Windows cross the VM boundary; large repos + heavy filesystem work (bundlers, test runners) can be 5–10× slower than native. Mitigations: `:cached` / `:delegated` consistency flags (older), or VirtioFS in Docker Desktop 4.6+.
- **Path leaks** — mounting `/` or `/etc` gives the container the host's real filesystem. Avoid overly-broad mounts.

---

## `tmpfs` — In-Memory Ephemeral

For data that must not touch disk (secrets fetched at runtime, scratch space):

```bash
docker run --rm \
  --tmpfs /tmp:rw,size=64m,mode=1777 \
  myapp:latest
```

- Never persisted anywhere.
- Faster than any disk-backed option.
- Sized in RAM — set a cap.

Compose secrets are effectively `tmpfs`-backed under the hood — that's why `/run/secrets/<name>` doesn't survive a restart of the container.

---

## Read-Only Mounts

Mount a config directory read-only so the container can't tamper with it:

```bash
docker run -d \
  -v /etc/myapp/config:/config:ro \
  myapp:latest
```

Combine with `--read-only` (makes the *whole container FS* read-only) and a small named `tmpfs` for `/tmp` — a strong security posture. See [[Docker - Security]].

---

## Backup Patterns

Named volumes are just directories on the host. Two idioms:

### One-shot tar dump

```bash
docker run --rm \
  -v pg-data:/data:ro \
  -v "$(pwd)":/backup \
  alpine tar czf /backup/pg-data-$(date +%F).tgz -C /data .
```

Spins a throwaway alpine container that reads the volume read-only and writes a compressed tarball to the current directory.

### Cross-host copy

```bash
# on source host
docker run --rm -v pg-data:/data alpine tar czf - -C /data . \
  | ssh dest 'docker run --rm -i -v pg-data:/data alpine tar xzf - -C /data'
```

### Application-native backups (preferred for DBs)

Stateful services usually ship their own backup tools that respect transactions:
- Postgres → `pg_dump` / `pg_basebackup` / WAL archiving.
- MySQL → `mysqldump` / `xtrabackup`.
- Redis → `SAVE` / `BGSAVE` + AOF snapshots.
- Object stores (Minio, etc.) → their replication feature.

Copying raw data files while the DB is running is a corruption risk. Snapshot after a clean shutdown, use LVM/ZFS filesystem snapshots, or use the DB's own online backup tool.

---

## Deprecated: `volumes_from`

`--volumes-from <container>` (and the Compose v2-file `volumes_from:` key) is legacy. It let one container inherit another's mounts. Modern practice: define named volumes at the top level and reference them from each service.

---

## Cleanup

```bash
docker volume ls                 # list
docker volume ls -qf dangling=true   # not referenced by any container
docker volume prune              # remove all dangling
docker volume rm pg-data         # explicit removal
```

Volumes are **not** removed with the container by default. `docker rm -v <container>` removes anonymous volumes tied to it; named volumes always survive.

---

## Summary

| Situation | Reach for |
|-----------|-----------|
| Production database, uploads, model files | Named volume + application-native backup tool |
| Dev live-reload of source code | Bind mount (`-v "$(pwd)":/app`) |
| Per-env config, TLS certs, k8s ConfigMaps | Read-only bind or projected volume |
| Runtime secrets that mustn't hit disk | `tmpfs` mount (`--tmpfs`) or Compose secrets |
| Backup a named volume | `tar cz` via ephemeral alpine, or the DB's own tooling |
| macOS/Windows dev with big repos | Bind + VirtioFS, or move to a devcontainer / native volume |

---

## Related Notes

- [[Docker - Compose for Dev Environments]] — `volumes:` top-level block and per-service `volumes:`
- [[Docker - Security]] — read-only root FS + tmpfs for `/tmp` = harder to persist an exploit
- [[Docker - Fundamentals]] — why the container-writable layer is not a durable store
