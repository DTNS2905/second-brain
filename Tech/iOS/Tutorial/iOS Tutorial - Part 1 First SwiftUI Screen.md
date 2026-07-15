---
tags:
  - ios
  - swiftui
  - tutorial
  - mobile
created: 2026-07-02
source: https://developer.apple.com/tutorials/swiftui
---

# iOS Tutorial — Part 1: First SwiftUI Screen

> Static list, static rows, static data. No state, no logic, no networking. Just SwiftUI vocabulary and layout. Back to index: [[iOS Tutorial Guide]].

---

## New Keywords in This Part

Every unknown word is one click away. Full definitions in [[iOS Tutorial Glossary]].

**Swift:** [[iOS Tutorial Glossary#`struct`|struct]], [[iOS Tutorial Glossary#`let` vs `var`|let vs var]], [[iOS Tutorial Glossary#Closure `{ … }`|closure]]
**SwiftUI core:** [[iOS Tutorial Glossary#`View` protocol|View]], [[iOS Tutorial Glossary#`body`|body]], [[iOS Tutorial Glossary#`some View` (opaque return type)|some View]], [[iOS Tutorial Glossary#`App` protocol|App]], [[iOS Tutorial Glossary#`Scene`|Scene]], [[iOS Tutorial Glossary#`WindowGroup`|WindowGroup]], [[iOS Tutorial Glossary#`@main`|@main]], [[iOS Tutorial Glossary#Modifier|Modifier]], [[iOS Tutorial Glossary#`#Preview` macro|#Preview]]
**SwiftUI views:** [[iOS Tutorial Glossary#`Text`|Text]], [[iOS Tutorial Glossary#`HStack`, `VStack`, `ZStack`|HStack / VStack]], [[iOS Tutorial Glossary#`List`|List]], [[iOS Tutorial Glossary#`NavigationStack` (iOS 16+)|NavigationStack]], [[iOS Tutorial Glossary#`.padding()`, `.font()`, `.foregroundStyle()`|.padding / .font / .foregroundStyle]]
**Types & protocols:** [[iOS Tutorial Glossary#`KeyPath` (`\.name`)|KeyPath]]

---

## Goal

By the end of this part, you can run the app and see:

```
┌──────────────────────────────┐
│  Countries                   │  ← navigation title
├──────────────────────────────┤
│  🇻🇳  Vietnam                 │
│     Hanoi                    │
├──────────────────────────────┤
│  🇯🇵  Japan                   │
│     Tokyo                    │
├──────────────────────────────┤
│  🇫🇷  France                  │
│     Paris                    │
└──────────────────────────────┘
```

---

## Step 1 — Create the Project

1. Xcode → **File → New → Project → App**.
2. Product name: `CountriesApp`. Interface: **SwiftUI**. Language: **Swift**.
3. Delete the auto-generated `ContentView.swift` (we'll rename it).

---

## Step 2 — Model (temporary, will move to Domain in Part 4)

Create `Country.swift`:

```swift
struct Country {
    let name: String
    let capital: String
    let flag: String   // emoji for now — no network yet
}
```

A `struct` is a value type. It's cheap to copy and safe to pass to SwiftUI, which re-runs `body` a lot. See [[iOS SwiftUI - Core Concepts]] on why SwiftUI prefers value types.

---

## Step 3 — Row View

Create `CountryRow.swift`:

```swift
import SwiftUI

struct CountryRow: View {
    let country: Country

    var body: some View {
        HStack(spacing: 12) {
            Text(country.flag)
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 4) {
                Text(country.name)
                    .font(.headline)
                Text(country.capital)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### What's happening

| Line | Concept |
|------|---------|
| `struct CountryRow: View` | Every SwiftUI screen or piece is a `struct` conforming to `View`. |
| `var body: some View` | `some View` is an **opaque return type** — "I return one specific `View` type, don't ask which." |
| `HStack { … }` | Lays children horizontally. |
| `VStack(alignment: .leading)` | Lays children vertically, left-aligned. |
| `.font(.headline)` | A **modifier**. Modifiers return a new `View`, they don't mutate. Order matters. |
| `.foregroundStyle(.secondary)` | iOS 15+ replacement for `.foregroundColor`. Adapts to light/dark. |

---

## Step 4 — List View

Create `CountriesListView.swift`:

```swift
import SwiftUI

struct CountriesListView: View {
    let countries: [Country] = [
        Country(name: "Vietnam", capital: "Hanoi",  flag: "🇻🇳"),
        Country(name: "Japan",   capital: "Tokyo",  flag: "🇯🇵"),
        Country(name: "France",  capital: "Paris",  flag: "🇫🇷")
    ]

    var body: some View {
        NavigationStack {
            List(countries, id: \.name) { country in
                CountryRow(country: country)
            }
            .navigationTitle("Countries")
        }
    }
}

#Preview {
    CountriesListView()
}
```

### What's happening

- `NavigationStack` — iOS 16+ replacement for `NavigationView`. Gives you the title bar and pushes.
- `List(countries, id: \.name)` — SwiftUI needs a **stable identity** for each row so it can diff them. `\.name` is a `KeyPath`. In Part 3 we'll make `Country` conform to `Identifiable` and drop the `id:` parameter.
- `#Preview { … }` — Xcode Previews. Rebuilds every time you save; no need to run the simulator for every tweak.

---

## Step 5 — Wire It Up

In `CountriesAppApp.swift` (the `@main` entry point):

```swift
import SwiftUI

@main
struct CountriesAppApp: App {
    var body: some Scene {
        WindowGroup {
            CountriesListView()
        }
    }
}
```

`App` is the top-level protocol. `WindowGroup` is a scene that hosts one or more windows (on iPhone/iPad it's the single main window).

Run with `Cmd+R`. You should see the list.

---

## Concepts Landed in Part 1

| Concept                     | Where it appeared                                           |
| --------------------------- | ----------------------------------------------------------- |
| `View` protocol             | Every struct that draws                                     |
| `some View` (opaque return) | `body`                                                      |
| View composition            | `CountriesListView` uses `CountryRow`                       |
| Layout containers           | `HStack`, `VStack`, `NavigationStack`                       |
| Modifiers                   | `.font`, `.padding`, `.foregroundStyle`, `.navigationTitle` |
| `List` + identity           | `id: \.name`                                                |
| Previews                    | `#Preview { … }`                                            |
|                             |                                                             |

Deeper dive → [[iOS SwiftUI - Core Concepts]], [[iOS SwiftUI - Core Components]].

---

## What's Missing (and Coming Next)

- The data is hard-coded in the view. → **Part 2** hoists to `@State` so we can *change* it.
- There's no interactivity. → **Part 2** adds search.
- The view knows too much. → **Part 3** extracts a ViewModel.

Continue → [[iOS Tutorial - Part 2 Local State]]
