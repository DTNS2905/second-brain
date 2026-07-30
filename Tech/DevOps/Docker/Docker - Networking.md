---
tags:
  - devops
  - docker
  - networking
created: 2026-07-17
source: https://docs.docker.com/network/
---

# Docker - Networking

> Every container gets a network namespace. Docker's job is to wire that namespace to a driver — `bridge`, `host`, `overlay`, or `none`. Back to [[Docker Guide]].

---

## Network Drivers

| Driver | Scope | Container-to-container | Container-to-host | Cross-host |
|--------|-------|-----------------------|-------------------|------------|
| **`bridge`** (default) | Single host | Yes, on same bridge | Via published ports | No |
| **`host`** | Single host | N/A — container shares host stack | Direct — no NAT | No |
| **`none`** | Single host | No network | No network | No |
| **`overlay`** | Multi-host (Swarm) | Yes, across nodes | Via published ports | Yes |
| **`ipvlan` / `macvlan`** | Single host | Yes, direct L2/L3 | Advanced — container gets its own MAC/IP on host LAN | No |

Default is `bridge`. For most single-host workloads, that's what you want.

---

## The Default Bridge vs User-Defined Bridges

Docker creates a network called `bridge` at install. **Do not use it** for anything beyond `docker run` demos.

| | Default `bridge` | User-defined bridge |
|---|-----------------|---------------------|
| Container DNS by name | ❌ No — must use `--link` (deprecated) | ✅ Yes — resolve peers by container/service name |
| Isolation from other networks | Weak | Strong |
| Runtime `--network-alias` | ❌ | ✅ |

Create your own:

```bash
docker network create app-net
docker run -d --name db  --network app-net postgres:16-alpine
docker run -d --name api --network app-net myapp:latest
# api can reach db at db:5432 — DNS is automatic
```

Compose creates a user-defined bridge per project — that's why services resolve each other by service name automatically.

---

## `host` Networking — When You Actually Want It

`--network host` skips the network namespace entirely. The container shares the host's interfaces, ports, and stack.

**Use when:**
- Ultra-low-latency requirements (adds no NAT overhead).
- Software that needs to observe the host network directly (Prometheus node exporter, some tracing agents).
- Port ranges too large to list in `-p` (e.g. WebRTC's ephemeral UDP range).

**Cost:**
- No isolation — the container's `netstat` is your host's.
- Port conflicts with the host and every other `host`-mode container.
- **Linux-only.** On Docker Desktop (macOS/Windows), `host` doesn't work the same way because the VM boundary makes it meaningless. Docker Desktop 4.29+ has an experimental host-networking feature; check status before relying on it.

---

## Port Publishing (`-p`)

```bash
docker run -p 8080:80 nginx           # host 8080 → container 80
docker run -p 127.0.0.1:8080:80 nginx # bind to loopback only — safer default
docker run -p 8080:80/udp nginx        # UDP
docker run -P nginx                    # publish all EXPOSEd ports to random host ports
```

### Common Pitfalls

**Binding to `0.0.0.0` by default.** `-p 8080:80` binds to all host interfaces — publicly reachable on cloud VMs. On a laptop behind a NAT it feels safe; on a bare EC2 instance it's not. Prefer `127.0.0.1:8080:80` unless you specifically want external access.

**`EXPOSE` does not publish.** `EXPOSE 80` in a Dockerfile is documentation. It doesn't open a port on the host — only `-p` / `-P` / Compose `ports:` does.

**IPv6 traffic bypassing rules.** For a long time Docker's iptables integration only covered IPv4. Modern Docker (25.0+) has better v6 handling, but if your host has a public v6 address, verify with `ss -tulnp` that `-p 127.0.0.1:8080:80` isn't listening on `::` too.

**Docker rewrites iptables.** Setting up firewall rules that Docker later blows away is a classic footgun. Docker inserts its own `DOCKER` chain in the `nat` table; put your host rules in a chain Docker won't touch, or use `iptables=false` in `dockerd` and manage it yourself (advanced).

---

## Container-to-Container Communication

**Within one bridge network** — reach peers by name.

```bash
docker network create app-net
docker run -d --name redis --network app-net redis:7-alpine
docker run --rm --network app-net alpine sh -c 'apk add curl && ping -c1 redis'
```

**Across networks** — a container can join multiple networks with `--network` per call, or `docker network connect <net> <container>` after the fact.

**Bridge to host** — from inside a bridge container, the host is reachable at the special DNS name `host.docker.internal` (Docker Desktop always; Linux with `--add-host=host.docker.internal:host-gateway` since Engine 20.10).

---

## `overlay` — Multi-Host (Swarm)

Overlay networks span multiple Docker hosts using VXLAN encapsulation. Historically the way to do multi-host Docker without Kubernetes.

- Requires Swarm mode (`docker swarm init` on the leader, `docker swarm join` on workers).
- Encrypted by default when created with `--opt encrypted`.
- **Reality check for 2026**: Kubernetes CNI plugins (Calico, Cilium, Flannel) dominate this space. If you're picking multi-host networking today, you're picking Kubernetes; overlay networks are a Swarm-era construct.

---

## Inspecting Networks

```bash
docker network ls                       # list networks
docker network inspect app-net          # subnets, containers, driver options
docker inspect <container> \
  --format '{{json .NetworkSettings}}'  # container's own view
docker exec <container> ip a            # namespace-side view
```

---

## Summary

| Question | Answer |
|----------|--------|
| Which driver by default? | `bridge` — but use a **user-defined** bridge, not the built-in `bridge` |
| DNS by container name? | Only on user-defined bridges (or Compose networks) |
| Need max performance / host-scope tooling? | `--network host` (Linux only, watch port conflicts) |
| `EXPOSE` publishes ports? | No — pure documentation |
| Publish safely by default? | `-p 127.0.0.1:8080:80` — bind to loopback unless external access is needed |
| Cross-host in Docker? | `overlay` + Swarm — but in 2026 that's Kubernetes territory |
| Reach host from container? | `host.docker.internal` (with `--add-host=host.docker.internal:host-gateway` on Linux) |

---

## Related Notes

- [[Docker - Compose for Dev Environments]] — project-scoped bridge network with service-name DNS
- [[Docker - Security]] — network isolation is one leg of the stool
- [[Docker - Production Considerations]] — why Kubernetes replaced Swarm for multi-host
