---
tags:
  - ios
  - swiftui
  - tutorial
  - mvvm
  - observation
  - mobile
created: 2026-07-02
source: https://developer.apple.com/documentation/observation
---
country
# iOS Tutorial — Part 3: MVVM ViewModel

> Extract the data + filter logic out of the View, into an `@Observable` ViewModel. Same behavior, cleaner boundary. Back to index: [[iOS Tutorial Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**Property wrappers:** [[iOS Tutorial Glossary#`@Observable` (iOS 17+)|@Observable]], [[iOS Tutorial Glossary#`@Bindable` (iOS 17+)|@Bindable]]
**Swift:** [[iOS Tutorial Glossary#`class`|class]], [[iOS Tutorial Glossary#`final`|final]], [[iOS Tutorial Glossary#`private(set)`|private(set)]]
**Architecture:** [[iOS Tutorial Glossary#MVVM — Model / View / ViewModel|MVVM]]

---

## Prerequisites — Read These First

This part introduces the ViewModel — an object whose lifetime, thread of execution, and observation model must all be correct or you get subtle bugs (state resets on navigation, purple thread warnings, VMs recreated on every keystroke). Skim these before implementing:

| Note | Why you need it here |
|------|----------------------|
| [[iOS SwiftUI - Lifecycle]] | **When is the VM created and destroyed?** `@State` on an `@Observable` ties the VM's lifetime to view *identity*, not the view struct. If you don't grasp identity vs. re-render, you'll be surprised when your VM resets. |
| [[iOS SwiftUI Architecture - Observation Macro]] | **How does SwiftUI know what to re-render?** `@Observable` tracks per-property reads at compile time. This is different from `ObservableObject`'s broadcast-everything model. |
| [[iOS SwiftUI - Concurrency and Threading]] | **Why does state mutation need the main thread?** Even though we don't hop threads *yet* (no network in Part 3), the moment we add async work in [[iOS Tutorial - Part 4 Domain Layer]] and [[iOS Tutorial - Part 5 Data Layer]], main-actor rules kick in. Learn them now. |

If any of those feel dense, that's fine — read the first two sections of each, then come back.

---

## Goal

The View becomes a dumb renderer. The ViewModel owns the list, the search string, and the filter logic. UI still identical to [[iOS Tutorial - Part 2 Local State]].

```
┌─────────────────────────────────────────────┐
│  CountriesListView   ← reads viewModel      │
│         │                                   │
│         ▼                                   │
│  CountriesViewModel  ← @Observable          │
│    • countries: [Country]                   │
│    • searchText: String                     │
│    • filtered: [Country]  (computed)        │
└─────────────────────────────────────────────┘
```

---

## Step 1 — Create the ViewModel

Create `CountriesViewModel.swift`:

```swift
import Observation

@Observable
final class CountriesViewModel {
    var searchText: String = ""

    private(set) var countries: [Country] = [
        Country(name: "Vietnam", capital: "Hanoi",  flag: "🇻🇳"),
        Country(name: "Japan",   capital: "Tokyo",  flag: "🇯🇵"),
        Country(name: "France",  capital: "Paris",  flag: "🇫🇷"),
        Country(name: "Germany", capital: "Berlin", flag: "🇩🇪"),
        Country(name: "Italy",   capital: "Rome",   flag: "🇮🇹")
    ]

    var filtered: [Country] {
        guard !searchText.isEmpty else { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}
```

### What `@Observable` does

`@Observable` is a Swift **macro** (iOS 17+) that rewrites your class at compile time so SwiftUI can track *which properties* each view actually reads. When only `searchText` changes, only views that read `searchText` re-render — not everyone observing the object.

Contrast with the older `ObservableObject` + `@Published`: **any** `@Published` change re-rendered **every** observing view. `@Observable` is finer-grained and requires no property wrappers on the properties themselves.

Deep dive → [[iOS SwiftUI Architecture - Observation Macro]].

### Why `final class`?

- **`class`** because ViewModel needs identity (same instance across body re-runs) and reference semantics (multiple views may mutate the same VM).
- **`final`** because we're not subclassing it, and `final` lets the compiler devirtualize calls (small perf win, and required in some macro contexts).

### Why `private(set)` on `countries`?

Views can read the list but only the VM should mutate it. When we swap in a network fetch in [[iOS Tutorial - Part 5 Data Layer]], mutation will happen in a `load()` method inside the VM.

---

## Step 2 — Update the View

Update `CountriesListView.swift`:

```swift
import SwiftUI

struct CountriesListView: View {
    @State private var viewModel = CountriesViewModel()

    var body: some View {
        NavigationStack {
            List(viewModel.filtered) { country in
                CountryRow(country: country)
            }
            .navigationTitle("Countries")
            .searchable(text: $viewModel.searchText, prompt: "Search countries")
        }
    }
}

#Preview {
    CountriesListView()
}
```

### The one surprise: `@State` on a ViewModel

With `ObservableObject` you'd write `@StateObject var viewModel = …`. With `@Observable` you use **plain `@State`**. That's not a mistake — Apple's guidance is:

> Use `@State` to instantiate the observable object; use `@Bindable` when you need a `Binding` into it; pass it via `@Environment` for shared state.

`@State` here means "SwiftUI, please **own** this object for the lifetime of this view identity — don't recreate it every body re-run." Same lifecycle guarantee `@StateObject` used to give you.

| Old (`ObservableObject`) | New (`@Observable`) |
|--------------------------|---------------------|
| `@StateObject var vm = VM()` | `@State private var vm = VM()` |
| `@ObservedObject var vm: VM` | plain `let vm: VM` (or `@Bindable` for bindings) |
| `@Published var name` | plain `var name` |

### `$viewModel.searchText`

For a **binding into an `@Observable` object**, you generally need `@Bindable`. But `@State` on an observable gives you `$` for free — the `$` on a `@State`-wrapped `@Observable` produces bindings to its properties. If you were *receiving* the VM as a parameter, you'd add `@Bindable var viewModel: CountriesViewModel` inside the view.

---

## Step 3 — Test the Separation

Try this thought experiment: **could you unit-test the ViewModel without any SwiftUI import?**

Yes:

```swift
import Testing

@Test func filtersByCaseInsensitiveContains() {
    let vm = CountriesViewModel()
    vm.searchText = "JA"
    #expect(vm.filtered.count == 1)
    #expect(vm.filtered.first?.name == "Japan")
}
```

The VM has zero UI dependencies. It's just Swift. That's the point of MVVM — logic is testable in isolation.

---

## What Changed vs Part 2

| Concern | Part 2 (View owns) | Part 3 (VM owns) |
|---------|--------------------|--------------------|
| Data source | `let countries` inside View | `private(set) var countries` in VM |
| Search text | `@State` in View | `var searchText` in VM |
| Filter logic | Computed in View | Computed in VM |
| View responsibility | Data + logic + layout | Just layout + binding |

The View file went from ~25 lines of mixed concerns to ~10 lines of pure UI.

---

## Concepts Landed in Part 3

| Concept | Where |
|---------|-------|
| `@Observable` macro | Class-level attribute on the VM |
| `@State` for owning an observable | `@State private var viewModel = …` |
| `private(set)` | Read-only from outside, mutable inside |
| MVVM boundary | VM has zero SwiftUI imports |
| Bindings into an `@Observable` | `$viewModel.searchText` |

---

## What's Missing (and Coming Next)

The VM still hard-codes the data. In a real app, data comes from **somewhere else** — a server, a database, a file. Where should the fetch code live?

- Not in the View (breaks the layer separation we just built).
- Not in the ViewModel directly — that would tie the VM to `URLSession`, making it impossible to test without a real network.

We need a boundary. That boundary is the **Domain layer**.

Continue → [[iOS Tutorial - Part 4 Domain Layer]]
