---
tags:
  - devops
  - ci-cd
  - security
  - supply-chain
  - slsa
  - sigstore
  - sbom
created: 2026-07-17
source: https://slsa.dev/spec/v1.0/levels
---

# CI-CD - Security and Compliance

> SAST + DAST + SBOM + signed artifacts + SLSA provenance. In 2026, supply-chain security is a first-class pipeline concern, not an afterthought. Back to [[CI-CD Guide]].

---

## The Layered Model

| Layer | Question | Tools |
|-------|----------|-------|
| **Static analysis (SAST)** | Does the source have known-vulnerable code patterns? | Semgrep, CodeQL, SonarQube, Bandit, gosec |
| **Dependency scanning** | Do our deps have known CVEs? | Dependabot, Renovate, Snyk, OWASP Dependency Check |
| **Container scanning** | Does the image have known-vulnerable packages? | Trivy, Grype, Docker Scout, Snyk Container |
| **SBOM** | What's actually in this artifact? | Syft, cyclonedx, Trivy SBOM |
| **Dynamic testing (DAST)** | Do the endpoints exhibit exploitable behavior? | OWASP ZAP, Burp Suite Enterprise, StackHawk |
| **Secret scanning** | Are there credentials in the repo? | GitGuardian, Gitleaks, TruffleHog, GitHub secret scanning |
| **Signing & provenance** | Was this artifact built from what it claims? | Sigstore (cosign, Fulcio, Rekor), in-toto attestations |
| **Policy enforcement** | Do artifacts meet our policy at deploy time? | Sigstore policy-controller, Kyverno, OPA/Gatekeeper |

Each layer catches things the others miss. Skip none.

---

## SAST — Static Application Security Testing

Scans source code for known-bad patterns (SQLi concatenation, hardcoded secrets, insecure crypto).

**Semgrep** — rule-driven, fast, low false-positive rate. OSS + paid tiers. Custom rules in a simple DSL. Common CI default in 2026.

**CodeQL** — GitHub's semantic query engine; deeper analysis than pattern matching. Free for public repos. Integrated with GitHub Advanced Security for private repos.

**Language-specific**: `gosec` (Go), `bandit` (Python), `brakeman` (Rails), `semgrep-rules` for most.

Run on every PR. Block on high-severity findings; annotate lower ones for human triage. Feed suppression lists in-repo (`.semgrepignore`, CodeQL config) so triaged findings don't re-fire.

---

## Dependency Scanning

Every language ecosystem has a vulnerability database (npm audit, pip-audit, cargo audit, OSV). Tools normalize across ecosystems:

- **Dependabot** (GitHub-native) — auto-opens PRs to bump vulnerable deps. Free.
- **Renovate** — third-party equivalent with vastly more configuration surface (grouping, schedules, auto-merge). Works on every VCS.
- **Snyk** — commercial; strong language coverage, remediation suggestions, license scanning.
- **OSV-Scanner** (Google) — CLI over the OSV database; use in CI for a fast, dep-only scan.

Run on every PR, gated by severity. Auto-merge Renovate/Dependabot patch bumps behind a green CI as a matter of hygiene.

---

## Container Scanning

See [[Docker - Security]] for the tool comparison. Standard CI wiring:

```yaml
- run: trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed \
         ghcr.io/acme/api:${{ github.sha }}
```

`--ignore-unfixed` avoids paging on CVEs with no upstream patch — you can't fix them by rebuilding.

---

## SBOM Generation

A **Software Bill of Materials** is a machine-readable list of every component in an artifact. Increasingly required by regulation (US EO 14028, EU CRA) and by enterprise customers.

**Formats**: SPDX (Linux Foundation) and CycloneDX (OWASP) are the two standards. Both are supported everywhere; pick one and be consistent.

**Tools**:
- **Syft** (Anchore) — generates SBOM from container images, filesystems, source dirs.
- **cyclonedx-cli / cyclonedx-npm / cyclonedx-python** — CycloneDX-native generators per language.
- **Trivy** — can also emit SBOMs (`trivy image --format cyclonedx`).

Store SBOMs as attestations attached to the image (via cosign), not as loose files. That way anyone pulling the image can verify what's inside.

---

## Signing with Sigstore / Cosign

**Sigstore** makes signing artifacts as easy as pushing them. **Cosign** is the CLI.

### Keyless signing (the 2026 default)

Traditional signing requires managing a long-lived private key. Sigstore's keyless mode eliminates it:

1. Cosign generates an ephemeral in-memory keypair.
2. The private key signs the artifact.
3. **Fulcio** (Sigstore's CA) issues a short-lived X.509 cert (~10 minutes) binding the ephemeral public key to an **OIDC identity** (GitHub, Google, Microsoft).
4. The private key is **destroyed immediately**.
5. The signature + cert are published to **Rekor** (the transparency log).

No signing key exists after the signing step. Verification checks the cert chain to Fulcio's root + the OIDC identity claim in the cert.

### In a CI job (GitHub Actions example)

```yaml
permissions:
  id-token: write   # needed for OIDC
  packages: write

steps:
  - uses: sigstore/cosign-installer@v3
  - run: |
      cosign sign --yes \
        ghcr.io/acme/api@${{ steps.push.outputs.digest }}
```

Cosign automatically detects the CI's OIDC token and requests a Fulcio cert bound to the workflow identity (`repo:acme/api:ref:refs/heads/main`).

### Verification

```bash
cosign verify \
  --certificate-identity 'https://github.com/acme/api/.github/workflows/release.yaml@refs/heads/main' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/acme/api@sha256:...
```

Fails if the image wasn't signed by the specified workflow on the specified branch.

---

## Admission-Time Enforcement

Signing is useless if the cluster still runs unsigned images. Enforce at deploy time.

**Sigstore policy-controller** (Kubernetes admission webhook):

```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: only-signed-by-our-ci
spec:
  images:
    - glob: "ghcr.io/acme/**"
  authorities:
    - keyless:
        url: https://fulcio.sigstore.dev
        identities:
          - issuer: https://token.actions.githubusercontent.com
            subject: "https://github.com/acme/*/.github/workflows/release.yaml@*"
```

Unsigned images or images signed by anyone else are rejected before pods start. **Kyverno** and **OPA/Gatekeeper** can enforce equivalent policies.

---

## SLSA — Supply-Chain Levels for Software Artifacts

SLSA v1.0 defines a **Build track** with four levels (L0–L3):

| Level | Requirement |
|-------|-------------|
| **L0** | No guarantees. |
| **L1** | Provenance exists — describes build platform, process, top-level inputs. May be unsigned. |
| **L2** | Build runs on **hosted infrastructure** (not a laptop), provenance is **digitally signed** by the platform. Prevents post-build tampering. |
| **L3** | Hardened builds. Runs cannot influence each other; signing secrets are inaccessible to user-defined build steps. Defends against insider threats. |

**Provenance** is verifiable metadata: where, when, how the artifact was built. The `builder.id` URI is the sole determiner of the SLSA Build level — trust flows from identifying which platform emitted the attestation.

`externalParameters` (user-controlled — untrusted, MUST be verified downstream) are separated from `internalParameters` (platform-controlled — trusted). `resolvedDependencies` lists everything the build pulled.

### Practical level goals

- **L1**: emit any provenance. `docker buildx --provenance mode=max` gives you this.
- **L2**: use a hosted CI (GitHub Actions, GitLab, CircleCI) and sign the provenance. Cosign + OIDC does this.
- **L3**: needs a hardened builder — GitHub's reusable "SLSA generator" workflows, or self-host with the required isolation. The extra step from L2 to L3 is real work.

---

## DAST — Dynamic Application Security Testing

Runs against a *deployed* app; probes for XSS, SQLi, IDOR, auth bypass. Slower than SAST; catches things SAST can't.

- **OWASP ZAP** — free, scriptable, mature. Run against a staging deploy nightly, not on every PR.
- **Burp Suite Enterprise** — commercial, integrates deeper.
- **StackHawk** — CI-native DAST, faster to configure than ZAP.

Gate on high-severity findings; run in a scheduled trunk job, not on every PR (too slow).

---

## Secret Scanning

Every commit is a candidate leak. Tools:

- **GitHub secret scanning** (free for public repos, GitHub Advanced Security for private) — vendor-partnered pattern set that revokes leaked keys automatically at supported providers.
- **Gitleaks** — CLI + pre-commit hook.
- **TruffleHog** — CLI; also scans history + validates leaked secrets by testing them against APIs.
- **GitGuardian** — commercial, full audit + rotation flows.

Run **pre-commit** (in devs' hooks), **PR-time** (blocking), and **historically** (past leaks may still be valid).

---

## Compliance Frameworks (Who Asks For This)

- **SOC 2** — SBOM + change tracking + access logs + retention.
- **PCI DSS** — dep scanning, image scanning, signed artifacts.
- **FedRAMP / DoD IL5** — full SBOM + SLSA + admission enforcement.
- **EU CRA (Cyber Resilience Act, 2024–2027 rollout)** — SBOM + vuln management for products sold in the EU.
- **US EO 14028** — SBOMs for federal software procurement.

Even if not directly regulated, enterprise procurement will start asking for SBOMs and provenance. Building the pipeline for it early is cheaper than retrofitting.

---

## Summary

| Practice | Where in pipeline |
|----------|------------------|
| SAST (Semgrep, CodeQL) | Every PR, blocking |
| Dependency scanning (Dependabot/Renovate) | Continuous; auto-PRs |
| Container scanning (Trivy) | After image build, blocking |
| SBOM generation (Syft, Trivy) | After image build; attached as attestation |
| Keyless signing (cosign + Fulcio) | Immediately after image push, in same job |
| Admission policy (policy-controller/Kyverno) | Deploy time |
| SLSA L2 provenance | Emitted by hosted CI; verified downstream |
| DAST (OWASP ZAP) | Nightly against staging |
| Secret scanning | Pre-commit + PR-time |

---

## Related Notes

- [[CI-CD - Secrets Management]] — the secret-in-CI attack surface these tools defend
- [[Docker - Security]] — image-level equivalents (Trivy, cosign, digest pinning)
- [[GitHub Actions - Security Hardening]] — actions-side controls (SHA-pinning, GITHUB_TOKEN scopes)
- [[CI-CD - Deployment Strategies]] — admission control gates the deploy
