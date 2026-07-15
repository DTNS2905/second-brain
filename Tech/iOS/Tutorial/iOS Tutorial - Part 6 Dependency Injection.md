---
tags:
  - ios
  - swiftui
  - tutorial
  - clean-architecture
  - dependency-injection
  - mobile
created: 2026-07-02
source: https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
---

# iOS Tutorial — Part 6: Dependency Injection

> A `DIContainer` builds the object graph once at the app root. Views and Previews get a ready-made ViewModel — no manual chain plumbing. Back to index: [[iOS Tutorial Guide]].

---

## Prerequisites — Read These First

This part introduces `@MainActor` on the VM factory. Skim the relevant section of [[iOS SwiftUI - Concurrency and Threading]] first — specifically the "**`@MainActor` — the Swift Concurrency Way**" section. It'll explain why the factory carries the annotation and what it protects against.

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**Architecture:** [[iOS Tutorial Glossary#DI Container|DI Container]], [[iOS Tutorial Glossary#Composition Root|Composition Root]], [[iOS Tutorial Glossary#Factory Method|Factory Method]]
**Concurrency:** [[iOS Tutorial Glossary#`@MainActor`|@MainActor]]
**Combine:** [[iOS Tutorial Glossary#`Fail`|Fail]], [[iOS Tutorial Glossary#`Empty`|Empty]]
**Testing:** [[iOS Tutorial Glossary#Swift Testing framework|Swift Testing]], [[iOS Tutorial Glossary#`@Test`|@Test]], [[iOS Tutorial Glossary#`@Suite`|@Suite]], [[iOS Tutorial Glossary#`#expect`|#expect]], [[iOS Tutorial Glossary#`@testable import`|@testable import]]

---

## Goal

Kill the 5-deep constructor tower in `CountriesAppApp`. After this part:

```swift
@main
struct CountriesAppApp: App {
    let container = DIContainer.live

    var body: some Scene {
        WindowGroup {
            CountriesListView(viewModel: container.makeCountriesViewModel())
        }
    }
}
```

Previews will use `DIContainer.mock` — the *only* line that differs between prod and preview.

---

## Step 1 — Create the Container

Create `DI/DIContainer.swift`:

```swift
import Foundation

struct DIContainer {
    // MARK: - Infrastructure (leaves of the graph)
    let apiClient: APIClient
    let apiKey: String

    // MARK: - Data layer
    private var countriesRepository: CountriesRepository {
        CountriesRepositoryImpl(apiClient: apiClient, apiKey: apiKey)
    }

    // MARK: - Domain layer
    private var fetchCountriesUseCase: FetchCountriesUseCase {
        FetchCountriesUseCaseImpl(repository: countriesRepository)
    }

    // MARK: - Presentation factories
    @MainActor
    func makeCountriesViewModel() -> CountriesViewModel {
        CountriesViewModel(fetchCountries: fetchCountriesUseCase)
    }
}
```

### Design notes

- **`struct`, not `class`.** No hidden state. Cheap to copy.
- **Everything but leaves is a `private var { … }` computed property.** Constructed on demand — cheap because these are structs. If you had heavy singletons (a `Database`), you'd store them as `let` properties.
- **`makeCountriesViewModel()` is a factory.** Each call returns a fresh VM. That matters: views own their VMs (via `@State`), and each screen instance wants its own.
- **`@MainActor` on the factory.** `CountriesViewModel` mutates `@Observable` properties observed by SwiftUI, so it lives on the main actor. Marking the factory keeps that annotation flowing.

---

## Step 2 — Container Configurations

Extend the container with named configurations at the bottom of `DIContainer.swift`:

```swift
extension DIContainer {
    static let live = DIContainer(
        apiClient: URLSessionAPIClient(),
        apiKey: "rc_live_demo"          // swap for a real key before shipping
    )

    static let mock = DIContainer(
        apiClient: MockAPIClient(),
        apiKey: "unused-in-mock"        // MockAPIClient ignores the key
    )
}
```

We need a `MockAPIClient` for the mock container. Create `Data/Network/MockAPIClient.swift`:

```swift
import Combine
import Foundation

struct MockAPIClient: APIClient {
    func get<T: Decodable>(_ request: URLRequest, as type: T.Type) -> AnyPublisher<T, Error> {
        // Return the mock countries wrapped in the same envelope the real server uses.
        let envelope = CountriesResponseDTO(
            data: .init(objects: [
                CountryDTO(names: .init(common: "Vietnam"), capitals: [.init(name: "Hanoi")],  flag: .init(emoji: "🇻🇳")),
                CountryDTO(names: .init(common: "Japan"),   capitals: [.init(name: "Tokyo")],  flag: .init(emoji: "🇯🇵")),
                CountryDTO(names: .init(common: "France"),  capitals: [.init(name: "Paris")],  flag: .init(emoji: "🇫🇷")),
                CountryDTO(names: .init(common: "Germany"), capitals: [.init(name: "Berlin")], flag: .init(emoji: "🇩🇪")),
                CountryDTO(names: .init(common: "Italy"),   capitals: [.init(name: "Rome")],   flag: .init(emoji: "🇮🇹"))
            ])
        )

        guard let cast = envelope as? T else {
            return Fail(error: URLError(.cannotDecodeContentData)).eraseToAnyPublisher()
        }
        return Just(cast)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}
```

> **Note:** `envelope as? T` only works when `T` is `CountriesResponseDTO` — this mock is scoped to *this app's* endpoints. A production mock swaps by URL path and returns bundled JSON fixtures. Acceptable trade-off for a tutorial.

Now you can delete `MockCountriesRepository.swift` — `DIContainer.mock` handles the same job through the `APIClient` seam.

---

## Step 3 — Simplify the App Entry Point

Update `App/CountriesAppApp.swift`:

```swift
import SwiftUI

@main
struct CountriesAppApp: App {
    let container = DIContainer.live

    var body: some Scene {
        WindowGroup {
            CountriesListView(viewModel: container.makeCountriesViewModel())
        }
    }
}
```

Compare with Part 5:

```swift
// Before
CountriesListView(
    viewModel: CountriesViewModel(
        fetchCountries: FetchCountriesUseCaseImpl(
            repository: CountriesRepositoryImpl(
                apiClient: URLSessionAPIClient(),
                apiKey: "rc_live_demo"
            )
        )
    )
)
// After
CountriesListView(viewModel: container.makeCountriesViewModel())
```

The **construction concern** now lives in one file, one place.

---

## Step 4 — Previews

Update the `#Preview` in `Presentation/CountriesListView.swift`:

```swift
#Preview("Live-shape (mock data)") {
    CountriesListView(viewModel: DIContainer.mock.makeCountriesViewModel())
}
```

Previews are now:

- **Deterministic** — no network, no flakes.
- **Fast** — no 250-country JSON decode.
- **Real code path** — VM → UseCase → Repository → APIClient — everything except the URL round-trip.

---

## Step 5 — Preview a Specific State

Sometimes you want the preview to show the error state. Add extra factories:

```swift
extension DIContainer {
    @MainActor
    func makeCountriesViewModel_loading() -> CountriesViewModel {
        let vm = CountriesViewModel(fetchCountries: NeverFinishingUseCase())
        vm.load()
        return vm
    }

    @MainActor
    func makeCountriesViewModel_error() -> CountriesViewModel {
        let vm = CountriesViewModel(fetchCountries: FailingUseCase())
        vm.load()
        return vm
    }
}

private struct NeverFinishingUseCase: FetchCountriesUseCase {
    func execute() -> AnyPublisher<[Country], Error> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }
}

private struct FailingUseCase: FetchCountriesUseCase {
    func execute() -> AnyPublisher<[Country], Error> {
        Fail(error: URLError(.notConnectedToInternet)).eraseToAnyPublisher()
    }
}
```

Then:

```swift
#Preview("Loading") {
    CountriesListView(viewModel: DIContainer.mock.makeCountriesViewModel_loading())
}

#Preview("Error") {
    CountriesListView(viewModel: DIContainer.mock.makeCountriesViewModel_error())
}
```

Three preview variants, one file, zero real network. This is where MVVM + DI genuinely pays off.

---

## Step 6 — Unit Tests

Create a test target if you don't have one (`File → New → Target → Unit Testing Bundle`).

```swift
import Testing
@testable import CountriesApp

@Suite("CountriesViewModel")
struct CountriesViewModelTests {

    @Test
    func filtersByCaseInsensitiveContains() async {
        let vm = await DIContainer.mock.makeCountriesViewModel()
        await vm.load()
        // give the Just publisher a tick — in real code use expectations
        try? await Task.sleep(for: .milliseconds(10))

        await MainActor.run {
            vm.searchText = "JA"
            #expect(vm.filtered.count == 1)
            #expect(vm.filtered.first?.name == "Japan")
        }
    }
}
```

Notice the test **never imports SwiftUI**. It never touches `URLSession`. The mock container gives you a fully wired VM with predictable data.

Deep reference → [[iOS SwiftUI Architecture - Dependency Injection]].

---

## Concepts Landed in Part 6

| Concept | Where |
|---------|-------|
| Composition root | `DIContainer.live` / `.mock` |
| Factory methods | `makeCountriesViewModel()` returns fresh VMs |
| Configuration-based DI | Swap the whole graph via `static let` variants |
| Preview isolation | Previews use `.mock` — no network dependency |
| Preview state factories | `_loading`, `_error` variants for edge cases |
| Testable VM | Test file imports the app, not SwiftUI |

---

## Continue

You built a working Clean Architecture app across 6 parts. One last thing: **step back and look at the whole shape**. That's Part 7.

Continue → [[iOS Tutorial - Part 7 Recap and Folder Layout]]
