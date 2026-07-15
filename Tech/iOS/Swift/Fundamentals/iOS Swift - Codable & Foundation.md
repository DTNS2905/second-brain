---
tags:
  - ios
  - swift
  - fundamentals
  - codable
  - foundation
  - mobile
created: 2026-07-10
source: https://developer.apple.com/documentation/swift/codable
apple_docs:
  - https://developer.apple.com/documentation/swift/codable
  - https://developer.apple.com/documentation/foundation
  - https://developer.apple.com/documentation/foundation/jsondecoder
  - https://developer.apple.com/documentation/foundation/jsonencoder
---

# iOS Swift — Codable & Foundation

> How Swift turns JSON into structs, and the Foundation types every iOS app touches. Back to [[iOS Swift Fundamentals Guide]].

---

## Definitions

- **Foundation**: Apple's cross-platform standard library for values, collections, dates, files, networking primitives, and formatting. Imported implicitly on iOS via `Foundation`. Distinct from the Swift *standard library* (which gives you `Int`, `String`, `Array`, etc.).
- **`Encodable`**: a protocol; conforming types can be *encoded* into an external representation (usually JSON `Data`).
- **`Decodable`**: a protocol; conforming types can be *decoded* from an external representation.
- **`Codable`**: `typealias Codable = Encodable & Decodable`. Conform to this when you need both directions.
- **`JSONEncoder` / `JSONDecoder`**: the concrete coders that turn `Codable` types into `Data` and back.
- **`CodingKeys`**: a nested `enum: String, CodingKey` inside a `Codable` type that maps between property names and JSON keys.
- **Synthesis**: the compiler auto-generates `init(from:)` and `encode(to:)` for structs/enums where every stored property is itself `Codable`.
- **DTO** (Data Transfer Object): a struct that mirrors the shape of the server's JSON, lives in the Data Layer, conforms to `Codable`.
- **Entity**: the framework-free domain type used by the rest of the app, lives in the Domain Layer, does **not** conform to `Codable`.

Prerequisites: [[iOS Swift - Values and Types]], [[iOS Swift - Optionals]], [[iOS Swift - Error Handling]].

---

## Automatic Synthesis

If every stored property conforms to `Codable`, the compiler writes the encode/decode code for you.

```swift
struct Country: Codable {
    let name: String
    let population: Int
    let independent: Bool
    let capital: String?
}

let json = """
{ "name": "Vietnam", "population": 97000000, "independent": true, "capital": "Hanoi" }
""".data(using: .utf8)!

let country = try JSONDecoder().decode(Country.self, from: json)
let back = try JSONEncoder().encode(country)
```

Rules:

- All stored properties must be `Codable`.
- Property names must match JSON keys **exactly** (case-sensitive) — unless you provide `CodingKeys` or a key strategy.
- `Optional` properties become "may be absent or `null` in JSON."

---

## `CodingKeys` — Renaming Individual Keys

When the JSON's naming disagrees with your Swift style, add a nested `CodingKeys` enum. List every property; the compiler uses this instead of the auto-generated one.

```swift
struct Country: Codable {
    let commonName: String
    let officialName: String
    let population: Int

    enum CodingKeys: String, CodingKey {
        case commonName = "common_name"
        case officialName = "official"
        case population
    }
}
```

If you list a property in `CodingKeys` but omit it, decoding will *skip* that property — useful for excluding a computed or client-only field from encoding.

---

## `JSONDecoder` Strategies

Configure a single decoder for whole-payload transforms instead of hand-writing `CodingKeys` for every type.

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
decoder.dateDecodingStrategy = .iso8601

struct Post: Decodable {
    let id: UUID
    let authorName: String        // decodes from "author_name"
    let createdAt: Date           // decodes from "2026-07-10T09:00:00Z"
}
```

| Strategy | Options |
|----------|---------|
| `keyDecodingStrategy` | `.useDefaultKeys`, `.convertFromSnakeCase`, `.custom` |
| `dateDecodingStrategy` | `.deferredToDate`, `.iso8601`, `.secondsSince1970`, `.millisecondsSince1970`, `.formatted(DateFormatter)`, `.custom` |
| `dataDecodingStrategy` | `.base64`, `.custom`, `.deferredToData` |
| `nonConformingFloatDecodingStrategy` | `.throw`, `.convertFromString(...)` (for `Infinity`/`NaN`) |

`JSONEncoder` has the same knobs (`keyEncodingStrategy`, `dateEncodingStrategy`, `outputFormatting = .prettyPrinted`, etc.).

---

## Custom `init(from decoder:)`

Reach for this when synthesis can't express the transformation — flattening nested containers, decoding a heterogeneous field, or accepting multiple shapes.

```swift
struct Country: Decodable {
    let name: String
    let capital: String?

    enum CodingKeys: String, CodingKey {
        case name, capitals
    }

    private enum NameKeys: String, CodingKey { case common }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)

        let nameContainer = try root.nestedContainer(keyedBy: NameKeys.self, forKey: .name)
        self.name = try nameContainer.decode(String.self, forKey: .common)

        var capitals = try root.nestedUnkeyedContainer(forKey: .capitals)
        self.capital = try? capitals.decode(String.self)
    }
}
```

Symmetric override: `func encode(to encoder: Encoder) throws`. Decoding errors thrown here become `DecodingError` cases — see [[iOS Swift - Error Handling]].

---

## Foundation Types You'll See Constantly

| Type | Use |
|------|-----|
| `Date` | An instant in time (no timezone attached — it's just seconds since 2001-01-01 UTC) |
| `URL` | A validated URL. Prefer `URL(string:)` (returns optional) over string concatenation |
| `URLComponents` | Build/parse URLs safely — query items, scheme, host |
| `Data` | A byte buffer. What `JSONEncoder` produces and `URLSession` returns |
| `UUID` | 128-bit identifier. Codable-friendly, great for entity IDs |
| `Measurement<UnitLength>` (etc.) | Values-with-units. Automatic conversion + locale-aware formatting |
| `Locale`, `TimeZone`, `Calendar` | The trio behind every date/number/currency format |
| `URLSession` | HTTP client. See [[iOS SwiftUI Architecture - Data Layer]] |

Quick tour:

```swift
let id = UUID()

var comps = URLComponents(string: "https://api.example.com/posts")!
comps.queryItems = [URLQueryItem(name: "page", value: "2")]
let url = comps.url!    // https://api.example.com/posts?page=2

let distance = Measurement(value: 5, unit: UnitLength.kilometers)
let miles = distance.converted(to: .miles)
print(miles.value)      // 3.10685...
```

---

## Date Formatting: Three APIs, One Choice Each Time

| API | Use when |
|-----|----------|
| `ISO8601DateFormatter` | Round-tripping timestamps with a server (`2026-07-10T09:00:00Z`). Thread-safe. |
| `Date.FormatStyle` (iOS 15+) | Displaying dates to the user. Modern, locale-aware, allocation-light. |
| `DateFormatter` | Legacy or when you need a custom format string. Expensive to instantiate — cache it. |

```swift
let iso = ISO8601DateFormatter().string(from: .now)
// "2026-07-10T09:15:32Z"

let human = Date.now.formatted(date: .abbreviated, time: .shortened)
// "Jul 10, 2026 at 4:15 PM" (en-US)

let custom = Date.now.formatted(
    .dateTime.year().month(.wide).day().hour().minute()
)
```

For anything user-facing, prefer `Date.FormatStyle` — it handles locale, calendar, and RTL automatically.

---

## Codable in Clean Architecture

The layer boundary is the whole point of DTO/Entity separation.

```swift
// ─── Data Layer ──────────────────────────────────────────
struct CountryDTO: Decodable {
    let name: NameDTO
    let capital: [String]?
    let population: Int

    struct NameDTO: Decodable {
        let common: String
        let official: String
    }
}

extension CountryDTO {
    func toDomain() -> Country? {
        guard let capital = capital?.first else { return nil }
        return Country(name: name.common, capital: capital, population: population)
    }
}

// ─── Domain Layer ────────────────────────────────────────
struct Country: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let capital: String
    let population: Int
}
```

`CountryDTO` conforms to `Decodable` because it's a *wire format*. `Country` does **not** — it lives above the framework line, has no idea JSON exists, and can be tested without a network fixture.

See [[iOS SwiftUI Architecture - Data Layer]] and [[iOS SwiftUI Architecture - Domain Layer]].

---

## Anti-Pattern: DTO in the UI Layer

### ❌ Before — SwiftUI view depends on server shape

```swift
struct CountryRow: View {
    let dto: CountryDTO             // view now knows about JSON

    var body: some View {
        HStack {
            Text(dto.name.common)   // reaches into nested DTO
            Spacer()
            Text(dto.capital?.first ?? "—")
        }
    }
}
```

The view breaks the day the backend renames `common` to `commonName`. Tests need JSON fixtures. Previews need fake DTOs shaped exactly like the wire format.

### ✅ After — view depends on the Entity

```swift
struct CountryRow: View {
    let country: Country

    var body: some View {
        HStack {
            Text(country.name)
            Spacer()
            Text(country.capital)
        }
    }
}
```

The DTO stays in the Data Layer. The view is trivially previewable with `Country(name: "Vietnam", capital: "Hanoi", population: 97_000_000)`. Server rename? One `CodingKey` change, no UI touched.

---

## Anti-Pattern: Force-Try on Decoding

### ❌ Before

```swift
let country = try! JSONDecoder().decode(Country.self, from: data)
```

Crashes the app on any malformed payload — including transient server bugs.

### ✅ After

```swift
do {
    let country = try JSONDecoder().decode(Country.self, from: data)
    return .success(country)
} catch let DecodingError.keyNotFound(key, ctx) {
    return .failure(.missingField(key.stringValue, path: ctx.codingPath))
} catch {
    return .failure(.unknown(error))
}
```

`DecodingError` gives you the exact failing key path — invaluable for logs. See [[iOS Swift - Error Handling]].

---

## Summary

| Piece | Role |
|-------|------|
| `Codable` | `Encodable & Decodable` — the both-ways protocol |
| Synthesis | Free `init(from:)` / `encode(to:)` when all properties are Codable |
| `CodingKeys` | Per-property JSON key renaming |
| `keyDecodingStrategy` | Whole-payload transforms (e.g. snake_case → camelCase) |
| `dateDecodingStrategy` | `.iso8601` for APIs; `.formatted` for custom formats |
| `init(from:)` override | Escape hatch when synthesis can't express the shape |
| DTO | Codable, Data Layer, mirrors server |
| Entity | Not Codable, Domain Layer, framework-free |
| `Date.FormatStyle` | Modern user-facing date rendering (iOS 15+) |
| `ISO8601DateFormatter` | Wire-format timestamps |

Golden rule: **`Codable` conformance stops at the Data Layer.**

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Values and Types]] — DTOs and Entities are (almost always) structs
- [[iOS Swift - Optionals]] — modelling absent fields
- [[iOS Swift - Error Handling]] — catching `DecodingError`
- [[iOS Swift - Protocols]] — `Codable` is a protocol composition
- [[iOS SwiftUI Architecture - Data Layer]] — where DTOs live
- [[iOS SwiftUI Architecture - Domain Layer]] — where Entities live

## Apple Docs

- `Codable` reference — https://developer.apple.com/documentation/swift/codable
- Foundation overview — https://developer.apple.com/documentation/foundation
- `JSONDecoder` — https://developer.apple.com/documentation/foundation/jsondecoder
- `JSONEncoder` — https://developer.apple.com/documentation/foundation/jsonencoder
- `Date.FormatStyle` — https://developer.apple.com/documentation/foundation/date/formatstyle
