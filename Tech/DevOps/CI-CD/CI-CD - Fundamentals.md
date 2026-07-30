---
tags:
  - devops
  - ci-cd
  - fundamentals
  - trunk-based-development
  - dora
created: 2026-07-17
source: https://martinfowler.com/articles/continuousIntegration.html
---

# CI-CD - Fundamentals

> The definitions matter — most "CI/CD" you'll see in the wild isn't. Fowler, Kent Beck, DORA, and the trunk-based development community converge on the same picture. Back to [[CI-CD Guide]].

---

## CI vs CD vs Continuous Deployment

| Term | Definition | Prerequisite |
|------|-----------|--------------|
| **Continuous Integration** | Every developer commits to trunk at least daily; every commit gets built and tested. Broken builds are reverted, not left. | Self-testing code |
| **Continuous Delivery** | Trunk is always in a releasable state. A human (or a scheduled job) can cut a release at any time. | CI |
| **Continuous Deployment** | Every green commit to trunk auto-deploys to production. | CD + progressive rollout + fast rollback |

You can practice CI without CD. You cannot practice CD without CI. Continuous Deployment is a strict extension of Continuous Delivery.

---

## The Fowler Definition of CI (Verbatim)

Martin Fowler's canonical CI article (the reference every other definition traces back to):

> *"Every developer should commit to the mainline every day."*
> *"No code sits unintegrated for more than a couple of hours."* (Kent Beck)
> *"Self-testing code is so important to Continuous Integration that it is a necessary prerequisite."*
> *"Nobody has a higher priority task than fixing the build."*
> *"Usually the best way to fix the build is to revert the faulty commit from the mainline."*

Fowler distinguishes **CI** (push to trunk daily) from **semi-integration** (feature branches that only *pull*):

> *"[Feature branches that don't push] don't prevent branches from diverging, conflicts from festering."*

If your team has a two-week feature branch that pulls from `main` daily, you are not practicing CI. You are avoiding merge conflicts, not preventing them.

---

## Trunk-Based Development (TBD)

**Trunk-based development is the working model that makes CI possible.**

From trunkbaseddevelopment.com (Paul Hammant, the canonical reference):

- *"All team members commit to trunk at least once every 24 hours."*
- Short-lived branches exist *"for code review and build checking (CI), but not artifact creation or publication."*
- The codebase stays *"always releasable on demand."*

DORA's *Accelerate* research independently lists TBD as a core capability of elite performers and *"draws the line at 24 hours."* The 2024 and 2025 State of DevOps reports continue to affirm it.

### What TBD Is Not

- ❌ *"Everyone commits directly to `main` with no review."* — TBD supports PRs; they just close within a day.
- ❌ *"No branches allowed."* — Short-lived branches (hours, not weeks) are the norm.
- ❌ *"Release branches are forbidden."* — Release branches *for shipping* are fine. Just don't develop new features on them.

### Contrasting Branching Strategies

| Strategy | Branch lifetime | Fits with CI? |
|----------|----------------|---------------|
| **Trunk-based** | Hours | ✅ Yes — the model CI was designed for |
| **GitHub Flow** | Days | ⚠️ Works if PRs are small and merged fast |
| **Git Flow** | Weeks/months (`develop`, `release`, `feature`) | ❌ Explicitly optimizes for delayed integration |
| **Release train** | Fixed cadence | ⚠️ CD-friendly but weaker on rapid delivery |

Git Flow was influential in the early 2010s and remains widespread — but its inventor (Vincent Driessen) has publicly walked back the recommendation for anything but strictly versioned software with parallel supported versions.

---

## Self-Testing Code

Self-testing code is a prerequisite, not a nice-to-have. Fowler's framing:

> *"Instituting Continuous Integration without self-testing code won't work."*

**What "self-testing" means:**
- Running the test suite from a fresh clone succeeds without human intervention.
- Failures point at real problems (not flakes, not env issues).
- Coverage is broad enough that a green run gives *reasonable* confidence.

You don't need 100% coverage. You need enough coverage that green means green. See [[CI-CD - Testing in Pipelines]] for pyramid application in CI.

---

## The Broken Build

The single most important cultural rule:

> *"Nobody has a higher priority task than fixing the build."*

**Standard response is revert.** Not forward-fix. Not "I'll fix it after lunch."

- Revert restores everyone else's ability to integrate.
- The reverted commit still exists in the author's branch; they can fix it and re-PR.
- Forward-fix is only appropriate when the fix is obviously trivial (<10 minutes) and definitely safe.

Teams that tolerate a red trunk *"for a while"* end up with a red trunk *for a long time* — the invariant breaks and doesn't self-repair.

---

## Merge Queues

At scale, PR-time green doesn't guarantee post-merge green — two PRs that each pass CI can conflict semantically when both merge. **Merge queues** solve this by:

1. PR gets marked "ready to merge".
2. Queue runs CI on `PR + latest trunk`.
3. If green, merged; if red, kicked back to the author.

Available in: GitHub (merge queue), GitLab (merge trains), Mergify, Aviator, Trunk.io. Essential above ~50 devs/repo; a nice-to-have below that.

---

## DORA Capabilities (What Elite Teams Do)

DORA's *Accelerate* research identifies capabilities that correlate with software delivery performance. Relevant to CI/CD:

| Capability | What it looks like |
|------------|-------------------|
| Trunk-based development | 24-hour merge cadence |
| Continuous integration | Every commit built + tested against trunk |
| Continuous delivery | Trunk always releasable |
| Deployment automation | No manual steps between merge and deploy |
| Test automation | Suites give reliable, actionable feedback |
| Test data management | Tests seed and clean their own data |
| Version control | *All* production artifacts + config live in version control |
| Loosely coupled architecture | Teams can deploy without cross-team coordination |

The 2024/2025 State of DevOps reports also emphasize **platform engineering** and **AI-assisted development** as newer capabilities.

---

## The Four (Now Five) DORA Metrics

| Metric | Elite performer |
|--------|-----------------|
| Deployment frequency | Multiple per day |
| Lead time for changes | Less than a day |
| Change failure rate | 0–15% |
| Failed deployment recovery time | Less than an hour |
| **Reliability** (added 2021) | Meets/exceeds SLOs |

Track these on your team dashboard. See [[CI-CD - Observability and Rollback]] for how to instrument them.

---

## Summary

| Principle | Practical form |
|-----------|---------------|
| Daily commits to trunk | PRs merged within 24 hours |
| Self-testing code | Green suite = safe to release |
| Green trunk is #1 priority | Revert broken commits; don't forward-fix by default |
| Short-lived branches | Code review + CI only; not artifact publication |
| Merge queues at scale | Serialize final CI vs. latest trunk |
| DORA capabilities | Trunk-based dev + full test automation + versioned everything |

---

## Related Notes

- [[CI-CD - Pipeline Design Patterns]] — how to structure the pipeline these principles produce
- [[CI-CD - Testing in Pipelines]] — what "self-testing code" looks like at pipeline scale
- [[CI-CD - Deployment Strategies]] — what "always releasable" enables
- [[CI-CD - Observability and Rollback]] — measuring DORA metrics
