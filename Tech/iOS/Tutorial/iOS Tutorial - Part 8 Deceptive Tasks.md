---
tags:
  - ios
  - swiftui
  - tutorial
  - clean-architecture
  - business-logic
  - edge-cases
  - mobile
created: 2026-07-14
source: internal
---

# iOS Tutorial — Part 8: Deceptive Tasks

> Tasks that look easy at first glance but grow teeth as you implement them. Each one starts as "just a few lines" and ends up teaching you why Clean Architecture pays for itself. Sits between [[iOS Tutorial - Part 7 Recap and Folder Layout]] (which recaps the layers) and [[iOS Tutorial - Part 9 From Tutorial to Real App]] (which turns the code into a shippable app). Back to index: [[iOS Tutorial Guide]].

---

## Why This Part Exists

The Part 9 backlog gives you an ordered set of concrete tasks. This part gives you **traps** — tasks a product manager writes in one line and a junior implements in one hour, then spends three days debugging.

For each task you get:

1. **The One-Liner** — how it's stated (deceptive simplicity)
2. **First Draft** — the naive 20-line solution
3. **The Cracks** — what breaks in the real world
4. **Hidden Business Rules** — rules you didn't know were rules
5. **Layer Consequences** — where each concern actually lives
6. **Acceptance Criteria** — the spec that forces correctness
7. **Hints** — what to reach for

**Recommended workflow:** read the One-Liner, write the First Draft yourself before reading further, then compare with the Cracks section. That's how you build the instinct.

---

## New Keywords in This Part

Full definitions in [[iOS Tutorial Glossary]].

- **Optimistic UI** — updating the UI before the server confirms; roll back on failure.
- **Idempotent** — an operation that produces the same result when repeated (safe to retry).
- **Debounce** — wait for a pause in events before acting; keeps only the last event's effect.
- **Cancellation token** — a handle used to abort in-flight work when it's superseded.
- **State machine** — an explicit enum of allowed states + allowed transitions.

---

## Task D1 — Add a Favorite Star

### The One-Liner
> "Add a star button. Tap it to favorite a country. Show a filled star if favorited."

### First Draft (what you'll write)
```swift
Button {
    viewModel.toggleFavorite(country)
} label: {
    Image(systemName: country.isFavorite ? "star.fill" : "star")
}
```

And in the ViewModel:
```swift
func toggleFavorite(_ country: Country) {
    Task {
        try await repository.toggle(country.id)
        await load()
    }
}
```

### The Cracks
- **Latency.** `toggle` hits the network — user sees a 300ms lag before the star flips. Feels broken.
- **Re-fetch.** `await load()` refetches the whole list — 2 seconds of spinner just to flip one star.
- **Failure.** Network drops mid-toggle. The star doesn't flip. User taps again. Now the server has *toggled twice*.
- **Race.** User taps star 5 times rapidly. 5 in-flight requests. Final server state = ??? (order-dependent).
- **Kill.** User kills the app between toggle and re-fetch. Local view is stale on relaunch.
- **Sync.** User favorites on device A. Device B still shows unfavorited.

### Hidden Business Rules
- Toggle **must feel instant** — even offline.
- The final server state **must match the user's final tap** — not the first, not a random one.
- A failed toggle **must revert visibly** — not silently.
- Rapid taps on the same country should coalesce to one server call.

### Layer Consequences
- **Presentation:** owns the *optimistic* boolean. Flips instantly on tap.
- **Domain:** `ToggleFavoriteUseCase` — pure business rule (idempotent by design; sends the *desired* state, not "toggle").
- **Data:** owns the retry, coalescing, and reconciliation with server truth.

The naive `toggle()` API is wrong — it's not idempotent. Prefer `setFavorite(id: String, favorite: Bool)`.

### Acceptance
- Star flips on tap with zero perceived latency (< 16ms).
- Airplane mode → tap star → star flips → shows "will sync when online" state.
- Rapid taps (5 in 1 second) result in exactly **one** server call carrying the final state.
- Network fails → star reverts with a toast; retry is available.
- Kill mid-op → on relaunch, local state matches last user intent; syncs when online.

### Hints
- Local truth: SwiftData or `@AppStorage`-backed `Set<String>` of favorite IDs, updated synchronously.
- Server sync: a debounced `PassthroughSubject<(id, bool), Never>` in the Data layer, `.debounce(300ms)` before firing.
- Rollback: a compensating write to the local store on server failure + user toast.

---

## Task D2 — Recent Searches (last 5)

### The One-Liner
> "Show the user's last 5 search terms as tappable chips under the search bar."

### First Draft
```swift
@AppStorage("recentSearches") private var raw = "[]"

func record(_ term: String) {
    var arr = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
    arr.insert(term, at: 0)
    arr = Array(arr.prefix(5))
    raw = String(data: (try? JSONEncoder().encode(arr)) ?? Data(), encoding: .utf8) ?? "[]"
}
```

Called from `.onChange(of: searchText) { record($0) }`.

### The Cracks
- **Every keystroke recorded.** Typing "vietnam" saves `v`, `vi`, `vie`, `viet`, `vietn`, `vietna`, `vietnam` — instantly filling the list with useless prefixes.
- **Duplicates.** Searching "japan" twice puts it in twice.
- **Case sensitivity.** "Japan" and "japan" are two entries.
- **Whitespace.** "japan " ≠ "japan".
- **Empty strings.** User backspaces to empty → "" enters the list.
- **What counts as a "search"?** Typing or *committing* (pressing return, tapping a result)?
- **Order.** Newest-first? Most-frequent-first? Both?
- **Delete.** How does the user remove one? Clear all?

### Hidden Business Rules
- A "search" is recorded **only when the user acts on it** — tapping a result or pausing 800ms after last keystroke.
- Terms are **normalized** before compare: trimmed, lowercased for the compare (but stored with original case for display).
- Duplicates **bubble to the top**, don't stack.
- Empty and whitespace-only strings are never recorded.

### Layer Consequences
- **Domain:** `RecentSearchesUseCase` — normalization + dedup + cap-at-N is a business rule, not a UI concern.
- **Data:** persistence (UserDefaults, SwiftData, or Keychain if searches are considered sensitive).
- **Presentation:** debounce on the search field + rendering chips.

If normalization lives in Presentation, you'll re-implement it wrong when a second entry point appears (e.g., voice search).

### Acceptance
- Typing "vietnam" then tapping a result records exactly one entry: "vietnam".
- Typing "japan" then "Japan" results in one chip labeled "Japan" (most recent form).
- Whitespace-only or empty searches never appear.
- Tapping a chip prefills the field and fires a search — and moves that chip to position 0.
- Long-press on a chip deletes it. A "Clear all" affordance exists.
- Survives kill-and-relaunch.

### Hints
- Debounce the "should I record?" decision, don't debounce the search itself (those are two different debounces).
- Store as `[RecentSearch]` where `RecentSearch` = `{ id: UUID, term: String, timestamp: Date }` — timestamps let you show "5 minutes ago" later.

---

## Task D3 — Pagination Meets Search

### The One-Liner
> "Load 20 countries at a time; load more when the user scrolls near the bottom. Search still works."

### First Draft
```swift
List(viewModel.countries) { country in
    CountryRow(country)
        .onAppear { if country == viewModel.countries.last { viewModel.loadMore() } }
}
```

### The Cracks
- **Search + pagination.** User searches "vi" after loading page 3. What's the source of truth — filtered subset of loaded pages, or a fresh search-server call from page 1?
- **Search then scroll.** User searches, scrolls, clears search. Do they land on their old scroll position (all 60 loaded) or a fresh page 1?
- **Cancellation.** Page 4 request is in flight; user starts a search. Page 4's response arrives and appends to filtered results — corrupting state.
- **Duplicates.** Server-side pagination sometimes returns overlapping items across page boundaries (data changed between requests). Naive append gives duplicates.
- **Refresh mid-scroll.** User pulls to refresh on page 3. What happens to pages 1-3? Discard? Reload only 1?
- **Empty page mid-list.** Server returns 0 items for page 5 — end of list, or transient error?
- **Error mid-pagination.** Page 4 fails after pages 1-3 loaded. Do you show an error banner? Retry button inline at the bottom?

### Hidden Business Rules
- Search **resets** pagination — it's a different query.
- Every in-flight request has an identity; results from stale requests must be **discarded**, not merged.
- End-of-list detection is a **contract** with the server (empty response? explicit hasNext flag?), not a UI heuristic.
- "Load more" should only fire when **not** already loading and **not** in an error state.

### Layer Consequences
- **Domain:** `LoadPageUseCase(query, cursor)` — cursor is opaque; the UseCase doesn't know if it's an offset, a token, or a timestamp.
- **Data:** repository handles the concrete cursor scheme + response mapping + dedup by ID.
- **Presentation:** owns pagination state as a small state machine: `.idle | .loadingPage(n) | .loaded(page: n, hasMore: Bool) | .error(page: n, retry)`.

Anti-pattern: representing pagination state as three separate booleans (`isLoading`, `hasMore`, `errorMessage`). They become inconsistent within an afternoon. Use a single `enum` state.

### Acceptance
- Fresh launch → page 1 (20 items). Scroll to bottom → page 2 appends. Scroll → page 3 appends. Search "vi" → all pages discarded, fresh search-page 1 loads. Clear search → back to page 1 of the unfiltered list (**not** the previous scroll depth).
- 5 rapid "load more" scroll triggers fire exactly **one** network call.
- Response to page 3 arrives after user has started a search → the response is discarded silently.
- Error on page 4 → inline retry button at bottom of list, keeps pages 1-3 visible.
- Duplicate country IDs across pages appear only once.

### Hints
- Cancellation: keep a `Task` handle for the current in-flight request; cancel + replace on state change.
- Dedup: keep a `Set<Country.ID>` alongside the array.
- Debounce: for "near the bottom" — throttle `onAppear` triggers to at most once per 200ms.

---

## Task D4 — Sort by Population + Group by Region

### The One-Liner
> "Group countries by region. Within each region, sort by population descending."

### First Draft
```swift
Dictionary(grouping: countries, by: \.region)
    .mapValues { $0.sorted { $0.population > $1.population } }
```

### The Cracks
- **Nil populations.** API returns `null` for some countries. Where do they sort — top, bottom, hidden?
- **Nil regions.** Same problem, uglier — a country with no region needs its own "Unknown" section? Or filtered out?
- **Same population.** Two countries with population 1M — deterministic sort or platform-dependent?
- **Section order.** `Dictionary` has no order. Should Africa come before Americas? Alphabetical? User's continent first? Localized?
- **Locale.** Alphabetical order for "Việt Nam" differs from "Vietnam" — depending on locale.
- **Numbers-as-strings.** If population comes in as a string ("1,340,000,000") — parse or fail?

### Hidden Business Rules
- Nil populations sort **last** within their region (a country you don't know the size of shouldn't top the list).
- Countries with no region are grouped under a **localized** "Other" section, which appears **last**.
- Section order is **alphabetical by localized region name**, respecting the user's locale (diacritic-aware).
- Ties in population fall back to alphabetical by name — again locale-aware.

### Layer Consequences
- **Domain:** the `GroupedCountriesUseCase` owns *all* of the above. Nowhere else. If a designer says "wait, Asia first," you change one file.
- **Data:** normalizes nil / string populations at DTO → Entity mapping. Domain sees clean values.
- **Presentation:** just renders `[(Region, [Country])]` — no sorting logic, no nil handling.

Anti-pattern: `viewModel.groupedCountries` runs the sort every re-render. Cache the result; recompute only on `countries` or `sortMode` change.

### Acceptance
- A country with null population appears at the bottom of its region.
- A country with no region appears in the "Other" section, which is always last.
- Section labels reflect the user's locale (Vietnamese vs English).
- Sort within a section is deterministic — the same data always renders in the same order.
- Sorting 250 countries takes < 5ms (measure with `Instruments`).

### Hints
- Use `Locale.current` + `String.compare(_:options:range:locale:)` for locale-aware sort.
- Consider a `Region.priority: Int` for a fixed non-alphabetical order later.

---

## Task D5 — Pull-to-Refresh During Ongoing Fetch

### The One-Liner
> "Add pull-to-refresh."

### First Draft
```swift
List(...) { ... }
    .refreshable {
        await viewModel.load()
    }
```

### The Cracks
- **Concurrent loads.** User taps a retry button (fires `load()`) and immediately pulls to refresh (fires another `load()`). Now two network calls; whichever finishes last wins — possibly the older data.
- **Spinner double-show.** The in-VM loading spinner + the pull-to-refresh spinner both appear.
- **Cancellation.** User pulls to refresh, then backgrounds the app. `await` continues, wastes battery, response arrives to an inactive view.
- **Rate-limit.** User pulls 5 times in a row. Server returns 429. Do you show an error? Wait?
- **First launch.** Initial load hasn't finished; user pulls to refresh. What happens to the initial load?

### Hidden Business Rules
- Only **one** load may be in flight at a time.
- The most recent user intent **wins** — a pull-to-refresh supersedes an in-flight load.
- Backgrounding the app **cancels** the load; on foreground, we don't auto-retry (the user can pull again).
- The visible spinner is exactly one at a time — the pull-to-refresh spinner takes precedence over the in-view spinner while a pull is active.

### Layer Consequences
- **Presentation VM:** owns the current `Task<Void, Never>?` — a single field. Every load call replaces it after cancelling the previous.
- **Domain:** stays synchronous in its intent — the UseCase doesn't know about cancellation strategies.
- **Data:** must be **cancellation-safe** — a cancelled URLSession task should not corrupt any cache.

### Acceptance
- Two rapid `load()` invocations → exactly one Publisher subscription / URL request survives.
- Pull-to-refresh while loading → in-view spinner hides, pull spinner shows, one request in flight.
- Background the app mid-load → task cancels; no update on return.
- 429 response → error banner with countdown before retry allowed.

### Hints
- `Task.checkCancellation()` inside long-running steps in the Data layer.
- `withTaskCancellationHandler` for cleanup.
- A single `@Observable` property `currentLoad: Task<Void, Never>?` cancelled and replaced on each load.

---

## Task D6 — Rate Limit Handling

### The One-Liner
> "Handle 429 Too Many Requests gracefully."

### First Draft
```swift
if response.statusCode == 429 {
    errorMessage = "Rate limited"
}
```

### The Cracks
- **No user guidance.** They see "Rate limited" and stare — retry immediately? Wait forever?
- **`Retry-After` header.** Real servers tell you when to retry. Ignoring it is disrespectful and often gets you throttled harder.
- **Exponential backoff.** A cheap client retries every second forever. A good one backs off: 1s, 2s, 4s, 8s, capped.
- **User taps retry mid-cooldown.** Do they override the cooldown? Reset the backoff? Extend it?
- **Cross-endpoint rate limits.** 429 on `/countries` also blocks `/regions` (same rate bucket). Global vs per-endpoint tracking.
- **Success mid-backoff.** A different request succeeded, meaning the limit lifted. Do you cancel the countdown?

### Hidden Business Rules
- Respect `Retry-After` if present; fall back to exponential backoff (base 1s, factor 2, cap 60s) otherwise.
- Show the user a live countdown, not just "wait."
- User-initiated retry **resets** the backoff counter and attempts immediately — this is a UX choice, not "correct" — but be explicit about it.
- Backoff state is **per-endpoint** unless the server sends a global limit header.

### Layer Consequences
- **Data:** owns the retry policy. Wrap the network call in a retry operator that reads `Retry-After` and backs off.
- **Domain:** unaware of retries. The Repository returns a Publisher that eventually succeeds or fails after policy is exhausted.
- **Presentation:** shows the countdown driven by a `Publisher<TimeInterval, Never>` from the Data layer's backoff state.

Anti-pattern: putting retry logic in the ViewModel. Then every feature needs its own copy.

### Acceptance
- 429 with `Retry-After: 30` → countdown shown, no auto-retry until 30s elapse.
- 429 without header → 1s → 2s → 4s → 8s → 16s → 32s → 60s cap.
- User taps "Retry now" during countdown → immediate retry; backoff resets on next 429.
- 3 different pages hitting 429 share the countdown (same server bucket).

### Hints
- Combine: `.retry(when:)` doesn't exist by default; write a custom operator with `.catch { error in delay + retry }`.
- Store backoff state in a repository-scoped actor for thread safety.

---

## Task D7 — Undo Delete Favorite (5-second window)

### The One-Liner
> "When a user removes a favorite, show a 'Undo' snackbar for 5 seconds."

### First Draft
```swift
func unfavorite(_ c: Country) {
    let removed = c
    favorites.remove(c)
    showUndo(removed) { self.favorites.insert(removed) }
}
```

### The Cracks
- **User unfavorites 3 in a row.** Three snackbars? A stacked "Undo" list? Only the latest?
- **User backgrounds the app.** The 5-second countdown pauses? Continues? Cancels?
- **User closes the app.** The delete is committed early? Or reverted?
- **Server sync.** Do you send the delete immediately (and undo means POST it back), or wait 5 seconds (and undo just cancels the pending delete)?
- **User unfavorites, then favorites again from the list.** Undo now means... what?
- **Notification tapped.** External event opens the app during undo — does the countdown continue?
- **Multi-device.** Device A unfavorites; Device B sees the delete immediately. Device A undoes 3 seconds later — Device B needs to re-favorite.

### Hidden Business Rules
- Deletes are **deferred by 5 seconds** — no network call is fired during the undo window.
- If the user takes any other action on the same country during the window, the undo is invalidated (deleted becomes final).
- Backgrounding the app **commits** all pending deletes immediately (the user made peace with them by leaving).
- Only one undo snackbar visible at a time — a new delete replaces the previous snackbar and **commits** the previous delete immediately.

### Layer Consequences
- **Presentation:** the snackbar and countdown.
- **Domain:** an `UnfavoriteWithUndoUseCase` that takes a `commitAfter: TimeInterval` and returns a `pending: Cancellable` handle.
- **Data:** no change — deletes are still just deletes, they just happen later.

The 5-second delay is a business rule ("give the user grace"), so it belongs in Domain, not Presentation.

### Acceptance
- Unfavoriting a country instantly removes it from the visible list.
- The snackbar shows "Removed — Undo" with a 5-second visible countdown.
- Tapping Undo restores the item; no network call was made.
- Waiting 5 seconds fires the delete network call.
- Backgrounding during the window commits the delete.
- Unfavoriting a second country replaces the snackbar and commits the first delete.

### Hints
- Combine: `Timer.publish(every: 1, on: .main, in: .common)` for the countdown display.
- `Task.sleep(for: .seconds(5))` in the UseCase, cancellable by the caller.
- Listen to `ScenePhase` transitions and cancel-with-commit on `.background`.

---

## Task D8 — "Last Viewed" Ordering

### The One-Liner
> "In the country list, show the countries the user opened most recently at the top."

### First Draft
```swift
.onAppear { UserDefaults.standard.set(Date(), forKey: "lastViewed_\(country.id)") }
```

Sort in the VM by reading UserDefaults for each row.

### The Cracks
- **UserDefaults from the View.** Layer leak — `View.onAppear` writes persistence.
- **Sort reads storage.** `body` re-renders often; N UserDefaults reads per render blocks the main thread.
- **What is "viewing"?** Opening the detail? Scrolling past? Being in the visible portion of the list?
- **Guests / privacy.** Some users don't want tracked. Where's the opt-out?
- **Ties.** Never-viewed countries — where do they sort? Alphabetical at the bottom?
- **Sync.** Device A views Vietnam; Device B still doesn't know.
- **Storage size.** 250 country IDs is fine; but if this app grows to 50k items, UserDefaults becomes slow.
- **What triggers "viewed"?** Auto-scroll (accidental) shouldn't count. Deep-link into detail should.

### Hidden Business Rules
- A "view" = **detail screen shown for > 2 seconds** (not a scroll-past).
- Timestamps are **local** — no server sync in v1. Document explicitly.
- Never-viewed items sort **alphabetically** at the bottom of the list.
- The user can toggle "recently viewed sort" on/off in settings; default off (surprise sorts frustrate users).

### Layer Consequences
- **Domain:** `RecordViewUseCase(countryId, at: Date)` + `SortByRecencyUseCase`. Records are timestamped facts, sorting is a query.
- **Data:** `ViewHistoryRepository` — SwiftData with `@Model class ViewRecord { id, timestamp }`. Indexed.
- **Presentation:** dispatches `RecordViewUseCase` after 2-second timer on the detail; **never touches storage directly**.

Anti-pattern: putting `UserDefaults.set` in the View or ViewModel. It works today, breaks the moment you need cross-device sync (Domain change → callsites change).

### Acceptance
- Opening a detail screen for < 2 seconds does not record a view.
- Opening for > 2 seconds records exactly one view (a re-render inside those 2 seconds doesn't record twice).
- Sort-by-recency renders viewed items at the top in reverse-timestamp order.
- Toggling the sort setting off returns to alphabetical instantly.
- No `UserDefaults.` or SwiftData API call appears in a `View` file (grep to verify).

### Hints
- `.task(id: country.id) { try? await Task.sleep(for: .seconds(2)); recordView() }` — task auto-cancels if the view goes away.
- SwiftData `@Query(sort: \.timestamp, order: .reverse)` for the sorted list.

---

## Meta-Patterns You'll See Repeated

After doing 3-4 of these tasks, you'll notice patterns:

| Pattern | What it looks like |
|---|---|
| **Optimistic UI + rollback** | D1 (favorite), D7 (undo delete) |
| **Cancellation of superseded work** | D3 (pagination), D5 (refresh), D6 (rate limit) |
| **Business rule masquerading as UI code** | D2 (dedup/normalize), D4 (nil-handling), D8 (view-counts-as-view) |
| **State-as-enum vs state-as-booleans** | D3 (pagination state machine), D5 (loading state), D7 (undo state) |
| **Layer leakage via persistence** | D2, D8 (UserDefaults temptation from View) |
| **Composition of orthogonal features** | D3 (search × pagination), D4 (group × sort × nil), D5 (refresh × existing load) |

If you can spot these patterns before starting, you'll design the layers right the first time.

---

## Anti-Patterns These Tasks Expose

### ❌ Booleans for state that has more than 2 meanings

```swift
@Published var isLoading = false
@Published var hasMore = true
@Published var errorMessage: String?
```

Three booleans, eight possible states, three of which are illegal (loading + error?). Any UI reading these three has to encode the invalid combinations manually.

```swift
enum ListState {
    case idle
    case loading(page: Int)
    case loaded(items: [Country], page: Int, hasMore: Bool)
    case error(page: Int, message: String)
}
```

Four states, all legal, all exhaustive to switch on.

### ❌ Persistence from a View

```swift
.onAppear { UserDefaults.standard.set(Date(), forKey: key) }
```

If you can move it out of the View, do. Every persistence call in a View is an unpaid loan against your next migration.

### ❌ "Toggle" instead of "Set"

```swift
func toggleFavorite(_ id: String) async throws
```

Not idempotent. Retrying a failed toggle *doubles* the effect.

```swift
func setFavorite(_ id: String, favorite: Bool) async throws
```

Same call sent 3 times = same result. Retryable, cacheable, dedupable.

---

## Suggested Order

Tackle in this order if you want increasing difficulty:

1. **D2** (Recent Searches) — small scope, hits normalization + persistence.
2. **D4** (Group + Sort) — pure Domain work, no async.
3. **D5** (Pull-to-Refresh) — introduces cancellation.
4. **D1** (Favorites) — optimistic UI + failure.
5. **D3** (Pagination) — full state-machine thinking.
6. **D6** (Rate Limiting) — pure Data-layer complexity.
7. **D7** (Undo Delete) — timers + lifecycle + business rules.
8. **D8** (Last Viewed) — cross-cutting persistence + layer discipline.

---

## Related

- [[iOS Tutorial - Part 9 From Tutorial to Real App]] — the straight-forward feature backlog
- [[iOS SwiftUI Architecture - Error Handling]] — enum-based `LoadState` pattern used here
- [[iOS SwiftUI Architecture - Clean Architecture]] — layer rules these tasks exercise
- [[iOS SwiftUI Architecture - MVVM with Combine]] — cancellation + `AnyCancellable` patterns
- [[iOS SwiftUI - SwiftData]] — persistence for D1, D8
- [[iOS SwiftUI - Navigation]] — deep-link edge cases for D8

---

## Apple Docs (Primary Source)

| Topic | URL |
|-------|-----|
| Task cancellation | https://developer.apple.com/documentation/swift/task/cancellationhandler |
| Combine debounce | https://developer.apple.com/documentation/combine/publisher/debounce(for:scheduler:options:) |
| SwiftUI refreshable | https://developer.apple.com/documentation/swiftui/view/refreshable(action:) |
| ScenePhase | https://developer.apple.com/documentation/swiftui/scenephase |
| SwiftData Model | https://developer.apple.com/documentation/swiftdata/model() |
| Human Interface — Feedback | https://developer.apple.com/design/human-interface-guidelines/feedback |
