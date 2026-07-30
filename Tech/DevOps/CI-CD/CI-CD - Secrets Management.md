---
tags:
  - devops
  - ci-cd
  - secrets
  - security
  - oidc
  - vault
created: 2026-07-17
source: https://developer.hashicorp.com/vault
---

# CI-CD - Secrets Management

> Long-lived cloud keys in CI secrets are the biggest attack vector in modern pipelines. The 2026 default is **OIDC federation** — the CI runner mints a short-lived cloud identity per job. Back to [[CI-CD Guide]].

---

## The Old Way vs. the New Way

| | Old (2015-era) | New (2026) |
|---|--------------|-----------|
| **AWS creds in CI** | Long-lived `AKIA…` key stored as CI secret | OIDC token exchanged for a temporary role |
| **Rotation** | Manual, quarterly (rarely done) | Every job; ephemeral by construction |
| **Blast radius on leak** | Keys valid until manually revoked | Token expires in minutes |
| **Audit** | Access-key ID in CloudTrail | Full OIDC identity (`repo`, `ref`, `job`) in claims |

If you're still shipping `AWS_ACCESS_KEY_ID` as a CI variable, that's the single biggest security win available.

---

## OIDC Federation — The Core Pattern

```
CI runner  ──▶  identity provider (GitHub/GitLab/CircleCI)  ──▶  issues signed JWT
                                                                      │
                                                                      ▼
                                                          cloud IAM (AWS/GCP/Azure)
                                                                      │
                                                                      ▼
                                                       exchanges JWT for temp creds
                                                                      │
                                                                      ▼
                                                              CI runner uses temp creds
                                                                (expires in minutes)
```

The runner never handles a long-lived cloud key. The cloud provider verifies the JWT signature against the CI's public key, checks its trust policy (does this repo/branch match?), and issues short-lived credentials.

### AWS

`sts:AssumeRoleWithWebIdentity`. The trust policy conditions on the OIDC issuer + subject:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::123:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:acme/api:ref:refs/heads/main"
    }
  }
}
```

Only the `main` branch of `acme/api` can assume this role. No branch on a fork can. No workflow from any other repo can. See [[GitHub Actions - Secrets and OIDC]] for the workflow side.

### GCP

Workload Identity Federation. Set up a pool, map the OIDC issuer, bind IAM to `principalSet://` on subject claims.

### Azure

Federated credentials on an app registration. Match on `subject`, `issuer`, `audience`.

---

## Vaults — When You Still Need Static Secrets

Not everything federates. Third-party APIs, DB passwords, TLS keys, license tokens — these still exist. Store them in a secrets manager:

| Provider | Notes |
|----------|-------|
| **HashiCorp Vault** | Cross-cloud, self-hosted or HCP. Rich engine model (KV, database, PKI, transit) with dynamic secrets. |
| **AWS Secrets Manager** | Native rotation for RDS/Redshift/DocumentDB. IAM-gated. |
| **Google Secret Manager** | GCP-native, IAM-gated, versioned. |
| **Azure Key Vault** | Azure equivalent. |
| **Doppler / 1Password / Infisical** | SaaS secret managers with CI integrations. |

**Pattern**: OIDC-federate into the cloud identity that has permission to read the vault. The CI runner never sees the vault credential — only what the vault returns.

```
CI runner ─OIDC─▶ cloud IAM ─IAM─▶ Secrets Manager ─read─▶ secret value ─▶ used in job
```

---

## Dynamic Secrets (Vault's Superpower)

HashiCorp Vault can *generate* short-lived credentials on demand — a DB user that lives for 5 minutes then vanishes:

```
CI job needs DB access ──▶ Vault database engine ──▶ creates user with time-bound grant
                                                        │
                                                        ▼
                                          job uses creds ──▶ Vault revokes at TTL
```

No static DB password. No rotation problem. Every job gets fresh credentials scoped to what it needs.

Same pattern for cloud IAM, SSH CA, PKI certs, and more via Vault's Secrets Engines.

---

## What Goes Where

| Kind of secret | Storage | Access pattern |
|----------------|---------|---------------|
| Cloud IAM (AWS/GCP/Azure) | **Not stored** — OIDC federation | Ephemeral, per-job |
| DB password (short-lived) | Vault dynamic secrets | Ephemeral, per-job |
| DB password (static, legacy) | Cloud secrets manager | Read at job start via OIDC |
| Third-party API keys | Cloud secrets manager | Read at job start via OIDC |
| Signing keys | Fulcio (keyless, OIDC) or KMS | Never leaves KMS |
| Registry credentials | OIDC → registry (e.g., GHCR trust GitHub Actions natively) | Ephemeral |
| SSH keys | Vault SSH CA (dynamic) or KMS | Ephemeral cert, not a raw key |
| Encryption keys | KMS (AWS/GCP/Azure/HashiCorp Vault Transit) | Never handled directly — envelope encryption |

**Rule**: if the secret can be minted on demand, mint it. If it must be stored, store it in one place with an audit trail, and access it via a federated identity.

---

## Rotation

For static secrets that *do* need to exist:

- **Automated rotation** — Secrets Manager can rotate RDS/Redshift/etc. on a schedule. Turn it on.
- **Custom rotation lambdas** — For third-party API keys, write a rotation function that calls the vendor's key-rotation API and updates Secrets Manager.
- **Blast-radius reduction** — even with rotation, prefer scoped/limited keys over root/admin.

**Never** rotate a secret without a working consumer path. A rotated key with old consumers still holding the previous value causes outages.

---

## Anti-Patterns

- ❌ Cloud access keys stored as CI secrets. Use OIDC federation.
- ❌ Same secret across environments (dev key = prod key). Separate vaults / paths per environment.
- ❌ Secrets in environment variables printed to logs. Mask them; keep them in files with `--mount=type=secret` (Docker) or CI's masked-secret storage.
- ❌ Committing `.env` files. Enforce via `.gitignore` + a secret-scanner (GitGuardian, Gitleaks, TruffleHog) in CI.
- ❌ Long-lived tokens for third-party APIs when they support OAuth device flow or short-lived tokens.
- ❌ One secret per developer laptop copied into CI. One source of truth (vault), every environment reads from it.

---

## Secrets in Docker Builds

Build-time secrets belong on `RUN --mount=type=secret,…`, not `ARG` or `ENV`. Runtime secrets belong on Compose secrets (`/run/secrets/…`) or the orchestrator's secret store (Kubernetes Secrets, ideally backed by External Secrets Operator → Vault / cloud secrets manager). See [[Docker - Security]] and [[Docker - Compose for Dev Environments]].

---

## Summary

| Practice | Effect |
|----------|--------|
| OIDC federation for cloud IAM | No long-lived cloud keys in CI |
| Vault dynamic secrets for DBs | No static DB passwords; per-job credentials |
| Cloud secrets manager for legacy static secrets | One store, audit trail, IAM-gated reads |
| Sigstore keyless signing (see [[CI-CD - Security and Compliance]]) | No signing keys in CI at all |
| Automated rotation for what remains | Blast-radius bounded even without ephemeral creds |
| Secret scanner in CI | Commit-time detection of accidental leaks |
| Per-environment separation | Dev leak doesn't compromise prod |

---

## Related Notes

- [[GitHub Actions - Secrets and OIDC]] — the GitHub-side workflow syntax
- [[CI-CD - Security and Compliance]] — signing, SBOM, SLSA
- [[Docker - Security]] — build-time secret mounts, runtime secret injection
- [[Docker - Compose for Dev Environments]] — `/run/secrets/` mechanism
