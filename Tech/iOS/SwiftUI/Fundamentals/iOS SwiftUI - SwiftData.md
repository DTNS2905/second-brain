---
tags:
  - ios
  - swiftui
  - swiftdata
  - persistence
  - fundamentals
  - mobile
created: 2026-07-10
source: https://developer.apple.com/documentation/swiftdata
---

# iOS SwiftUI - SwiftData

> Apple's iOS 17+ persistence framework — declarative, macro-driven, built on top of Core Data. Link back to [[iOS SwiftUI Fundamentals Guide]].

**Load-bearing prerequisites:** [[iOS SwiftUI - Property Wrappers]] (for `@Query`, `@Environment`) and [[iOS SwiftUI Architecture - Data Layer]] (SwiftData sits in the Data layer).

---

## Definitions

| Term | Meaning |
|------|---------|
| **Persistence** | Storing data on disk so it survives app restarts (opposite of "in-memory only"). |
| **SwiftData** | Apple's iOS 17+ persistence framework. Replaces Core Data for most new apps but is built on top of Core Data internally. |
| **Core Data** | Apple's older (2005) object-graph and persistence framework. Powerful but verbose; SwiftData is the modern facade. |
| **Model** | A Swift class marked `@Model` — one row in the persistent store, one instance in memory. |
| **Schema** | The set of all model types the app knows about — defines the DB shape. |
| **`ModelContainer`** | The top-level object that owns the store file, the schema, and creates contexts. Similar to Core Data's `NSPersistentContainer`. |
| **`ModelContext`** | A scratchpad where you insert / delete / edit models before saving. Similar to Core Data's `NSManagedObjectContext`. |
| **Macro** | Swift 5.9+ compile-time code generator. `@Model` expands into stored-property observers, `PersistentModel` conformance, and identity boilerplate. |
| **Property wrapper** | A Swift feature (`@Query`, `@Environment`) that wraps a value with extra behavior — here, subscribing a View to data changes. |
| **Predicate** | Type-safe filter expression: `#Predicate<Item> { $0.done == false }`. Compiles to SQLite `WHERE`. |
| **Relationship** | A reference from one model to another — SwiftData tracks the graph and cascades operations per `deleteRule`. |
| **Migration** | Evolving the schema (add / remove / rename properties) without losing existing data on device. |

---

## The `@Model` Macro

Annotate a class — SwiftData turns every stored property into a persistent attribute.

```swift
import SwiftData

@Model
final class Item {
    var title: String
    var done: Bool
    var createdAt: Date

    init(title: String, done: Bool = false, createdAt: Date = .now) {
        self.title = title
        self.done = done
        self.createdAt = createdAt
    }
}
```

**What the macro adds:**
- Conformance to `PersistentModel` and `Observable`
- A hidden `persistentModelID` for identity
- Change tracking on every stored property
- Automatic KVO / `Observation` hooks so SwiftUI re-renders on mutation

Must be a **class** (reference type). Structs cannot be `@Model`.

---

## Required Setup — `.modelContainer`

Attach a container to the root Scene. Every child View can now access the context.

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Item.self)
    }
}
```

Multiple models:

```swift
.modelContainer(for: [Item.self, Tag.self, Folder.self])
```

Forgetting `.modelContainer` → runtime crash: *"No ModelContext found"*.

---

## Reading — the `@Query` Property Wrapper

`@Query` fetches models **and re-runs automatically** whenever the store changes.

```swift
struct ItemListView: View {
    @Query var items: [Item]

    var body: some View {
        List(items) { Text($0.title) }
    }
}
```

### Sorting

```swift
@Query(sort: \.createdAt, order: .reverse) var items: [Item]
```

Multiple sort descriptors:

```swift
@Query(sort: [SortDescriptor(\Item.done), SortDescriptor(\Item.createdAt, order: .reverse)])
var items: [Item]
```

### Filtering with `#Predicate`

```swift
@Query(filter: #Predicate<Item> { !$0.done }) var openItems: [Item]
```

`#Predicate` is a compile-time macro — typos and wrong key paths are caught by the compiler, unlike Core Data's `NSPredicate` strings.

### Dynamic queries

Runtime-parameterized queries need to be built in `init`:

```swift
struct FilteredList: View {
    @Query private var items: [Item]

    init(hidingDone: Bool) {
        let predicate = #Predicate<Item> { !hidingDone || !$0.done }
        _items = Query(filter: predicate, sort: \.createdAt)
    }
}
```

---

## Writing — `@Environment(\.modelContext)`

```swift
struct AddItemView: View {
    @Environment(\.modelContext) private var context
    @State private var title = ""

    var body: some View {
        Form {
            TextField("Title", text: $title)
            Button("Save") {
                context.insert(Item(title: title))
            }
        }
    }
}
```

Common operations:

```swift
context.insert(item)          // add
context.delete(item)          // remove
try context.save()            // flush pending changes to disk
```

**Auto-save:** SwiftData saves periodically on its own. Call `save()` explicitly before an operation the user can't retry (share sheet, background upload).

---

## Relationships — `@Relationship`

```swift
@Model
final class Folder {
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \Item.folder)
    var items: [Item] = []

    init(name: String) { self.name = name }
}

@Model
final class Item {
    var title: String
    var folder: Folder?

    init(title: String, folder: Folder? = nil) {
        self.title = title
        self.folder = folder
    }
}
```

### Delete rules

| Rule | Behavior when the parent is deleted |
|------|-------------------------------------|
| `.cascade` | Delete all children too |
| `.nullify` | Set the children's back-reference to `nil` (default) |
| `.deny` | Refuse to delete if children exist |
| `.noAction` | Do nothing — you promise to fix the graph yourself |

### Many-to-many

Just make both sides an array; SwiftData creates the join table automatically.

```swift
@Model final class Post { @Relationship var tags: [Tag] = [] }
@Model final class Tag  { @Relationship(inverse: \Post.tags) var posts: [Post] = [] }
```

---

## Unique Identifiers — `@Attribute(.unique)`

```swift
@Model
final class User {
    @Attribute(.unique) var email: String
    var name: String

    init(email: String, name: String) {
        self.email = email
        self.name = name
    }
}
```

Inserting a second `User` with the same email **upserts** — updates the existing row. Handy for syncing server data by primary key.

Other attribute options:

| Option | Effect |
|--------|--------|
| `.unique` | Enforce uniqueness / upsert on insert |
| `.externalStorage` | Store large `Data`/blobs outside the DB file |
| `.transformable(by:)` | Encode custom types via a `ValueTransformer` |
| `.transient` | Not persisted — in-memory only |

---

## Migration Story

### Lightweight (automatic)

Adding a new optional property, adding a new model, or removing a property → SwiftData migrates on next launch with no code.

```swift
@Model final class Item {
    var title: String
    var done: Bool
    var priority: Int?     // ✅ new optional — auto-migrates
}
```

### Versioned schemas (manual)

Renames, type changes, or splits need explicit versioning.

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Item.self] }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ItemV2.self] }
}

enum MyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.custom(fromVersion: SchemaV1.self, toVersion: SchemaV2.self,
                 willMigrate: nil, didMigrate: { ctx in /* backfill */ })]
    }
}
```

Wire it into the container:

```swift
.modelContainer(for: Item.self, migrationPlan: MyMigrationPlan.self)
```

---

## Interaction with Clean Architecture

SwiftData models are **persistence models** — they belong in the Data Layer, next to DTOs. They should not travel across layer boundaries into ViewModels or Views.

```
Data Layer:      @Model class ItemEntity   (SwiftData)
                          │
                          │ mapper
                          ▼
Domain Layer:    struct Item                (plain struct, no framework deps)
                          │
                          ▼
Presentation:    ItemListViewModel
Views:           ItemListView
```

### Mapping in the Repository

```swift
// Data/Persistence/ItemEntity.swift
@Model
final class ItemEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var done: Bool

    init(id: UUID, title: String, done: Bool) {
        self.id = id; self.title = title; self.done = done
    }
}

extension ItemEntity {
    var toDomain: Item { Item(id: id, title: title, done: done) }
}

// Domain/Entities/Item.swift  — no SwiftData import
struct Item: Identifiable, Equatable {
    let id: UUID
    var title: String
    var done: Bool
}

// Data/Repositories/ItemRepositoryImpl.swift
final class ItemRepositoryImpl: ItemRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all() throws -> [Item] {
        try context.fetch(FetchDescriptor<ItemEntity>()).map(\.toDomain)
    }

    func add(_ item: Item) throws {
        context.insert(ItemEntity(id: item.id, title: item.title, done: item.done))
        try context.save()
    }
}
```

See [[iOS SwiftUI Architecture - Data Layer]] for the same pattern applied to network DTOs.

---

## Anti-Patterns

### ❌ `@Model` classes crossing layer boundaries

```swift
// ❌ Domain now depends on SwiftData
protocol ItemRepository {
    func all() -> [ItemEntity]     // @Model type leaked
}
```

```swift
// ✅ Domain speaks in plain structs
protocol ItemRepository {
    func all() throws -> [Item]    // Item is a plain Domain struct
}
```

### ❌ Using `@Model` classes directly in a ViewModel

```swift
// ❌ ViewModel now coupled to SwiftData + change tracking + threading rules
@MainActor final class ItemListViewModel: ObservableObject {
    @Published var items: [ItemEntity] = []
}
```

```swift
// ✅ ViewModel owns Domain values
@MainActor final class ItemListViewModel: ObservableObject {
    @Published var items: [Item] = []
    private let repo: ItemRepository
    func load() { items = (try? repo.all()) ?? [] }
}
```

### ❌ Forgetting `.modelContainer`

```swift
// ❌ Runtime crash: "No ModelContext found"
@main struct MyApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
```

```swift
// ✅
WindowGroup { ContentView() }.modelContainer(for: Item.self)
```

### ❌ Storing large binary data inline

```swift
// ❌ Inflates the DB file, slows every query
@Model final class Photo { var jpeg: Data }
```

```swift
// ✅ SwiftData writes it to a side file
@Model final class Photo { @Attribute(.externalStorage) var jpeg: Data }
```

### ❌ Filtering in memory when a predicate would do

```swift
// ❌ Loads all items into RAM then filters
@Query var all: [Item]
var open: [Item] { all.filter { !$0.done } }
```

```swift
// ✅ Filter in SQLite
@Query(filter: #Predicate<Item> { !$0.done }) var open: [Item]
```

---

## Persistence Options Compared

| Tool | Use for | Encrypted | Structured queries | Notes |
|------|---------|-----------|--------------------|-------|
| **SwiftData** | Structured user data — todos, notes, chats, offline caches | No (device-encrypted at rest by iOS) | ✅ `#Predicate` + relationships | iOS 17+. Built on Core Data. |
| **Core Data** | Same as SwiftData, pre-iOS 17 or when you need CloudKit fine control | No | ✅ `NSPredicate` (string) | Verbose. Interop with SwiftData via same store. |
| **`UserDefaults`** | Small key-value settings (flags, IDs, last-opened tab) | No | ❌ | Written to a plist. Not for large data. |
| **Keychain** | Secrets — tokens, passwords, refresh tokens | ✅ hardware-backed | ❌ | Slow. Small values only. Persists across reinstalls. |
| **File system** | Media blobs, downloaded documents | No (unless you encrypt) | ❌ | Use `FileManager` + `URL`. |

---

## Summary

| ✅ Do | ❌ Don't |
|------|---------|
| Attach `.modelContainer` at the App scene | Forget the container (runtime crash) |
| Map `@Model` classes to Domain structs at the Repository | Pass `@Model` types into ViewModels / Views |
| Filter with `#Predicate` | Load everything and filter in Swift |
| `@Attribute(.externalStorage)` for blobs | Store large `Data` inline |
| Versioned schema for renames / type changes | Rely on lightweight migration for everything |
| Use `@Attribute(.unique)` for server IDs → upsert | Manually check-then-insert on every sync |

---

## Apple Docs (Primary References)

- SwiftData framework: https://developer.apple.com/documentation/swiftdata
- `@Model` macro: https://developer.apple.com/documentation/swiftdata/model()
- `@Query`: https://developer.apple.com/documentation/swiftdata/query
- `ModelContainer`: https://developer.apple.com/documentation/swiftdata/modelcontainer
- `ModelContext`: https://developer.apple.com/documentation/swiftdata/modelcontext
- `@Relationship`: https://developer.apple.com/documentation/swiftdata/relationship

---

## Related

- [[iOS SwiftUI Fundamentals Guide]] — parent index
- [[iOS SwiftUI - Property Wrappers]] — how `@Query` and `@Environment` work
- [[iOS SwiftUI Architecture - Data Layer]] — where SwiftData sits in Clean Architecture
- [[iOS SwiftUI Architecture - Clean Architecture]] — the layer boundaries this note respects
- [[iOS Swift - Codable & Foundation]] — mapping DTOs / on-disk formats
- [[iOS Swift - Error Handling]] — `try context.save()` failure handling
