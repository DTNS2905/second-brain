---
tags:
  - ios
  - architecture
  - comparison
  - decision-guide
  - mobile
created: 2026-07-10
source: internal
---

# iOS SwiftUI Architecture - Comparison

> Decision guide: which iOS architecture to pick for your situation. Link back to [[iOS SwiftUI Architecture Guide]].

---

## The 5 Contenders

| Architecture | Note | Layers | Style |
|---|---|---|---|
| **MVC** | [[iOS SwiftUI Architecture - MVC]] | Model / View / Controller | Cocoa classic, UIKit |
| **MVP** | [[iOS SwiftUI Architecture - MVP]] | Model / View (passive) / Presenter | Controller-active variant |
| **MVVM** | [[iOS SwiftUI Architecture - MVVM with Combine]] | Model / View / ViewModel | SwiftUI-native |
| **VIPER** | [[iOS SwiftUI Architecture - VIPER]] | View / Interactor / Presenter / Entity / Router | Enterprise, strict |
| **Clean Architecture** | [[iOS SwiftUI Architecture - Clean Architecture]] | Presentation / Domain / Data | Uncle Bob, framework-agnostic |
| **TCA** | [[iOS SwiftUI Architecture - TCA]] | State / Action / Reducer / Effect / Store | Redux-style, Point-Free |

---

## Side-by-Side Matrix

| Criteria | MVC | MVP | MVVM | VIPER | Clean | TCA |
|---|---|---|---|---|---|---|
| Fits SwiftUI natively | ❌ | ⚠️ | ✅ | ⚠️ | ✅ | ✅ |
| Fits UIKit | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Boilerplate | Low | Medium | Medium | **High** | Medium-High | Medium-High |
| Learning curve | Easy | Easy | Medium | Hard | Medium-Hard | **Hard** |
| Test coverage ceiling | Low | High | High | **Very High** | Very High | **Very High** |
| Team scaling | Poor | OK | Good | **Excellent** | Excellent | Good |
| 3rd-party dep required | No | No | No | No | No | **Yes** (TCA lib) |
| Handles complex state | Poorly | OK | OK | Good | Good | **Excellent** |
| Community momentum (2026) | Declining | Declining | Strong | Declining | Strong | Growing |

---

## Decision Tree

```
Are you writing SwiftUI (not UIKit)?
├── No (UIKit only)
│   ├── Legacy code with a pattern already? → Keep it
│   ├── Team >10 devs? → VIPER
│   └── Else → MVC or MVVM
│
└── Yes (SwiftUI)
    │
    ├── App size?
    │   ├── <5 screens, mostly CRUD → MVVM alone (skip Clean)
    │   ├── 5-20 screens, some business logic → MVVM + Clean Architecture
    │   └── 20+ screens, enterprise → Clean Architecture strict, or TCA
    │
    ├── Team background?
    │   ├── Coming from Redux/React → TCA feels natural
    │   ├── Coming from UIKit MVC → MVVM is the smallest jump
    │   └── Coming from Android Clean → Clean Architecture (concepts transfer)
    │
    └── Testing requirements?
        ├── Casual (happy-path only) → MVVM
        ├── High coverage required → Clean Architecture
        └── Ceremony-enforced tests → TCA (TestStore)
```

---

## Common Combinations

Architectures usually **don't stand alone** — they combine:

| Combination | Who uses it | Notes |
|---|---|---|
| **MVVM + Clean Architecture + Combine** | ← This vault's stack | MVVM is the pattern inside the Presentation layer; Clean is the macro-structure |
| MVVM + Coordinator pattern | Common in medium apps | Coordinator owns navigation, keeps it out of the ViewModel |
| VIPER + RxSwift | Uber, older Ola | Pre-Combine era |
| TCA (all-in) | Point-Free adopters | Doesn't mix with anything — TCA is self-contained |
| MVC + Coordinator | Medium UIKit apps | Partially solves "Massive VC" |

---

## Quick Recommendations by Context

### 👤 iOS beginner, solo learner, SwiftUI 2026+ (this vault's audience)

**Recommended:** **MVVM + Clean Architecture + Combine** (the vault's chosen stack).

Why:
- Teaches you to separate concerns — a skill that transfers to every platform.
- Combine + MVVM is the **native pattern** Apple implicitly encourages for SwiftUI.
- Clean Architecture lets you later refactor the Data layer (swap backend, add caching) without touching the UI.
- Avoid TCA when starting out — an extra conceptual layer (Redux) you don't need yet.

### 🏢 Startup team of 2-5 iOS devs, shipping fast

Plain MVVM. Skip Clean Architecture until you feel the pain (repeated Repositories, business rules scattered around).

### 🏦 Enterprise team of 10+ devs, complex app

VIPER or strict Clean Architecture. Router/Coordinator for navigation. Test coverage requirement >80%.

### 🧪 Functional-leaning team, Redux background from the web

TCA. Excellent testing story, mature ecosystem.

---

## Anti-Patterns (across all architectures)

### ❌ Picking a heavy architecture for a simple app

Not every app needs layer isolation. A 3-screen TODO app doesn't need Clean Architecture — MVVM is enough.

### ❌ Mixing multiple architectures in one codebase

If you chose MVVM for a new feature, don't write the next one in VIPER "to try it out". Mixed codebases are miserable to maintain.

### ❌ Copying a pattern from Android/Web without understanding it

Redux on the web works differently (one global store for the whole app) from TCA (feature-scoped stores). Don't port 1-to-1.

### ❌ Architecture-first, feature-later

Don't build out 5 layers before you have one screen running. Build a feature end-to-end first; refactor once you see the pattern repeat.

---

## Migration Paths

If you already picked wrong:

- **MVC → MVVM:** Extract the Controller's non-UI code into a new ViewModel class. Keep the Controller as a thin shell.
- **MVVM → Clean Architecture:** Add a Domain layer (Use Cases + Entities). Move networking from ViewModel down to Repository in the Data layer.
- **VIPER → Clean+MVVM:** Merge Interactor + Presenter into a ViewModel. Router can stay or be replaced by SwiftUI's `NavigationStack`.
- **Anything → TCA:** Mostly a rewrite. TCA doesn't mix well with other styles.

---

## Related

- [[iOS SwiftUI Architecture Guide]] — index for the whole topic
- [[iOS SwiftUI Architecture - Clean Architecture]] — the vault's chosen stack
- [[iOS SwiftUI Architecture - MVVM with Combine]] — the vault's chosen pattern
