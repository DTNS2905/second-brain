---
tags:
  - ios
  - swiftui
  - clean-architecture
  - error-handling
  - combine
  - mobile
created: 2026-07-10
source: https://developer.apple.com/documentation/swift/errorhandling
---

# iOS SwiftUI Architecture - Error Handling

> How errors propagate — and get translated — across Data → Domain → Presentation → View. Link back to [[iOS SwiftUI Architecture Guide]].

**Load-bearing prerequisites:** [[iOS Swift - Error Handling]] (`throws`, `try`, `Result`, `Error` protocol) and [[iOS SwiftUI Architecture - Combine Operators]] (`mapError`, `catch`, `retry`).

---

## Definitions

| Term | Meaning |
|------|---------|
| **`Error`** | An empty Swift protocol. Anything conforming to it can be thrown. Almost always an `enum`. |
| **`throws` / `try`** | A function marked `throws` may fail. Callers must prefix a call with `try` (or `try?` / `try!`). |
| **`Result<Success, Failure>`** | An enum with `.success(value)` and `.failure(error)` cases — represents a completed operation. |
| **`URLError`** | Foundation's error type for `URLSession` failures (no internet, timeout, cancelled, bad URL, …). |
| **`DecodingError`** | `JSONDecoder` / `PropertyListDecoder` failure — key not found, type mismatch, corrupted data. |
| **`LocalizedError`** | Protocol that adds `errorDescription`, `failureReason`, `recoverySuggestion` — feeds `Alert` and `Text` naturally. |
| **Data-layer error** | Errors about *how the data got here*: network, decoding, disk. |
| **Domain-layer error** | Errors about *business rules*: not found, unauthorized, quota exceeded. |
| **Error mapping** | Translating a lower-layer error into a higher-layer one at the boundary — so nothing leaks upward. |
| **`.mapError`** | Combine operator that transforms the failure type of a publisher. |
| **`.catch`** | Combine operator that replaces a failing publisher with another publisher (recovery). |
| **`.retry(n)`** | Combine operator that resubscribes up to N times on failure. |
| **`.replaceError(with:)`** | Combine operator that swaps a failure for a fallback value and turns the failure type to `Never`. |

---

## The Problem

Different subsystems throw completely different error types:

```
URLSession           →  URLError            (transport)
JSONDecoder          →  DecodingError       (shape mismatch)
Server               →  HTTP 4xx / 5xx      (semantic)
SwiftData / Disk     →  CocoaError / NSError
Business rule        →  ??? (yours)
```

A View can't render five unrelated error types with useful messages. **Each layer defines its own error type; boundaries translate.**

```
┌───────────┐   DataError   ┌────────────┐   DomainError   ┌──────────────┐   String
│   Data    │──────────────▶│   Domain   │────────────────▶│  Presentation │──────▶ View
└───────────┘  (Repository) └────────────┘   (ViewModel)   └──────────────┘
```

See [[iOS SwiftUI Architecture - Clean Architecture]] for the layer definitions.

---

## Data Layer Errors

Everything the outside world can do to you: network, decoding, HTTP status codes.

```swift
enum DataError: Error {
    case network(URLError)
    case decoding(DecodingError)
    case server(statusCode: Int)
    case unknown(Error)
}
```

Produced inside `APIService`:

```swift
func request<T: Decodable>(_ endpoint: Endpoint) -> AnyPublisher<T, DataError> {
    session.dataTaskPublisher(for: req)
        .mapError { DataError.network($0) }
        .tryMap { data, response in
            guard let http = response as? HTTPURLResponse else {
                throw DataError.server(statusCode: -1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw DataError.server(statusCode: http.statusCode)
            }
            return data
        }
        .decode(type: T.self, decoder: decoder)
        .mapError { err in
            if let d = err as? DataError { return d }
            if let d = err as? DecodingError { return .decoding(d) }
            return .unknown(err)
        }
        .eraseToAnyPublisher()
}
```

See [[iOS SwiftUI Architecture - Data Layer]] for the full network stack.

---

## Domain Layer Errors

Business-rule failures — vocabulary the *feature* cares about, not HTTP.

```swift
enum UserError: Error {
    case notFound
    case unauthorized
    case emailAlreadyTaken
    case weakPassword
    case offline
    case unknown
}
```

The Domain layer defines its own `Error` enum per bounded concept (`UserError`, `PaymentError`, `SyncError`). Views should only ever see these.

---

## Mapping — the Boundary Job

**The Repository translates `DataError` → `DomainError`.** This is the whole point of the Repository pattern for error handling.

```swift
final class UserRepositoryImpl: UserRepository {
    private let api: APIService

    func fetchUser(id: Int) -> AnyPublisher<User, UserError> {
        api.request(.userById(id))
            .map(\.toDomain)
            .mapError { dataError -> UserError in
                switch dataError {
                case .server(statusCode: 404):          return .notFound
                case .server(statusCode: 401):          return .unauthorized
                case .network(let u) where u.code == .notConnectedToInternet:
                    return .offline
                default:                                return .unknown
                }
            }
            .eraseToAnyPublisher()
    }
}
```

**Rules:**
- The UseCase / ViewModel never imports `URLError` or `DecodingError`.
- Every `Repository` returns a Domain-typed error.
- If new HTTP codes matter, extend the mapping — not the ViewModel.

---

## Presentation Errors — Human-Readable

The ViewModel converts a Domain error into a display string. Prefer `LocalizedError` so the same enum feeds both `Alert` and inline `Text`.

```swift
extension UserError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound:          return "We couldn't find that user."
        case .unauthorized:      return "Please sign in again."
        case .emailAlreadyTaken: return "That email is already registered."
        case .weakPassword:      return "Password must be at least 8 characters."
        case .offline:           return "You're offline. Check your connection."
        case .unknown:           return "Something went wrong. Please try again."
        }
    }
}
```

Now:

```swift
Text(error.localizedDescription)   // uses errorDescription
```

---

## Combine Publisher Error Handling

### `.mapError` — translate

```swift
publisher
    .mapError { DomainError.from($0) }
```

Turns `Publisher<T, DataError>` into `Publisher<T, DomainError>`. Used at every layer boundary.

### `.catch` — recover with another publisher

```swift
primaryAPI.fetch()
    .catch { _ in fallbackAPI.fetch() }
```

The failing chain gets replaced with a fresh publisher. Use for fallback endpoints, cache-then-network, mock data.

### `.retry(n)` — resubscribe on failure

```swift
api.request(.users)
    .retry(2)          // total attempts = 3
```

**Only retry idempotent operations** — a `GET` is fine, a `POST /purchase` is not. Pair with `catch` to give up gracefully after the last retry.

### `.replaceError(with:)` — swallow to a fallback value

```swift
useCase.execute()
    .replaceError(with: [])           // Publisher<[User], Never>
    .assign(to: &$users)
```

Changes the failure type to `Never` so it binds cleanly to `@Published`. **The error is lost** — only use for genuinely optional data (e.g., a recommendations strip that can just be empty).

### When to use which

| You want to… | Operator |
|--------------|----------|
| Change the error type at a layer boundary | `.mapError` |
| Fall back to a different publisher | `.catch` |
| Try again on transient failure | `.retry(n)` |
| Give up and show empty state | `.replaceError(with:)` |
| Handle failure in the subscriber | `sink(receiveCompletion:)` |

See [[iOS SwiftUI Architecture - Combine Operators]] for the operator catalogue.

---

## `async/await` Error Handling

Same taxonomy — different syntax.

```swift
func fetchUser(id: Int) async throws -> User {
    do {
        let dto: UserDTO = try await api.request(.userById(id))
        return dto.toDomain
    } catch let e as DataError {
        throw UserError.from(e)          // ✅ translate at the boundary
    }
}
```

### `Result` for concurrent chains

`async let` gives you structured concurrency but any failure cancels siblings. Use `Result` when you want each branch to succeed or fail independently:

```swift
async let profile = Result { try await userRepo.fetchProfile() }
async let posts   = Result { try await postRepo.fetchRecent() }
async let friends = Result { try await socialRepo.fetchFriends() }

let (p, po, f) = await (profile, posts, friends)
// Each is Result<T, Error> — inspect individually
```

### `try?` vs `try!` vs `do/catch`

| Form | Behavior | When |
|------|----------|------|
| `try` | Propagates | You handle it further up |
| `try?` | Failure → `nil` | You genuinely don't care why |
| `try!` | Failure → crash | Only for invariants you've proven |
| `do/catch` | Explicit branches | Multiple error kinds to translate |

---

## Loading State Pattern

A single enum drives the entire View — no separate `isLoading`, `error`, `items` booleans that can lie to each other.

```swift
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(Error)
}
```

ViewModel:

```swift
@MainActor
final class UserListViewModel: ObservableObject {
    @Published var state: LoadState<[User]> = .idle
    private let useCase: FetchUsersUseCase
    private var bag = Set<AnyCancellable>()

    func load() {
        state = .loading
        useCase.execute()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] c in
                    if case .failure(let e) = c { self?.state = .failed(e) }
                },
                receiveValue: { [weak self] users in self?.state = .loaded(users) }
            )
            .store(in: &bag)
    }
}
```

View:

```swift
struct UserListView: View {
    @StateObject var vm: UserListViewModel

    var body: some View {
        switch vm.state {
        case .idle:            Color.clear.onAppear { vm.load() }
        case .loading:         ProgressView()
        case .loaded(let us):  List(us) { Text($0.name) }
        case .failed(let e):   ErrorView(error: e, retry: vm.load)
        }
    }
}
```

**Why this is better than three booleans:** the compiler proves you can't be `loading` and `loaded` at the same time.

---

## User-Facing Patterns

### Inline error

```swift
if case .failed(let e) = vm.state {
    Text(e.localizedDescription).foregroundStyle(.red)
}
```

### Alert

```swift
.alert("Couldn't load",
       isPresented: $vm.showError,
       presenting: vm.currentError) { _ in
    Button("Retry") { vm.load() }
    Button("Cancel", role: .cancel) {}
} message: { error in
    Text(error.localizedDescription)
}
```

### Retry button + empty state

```swift
struct ErrorView: View {
    let error: Error
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
        }
    }
}
```

---

## Layer Boundary Discussion

| Layer | Owns errors of type | Never sees | Emits |
|-------|--------------------|-----------|-------|
| **Data** | `DataError` (network / decoding / status) | Business rules | `DataError` upward |
| **Domain (Repository)** | Translation | `URLError`, `DecodingError` beyond this point | `DomainError` upward |
| **Domain (UseCase)** | `DomainError` | HTTP details | `DomainError` upward |
| **Presentation (ViewModel)** | Turns `DomainError` into `LoadState.failed` | Anything below `DomainError` | `LocalizedError` string |
| **View** | Display only | `Error` construction | Renders `errorDescription` |

**The invariant:** a `URLError` should be impossible to observe from a `View`. If you can `if let e = err as? URLError { ... }` in a View, your architecture has a leak.

---

## Anti-Patterns

### ❌ Swallowing errors with `try?`

```swift
// ❌ Silent failure — the list is just empty and nobody knows why
let users = (try? await repo.fetchUsers()) ?? []
```

```swift
// ✅ Preserve failure in state
do {
    self.state = .loaded(try await repo.fetchUsers())
} catch {
    self.state = .failed(error)
}
```

### ❌ Leaking `URLError` to Views

```swift
// ❌ View pattern-matches on Foundation types
if let u = error as? URLError, u.code == .notConnectedToInternet {
    Text("Offline")
}
```

```swift
// ✅ View pattern-matches on Domain vocabulary
if case .offline = error {
    Text("Offline")
}
```

### ❌ String-based errors

```swift
// ❌ Not exhaustive-switchable, not testable, not localizable
throw NSError(domain: "app", code: 0,
              userInfo: [NSLocalizedDescriptionKey: "User not found"])
```

```swift
// ✅ Typed enum — compiler-checked, localizable via LocalizedError
throw UserError.notFound
```

### ❌ `catch { print(error) }` in production

```swift
// ❌ Silently ignores + no UI feedback + no telemetry
do { try await repo.save() } catch { print(error) }
```

```swift
// ✅ Update state, log to telemetry, let View react
do {
    try await repo.save()
} catch {
    logger.error("save failed: \(error)")
    self.state = .failed(error)
}
```

### ❌ Retrying non-idempotent operations

```swift
// ❌ Charges the customer three times on a flaky network
purchaseAPI.charge(cart).retry(3)
```

```swift
// ✅ Use idempotency keys, or surface the error and let the user retry deliberately
purchaseAPI.charge(cart, idempotencyKey: id)
```

### ❌ Global `try!`

```swift
// ❌ Crashes the app whenever the server has a hiccup
let users = try! await repo.fetchUsers()
```

Reserve `try!` for invariants (e.g., a regex literal you've tested at build time).

---

## Summary

| ✅ Do | ❌ Don't |
|------|---------|
| Define a typed `Error` enum per layer | Throw `NSError` / string errors |
| `mapError` at every layer boundary | Let `URLError` reach a View |
| Conform Domain errors to `LocalizedError` | Duplicate error strings across Views |
| Use `LoadState<T>` for View state | Juggle `isLoading` + `error` + `data` bools |
| `retry` only idempotent GETs | Retry `POST /charge` |
| `replaceError(with:)` only when data is truly optional | Silently drop errors on load-critical calls |
| Log failures to a real logger | `print(error)` in production |

---

## Apple Docs (Primary References)

- Error handling (Swift language guide): https://developer.apple.com/documentation/swift/errorhandling
- `Error` protocol: https://developer.apple.com/documentation/swift/error
- `LocalizedError`: https://developer.apple.com/documentation/foundation/localizederror
- `URLError`: https://developer.apple.com/documentation/foundation/urlerror
- `JSONDecoder` (throws `DecodingError`): https://developer.apple.com/documentation/foundation/jsondecoder
- Combine `mapError`: https://developer.apple.com/documentation/combine/publisher/maperror(_:)
- Combine `catch`: https://developer.apple.com/documentation/combine/publisher/catch(_:)
- Combine `retry`: https://developer.apple.com/documentation/combine/publisher/retry(_:)

---

## Related

- [[iOS SwiftUI Architecture Guide]] — parent index
- [[iOS SwiftUI Architecture - Clean Architecture]] — the layer boundaries this note enforces
- [[iOS SwiftUI Architecture - Data Layer]] — where `DataError` is produced
- [[iOS SwiftUI Architecture - Domain Layer]] — where `DomainError` lives
- [[iOS SwiftUI Architecture - Presentation Layer]] — `LoadState` in the ViewModel
- [[iOS SwiftUI Architecture - MVVM with Combine]] — publisher chains in the ViewModel
- [[iOS SwiftUI Architecture - Combine Operators]] — `mapError`, `catch`, `retry`, `replaceError`
- [[iOS Swift - Error Handling]] — language-level `throws` / `try` / `Result`
- [[iOS Swift - Codable & Foundation]] — where `DecodingError` comes from
