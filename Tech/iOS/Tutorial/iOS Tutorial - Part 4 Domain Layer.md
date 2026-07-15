---
tags:
  - ios
  - swiftui
  - tutorial
  - clean-architecture
  - domain
  - mobile
created: 2026-07-02
source: https://developer.apple.com/documentation/swift
---

# iOS Tutorial — Part 4: Domain Layer

> Extract business rules into a framework-free Domain layer. Introduce Entity, UseCase, and Repository *protocol*. Data still hard-coded — that comes in Part 5. Back to index: [[iOS Tutorial Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**Swift types & protocols:** [[iOS Tutorial Glossary#`protocol`|protocol]], [[iOS Tutorial Glossary#`Equatable` / `Hashable`|Equatable]]
**Architecture:** [[iOS Tutorial Glossary#Clean Architecture|Clean Architecture]], [[iOS Tutorial Glossary#Layer|Layer]], [[iOS Tutorial Glossary#Entity|Entity]], [[iOS Tutorial Glossary#Use Case (Interactor)|Use Case]], [[iOS Tutorial Glossary#Repository — protocol vs impl|Repository]], [[iOS Tutorial Glossary#Dependency Rule|Dependency Rule]], [[iOS Tutorial Glossary#Dependency Injection (DI)|Dependency Injection]], [[iOS Tutorial Glossary#Constructor Injection|Constructor Injection]]
**Combine:** [[iOS Tutorial Glossary#`Publisher`|Publisher]], [[iOS Tutorial Glossary#`AnyPublisher<Output, Failure>`|AnyPublisher]], [[iOS Tutorial Glossary#`Just`|Just]], [[iOS Tutorial Glossary#`.map`|.map]], [[iOS Tutorial Glossary#`.sink(receiveCompletion:receiveValue:)`|.sink]], [[iOS Tutorial Glossary#`.receive(on:)`|.receive(on:)]], [[iOS Tutorial Glossary#`.eraseToAnyPublisher()`|.eraseToAnyPublisher]], [[iOS Tutorial Glossary#`.setFailureType(to:)`|.setFailureType]], [[iOS Tutorial Glossary#`.store(in:)`|.store(in:)]], [[iOS Tutorial Glossary#`Cancellable` / `AnyCancellable`|Cancellable / AnyCancellable]]
**Swift:** [[iOS Tutorial Glossary#`[weak self]` — closure capture list|[weak self]]], [[iOS Tutorial Glossary#Access levels — `private`, `internal`, `public`|access levels]]
**SwiftUI:** [[iOS Tutorial Glossary#`ProgressView`|ProgressView]], [[iOS Tutorial Glossary#`ContentUnavailableView` (iOS 17+)|ContentUnavailableView]], [[iOS Tutorial Glossary#`@ViewBuilder`|@ViewBuilder]], [[iOS Tutorial Glossary#`.onAppear` / `.onDisappear`|.onAppear]], [[iOS Tutorial Glossary#`_propName` — the wrapper itself|_viewModel (State init trick)]]
**Foundation:** [[iOS Tutorial Glossary#`DispatchQueue`|DispatchQueue]], [[iOS Tutorial Glossary#`Set<AnyCancellable>`|Set<AnyCancellable>]]

---

## Prerequisites — Read These First

This part is the first place the Countries app touches **asynchronous work** — Combine publishers, `.receive(on: DispatchQueue.main)`, `[weak self]`, and a `cancellables` set. All three of those are consequences of Apple's threading and lifecycle model. If you write them by rote without understanding *why*, you'll silently ship purple thread warnings, memory leaks, or subscriptions that never fire.

| Note | What it explains that Part 4 depends on |
|------|-----------------------------------------|
| [[iOS SwiftUI - Concurrency and Threading]] | **Why `.receive(on: DispatchQueue.main)` exists.** URLSession delivers on a background queue; `@Observable` state mutation must happen on the main thread. |
| [[iOS ARC Guide]] (and [[iOS ARC - Retain Cycles]] specifically) | **Why `[weak self]` inside the stored `.sink { }` is mandatory.** The Combine subscription is stored on the VM; without `[weak self]` you form a self → cancellables → closure → self cycle. The `deinit` never runs, the VM leaks. |
| [[iOS SwiftUI - Lifecycle]] | **When the VM (and its cancellables) is created and destroyed.** The `Set<AnyCancellable>` lives as long as the VM lives; the VM lives as long as the view identity. If either lifetime is wrong, subscriptions leak or die early. |
| [[iOS SwiftUI Architecture - Combine Operators]] | **Full operator catalog** — `map`, `flatMap`, `sink`, `assign`, `receive(on:)`, `subscribe(on:)`, `eraseToAnyPublisher`. Skim the summary table before typing the pipeline below. |
| [[iOS SwiftUI Architecture - Clean Architecture]] | **Why we're adding layers now** — the theory behind Entity / UseCase / Repository. This part is where you *build* the layer; that note is where you understand *why*. |

If you're skimming just one, read the **Concurrency and Threading** note — it's the one whose absence causes the most confusing bugs later.

---

## Goal

The ViewModel stops knowing where countries come from. It asks a **Use Case** for them. The Use Case asks a **Repository protocol**. A mock implementation of that protocol returns the hard-coded array — for now.

```
ViewModel  →  FetchCountriesUseCase  →  CountriesRepository (protocol)
                                              ▲
                                              │ conforms to
                                    MockCountriesRepository   ← still hard-coded
```

Nothing in the Domain layer imports SwiftUI, Foundation.URLSession, or Combine. It's **pure Swift**.

---

## Step 1 — Set Up Folders

In Xcode, create groups (they're just folders):

```
CountriesApp/
├── Domain/
│   ├── Entities/
│   ├── UseCases/
│   └── Repositories/
├── Data/                    ← empty for now
├── Presentation/
│   ├── CountriesListView.swift    ← move here
│   ├── CountryRow.swift            ← move here
│   └── CountriesViewModel.swift    ← move here
└── App/
    └── CountriesAppApp.swift       ← move here
```

Groups are visual only — the file system layout matches. Drag files in Xcode's Project Navigator.

---

## Step 2 — Move `Country` to Domain

Move `Country.swift` into `Domain/Entities/`. This is your **Entity** — the core, framework-independent representation of a country.

```swift
// Domain/Entities/Country.swift
struct Country: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let capital: String
    let flag: String
}
```

Added `Equatable` — useful for tests and SwiftUI diffing. No imports. Zero framework dependencies.

> **Entity vs DTO.** The Entity is what the *rest of the app* uses. A DTO (`CountryDTO`) is what matches the *server's JSON shape*. They can differ: REST Countries v5 sends `capitals: [{name: "Hanoi"}, …]` (an array of objects, since some countries have multiple capitals), but your Entity uses `String` (first one). Mapping happens in the Data layer — see [[iOS Tutorial - Part 5 Data Layer]].

---

## Step 3 — Repository Protocol

Create `Domain/Repositories/CountriesRepository.swift`:

```swift
import Combine

protocol CountriesRepository {
    func fetchCountries() -> AnyPublisher<[Country], Error>
}
```

Wait — `import Combine` in the Domain layer? Isn't Combine a framework?

**Yes, it's a compromise.** Purists put a domain-defined async abstraction here (custom `Result` streams). Pragmatically, Combine's `AnyPublisher` is stable, first-party, and works with SwiftUI's `.onReceive`, so most Swift Clean Architecture references (including [[iOS SwiftUI Architecture - Clean Architecture]]) allow it in Domain. The alternative is `async throws` — see the callout below.

### `async/await` alternative

If you prefer:

```swift
protocol CountriesRepository {
    func fetchCountries() async throws -> [Country]
}
```

Both work. This tutorial uses Combine because Part 5 will use `URLSession.DataTaskPublisher` and the whole chain composes with operators (`map`, `receive(on:)`, etc.). See [[iOS SwiftUI Architecture - Combine Operators]] for what's available.

---

## Step 4 — Use Case

Create `Domain/UseCases/FetchCountriesUseCase.swift`:

```swift
import Combine

protocol FetchCountriesUseCase {
    func execute() -> AnyPublisher<[Country], Error>
}

struct FetchCountriesUseCaseImpl: FetchCountriesUseCase {
    let repository: CountriesRepository

    func execute() -> AnyPublisher<[Country], Error> {
        repository
            .fetchCountries()
            .map { $0.sorted { $0.name < $1.name } }   // business rule: alphabetical
            .eraseToAnyPublisher()
    }
}
```

### Why a UseCase if it just calls the Repository?

Fair question. The value shows up when the business rule grows:

- "Sort alphabetically" — a business rule. Sorting belongs here, not in the Repository (which just returns raw data) and not in the ViewModel (which is UI concern).
- "Only show countries with a capital" — filter here.
- "Combine countries + user favorites from two repositories" — orchestration here.

Rule of thumb: **if two features would compose the same logic differently, the UseCase is the reuse point.** For trivial pass-through, some teams skip UseCases entirely and let the VM depend on the Repository. That's a valid choice — Clean Architecture is guidance, not law.

---

## Step 5 — Mock Repository (temporary, will move to Data in Part 5)

Create `Domain/Repositories/MockCountriesRepository.swift`:

```swift
import Combine

struct MockCountriesRepository: CountriesRepository {
    func fetchCountries() -> AnyPublisher<[Country], Error> {
        let data: [Country] = [
            Country(name: "Vietnam", capital: "Hanoi",  flag: "🇻🇳"),
            Country(name: "Japan",   capital: "Tokyo",  flag: "🇯🇵"),
            Country(name: "France",  capital: "Paris",  flag: "🇫🇷"),
            Country(name: "Germany", capital: "Berlin", flag: "🇩🇪"),
            Country(name: "Italy",   capital: "Rome",   flag: "🇮🇹")
        ]
        return Just(data)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}
```

- `Just(data)` — a publisher that emits one value and finishes.
- `setFailureType(to: Error.self)` — `Just` has `Failure == Never`; the protocol needs `Failure == Error`, so we widen it.
- `eraseToAnyPublisher()` — erases the compound type to `AnyPublisher<[Country], Error>` so callers don't see the internal operator chain.

We'll delete this file in Part 5 (move it to `Data/` under a different name — it becomes useful in [[iOS Tutorial - Part 6 Dependency Injection]] for previews).

---

## Step 6 — Update the ViewModel

Update `Presentation/CountriesViewModel.swift`:

```swift
import Observation
import Combine

@Observable
final class CountriesViewModel {
    var searchText: String = ""
    private(set) var countries: [Country] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private let fetchCountries: FetchCountriesUseCase
    private var cancellables = Set<AnyCancellable>()

    init(fetchCountries: FetchCountriesUseCase) {
        self.fetchCountries = fetchCountries
    }

    var filtered: [Country] {
        guard !searchText.isEmpty else { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    func load() {
        isLoading = true
        errorMessage = nil

        fetchCountries.execute()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] countries in
                    self?.countries = countries
                }
            )
            .store(in: &cancellables)
    }
}
```

### What changed

- **Constructor takes a UseCase.** Not the Repository directly — that would skip a layer. The VM only knows about "the thing that fetches countries" — it doesn't know how or from where.
- **`cancellables` set.** Combine subscriptions are like Promises — you must hold onto them or the pipeline dies. `store(in:)` puts them in a `Set<AnyCancellable>` that's freed when the VM deallocs.
- **`receive(on: DispatchQueue.main)`.** Any UI update must happen on the main thread. `URLSession` publishers emit on a background queue, so we hop before touching `@Observable` properties. See [[iOS SwiftUI Architecture - Combine Operators]].
- **`[weak self]`.** Prevents a retain cycle: `cancellables` retains the sink → closure retains `self` → self retains `cancellables`. `[weak self]` breaks it.
- **`isLoading` / `errorMessage`.** Loading + error state is a Presentation concern. It lives in the VM, not the Domain.

---

## Step 7 — Update the View

Update `Presentation/CountriesListView.swift`:

```swift
import SwiftUI

struct CountriesListView: View {
    @State private var viewModel: CountriesViewModel

    init(viewModel: CountriesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Countries")
                .searchable(text: $viewModel.searchText, prompt: "Search countries")
                .onAppear { viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.countries.isEmpty {
            ProgressView("Loading…")
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView(
                "Something went wrong",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else {
            List(viewModel.filtered) { country in
                CountryRow(country: country)
            }
        }
    }
}

#Preview {
    CountriesListView(
        viewModel: CountriesViewModel(
            fetchCountries: FetchCountriesUseCaseImpl(
                repository: MockCountriesRepository()
            )
        )
    )
}
```

### Why the odd `init`?

`@State` on an `@Observable` normally instantiates in the property declaration. But now the VM has a *dependency* (`FetchCountriesUseCase`) — someone from outside has to provide it. The `_viewModel = State(initialValue:)` trick is the official way to feed a `@State` from an init parameter.

Ugly? Yes. In [[iOS Tutorial - Part 6 Dependency Injection]] we'll clean this up with a `DIContainer` factory.

### `ContentUnavailableView`

iOS 17+ built-in empty/error placeholder. Replaces the old "just show a `Text` in the center" pattern.

---

## Concepts Landed in Part 4

| Concept | Where |
|---------|-------|
| Domain layer | `Domain/` folder, zero UI imports |
| Entity | `Country` |
| Repository *protocol* | `CountriesRepository` in Domain |
| Repository *impl* | `MockCountriesRepository` (moves to Data next) |
| Use Case | `FetchCountriesUseCaseImpl` — business rules live here |
| Dependency direction | ViewModel → UseCase → Repository (protocol) — inward |
| Loading + error state | Presentation concern → in the ViewModel |
| Combine cancellables | `Set<AnyCancellable>` |
| Thread hop | `.receive(on: DispatchQueue.main)` |

Deep reference → [[iOS SwiftUI Architecture - Domain Layer]], [[iOS SwiftUI Architecture - Clean Architecture]].

---

## What's Missing (and Coming Next)

The Repository is still a mock returning hard-coded data. In Part 5 we implement a **real** repository that hits `https://api.restcountries.com/countries/v5` — introducing the Data layer with DTOs, network service, and JSON decoding.

Continue → [[iOS Tutorial - Part 5 Data Layer]]
