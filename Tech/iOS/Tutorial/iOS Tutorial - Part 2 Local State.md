---
tags:
  - ios
  - swiftui
  - tutorial
  - state
  - mobile
created: 2026-07-02
source: https://developer.apple.com/documentation/swiftui/state
---

# iOS Tutorial — Part 2: Local State

> Same UI as [[iOS Tutorial - Part 1 First SwiftUI Screen]] — plus a search field that filters the list. First taste of `@State`. Back to index: [[iOS Tutorial Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**Property wrappers:** [[iOS Tutorial Glossary#`@State`|@State]], [[iOS Tutorial Glossary#`@Binding`|@Binding]], [[iOS Tutorial Glossary#`$` — projected value|$ — projected value]]
**Protocols:** [[iOS Tutorial Glossary#`Identifiable`|Identifiable]]
**SwiftUI:** [[iOS Tutorial Glossary#`TextField`|TextField]], [[iOS Tutorial Glossary#`.searchable(text:prompt:)`|.searchable]]
**Swift:** [[iOS Tutorial Glossary#`guard`|guard]]

---

## Goal

Type in the search bar → list filters live.

```
┌──────────────────────────────┐
│  Countries                   │
│  🔍  ja                       │  ← search text
├──────────────────────────────┤
│  🇯🇵  Japan                   │
│     Tokyo                    │
└──────────────────────────────┘
```

---

## Step 1 — Make Country `Identifiable`

Update `Country.swift`:

```swift
struct Country: Identifiable {
    let id: String { name }   // ❌ won't compile — see fix below
    let name: String
    let capital: String
    let flag: String
}
```

Wait — that's wrong. `Identifiable` needs a **stored** `id`, or a computed `var`. Fix:

```swift
struct Country: Identifiable {
    var id: String { name }   // ✅ computed, uses name as identity
    let name: String
    let capital: String
    let flag: String
}
```

Now you can drop the `id:` parameter from `List`:

```swift
List(countries) { country in            // no more id: \.name
    CountryRow(country: country)
}
```

**Why identity matters:** SwiftUI diffs by identity. If two rows have the same `id`, SwiftUI thinks it's the *same* row and reuses it, animating text changes instead of insert/delete. Read [[iOS SwiftUI - Core Concepts]] on identity if you want the full picture.

---

## Step 2 — Introduce `@State`

Update `CountriesListView.swift`:

```swift
import SwiftUI

struct CountriesListView: View {
    @State private var searchText: String = ""

    private let countries: [Country] = [
        Country(name: "Vietnam", capital: "Hanoi",  flag: "🇻🇳"),
        Country(name: "Japan",   capital: "Tokyo",  flag: "🇯🇵"),
        Country(name: "France",  capital: "Paris",  flag: "🇫🇷"),
        Country(name: "Germany", capital: "Berlin", flag: "🇩🇪"),
        Country(name: "Italy",   capital: "Rome",   flag: "🇮🇹")
    ]

    private var filtered: [Country] {
        guard !searchText.isEmpty else { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { country in
                CountryRow(country: country)
            }
            .navigationTitle("Countries")
            .searchable(text: $searchText, prompt: "Search countries")
        }
    }
}
```

### `@State` in one paragraph

`@State` is a **property wrapper** that lets a `View` (which is a struct — normally immutable) hold mutable state. SwiftUI stores the actual value in a separate storage box tied to the view's identity, so when the view struct is recreated (which happens constantly), the state survives. When the wrapped value changes, SwiftUI re-runs `body`.

Rule of thumb: **`@State` is for state that is owned and used only by this view.** For shared state, you'll use `@Observable` in Part 3.

### `$searchText` — the projected value

`$searchText` gives you a `Binding<String>` — a **two-way** connection to the state. `.searchable(text:)` needs a binding so it can *write* to `searchText` when you type, not just read.

| Access | Type | Direction |
|--------|------|-----------|
| `searchText` | `String` | read |
| `$searchText` | `Binding<String>` | read + write |
| `_searchText` | `State<String>` | the wrapper itself (rarely needed) |

---

## Step 3 — Understand What Just Happened

The whole reactive loop:

```
1. You type "ja" into the search field
2. .searchable writes into $searchText Binding
3. @State detects the change, invalidates the view
4. SwiftUI re-runs body
5. `filtered` re-computes → returns [Japan]
6. List sees new data → diffs → animates rows out/in
```

You never wrote "reload the list." SwiftUI does that because `body` is a **function of state**.

---

## Concepts Landed in Part 2

| Concept | Where |
|---------|-------|
| `Identifiable` protocol | `Country` |
| `@State` property wrapper | `searchText` |
| `Binding` via `$` prefix | `$searchText` passed to `.searchable` |
| Computed property in a View | `filtered` |
| `.searchable(text:prompt:)` | Nav-integrated search bar (iOS 15+) |
| View as function of state | Type → state changes → body re-runs |

Full state catalog → [[iOS SwiftUI Architecture - MVVM with Combine]] (for legacy `ObservableObject`) and [[iOS SwiftUI Architecture - Observation Macro]] (for the modern `@Observable`).

---

## Why We Still Need to Refactor

Look at `CountriesListView` now. It holds:

- The hard-coded data (a **data source** concern)
- The filter logic (a **business** concern)
- The search state (a **presentation** concern)
- The layout (a **view** concern)

The View is doing four jobs. That's fine for 5 hard-coded countries — but the moment we add network loading, error states, retries, empty states, it becomes a mess. Time to extract a **ViewModel**.

Continue → [[iOS Tutorial - Part 3 MVVM ViewModel]]
