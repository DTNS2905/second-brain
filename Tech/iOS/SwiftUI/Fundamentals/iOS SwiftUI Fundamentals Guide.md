---
tags:
  - ios
  - swiftui
  - fundamentals
  - mobile
created: 2026-07-01
source: https://developer.apple.com/documentation/swiftui
apple_docs:
  - https://developer.apple.com/documentation/swiftui
  - https://developer.apple.com/tutorials/swiftui
---

# iOS SwiftUI Fundamentals Guide

> The mental model + the vocabulary. Read this before touching architecture. Pairs with [[iOS SwiftUI Architecture Guide]]. For a hands-on path that builds an app layer by layer, see [[iOS Tutorial Guide]].

---

## Contents

### SwiftUI-specific

| Note | Covers |
|------|--------|
| [[iOS SwiftUI - Core Concepts]] | View protocol, `some View`, `@ViewBuilder`, identity, layout rules, modifier order, environment |
| [[iOS SwiftUI - Core Components]] | Categorized catalog: layout, controls, collections, navigation, presentation, drawing, text/image, modifiers |
| [[iOS SwiftUI - Lifecycle]] | App → Scene → View lifecycle, `.task` vs `.onAppear`, `ScenePhase`, state-wrapper lifetimes, UIKit bridge |
| [[iOS SwiftUI - Property Wrappers]] | `@State`, `@Binding`, `@StateObject` vs `@ObservedObject`, `@Environment(Object)`, `@AppStorage`, `@Bindable`, `@FocusState`, `@Query` — the full wrapper catalog |
| [[iOS SwiftUI - Navigation]] | `NavigationStack`, `NavigationLink(value:)`, `.navigationDestination(for:)`, sheets, deep links, coordinator pattern |
| [[iOS SwiftUI - Animations]] | Implicit vs explicit, `withAnimation`, spring curves, `.transition`, `matchedGeometryEffect`, `PhaseAnimator`, `KeyframeAnimator` |
| [[iOS SwiftUI - SwiftData]] | `@Model`, `@Query`, `modelContainer`, `modelContext`, relationships — iOS 17+ persistence |

### Cross-cutting Swift + iOS fundamentals

Live outside the SwiftUI framework proper but are load-bearing for every SwiftUI app you write:

| Note | Covers |
|------|--------|
| [[iOS SwiftUI - Concurrency and Threading]] | Main-thread rule, `DispatchQueue` vs `@MainActor`, Combine `.receive(on:)`, retain cycles & `[weak self]`, async/await bridge |
| [[iOS ARC Guide]] | Automatic Reference Counting: how Swift frees memory, `strong` / `weak` / `unowned`, retain cycles, `deinit`, capture lists, Memory Graph Debugger |

---

## Where SwiftUI Fits

- **UI framework.** Replaces UIKit (iOS) / AppKit (macOS) / WatchKit / tvOS UIs with one API.
- **Declarative.** You describe *what* the UI should look like; SwiftUI figures out *how* to draw it and update it.
- **Cross-Apple-platform.** Same `View` code runs on iOS, iPadOS, macOS, watchOS, tvOS, visionOS (with platform-specific adjustments).
- **Data-driven.** Views are a **function of state**; changing state re-runs `body` and diffs the tree.

---

## The One-Sentence Mental Model

> **A SwiftUI `View` is a lightweight value (struct) describing what to display. SwiftUI computes the tree, diffs it against the previous tree, and updates only what changed.**

Same model as React (props/state → VDOM diff → commit). If you know [[React Reconciliation Guide]]-style rendering, this is familiar.

---

## Apple Docs (Primary References)

| Topic | Apple URL |
|-------|-----------|
| SwiftUI framework overview | https://developer.apple.com/documentation/swiftui |
| SwiftUI tutorials (start here) | https://developer.apple.com/tutorials/swiftui |
| `View` protocol | https://developer.apple.com/documentation/swiftui/view |
| View fundamentals | https://developer.apple.com/documentation/swiftui/view-fundamentals |
| Layout fundamentals | https://developer.apple.com/documentation/swiftui/layout-fundamentals |
| Picking container views | https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content |
| View modifiers | https://developer.apple.com/documentation/swiftui/view-modifiers |
| Managing model data | https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines/ |

---

## Related

- [[iOS SwiftUI Architecture Guide]] — how these fundamentals slot into Clean Architecture + MVVM
- [[iOS SwiftUI Architecture - Presentation Layer]] — where View + ViewModel meet
- [[iOS SwiftUI Architecture - Observation Macro]] — iOS 17+ state management
- [[iOS Tutorial Guide]] — hands-on 8-part tutorial that puts everything on this page into practice
- [[iOS Tutorial Glossary]] — plain-English definitions of every keyword used across the tutorial
