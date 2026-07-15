---
tags:
  - ios
  - swift
  - fundamentals
  - error-handling
  - mobile
created: 2026-07-10
source: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/
apple_docs:
  - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/
  - https://developer.apple.com/documentation/swift/error
  - https://developer.apple.com/documentation/foundation/localizederror
  - https://developer.apple.com/documentation/swift/result
---

# iOS Swift - Error Handling

> Swift's compile-checked way of saying "this might fail — here's why." The other half of failure handling next to [[iOS Swift - Optionals]]. Back to [[iOS Swift Fundamentals Guide]].

---

## Definitions

- **Error** — Swift's built-in marker protocol. Any type conforming to `Error` can be thrown. Almost always an `enum` with one case per failure reason.
- **`throws`** — a keyword on a function signature meaning "this call can exit by throwing an error instead of returning."
- **`try`** — required at every call site of a throwing function. Marks that "control flow may leave here."
- **`try?`** — call the throwing function and turn any error into `nil`. Return type becomes `Optional`.
- **`try!`** — call the throwing function and crash if it throws. The `!` sibling of force-unwrap.
- **`do` / `catch`** — Swift's version of `try / catch` from other languages. `do` opens a scope where errors can bubble; `catch` handles them.
- **`rethrows`** — a function that only throws if its closure argument throws. See [[iOS Swift - Closures]].
- **`Result<Success, Failure>`** — a two-case enum (`.success(Success)` / `.failure(Failure)`) that carries either a value or an error as a value. Useful for storing or passing errors around instead of raising them.
- **`LocalizedError`** — a Foundation protocol that adds user-facing message properties (`errorDescription`, `failureReason`, `recoverySuggestion`) on top of `Error`.
- **Typed throws** — Swift 6+ feature: `func foo() throws(MyError)` restricts what error type a function can throw. Untyped `throws` (Swift 5 and earlier default) means "any `Error`."

---

## Declaring an Error

An `enum` conforming to `Error` is the canonical shape. Each case is a named failure reason; associated values carry context.

```swift
enum NetworkError: Error {
    case invalidURL
    case noInternet
    case decoding(underlying: Error)
    case httpStatus(code: Int)
}
```

Prefer this over `NSError`, string errors, or booleans. The compiler forces callers to handle every case in an exhaustive `switch`, and IDE autocomplete lists the failure modes.

---

## Throwing a Function

Add `throws` after the parameter list, before the return arrow. Inside the body, use `throw` to raise.

```swift
func fetchCountry(code: String) throws -> Country {
    guard let url = URL(string: "https://api/\(code)") else {
        throw NetworkError.invalidURL
    }
    guard Reachability.isOnline else {
        throw NetworkError.noInternet
    }
    return try decodeCountry(from: url)
}
```

The `throws` marker is part of the function's type — it propagates upward. Any caller of `fetchCountry` must also use `try`.

---

## Calling: The Three `try` Forms

### `try` inside `do / catch` — full handling

```swift
do {
    let country = try fetchCountry(code: "VN")
    print(country.name)
} catch NetworkError.noInternet {
    showBanner("You're offline")
} catch NetworkError.httpStatus(let code) where code >= 500 {
    showBanner("Server error \(code)")
} catch let error as NetworkError {
    showBanner("Network problem: \(error)")
} catch {
    showBanner("Unexpected: \(error)")
}
```

`catch` patterns work like `switch` cases: bind associated values, add `where` clauses, cast with `as`, and fall through to a bare `catch` at the end.

### `try?` — turn the error into `nil`

```swift
let country = try? fetchCountry(code: "VN")   // Country? — nil if it threw
```

The error's *reason* is discarded. Use only when the caller doesn't care why it failed, only whether it did.

### `try!` — crash if it throws

```swift
let bundleData = try! Data(contentsOf: bundledJSONURL)
```

Runtime crash on any thrown error. Same discipline as force-unwrapping: acceptable only for compile-time-known inputs (files shipped in the app bundle, hard-coded URLs). Never on server data or user input.

---

## Rethrowing With `rethrows`

A function is `rethrows` when it *only* throws by way of a closure argument. Callers who pass a non-throwing closure don't need `try`.

```swift
func transform<T>(_ items: [T], with fn: (T) throws -> T) rethrows -> [T] {
    var result: [T] = []
    for item in items {
        result.append(try fn(item))
    }
    return result
}

let doubled = transform([1, 2, 3]) { $0 * 2 }         // no try needed
let parsed  = try transform(["1", "2"]) { s throws in
    guard let n = Int(s) else { throw ParseError.badInt }
    return n
}
```

You'll see this on standard-library higher-order functions like `map`, `filter`, `reduce`. See [[iOS Swift - Closures]].

---

## `Result<Success, Failure>` — Errors as Values

`throws` is *control flow* — the error jumps up the call stack. `Result` is *data* — the error sits inside a value you can store, pass around, and inspect later.

```swift
enum Result<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
}
```

### When to prefer `Result` over `throws`

- **Async callbacks (pre-`async/await`)** — `(Result<T, E>) -> Void`. Legacy but still common in third-party SDKs.
- **Storing a pending outcome** — a cached response you'll read later.
- **Sending failure across a boundary** — publisher output, actor return value.
- **Multiple returns where each may fail independently** — batch operations returning `[Result<T, E>]`.

For synchronous code inside a Clean Architecture use case, prefer plain `throws` — it's shorter and integrates with `do / catch`.

### Interop with `throws`

```swift
let result = Result { try fetchCountry(code: "VN") }   // Result<Country, Error>
let country = try result.get()                          // Throws again
```

---

## `LocalizedError` — User-Facing Messages

`Error.localizedDescription` on a plain enum returns something like `"The operation couldn't be completed. (AppName.NetworkError error 1.)"` — useless in UI. Conform to `LocalizedError` to control it.

```swift
enum NetworkError: LocalizedError {
    case noInternet
    case httpStatus(code: Int)

    var errorDescription: String? {
        switch self {
        case .noInternet:
            return "You appear to be offline."
        case .httpStatus(let code):
            return "Server returned \(code)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noInternet: return "Check your Wi-Fi and try again."
        case .httpStatus: return "Please try again in a moment."
        }
    }
}
```

Rule of thumb: any error that reaches the UI layer should conform to `LocalizedError`.

---

## `throws` vs `async throws`

An `async throws` function is asynchronous *and* can fail. Callers use `try await`.

```swift
func fetchCountry(code: String) async throws -> Country { ... }

let country = try await fetchCountry(code: "VN")
```

The `try` and `await` order is fixed. Concurrency details live in a future concurrency note.

---

## Typed `throws` (Swift 6+)

Since Swift 6, you can declare *which* error a function throws:

```swift
func fetchCountry(code: String) throws(NetworkError) -> Country { ... }

do {
    let country = try fetchCountry(code: "VN")
} catch {
    // error is inferred as NetworkError, not Error
    print(error.httpStatus)
}
```

Benefits: exhaustive `catch` (no need for a trailing `catch {}`), better documentation. Use in library APIs where the error surface is small and fixed. For app code that already funnels many error types into one, plain `throws` is still fine.

---

## Bridging Combine Errors

Combine publishers have a typed `Failure`. Two operators are the workhorses for error work — see [[iOS SwiftUI Architecture - Combine Operators]].

### `mapError` — change the error type

```swift
URLSession.shared.dataTaskPublisher(for: url)
    .mapError { urlError in
        NetworkError.transport(urlError)
    }
```

`URLSession.DataTaskPublisher.Failure` is `URLError` — `mapError` lifts it into your domain `NetworkError` so downstream operators see a single type.

### `tryMap` — throw inside a map

```swift
URLSession.shared.dataTaskPublisher(for: url)
    .tryMap { data, response in
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.httpStatus(code: -1)
        }
        return data
    }
    .mapError { $0 as? NetworkError ?? .unknown }
```

`tryMap` widens the publisher's `Failure` to plain `Error`. Follow it with `mapError` to narrow back to your domain error.

---

## Anti-Patterns

### Overusing `try!`

```swift
// ❌ Crashes the app on any network hiccup
let country = try! fetchCountry(code: "VN")

// ✅ Handle it or propagate
do {
    let country = try fetchCountry(code: "VN")
} catch {
    showBanner(error.localizedDescription)
}
```

### Swallowing errors

```swift
// ❌ You lose all information about what went wrong
do {
    try saveOrder(order)
} catch {
    // silent
}

// ✅ At minimum log; ideally surface to the user
do {
    try saveOrder(order)
} catch {
    Logger.error("saveOrder failed: \(error)")
    showBanner(error.localizedDescription)
}
```

### Strings as error types

```swift
// ❌ No type safety, no exhaustiveness, no localization hook
throw "URL was invalid"

// ✅ Named cases with structure
enum NetworkError: Error {
    case invalidURL
}
throw NetworkError.invalidURL
```

### Using `try?` to hide bugs

```swift
// ❌ You'll never know the JSON changed shape
let country = try? JSONDecoder().decode(Country.self, from: data)

// ✅ Handle decoding errors explicitly during development
do {
    let country = try JSONDecoder().decode(Country.self, from: data)
} catch let DecodingError.keyNotFound(key, _) {
    Logger.error("Missing key: \(key.stringValue)")
    throw NetworkError.decoding(underlying: error)
} catch {
    throw NetworkError.decoding(underlying: error)
}
```

---

## Errors Through the Clean Architecture Layers

In Clean Architecture, each layer owns its own error type and translates at the boundary. See [[iOS SwiftUI Architecture - Data Layer]] and [[iOS SwiftUI Architecture - MVVM with Combine]].

```
Data Layer          Domain Layer          Presentation Layer
DataError    -->    DomainError    -->    presented via LocalizedError
(URLError,          (business-             (Alert / banner /
 DecodingError)      readable failure)      inline field error)
```

```swift
// Data layer — raw failures
enum DataError: Error {
    case network(URLError)
    case decoding(DecodingError)
}

// Domain layer — business-readable failures
enum DomainError: LocalizedError {
    case countryNotFound
    case offline
    case unknown

    var errorDescription: String? {
        switch self {
        case .countryNotFound: return "We couldn't find that country."
        case .offline:         return "You appear to be offline."
        case .unknown:         return "Something went wrong."
        }
    }
}

// Repository translates at the boundary
final class CountryRepository {
    func country(code: String) async throws(DomainError) -> Country {
        do {
            return try await api.fetchCountry(code: code)
        } catch DataError.network(let urlError) where urlError.code == .notConnectedToInternet {
            throw .offline
        } catch DataError.network {
            throw .unknown
        } catch DataError.decoding {
            throw .unknown
        }
    }
}
```

The ViewModel only ever sees `DomainError`. That keeps `URLError` and `DecodingError` from leaking into the UI, and it means changing your networking library never touches the ViewModel.

---

## Summary

| Tool | Use when |
|------|----------|
| `enum ...: Error` | Modeling a small, fixed set of failure reasons |
| `throws` | Synchronous or `async throws` code that may fail with a *reason* |
| `try` in `do / catch` | You want to handle specific failures |
| `try?` | Caller doesn't care why it failed — treat as optional |
| `try!` | Compile-time-known inputs (bundled files, hard-coded URLs) |
| `rethrows` | Higher-order functions that only throw via their closure |
| `Result` | Errors need to be stored, passed as data, or crossed over callbacks |
| `LocalizedError` | Any error that could reach the UI |
| Typed throws | Library APIs on Swift 6+ with a small fixed error surface |
| `mapError` / `tryMap` | Reshaping errors inside a Combine pipeline |

Golden rule: **fail with a reason at the boundary, translate to domain errors before the UI sees them.**

---

## Related

- [[iOS Swift Fundamentals Guide]] — the index
- [[iOS Swift - Optionals]] — the "no result" alternative to "failed with a reason"
- [[iOS Swift - Closures]] — how `rethrows` propagates from closure arguments
- [[iOS Swift - Protocols]] — `Error` and `LocalizedError` are protocols
- [[iOS SwiftUI Architecture - Data Layer]] — where errors originate and get translated
- [[iOS SwiftUI Architecture - MVVM with Combine]] — how ViewModels expose errors to the UI
- [[iOS SwiftUI Architecture - Combine Operators]] — `mapError` and `tryMap` in publishers

## Apple Docs

- Error Handling — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/
- `Error` protocol — https://developer.apple.com/documentation/swift/error
- `LocalizedError` — https://developer.apple.com/documentation/foundation/localizederror
- `Result` — https://developer.apple.com/documentation/swift/result
