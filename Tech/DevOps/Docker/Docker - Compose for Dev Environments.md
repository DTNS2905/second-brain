---
tags:
  - devops
  - docker
  - compose
  - development
created: 2026-07-17
source: https://docs.docker.com/compose/
---

# Docker - Compose for Dev Environments

> **Compose** — YAML-driven multi-container orchestration for local dev, CI integration tests, and CI-only stacks. Not a production tool. Back to [[Docker Guide]].

---

## The Minimal `compose.yaml`

Compose v2 (Go rewrite, `docker compose` subcommand) is the current version. The file is called `compose.yaml` (or `compose.yml`); the older `docker-compose.yml` name still works.

```yaml
services:
  api:
    build: .
    ports:
      - "8080:8080"
    environment:
      DATABASE_URL: postgres://app:app@db:5432/app
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
      POSTGRES_DB: app
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s

volumes:
  db-data:
```

`docker compose up` starts everything in dependency order.

---

## Startup Order: `depends_on` + Healthchecks

Docker docs: *"On startup, Compose does not wait until a container is 'ready', only until it's running."* So plain `depends_on: [db]` will start the API immediately after Postgres's process starts — which is *before* Postgres is accepting connections.

**Fix**: use `depends_on` long syntax with a `condition`, and give the dependency a `healthcheck`.

| `condition` | Waits for |
|-------------|-----------|
| `service_started` (default) | Container process is running |
| `service_healthy` | Healthcheck reports healthy |
| `service_completed_successfully` | Container exited with code 0 (for one-shot init/migration jobs) — added in Compose v2.20.0 |

`service_completed_successfully` is how you gate an API on a migration job that runs once and exits:

```yaml
services:
  api:
    depends_on:
      migrate:
        condition: service_completed_successfully
  migrate:
    image: myapp:$GIT_SHA
    command: ["./migrate.sh"]
    depends_on:
      db:
        condition: service_healthy
```

---

## Healthcheck Attributes

| Attribute | Meaning |
|-----------|---------|
| `test` | Shell command; exit 0 = healthy |
| `interval` | Time between checks after startup |
| `timeout` | Per-check kill-if-no-response |
| `retries` | Consecutive failures before marked unhealthy |
| `start_period` | Grace window before failures count |
| `start_interval` | Frequency *during* `start_period` — added in Compose 2.20.2, requires Engine 25.0+ |

`start_period` + `start_interval` gives fast feedback on quick-booting services without punishing slow ones.

---

## Profiles: Optional Stacks

Compose profiles keep opt-in services out of a normal `up`.

```yaml
services:
  api:
    build: .

  db:
    image: postgres:16-alpine

  jaeger:
    image: jaegertracing/all-in-one
    profiles: ["debug"]

  loadtest:
    image: grafana/k6
    profiles: ["loadtest"]
```

- `docker compose up` — just `api` and `db`.
- `docker compose --profile debug up` — adds `jaeger`.
- `docker compose --profile debug --profile loadtest up` — everything.

Useful for tooling (tracers, load generators, admin UIs) that shouldn't run by default.

---

## Override Files: Dev-Only Layering

Compose auto-merges `compose.override.yaml` on top of `compose.yaml` when both exist. Use it for local-only concerns:

```yaml
# compose.yaml (checked in — CI-safe defaults)
services:
  api:
    build: .
    image: ghcr.io/acme/api:${TAG:-latest}
```

```yaml
# compose.override.yaml (gitignored — dev-only)
services:
  api:
    volumes:
      - .:/app                 # live-reload from host
    environment:
      LOG_LEVEL: debug
    ports:
      - "9229:9229"            # debugger port
```

For CI or prod-like stacks, explicitly pick files:

```bash
docker compose -f compose.yaml -f compose.ci.yaml up --exit-code-from tests
```

---

## Secrets in Compose

Compose supports first-class secrets. They're mounted **read-only** at `/run/secrets/<name>` — never in `ENV`, never in image layers.

```yaml
services:
  api:
    image: myapp:1.0
    secrets:
      - db_password         # explicit grant — top-level definition alone doesn't grant access

secrets:
  db_password:
    file: ./secrets/db_password.txt   # dev; use external:true for Swarm-managed secrets in prod
```

Inside the container the app reads `/run/secrets/db_password`. Default mode is `0444`. (Note: docker/compose#12658 documents drift to `0400` in v2.34.0+ — check if your app needs world-readable.)

---

## Networking (Just Enough)

Compose creates a **project-scoped bridge network** by default; every service gets a hostname matching its service name. `api` can reach `db` at `db:5432` — no `localhost`, no port publishing between services. See [[Docker - Networking]] for driver details.

---

## What Compose *Isn't*

Compose is a **dev/CI convenience**, not an orchestrator:
- No scheduling, no rolling updates, no health-based restart of unhealthy containers across nodes.
- No secrets store (files on disk).
- Single-host. Compose Swarm mode exists but is deprecated for new work.

For production, graduate to Kubernetes, ECS, or Nomad — see [[Docker - Production Considerations]].

---

## Summary

| Feature | Use it for |
|---------|-----------|
| `depends_on: condition: service_healthy` | Wait for a dependency to be *ready*, not just *running* |
| `service_completed_successfully` | Gate services on one-shot migration/init jobs |
| Healthchecks (`test`, `interval`, `start_period`, `start_interval`) | Distinguish "process alive" from "app ready" |
| Profiles | Opt-in tooling stacks (tracing, loadtest, admin UIs) |
| `compose.override.yaml` | Local dev overrides layered on shared base |
| Compose secrets (`/run/secrets/<name>`) | Keep credentials out of `ENV` and images |
| Project bridge network + service DNS | `api` can reach `db:5432` with zero config |

---

## Related Notes

- [[Docker - Networking]] — bridge/host/overlay drivers and DNS
- [[Docker - Volumes and Persistence]] — named volumes for `db-data`
- [[Docker - Security]] — why `/run/secrets/` beats `ENV`
- [[Docker - Production Considerations]] — when to graduate off Compose
