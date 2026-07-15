---
tags:
  - ios
  - swift
  - clean-architecture
  - data-layer
  - networking
  - combine
  - mobile
created: 2026-07-01
source: https://medium.com/@islammoussa.eg/swiftui-and-combine-building-a-solid-network-layer-for-handling-api-requests-5ccce878212a
---

# iOS SwiftUI Architecture - Data Layer

> Implements Domain protocols. Handles network, persistence, DTO mapping. Link back to [[iOS SwiftUI Architecture Guide]].

---

## What Lives Here

| Component | Role |
|-----------|------|
| **DTO** | `Codable` struct matching the wire/DB format 1:1 |
| **Mapper** | `dto.toDomain()` — DTO → Entity conversion |
| **APIService** | Generic network client returning `AnyPublisher<T, Error>` |
| **Endpoint** | Enum or struct describing URL, method, headers, body |
| **RepositoryImpl** | Conforms to `UserRepository` (from Domain), orchestrates API + persistence |

---

## DTOs — Isolate the Wire Format

Server changes a field name? Only the DTO and mapper change; Domain stays intact.

```swift
// Data/DTOs/UserDTO.swift
struct UserDTO: Codable {
    let id: Int
    let full_name: String        // snake_case from server
    let email_address: String
    let role: String
}

extension UserDTO {
    var toDomain: User {
        User(
            id: id,
            name: full_name,
            email: email_address,
            role: Role(rawValue: role) ?? .guest    // safe fallback
        )
    }
}
```

**Rule:** DTOs never leak past the Data layer. UseCases and ViewModels only see Entities.

---

## Endpoint Definition

```swift
enum HTTPMethod: String {
    case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]
    let body: Data?

    static func users() -> Endpoint {
        Endpoint(path: "/users", method: .get, queryItems: [], body: nil)
    }
}
```

---

## Combine-based APIService

Generic `request<T: Decodable>` returning a typed publisher:

```swift
final class APIService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared, baseURL: URL) {
        self.session = session
        self.baseURL = baseURL
    }

    func request<T: Decodable>(_ endpoint: Endpoint) -> AnyPublisher<T, Error> {
        var url = baseURL.appendingPathComponent(endpoint.path)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems
        url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        req.httpBody = endpoint.body

        return session.dataTaskPublisher(for: req)
            .tryMap { data, response in
                guard let http = response as? HTTPURLResponse else {
                    throw DomainError.network
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw http.statusCode == 401 ? DomainError.unauthorized : DomainError.network
                }
                return data
            }
            .decode(type: T.self, decoder: decoder)
            .eraseToAnyPublisher()
    }
}
```

**Key operators used:**

| Operator | Role |
|----------|------|
| `dataTaskPublisher(for:)` | Wraps `URLSession` as a Publisher |
| `tryMap` | Validate status code, throw Domain errors on failure |
| `decode(type:decoder:)` | JSON → `Decodable` type (DTO) |
| `eraseToAnyPublisher` | Hide concrete publisher chain — clean return type |

See [[iOS SwiftUI Architecture - Combine Operators]] for a full operator reference.

---

## Repository Implementation

```swift
// Data/Repositories/UserRepositoryImpl.swift
final class UserRepositoryImpl: UserRepository {
    private let api: APIService

    init(api: APIService) { self.api = api }

    func fetchUsers() -> AnyPublisher<[User], Error> {
        api.request(.users())                                    // AnyPublisher<[UserDTO], Error>
            .map { (dtos: [UserDTO]) in dtos.map(\.toDomain) }   // → [User]
            .eraseToAnyPublisher()
    }

    func fetchUser(id: Int) -> AnyPublisher<User, Error> {
        api.request(.userById(id))
            .map(\.toDomain)                                     // (UserDTO) -> User
            .eraseToAnyPublisher()
    }

    func register(email: String, password: String) -> AnyPublisher<User, Error> {
        let body = try? JSONEncoder().encode(RegisterDTO(email: email, password: password))
        return api.request(.register(body: body))
            .map(\.toDomain)
            .eraseToAnyPublisher()
    }
}
```

---

## Caching Pattern (Repository as Cache Coordinator)

The Repository is the natural place for "check cache, else fetch, then save":

```swift
final class UserRepositoryImpl: UserRepository {
    private let api: APIService
    private let cache: UserCache

    func fetchUsers() -> AnyPublisher<[User], Error> {
        let cached = cache.load()
        if !cached.isEmpty {
            return Just(cached).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return api.request(.users())
            .map { (dtos: [UserDTO]) in dtos.map(\.toDomain) }
            .handleEvents(receiveOutput: { [cache] in cache.save($0) })
            .eraseToAnyPublisher()
    }
}
```

**Why this belongs in Data, not Domain:** the UseCase should not care whether data came from network or disk. It just gets `[User]`.

---

## Anti-Patterns

### ❌ Codable directly on Domain Entity

```swift
// ❌ Now Domain knows about JSON shape
struct User: Codable, Identifiable {
    let id: Int
    let full_name: String   // ugly wire naming leaks into business layer
}
```

```swift
// ✅ DTO in Data, Entity in Domain
struct UserDTO: Codable { let id: Int; let full_name: String }
struct User: Identifiable { let id: Int; let name: String }
```

### ❌ ViewModel decoding JSON

```swift
// ❌ Presentation now depends on JSON structure
final class UserListViewModel: ObservableObject {
    func load() {
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: [UserDTO].self, decoder: JSONDecoder())
            ...
    }
}
```

`URLSession` and `UserDTO` are Data-layer details. ViewModel should call a Use Case.

### ❌ Leaking `URLError` to Views

```swift
// ❌ View shows "The Internet connection appears to be offline. (URLError -1009)"
```

Map at the boundary:

```swift
// ✅ APIService.tryMap { ... throw DomainError.network }
// View shows: "Can't connect. Check your internet."
```

---

## Summary

| ✅ Do                                           | ❌ Don't                               |
| ---------------------------------------------- | ------------------------------------- |
| One `RepositoryImpl` per Domain protocol       | One giant `DataManager` singleton     |
| DTO ↔ Entity mapping in Data                   | `Codable` on Domain Entities          |
| Map `URLError`/`DecodingError` → `DomainError` | Rethrow low-level errors upward       |
| Inject `APIService` via constructor            | `APIService.shared` inside Repository |
| Repository decides cache-vs-network            | Cache logic in ViewModel              |

---

## Apple Docs (Primary References)

- `URLSession`: https://developer.apple.com/documentation/foundation/urlsession
- `URLSession.DataTaskPublisher`: https://developer.apple.com/documentation/foundation/urlsession/datataskpublisher
- `JSONDecoder`: https://developer.apple.com/documentation/foundation/jsondecoder
- `Codable`: https://developer.apple.com/documentation/swift/codable
- Combine `tryMap`: https://developer.apple.com/documentation/combine/publisher/trymap(_:)
- Combine `decode`: https://developer.apple.com/documentation/combine/publisher/decode(type:decoder:)

---

## Related

- [[iOS SwiftUI Architecture - Domain Layer]] — the protocols implemented here
- [[iOS SwiftUI Architecture - Combine Operators]] — `map`, `tryMap`, `flatMap`, `decode`
- [[iOS SwiftUI Architecture - Dependency Injection]] — wiring `APIService` into `RepositoryImpl`
