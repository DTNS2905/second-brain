---
tags:
  - ios
  - swiftui
  - tutorial
  - roadmap
  - features
  - mobile
created: 2026-07-02
source: https://developer.apple.com/documentation/swiftui
---

# iOS Tutorial — Part 9: From Tutorial to Real App

> A feature-by-feature backlog to turn the Countries app you built in [[iOS Tutorial - Part 7 Recap and Folder Layout]] into a shippable product. Tasks are grouped into tiers — do a tier at a time, in order. Before you tackle this, [[iOS Tutorial - Part 8 Deceptive Tasks]] gives you the harder design-thinking exercises. Back to index: [[iOS Tutorial Guide]].

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

**SwiftUI:** [[iOS Tutorial Glossary#`NavigationLink`|NavigationLink]], [[iOS Tutorial Glossary#`Section`|Section]], [[iOS Tutorial Glossary#`Picker`|Picker]], [[iOS Tutorial Glossary#`.refreshable`|.refreshable]], [[iOS Tutorial Glossary#`.onChange(of:_:)` (iOS 17+ signature)|.onChange]], [[iOS Tutorial Glossary#`.animation`|.animation]]
**Property wrappers:** [[iOS Tutorial Glossary#`@AppStorage`|@AppStorage]]
**Swift:** [[iOS Tutorial Glossary#`enum`|enum]], [[iOS Tutorial Glossary#`async` / `await`|async / await]], [[iOS Tutorial Glossary#`Task { … }`|Task]]
**Combine:** [[iOS Tutorial Glossary#`.debounce(for:scheduler:)`|.debounce]]

---

## How to Use This Backlog

- Each task lists **Goal**, **Layer(s) touched**, **Acceptance**, and **Hints**.
- **Acceptance** is what "done" looks like. Test it in the simulator before crossing off.
- Tasks within a tier are roughly ordered by difficulty. Skip freely; nothing later depends on a specific earlier one *unless noted*.
- If a task feels too big, split it. A "task" that takes more than a day is really a mini-project.

---

## Tier 1 — Presentation Polish

You have a scrolling list. Users expect more.

### T1.1 — Country Detail Screen
- **Goal:** Tap a row → push a detail screen showing flag, name, capital, and a placeholder region label.
- **Layer(s):** Presentation only.
- **Acceptance:**
  - `NavigationLink` from row → `CountryDetailView`.
  - Back gesture works.
  - Detail screen has its own preview using `DIContainer.mock`.
- **Hints:** `NavigationStack` + `NavigationLink(value:)` + `.navigationDestination(for:)`. See [[iOS SwiftUI - Core Components]].

### T1.2 — Pull-to-Refresh
- **Goal:** Swipe down on the list → re-fetch countries.
- **Layer(s):** Presentation.
- **Acceptance:**
  - `.refreshable { … }` on the `List`.
  - VM exposes an `async` variant of `load()` or bridges the Combine call to `await`.
  - Refreshing shows the system spinner and completes when the pipeline finishes.
- **Hints:** `.refreshable` needs `async`. Use `await withCheckedContinuation` to bridge Combine → async, or wait until T4.1 (Combine → async/await migration) and revisit.

### T1.3 — Empty State + Retry Button
- **Goal:** When `filtered` is empty because search matched nothing, show a friendly empty state. When `errorMessage != nil`, add a "Try again" button.
- **Layer(s):** Presentation.
- **Acceptance:**
  - `ContentUnavailableView(...)` for both cases.
  - Retry button calls `viewModel.load()`.
- **Hints:** iOS 17+ has `ContentUnavailableView.search(text:)` for the empty-search case — one line.

### T1.4 — Row Animation on Filter
- **Goal:** When the user types in search, rows animate in/out instead of hard-cutting.
- **Layer(s):** Presentation.
- **Acceptance:**
  - `.animation(.default, value: viewModel.filtered)` (or `.easeInOut`) on the `List`.
  - Rows fade/slide when the filter narrows or widens.
- **Hints:** `Country` must be `Equatable` (already done in Part 4). `filtered` returns a new array reference each recompute — SwiftUI diffs by `id`.

---

## Tier 2 — Persistence

Users expect the app to remember things.

### T2.1 — Favorites (SwiftData) — depends on T1.1
- **Goal:** A star button on the detail screen toggles favorite. Favorites persist across launches.
- **Layer(s):** Domain (new Entity + Repository protocol), Data (SwiftData impl), Presentation (star toggle).
- **Acceptance:**
  - `FavoritesRepository` protocol in Domain: `toggle(_:)`, `isFavorite(_:) -> Bool`, `favorites() -> AnyPublisher<Set<String>, Never>`.
  - `FavoritesRepositoryImpl` uses `@Model` (SwiftData) or `UserDefaults` for a simpler v1.
  - `DIContainer.live` provides the SwiftData store; `.mock` provides an in-memory implementation.
  - Star state survives a kill-and-relaunch.
- **Hints:** SwiftData docs at https://developer.apple.com/documentation/swiftdata . Start with `UserDefaults` (a `Set<String>` of country names, encoded as JSON) — 20 lines — then upgrade to SwiftData once you're comfortable.

### T2.2 — Recent Searches
- **Goal:** The last 5 search terms show as chips below the search field when it's focused and empty.
- **Layer(s):** Presentation + a tiny Domain repo.
- **Acceptance:**
  - `@AppStorage("recentSearches") private var recentJSON = "[]"` in a helper, decoded into a Domain-visible history.
  - Tapping a chip prefills the search field.
- **Hints:** `@AppStorage` for `String`, `Data`, `Int`, `Double`, `Bool`, and `RawRepresentable`. For arrays, JSON-encode as `Data` or `String`. See https://developer.apple.com/documentation/swiftui/appstorage .

---

## Tier 3 — Richer Domain

Business rules that pay for the UseCase layer.

### T3.1 — Group by Region
- **Goal:** Switch the flat `List` to a `List` with sections: Africa, Americas, Asia, Europe, Oceania.
- **Layer(s):** Data (extend DTO + Entity with `region`), Domain (new UseCase or extend existing), Presentation (`Section`s).
- **Acceptance:**
  - `CountryDTO` decodes `region` from the API (add `region` to `response_fields=names.common,capitals.name,flag.emoji,region`).
  - `Country` entity has `region: Region` (an `enum`).
  - New `GroupedCountriesUseCase` returns `[Region: [Country]]` or `[(Region, [Country])]`.
  - View renders `Section(header: Text(region.name)) { ForEach(...) }`.
- **Hints:** Sort sections alphabetically; sort countries within a section alphabetically. The UseCase is where that composed rule belongs.

### T3.2 — Filter by Region — depends on T3.1
- **Goal:** A picker/menu at the top lets the user filter to one region.
- **Layer(s):** Presentation.
- **Acceptance:**
  - `Picker` bound to VM state.
  - Selecting "All" restores the full grouped list.
  - Filter composes with search (both active simultaneously).
- **Hints:** Add `var selectedRegion: Region?` to the VM. Recompute `filtered` from both signals.

### T3.3 — Sort Toggle
- **Goal:** Sort by **Name** (default) or **Population**.
- **Layer(s):** Data (add `population`), Domain (parameterize UseCase), Presentation (toggle).
- **Acceptance:**
  - UseCase accepts a sort mode: `enum SortMode { case name, populationDesc }`.
  - View has a menu control that changes the mode; list re-renders sorted.
- **Hints:** Keep the sort inside the UseCase — that's the business rule seam.

---

## Tier 4 — Architecture Stretch

Retire training-wheels and see the layers shine.

### T4.1 — Migrate Combine → `async/await`
- **Goal:** Replace `AnyPublisher<[Country], Error>` with `async throws -> [Country]` throughout Domain and Data. Presentation VM uses `Task { … }`.
- **Layer(s):** Domain, Data, Presentation.
- **Acceptance:**
  - No `import Combine` except where genuinely needed (e.g., `.searchable` debouncing, if you keep it).
  - `URLSession` uses `data(from:)` instead of `dataTaskPublisher(for:)`.
  - VM uses `Task` and `MainActor` isolation; no `cancellables`.
  - Tests still pass.
- **Hints:** This is the exercise that makes the point of Clean Architecture click — the Domain protocol changes shape once, and the VM + Repo impl follow. No View file changes. Compare with [[iOS SwiftUI Architecture - MVVM with Combine]] and [[iOS SwiftUI Architecture - Combine Operators]] to see what you're leaving behind.

### T4.2 — Modularize into Swift Packages
- **Goal:** Split the app into 4 targets — `Domain`, `Data`, `Presentation`, and the `App` target that wires them.
- **Layer(s):** Project structure.
- **Acceptance:**
  - `Domain` compiles with zero dependencies.
  - `Data` depends only on `Domain`.
  - `Presentation` depends only on `Domain`.
  - Attempting to `import Data` from `Presentation` fails at compile time — the **Dependency Rule enforced by the compiler**.
- **Hints:** File → New → Package. Add packages as local dependencies of the App target. `internal` → `public` bumps needed on the boundary types.

### T4.3 — Debounced Search
- **Goal:** Server-side search — when the user stops typing for 300ms, hit an API endpoint (or a new UseCase) instead of filtering the local array.
- **Layer(s):** Presentation → Domain (new UseCase) → Data.
- **Acceptance:**
  - Typing "vi" → "vie" → "viet" fires only one network call after the user pauses.
  - Uses Combine's `.debounce(for:scheduler:)` — a case where Combine still shines even after T4.1.
- **Hints:** Wire a `Just(searchText)` subject via Combine even if the rest of the pipeline is `async` — the two coexist. See [[iOS SwiftUI Architecture - Combine Operators]].

---

## Tier 5 — Quality

### T5.1 — Unit Tests (Domain + VM)
- **Goal:** Test every business rule and every VM state transition.
- **Layer(s):** Test target.
- **Acceptance:**
  - `FetchCountriesUseCaseTests` — verifies sort, verifies mapping-nil is dropped.
  - `CountriesViewModelTests` — loading state, error state, filter, region select.
  - All tests use the Swift Testing framework (`import Testing`, `@Test`, `#expect`), not the legacy XCTest.
  - Coverage of the Domain layer > 90%.
- **Hints:** Swift Testing docs: https://developer.apple.com/documentation/testing . Inject fake UseCases into the VM to test loading/error states deterministically.

### T5.2 — Snapshot Tests
- **Goal:** Every view has a snapshot test that fails when pixels change.
- **Layer(s):** Test target.
- **Acceptance:**
  - `CountryRow` snapshot in light + dark mode.
  - `CountriesListView` snapshot in loading + loaded + error states (use the state factories from [[iOS Tutorial - Part 6 Dependency Injection]]).
- **Hints:** `pointfreeco/swift-snapshot-testing` is the community standard. Add as a Swift Package Manager dependency.

### T5.3 — Accessibility Pass
- **Goal:** VoiceOver reads every row correctly. Dynamic Type sizes render without truncation.
- **Layer(s):** Presentation.
- **Acceptance:**
  - `.accessibilityLabel("\(name), capital \(capital)")` on each row.
  - Preview at `.dynamicTypeSize(.xxxLarge)` — no clipped labels.
  - Contrast passes at all system settings.
- **Hints:** Apple HIG accessibility section: https://developer.apple.com/design/human-interface-guidelines/accessibility .

---

## Tier 6 — Ship

### T6.1 — App Icon + Launch Screen
- **Goal:** Replace the default Xcode icon and launch storyboard.
- **Acceptance:** An icon set in `Assets.xcassets` with all required sizes; a `Launch Screen.storyboard` (or SwiftUI `LaunchScreen` info-plist key on iOS 14+).
- **Hints:** Use SF Symbols for a globe-themed monochrome icon if you don't have a designer.

### T6.2 — Localization (English + Vietnamese)
- **Goal:** All user-visible strings support two locales.
- **Layer(s):** Presentation.
- **Acceptance:**
  - `String Catalog` (`.xcstrings`) with `en` and `vi`.
  - Switching device language switches the app UI.
  - **Country names themselves stay English** — that's what the API returns; localizing content is a separate scope.
- **Hints:** iOS 15+ String Catalogs: https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog . Vietnamese-first strings play nice with the existing note style in this vault.

### T6.3 — TestFlight Beta
- **Goal:** A build in TestFlight that a friend can install on their device.
- **Acceptance:**
  - Apple Developer account enrolled.
  - Bundle ID registered.
  - Archive → upload via Xcode → build appears in App Store Connect.
  - Internal testing group has your friend's Apple ID; they install via TestFlight.
- **Hints:** First archive tends to surface signing issues — budget an afternoon.

---

## Tier 7 — Production Complexity (Post-Launch)

Real-world features with real business logic. Each of these would be a story-week (or more) at a real company. If any task feels "obvious" reading the Goal, read the Acceptance again — the depth is in the edges. Pairs with the design-thinking exercises in [[iOS Tutorial - Part 8 Deceptive Tasks]].

### T7.1 — API Key Rotation Without Downtime
- **Goal:** Rotate the API key from `rc_live_demo` → `rc_live_2` while the app is running, without kicking the user out or dropping in-flight requests.
- **Layer(s):** Data (network stack) — Domain unaware.
- **Acceptance:**
  - `AuthTokenProvider` protocol in Data owns the current key + a rotation lock.
  - A 401 response with header `X-Rotate-Key: rc_live_2` triggers rotation.
  - All in-flight requests that failed with 401-rotate are transparently retried once with the new key.
  - Concurrent requests must not each fetch a fresh key — a rotation-in-progress `Task` is deduplicated.
  - Persist the current key to Keychain (not UserDefaults — key is sensitive).
  - VM/View code is untouched.
- **Hints:** Wrap `URLSession.data` in an async interceptor. Use an `actor` for the rotation lock. Combine's `retry(when:)` isn't quite enough — write it in `async/await` post-T4.1. See https://developer.apple.com/documentation/security/keychain-services .

### T7.2 — Offline-First Favorites with Conflict Resolution
- **Goal:** User can favorite/unfavorite countries offline. On reconnect, sync with the server; if the server has a conflicting state (from another device), resolve deterministically.
- **Layer(s):** Domain (conflict policy), Data (queue + sync), Presentation (pending indicator). Depends on T2.1 and T7.1.
- **Acceptance:**
  - Local writes append to a persistent `OutboxQueue` (SwiftData) with `{id, desiredState, timestamp}`.
  - On reconnect, drain the queue oldest-first with idempotent `setFavorite(id, favorite)` calls.
  - Server returns its authoritative timestamp for the field; conflict = server timestamp newer than local timestamp.
  - Conflict policy: **last-writer-wins by timestamp**; user sees a subtle "Updated from another device" toast when local state is overwritten.
  - UI shows a "syncing…" dot on any country with a pending write; disappears on confirm.
  - Queue survives kill; empty queue on cold start with no changes = zero network calls.
  - Duplicate enqueues collapse — the queue never holds two entries for the same country.
- **Hints:** Vector clocks are overkill here — a single `updatedAt` field per record is enough for last-writer-wins. Watch for clock skew: prefer server-authoritative timestamps whenever the server has spoken.

### T7.3 — HTTP Cache with ETag + Stale-While-Revalidate
- **Goal:** Serve country data from cache instantly, revalidate in the background, and honor server cache headers.
- **Layer(s):** Data only.
- **Acceptance:**
  - `URLCache` sized to 20MB memory / 100MB disk, or a hand-rolled disk cache keyed by request signature.
  - `If-None-Match` + `ETag` handshake: 304 responses reuse the cached body but reset the freshness clock.
  - Serve stale data (up to 24h) immediately when a fresh fetch is in flight — user never waits.
  - Manual pull-to-refresh **bypasses** the cache (add `Cache-Control: no-cache`).
  - Cache stampede prevention: if 10 views request `/countries` simultaneously on cold start, exactly one network call fires; the rest wait on the same `Task`.
  - Delete cache on logout (link to T7.1's Keychain lifecycle).
- **Hints:** Wrap the cache logic in a Repository decorator; the concrete `URLSession`-backed repo has no idea it's cached. See https://developer.apple.com/documentation/foundation/urlcache .

### T7.4 — SwiftData Schema Migration (v1 → v2)
- **Goal:** Add a `note: String?` field to `FavoriteCountry` (user annotation on why they favorited it). Existing users' data must migrate without loss.
- **Layer(s):** Data.
- **Acceptance:**
  - `SchemaV1` (original) and `SchemaV2` (with `note`) both declared.
  - Lightweight migration is used because the field is optional additive.
  - A `MigrationPlan` declares the stages. On first launch after upgrade, migration runs.
  - Existing favorites keep their `id` and `addedAt`; new `note` is `nil`.
  - Migration failure is caught and reported to a "safe mode" screen — the app does not crash and users can export their data.
  - Migration is idempotent — running it twice does nothing.
  - A test fixture with 1000 pre-migration records completes migration in < 500ms.
- **Hints:** https://developer.apple.com/documentation/swiftdata/schemamigrationplan . Keep a compressed backup of the pre-migration store; delete it after two successful launches.

### T7.5 — Localized Country Names with Fallback Chain
- **Goal:** Show country names in the user's language when available, falling back cleanly when not.
- **Layer(s):** Data (multi-locale fetch), Domain (name-resolution rule), Presentation (display + search).
- **Acceptance:**
  - New DTO endpoint `/countries/translations?locales=vi,en` returns per-locale names.
  - `Country` entity gains `names: [String: String]` (locale code → name).
  - Name resolution rule: user's locale → user's language w/o region (`vi-VN` → `vi`) → `en` → whatever the base API returns. First non-empty wins.
  - Rule lives in a Domain function `Country.displayName(in: Locale)`; nowhere else.
  - Search matches **any** locale the user has cached (typing "Vietnam" or "Việt Nam" both work).
  - Locale change while running: list re-renders in the new language on next `body` recompute, no reload.
  - Falls back gracefully if the translations endpoint is offline (base API's English name).
- **Hints:** Locale identifier canonicalization: `Locale(identifier: "vi-VN").language.languageCode?.identifier`. Diacritic-insensitive search: `String.range(of:options: [.diacriticInsensitive, .caseInsensitive])`.

### T7.6 — Feature Flags with Kill Switch
- **Goal:** Turn features on/off remotely without shipping a build. Stable per-user rollout (same user always in the same bucket).
- **Layer(s):** Cross-cutting service (`FeatureFlags`) — treat as its own module.
- **Acceptance:**
  - Poll a remote JSON config every 60 minutes; cache locally (`URLCache` from T7.3 or a dedicated file).
  - App startup uses cached config; refresh in background.
  - Each flag has `{name, enabledPercent, forceOff, forceOn}`. `forceOff` is the **kill switch** — beats everything else.
  - User's bucket: `stableHash(userId + flagName) % 100`. Same user + same flag = same bucket forever (unless we change the algorithm).
  - Internal build override: env var / debug menu can override any flag locally.
  - Exposure logging: emit an analytics event **once per session per flag** when a flag is read (T7.8 dependency).
  - Reading a flag never blocks the caller — worst case returns the compiled-in default.
- **Hints:** Use `SHA256` from `CryptoKit` for stable hashing. `@Observable class FeatureFlags { }` accessed via `@Environment`. Do NOT put flag checks deep inside SwiftUI `body` — resolve at ViewModel init.

### T7.7 — Actionable Push Notifications with Deep Links
- **Goal:** Server pushes a notification like "🇻🇳 Vietnam's population passed 100M". Tapping opens the country's detail. A "Favorite" action button on the notification adds it to favorites without opening the app.
- **Layer(s):** Data (notification service + APNs registration), Presentation (deep-link handler), Domain (reuses existing UseCases).
- **Acceptance:**
  - APNs entitlement + `UNUserNotificationCenter` permission flow, with a soft-ask before the system prompt.
  - Registration token uploaded to server keyed by `userId`; refreshed on rotation.
  - Silent (`content-available`) notifications trigger a background refresh of `/countries`.
  - Rich notification has a `UNNotificationCategory` with a "Favorite" action.
  - Tapping the action favorites the country server-side via the same UseCase used in-app.
  - Tapping the body opens the detail screen even from a cold-start.
  - Permission previously denied: settings screen shows a "Notifications off — open Settings" row that deep-links to Settings.app.
- **Hints:** https://developer.apple.com/documentation/usernotifications . For deep link routing, keep a `NavigationPath` in an `AppRouter` `@Observable` and push routes from the AppDelegate/SceneDelegate handler.

### T7.8 — Analytics with Batched Upload + Persistent Retry Queue
- **Goal:** Track user actions (viewed country, favorited, searched) with resilient upload — no lost events, no PII leaked.
- **Layer(s):** Data (analytics module), all layers emit via a lightweight `Analytics.log(...)` facade.
- **Acceptance:**
  - Events buffered in memory; flushed every 30 seconds OR when 20 events accumulate OR on app background.
  - Flush uses one batched POST; on failure, events move to a persistent `SwiftData`-backed queue.
  - On next app launch or successful network call, drain the queue oldest-first.
  - Retry with backoff: 5s, 15s, 60s, 5min, 30min, 2h. After 2h, drop the batch and log a diagnostic event.
  - Payload contains **no country name, no search query text** — only stable IDs and enum labels.
  - Opt-out: setting toggle stops logging immediately; existing queue is flushed but not backfilled.
  - Kill-and-relaunch loses at most the current in-flight batch (a few events).
- **Hints:** Keep the analytics module free of Domain/Presentation imports — it's a leaf. A single actor owns the queue for thread safety. https://developer.apple.com/app-store/app-privacy-details/ .

### T7.9 — WebSocket Live Population Feed
- **Goal:** Populations update live from a WebSocket stream while the countries screen is visible.
- **Layer(s):** Data (WebSocket client), Domain (merge policy), Presentation (subscription lifecycle).
- **Acceptance:**
  - Connect via `URLSessionWebSocketTask` when the countries screen appears; disconnect on disappear.
  - Reconnect on drop with exponential backoff (1s → 60s cap); reset on successful message.
  - Each frame is `{id: String, population: Int, tick: Int}`. Frames with a `tick` ≤ last-seen for that ID are discarded (out-of-order tolerant).
  - Merging: local `[Country]` gets a per-ID `population` update; other fields untouched. UI animates the number changing.
  - Battery-aware: disconnect on `ScenePhase.background`; do NOT hold a background socket.
  - Data-saver / Low-Power mode: fall back to a 30-second HTTP poll (no socket).
  - Optional feature-flagged (T7.6): `liveFeedEnabled`.
- **Hints:** https://developer.apple.com/documentation/foundation/urlsessionwebsockettask . Combine bridge: expose the socket as `AnyPublisher<PopulationTick, Never>` via a `PassthroughSubject`.

### T7.10 — Home Screen Widget + App Intent
- **Goal:** A medium-sized home-screen widget shows the user's top favorite country. Siri and Shortcuts can trigger "Favorite the country I'm looking at".
- **Layer(s):** New Widget target, App Intents extension, shared Data via App Group.
- **Acceptance:**
  - New Widget target `CountriesWidget` with a `TimelineProvider` that reads favorites from a shared SwiftData store (App Group).
  - Widget refreshes at most every 15 minutes (respect system budget).
  - `AppIntent` "Favorite this country" accepts a country identifier parameter with dynamic value suggestions.
  - Siri phrase: "Favorite the current country in Countries" adds the currently-visible country.
  - Intent runs in the app's background, calls the same `SetFavoriteUseCase` as the UI.
  - Widget deep-links into the country's detail screen when tapped.
  - Both widget and app read from the same store — favoriting in-app updates the widget on next timeline reload.
- **Hints:** https://developer.apple.com/documentation/widgetkit and https://developer.apple.com/documentation/appintents . App Group entitlement + `ModelConfiguration(url:)` pointing at the shared container.

---

## Suggested Milestones

If you want a paced plan:

| Week | Goal |
|------|------|
| 1 | Tier 1 (all polish) — the app *feels* real |
| 2 | Tier 2 (favorites + recent searches) — the app *remembers* |
| 3 | Tier 3 (regions + sort) — the domain earns its keep |
| 4 | Tier 4.1 (async/await migration) — the layers prove themselves |
| 5 | Tier 5 (tests + a11y) — confidence to change things fast |
| 6 | Tier 6 (icon + localization + TestFlight) — ship |
| 7-8 | Tier 7.1-7.4 — auth rotation, offline-first sync, HTTP cache, schema migration |
| 9-10 | Tier 7.5-7.7 — localized names, feature flags, actionable push |
| 11-12 | Tier 7.8-7.10 — analytics, WebSocket, widget + App Intents |

Six weeks to ship v1; another 4-6 weeks to reach production-grade if you tackle Tier 7. Each Tier 7 task is a full sprint at a real company — do them as their own mini-projects, not as a race.

---

## What This Backlog Deliberately Leaves Out

- **Backend of your own.** You're using a public API. Rolling your own is a separate multi-week project.
- **In-app purchase / subscriptions (StoreKit 2).** Its own domain — receipt validation, restore purchases, family sharing.
- **iPad / Mac / visionOS split.** SwiftUI cross-platform is real but adds design surface. Ship iPhone-only first.
- **Real-time collaboration / CRDTs.** If you ever build the "shared favorite lists with friends" version, this is a book, not a task.
- **On-device ML.** Semantic search, image classification of flags — great follow-up, but Core ML is its own stack.

Note: push notifications, auth, and analytics used to live here but graduated into Tier 7 (T7.1, T7.7, T7.8) — they *are* worth building once the v1 ships.

---

## Where to Grow After This

- **Second app, different domain.** The best proof you internalized Clean Architecture is repeating it in a new problem — Todo, Recipes, Weather, whatever. The folder layout should feel obvious.
- **A feature-flagged team codebase.** Contribute to an open-source SwiftUI app that uses MVVM + Combine (or the async equivalent). Reading production code is the last-mile skill this tutorial can't give you.

---

## Cross-References

- All architecture notes: [[iOS SwiftUI Architecture Guide]]
- Fundamentals: [[iOS SwiftUI Fundamentals Guide]]
- The tutorial you're extending: [[iOS Tutorial Guide]]

---

**When you finish a tier, come back and check things off in this note.** That's the muscle memory Clean Architecture gives you — knowing *which layer* a new task touches without having to think.
