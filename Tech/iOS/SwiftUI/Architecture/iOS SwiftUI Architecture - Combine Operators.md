---
tags:
  - ios
  - swift
  - combine
  - reactive
  - operators
  - mobile
created: 2026-07-01
source: https://developer.apple.com/documentation/combine
apple_docs:
  - https://developer.apple.com/documentation/combine
  - https://developer.apple.com/documentation/combine/publisher
  - https://developer.apple.com/documentation/combine/receiving-and-handling-events-with-combine
  - https://developer.apple.com/documentation/combine/anycancellable
---

# iOS SwiftUI Architecture - Combine Operators

> The Combine operators you actually reach for in a MVVM ViewModel. Link back to [[iOS SwiftUI Architecture Guide]].

**Load-bearing prerequisites:** [[iOS SwiftUI - Concurrency and Threading]] (schedulers, `.receive(on:)` vs `.subscribe(on:)`, main-thread rule) and [[iOS ARC Guide]] (why `[weak self]` in `.sink`).

---

## Mental Model

Combine = **publishers** emit values over time; **operators** transform them; **subscribers** consume them.

```
Publisher ──▶ Operator ──▶ Operator ──▶ Subscriber
              (map)         (filter)       (sink)
```

Every operator returns a **new Publisher** — chains are lazy; nothing runs until a subscriber attaches.

---

## The Core Operators

### `map` — Synchronous 1:1 Transform

```swift
let doubled = Just(3).map { $0 * 2 }   // Publisher emitting 6
```

Like `Array.map` but on a stream. Preserves the failure type. Use for **DTO → Entity** conversion:

```swift
api.request(.users)                                    // Publisher<[UserDTO], Error>
   .map { (dtos: [UserDTO]) in dtos.map(\.toDomain) }  // Publisher<[User], Error>
```

### `tryMap` — Transform That Can Throw

```swift
.tryMap { data, response in
    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode) else {
        throw DomainError.network
    }
    return data
}
```

Converts a `Never`-failing publisher into an `Error`-failing one. Common at the network boundary.

### `flatMap` — Chain Another Async Operation

```swift
loginUseCase.execute(email, pw)                    // Publisher<Token, Error>
    .flatMap { token in
        userRepository.fetchProfile(token: token)  // Publisher<User, Error>
    }                                              // → Publisher<User, Error>
```

`flatMap` lets you kick off a **new** async operation using the previous result — sequential dependencies.

**Common gotcha:** `flatMap` merges results from multiple inner publishers. If your `query` publisher fires 5 searches, all 5 responses race — the slowest may arrive last and overwrite the newest.

### `switchToLatest` — Cancel-Previous Version of `flatMap`

```swift
$query
    .map { q in searchService.search(q) }   // Publisher of Publishers
    .switchToLatest()                       // ✅ cancel prior in-flight requests
    .assign(to: &$results)
```

**Use `switchToLatest` for search-as-you-type.** Only the latest inner publisher's output is emitted; prior in-flight ones are cancelled.

### `filter` / `removeDuplicates`

```swift
$query
    .filter { $0.count >= 2 }        // ignore short queries
    .removeDuplicates()              // skip repeated identical values
```

### `debounce` / `throttle`

```swift
$query
    .debounce(for: 0.3, scheduler: DispatchQueue.main)  // wait for pause
```

- **`debounce`** — emits only after N seconds of silence. Search-as-you-type.
- **`throttle`** — emits at most once per interval. Rate-limit scroll events.

### `combineLatest` / `zip` / `merge`

```swift
Publishers.CombineLatest($email, $password)
    .map { email, pw in !email.isEmpty && pw.count >= 8 }
    .assign(to: &$isFormValid)
```

| Operator | Emits when | Result |
|----------|-----------|--------|
| `combineLatest` | ANY input emits (after all have emitted once) | Tuple of latest values |
| `zip` | ALL inputs emit a new value (index-matched) | Paired tuples |
| `merge` | ANY input emits | Values interleaved (same type only) |

### `receive(on:)` / `subscribe(on:)`

```swift
useCase.execute()
    .subscribe(on: DispatchQueue.global())   // where upstream work runs
    .receive(on: DispatchQueue.main)         // where downstream (UI) runs
    .assign(to: &$users)
```

- **`subscribe(on:)`** — where the publisher does its work
- **`receive(on:)`** — where operators/subscribers below this line run

For UI: always `.receive(on: DispatchQueue.main)` before `sink`/`assign` to a `@Published`.

### `decode` — JSON → Type

```swift
session.dataTaskPublisher(for: url)
    .map(\.data)
    .decode(type: [UserDTO].self, decoder: JSONDecoder())
```

### `catch` / `replaceError` — Error Recovery

```swift
useCase.execute()
    .catch { _ in Just([User]()) }       // replace failure with a fallback publisher
    .replaceError(with: [])              // shorthand for a single fallback value
    .assign(to: &$users)
```

`replaceError` transforms `Publisher<T, Error>` into `Publisher<T, Never>` — useful before `.assign(to: &$prop)` since `@Published` is `Never`-failing.

### `eraseToAnyPublisher` — Hide the Chain

```swift
func fetchUsers() -> AnyPublisher<[User], Error> {
    api.request(.users)
       .map { $0.map(\.toDomain) }
       .eraseToAnyPublisher()          // ✅ callers see AnyPublisher, not Publishers.Map<Decode<…>>
}
```

Without erasure the return type becomes an unreadable nested generic. Always erase at API boundaries.

---

## Subscribers

### `sink` — Custom Handling

```swift
publisher
    .sink(
        receiveCompletion: { completion in
            if case .failure(let error) = completion { print(error) }
        },
        receiveValue: { value in print(value) }
    )
    .store(in: &cancellables)
```

For `Never`-failing publishers, the single-closure form works:

```swift
$users.sink { print($0) }.store(in: &cancellables)
```

### `assign(to:on:)` vs `assign(to:)`

```swift
// Form 1 — arbitrary target, returns AnyCancellable
publisher.assign(to: \.users, on: viewModel)
         .store(in: &cancellables)

// Form 2 — @Published only, lifetime auto-managed (recommended)
publisher.assign(to: &$users)
```

Form 2 requires the target to be a `@Published` on the **same** ViewModel and does **not** retain `self` — no cycle risk, no cancellable needed. Prefer it.

---

## Publisher Factories

| Factory | Purpose |
|---------|---------|
| `Just(value)` | Emits one value, then completes. `Never` failure. |
| `Empty(completeImmediately: true)` | Emits nothing, completes. |
| `Fail(error:)` | Emits a failure immediately. |
| `Future { promise in … }` | Bridge callback API into Combine. Emits once. |
| `PassthroughSubject<T, Error>` | Send values imperatively (`.send(x)`). |
| `CurrentValueSubject<T, Error>` | Like `Passthrough` but holds a current value (queryable via `.value`). |

**Bridging a callback:**

```swift
func loadFile() -> AnyPublisher<Data, Error> {
    Future { promise in
        oldStyleLoader { result in
            switch result {
            case .success(let d): promise(.success(d))
            case .failure(let e): promise(.failure(e))
            }
        }
    }
    .eraseToAnyPublisher()
}
```

**Note:** `Future` executes its closure **immediately on creation**, not on subscription. If you need lazy execution, wrap in `Deferred { Future { … } }`.

---

## When To Reach For What

| Task | Operator |
|------|----------|
| DTO → Entity mapping | `map` |
| Validate HTTP response | `tryMap` |
| Sequential async (login → fetch profile) | `flatMap` |
| Cancel prior in-flight (search) | `map` → `switchToLatest` |
| Wait for input to settle | `debounce` |
| Rate-limit high-frequency events | `throttle` |
| Skip identical repeats | `removeDuplicates` |
| Combine multiple state sources | `combineLatest` |
| Hop threads | `receive(on:)` |
| Silence errors | `catch` / `replaceError` |
| Bind to `@Published` cleanly | `assign(to: &$prop)` |
| Hide chain from callers | `eraseToAnyPublisher` |

---

## Combine vs `async/await` — Quick Take

| | Combine | async/await |
|---|---------|-------------|
| First-class SwiftUI binding | ✅ `@Published` | ⚠️ `Task { … self.x = … }` |
| Cancellation | Manual (`cancellables`) | Structured (`Task` cancellation) |
| Reactive streams (search, debounce) | ✅ built-in | ❌ need `AsyncSequence` / manual |
| One-shot requests | Works | ✅ cleaner |
| Debuggability | Long stack traces | ✅ readable |

**Practical mix:** many teams now use `async/await` in Data + Domain and expose `AnyPublisher` at ViewModel boundaries (or vice versa — bridge with `Publisher.values` and `Future`).

---

## Summary

| ✅ Do | ❌ Don't |
|------|---------|
| `eraseToAnyPublisher()` at API boundaries | Return `Publishers.Map<Decode<…>>` |
| `switchToLatest` for search-as-you-type | `flatMap` (races) |
| `receive(on: .main)` before UI writes | Publish to `@Published` from background |
| `assign(to: &$prop)` for own state | `.assign(to: \.x, on: self)` (leak risk) |
| `[weak self]` in `sink` closures | Strong `self` in stored subscriptions |

---

## Apple Docs (Primary References)

- Combine framework overview: https://developer.apple.com/documentation/combine
- `Publisher` protocol: https://developer.apple.com/documentation/combine/publisher
- `Publishers` namespace (operator implementations): https://developer.apple.com/documentation/combine/publishers
- `AnyCancellable`: https://developer.apple.com/documentation/combine/anycancellable
- `URLSession.DataTaskPublisher`: https://developer.apple.com/documentation/foundation/urlsession/datataskpublisher
- Tutorial — Receiving and Handling Events with Combine: https://developer.apple.com/documentation/combine/receiving-and-handling-events-with-combine

> Apple: "An `AnyCancellable` instance automatically calls `cancel()` when deinitialized." — matches the ["Cancellable bag" pattern](#the-cancellable-bag) above.

---

## Related

- [[iOS SwiftUI Architecture - MVVM with Combine]] — how these operators sit inside a ViewModel
- [[iOS SwiftUI Architecture - Data Layer]] — network chains using `tryMap` / `decode` / `map`
