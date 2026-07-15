---
tags:
  - ios
  - swiftui
  - tutorial
  - clean-architecture
  - data-layer
  - combine
  - urlsession
  - mobile
created: 2026-07-02
updated: 2026-07-06
source: https://developer.apple.com/documentation/foundation/urlsession/datataskpublisher
api-reference: https://restcountries.com/docs
---

# iOS Tutorial — Part 5: Data Layer

> Replace the mock repository with a real one that hits the REST Countries **v5** API. Introduce DTO, `URLSession.dataTaskPublisher`, and DTO → Entity mapping. Back to index: [[iOS Tutorial Guide]].

---

## Heads-up — the API changed (2026)

The tutorial originally used `https://restcountries.com/v3.1/all?fields=…`. That version is deprecated: it now returns an error payload, not country data. This part uses **v5**, which changed in three ways that matter to us:

| Change | v3.1 (old) | v5 (current) |
|--------|-----------|--------------|
| Host | `restcountries.com` | `api.restcountries.com` |
| Auth | none | **API key required** (Bearer header) |
| Envelope | bare array `[…]` | JSON:API — `{ "data": { "objects": […], "meta": {…} } }` |
| `name` shape | `{ common, official }` | `names: { common, official, native, … }` |
| `capital` shape | `["Hanoi"]` (array of strings) | `capitals: [{ name: "Hanoi", … }]` (array of objects) |
| `flag` shape | `"🇻🇳"` (string) | `flag: { emoji, url_svg, unicode, … }` (object) |
| Pagination | none | paginated — default 25, max 100 on free tier |

For the tutorial you can use the public demo key `rc_live_demo`. In a real app, sign up at [restcountries.com](https://restcountries.com/) and treat the key like any secret.

---

## Prerequisites — Read These First

This part is where the app first hits the real network. Two Fundamentals notes are load-bearing here:

| Note | Why you need it here |
|------|----------------------|
| [[iOS SwiftUI - Concurrency and Threading]] | `URLSession.dataTaskPublisher` delivers on a **background** queue. The `.decode`/`.map` operators run there too, and only `.receive(on: DispatchQueue.main)` hops back for UI safety. Understand the hop before writing the pipeline. |
| [[iOS ARC Guide]] | The pipeline is stored on the VM via `Set<AnyCancellable>`. If any closure inside the chain captures `self` strongly, you get a retain cycle. Read this before you sprinkle `[weak self]` from muscle memory. |

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**Architecture:** [[iOS Tutorial Glossary#DTO — Data Transfer Object|DTO]], [[iOS Tutorial Glossary#Envelope (JSON:API)|Envelope (JSON:API)]]
**Swift types & protocols:** [[iOS Tutorial Glossary#`extension`|extension]], [[iOS Tutorial Glossary#`Decodable` / `Encodable` / `Codable`|Decodable]], [[iOS Tutorial Glossary#Generics `<T>`|generics]]
**Combine:** [[iOS Tutorial Glossary#`.tryMap`|.tryMap]], [[iOS Tutorial Glossary#`.decode(type:decoder:)`|.decode]], [[iOS Tutorial Glossary#`.compactMap`|.compactMap]]
**Foundation:** [[iOS Tutorial Glossary#`URL`|URL]], [[iOS Tutorial Glossary#`URLRequest`|URLRequest]], [[iOS Tutorial Glossary#`URLSession`|URLSession]], [[iOS Tutorial Glossary#`URLSession.DataTaskPublisher`|dataTaskPublisher]], [[iOS Tutorial Glossary#`URLResponse` / `HTTPURLResponse`|HTTPURLResponse]], [[iOS Tutorial Glossary#`URLError`|URLError]], [[iOS Tutorial Glossary#`Data`|Data]], [[iOS Tutorial Glossary#`JSONDecoder`|JSONDecoder]]
**Swift:** [[iOS Tutorial Glossary#Optional (`?` and `!`)|Optional]], [[iOS Tutorial Glossary#`if let`|if let]]

---

## Goal

The Domain layer is unchanged. The `MockCountriesRepository` moves to `Data/` (where it stays useful for tests and previews). A new `CountriesRepositoryImpl` fetches real data.

```
Presentation                Domain                        Data
────────────                ──────                        ────
ViewModel                                                 CountriesRepositoryImpl
   │                                                            │
   ▼                                                            ▼
FetchCountriesUseCase  →  CountriesRepository (protocol)    APIClient
                                    ▲                           │
                                    │ implemented by            ▼
                                    │                       URLSession
                                    └───────────────────────────┘
```

`Presentation` depends only on `Domain`. `Data` depends only on `Domain`. Neither knows about the other. **That's the Dependency Rule.**

---

## Step 1 — Understand the JSON

Request:

```
GET https://api.restcountries.com/countries/v5
    ?response_fields=names.common,capitals.name,flag.emoji
    &limit=100
Authorization: Bearer rc_live_demo
```

Two things to notice in that URL:

- `response_fields=…` — a comma-separated **allowlist** of dot-paths. v5 returns 80+ fields per country by default; we ask for exactly three. Bandwidth stays small, parsing stays cheap.
- `limit=100` — v5 is paginated. Free-tier max per page is 100; there are ~250 countries in the world. For this tutorial we show the first 100 and treat pagination as an exercise (see [[iOS Tutorial - Part 9 From Tutorial to Real App]]).

Response:

```json
{
  "data": {
    "objects": [
      {
        "names": { "common": "Vietnam" },
        "capitals": [{ "name": "Hanoi" }],
        "flag": { "emoji": "🇻🇳" }
      },
      …
    ],
    "meta": {
      "total": 249,
      "count": 100,
      "limit": 100,
      "offset": 0,
      "more": true
    }
  }
}
```

Mismatches with our `Country` entity:

| Server | Entity |
|--------|--------|
| Wrapped in `{ data: { objects: [...] } }` | Just an array of `Country` |
| `names: { common: "Vietnam" }` (nested) | `name: "Vietnam"` (flat) |
| `capitals: [{ name: "Hanoi" }]` (array of objects — some countries have multiple, some have none) | `capital: "Hanoi"` (single string) |
| Every leaf is nullable | Non-optional Entity |

We handle this with a **DTO** — a struct that matches the server shape, then maps to the Entity.

---

## Step 2 — DTO

Create `Data/DTOs/CountryDTO.swift`:

```swift
struct CountriesResponseDTO: Decodable {
    let data: DataEnvelope

    struct DataEnvelope: Decodable {
        let objects: [CountryDTO]
    }
}

struct CountryDTO: Decodable {
    let names: NamesDTO
    let capitals: [CapitalDTO]?
    let flag: FlagDTO?

    struct NamesDTO: Decodable {
        let common: String
    }

    struct CapitalDTO: Decodable {
        let name: String
    }

    struct FlagDTO: Decodable {
        let emoji: String?
    }
}

extension CountryDTO {
    func toDomain() -> Country? {
        guard
            let capital = capitals?.first?.name,
            let flag = flag?.emoji
        else { return nil }

        return Country(
            name: names.common,
            capital: capital,
            flag: flag
        )
    }
}
```

### Why the two-level DTO?

`CountriesResponseDTO` matches the JSON:API **envelope** — the outer `{ data: { objects: […] } }` shape. `CountryDTO` matches one country record. Keeping them separate means:

- `CountryDTO` is reusable — the same shape appears in single-country endpoints (unwrapped from the envelope by the repository).
- The envelope structure is a data-transport detail; it should never leak into the repo signature. Callers still receive `[Country]`, not `CountriesResponseDTO`.

### Why `toDomain() -> Country?` (optional)?

If the server omits `capitals` or `flag`, we can't build a valid Entity. Returning `nil` and filtering out invalid rows at the mapping boundary keeps invariants clean:

> **Nothing outside the Data layer sees invalid data.**

The alternative is throwing — also fine, but noisier when 3 of 100 countries have missing fields.

---

## Step 3 — API Client

Create `Data/Network/APIClient.swift`:

```swift
import Foundation
import Combine

protocol APIClient {
    func get<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type
    ) -> AnyPublisher<T, Error>
}

struct URLSessionAPIClient: APIClient {
    let session: URLSession = .shared
    let decoder: JSONDecoder = JSONDecoder()

    func get<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type
    ) -> AnyPublisher<T, Error> {
        session
            .dataTaskPublisher(for: request)
            .tryMap { data, response -> Data in
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            .decode(type: T.self, decoder: decoder)
            .eraseToAnyPublisher()
    }
}
```

### Why `URLRequest`, not `URL`?

The previous draft of this tutorial took a bare `URL`. That works only for anonymous GETs — the moment you need an `Authorization` header (as v5 requires), a bare URL isn't enough. `URLRequest` is the small wrapper `URLSession` really wants: URL + method + headers + optional body. Passing it through the protocol keeps the seam clean and forward-compatible with POSTs and other verbs.

### What each operator does

| Operator | Effect |
|----------|--------|
| `dataTaskPublisher(for:)` | Emits `(Data, URLResponse)` when the request finishes. |
| `tryMap` | Like `map`, but the closure can throw. We use it to check status code. |
| `decode(type:decoder:)` | Runs `JSONDecoder.decode` — throws on parse failure. |
| `eraseToAnyPublisher()` | Hides the compound generic type. |

Full operator catalog → [[iOS SwiftUI Architecture - Combine Operators]].

### Why a protocol?

`APIClient` is a protocol so tests can substitute `MockAPIClient` returning `Just(fakeData)`. `URLSession` itself is hard to mock cleanly.

---

## Step 4 — Real Repository

Create `Data/Repositories/CountriesRepositoryImpl.swift`:

```swift
import Combine
import Foundation

struct CountriesRepositoryImpl: CountriesRepository {
    let apiClient: APIClient
    let apiKey: String

    private var request: URLRequest {
        var components = URLComponents(string: "https://api.restcountries.com/countries/v5")!
        components.queryItems = [
            URLQueryItem(name: "response_fields", value: "names.common,capitals.name,flag.emoji"),
            URLQueryItem(name: "limit", value: "100")
        ]
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    func fetchCountries() -> AnyPublisher<[Country], Error> {
        apiClient
            .get(request, as: CountriesResponseDTO.self)
            .map { response in
                response.data.objects.compactMap { $0.toDomain() }
            }
            .eraseToAnyPublisher()
    }
}
```

### Why `URLComponents` instead of a `URL(string:)` literal?

`URLComponents` percent-encodes query values for you. `response_fields=names.common,capitals.name,flag.emoji` happens to be URL-safe, but the moment you interpolate user input (a search term, a country code) into a query, hand-built URL strings become an injection footgun. Get the habit right now.

### The mapping line

```swift
.map { response in response.data.objects.compactMap { $0.toDomain() } }
```

- `map` on a `Publisher` transforms its output.
- We reach through the JSON:API envelope (`response.data.objects`) to the array of DTOs.
- `compactMap` on `Array` drops `nil`s from the DTO → Entity mapper.

Result: `[CountryDTO]` becomes `[Country]`, silently dropping countries with missing capital or flag.

### Where does the API key live?

Constructor-injected. In the tutorial we hard-code `rc_live_demo` at the app entry point (Step 6). In a real app it comes from a config file, keychain, or a build-time secret store — never checked into source. See [[iOS Tutorial - Part 9 From Tutorial to Real App]] T2.x for secret handling.

---

## Step 5 — Relocate the Mock

Move `MockCountriesRepository.swift` from `Domain/Repositories/` to `Data/Repositories/`. It's not a Domain concern — the Domain only owns the *protocol*. The mock is an *implementation*, so it lives in Data (or in a dedicated `TestSupport/` folder — team preference).

We'll use it in previews and unit tests in [[iOS Tutorial - Part 6 Dependency Injection]].

---

## Step 6 — Wire the Real Repo in the App Entry Point

Update `App/CountriesAppApp.swift`:

```swift
import SwiftUI

@main
struct CountriesAppApp: App {
    var body: some Scene {
        WindowGroup {
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
        }
    }
}
```

Look at that constructor chain: **VM ← UseCase ← Repository ← APIClient**. That's the Dependency Rule at runtime — outer layers depend on inner ones. It's ugly to write manually, which is exactly why the next part introduces a DI container.

> **Don't ship `rc_live_demo`.** The demo key is rate-limited and shared across everyone reading these docs. Register for a free key before you build for TestFlight.

---

## Step 7 — Info.plist (App Transport Security)

`api.restcountries.com` supports HTTPS so no ATS exception is needed. If you ever hit an HTTP-only endpoint, you'd add:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

Don't do this globally in production — scope with `NSExceptionDomains`.

---

## Step 8 — Run It

`Cmd+R`. You should see a live list of 100 countries, alphabetized, with real flags. Search still works.

If it hangs on "Loading…":

- Check the network in Simulator (Safari should load a page).
- Add a `.handleEvents(receiveOutput: { print($0) })` before `.decode(...)` in `URLSessionAPIClient.get` to see raw bytes.
- **401 Unauthorized** — the `Authorization` header is missing or the key is wrong. Log `request.allHTTPHeaderFields` before firing.
- **429 Too Many Requests** — the demo key is shared and rate-limited. Wait a minute or use your own key.
- **Empty list** — inspect the DTO decode error in the console. The v5 envelope changed once already (v4 → v5); if you see a `keyNotFound` for `data` or `objects`, the server shape drifted and the DTO needs to catch up.

---

## Concepts Landed in Part 5

| Concept | Where |
|---------|-------|
| DTO — matches server shape | `CountryDTO` |
| Envelope DTO — matches JSON:API wrapper | `CountriesResponseDTO` |
| DTO → Entity mapping | `.toDomain() -> Country?` |
| API client protocol | `APIClient` |
| `URLRequest` with a Bearer header | `CountriesRepositoryImpl.request` |
| `URLComponents` for safe query building | Same |
| `URLSession.dataTaskPublisher` | `URLSessionAPIClient.get` |
| Status-code validation via `tryMap` | Same |
| JSON decoding via `.decode(type:decoder:)` | Same |
| Publisher `map` reaching through an envelope | `response.data.objects` |
| Data layer boundaries | Data depends only on Domain protocols |

Deep reference → [[iOS SwiftUI Architecture - Data Layer]].

---

## What's Missing (and Coming Next)

The App entry point manually constructs a 5-deep dependency chain (VM ← UseCase ← Repo ← APIClient ← apiKey). Adding one more feature (say, a *favorite countries* store) would double the mess. And previews still have to build the whole chain by hand.

Time for a **DI container**.

Continue → [[iOS Tutorial - Part 6 Dependency Injection]]
