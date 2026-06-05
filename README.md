# CoreDataRepo

![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![iOS](https://img.shields.io/badge/iOS-18.0+-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)

A reactive query system for Core Data built on Combine.  
No `NSFetchedResultsController`. No incremental diffing.  
A clean, notification-driven requery pipeline with predictable state streaming.

## The idea

`NSFetchedResultsController` is a capable tool — but it binds you to a delegate pattern,
carries UIKit-era assumptions, and adds architectural friction in SwiftUI and
domain-driven codebases.

CoreDataRepo takes a different approach: when the store changes, **invalidate and refetch**.

```
store change → notification → invalidation → full fetch → published state
```

This is not incremental streaming. It is a notification-driven full refetch —
the right tradeoff when **simplicity and predictability** matter more than diff accuracy.

## What's inside

### `NSManagedObjectContext` extensions

A concurrency-safe fetch and count layer that covers both sync and async call sites.

**Sync fetch** — runs on the caller's queue, suitable for `performAndWait` blocks:

```swift
let results = context.fetch(
    TaskEntity.self,
    for: NSPredicate(format: "isDone == NO"),
    sorting: [NSSortDescriptor(key: "createdAt", ascending: false)]
)
```

**Async fetch** — always executes inside `perform`, correct queue guaranteed:

```swift
let results = await context.fetchAsync(
    TaskEntity.self,
    predicate: NSPredicate(format: "isDone == NO"),
    sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
    limit: 50,
    debug: true
)
```

Both variants return an empty array on error rather than throwing.  
The optional `debug` parameter enables per-call logging — you decide when it's active.  
Async variants use `@unchecked Sendable` wrappers for predicate and sort descriptors
to satisfy Swift concurrency without copying.

`count` and `countAsync` follow the same pattern.

**Save helpers** — async and sync variants that post a refresh notification on success:

```swift
let saved = await context.saveChanges()         // async, posts on MainActor
let saved = context.saveChangesSync()           // sync, posts via DispatchQueue.main
```

The `push` parameter lets you suppress the notification when the save
should not trigger a UI refresh.

---

### `DataRepo<Entity>`

A generic reactive repository. Publishes full result snapshots as a `[Entity]` stream.

```swift
let repo = DataRepo<TaskEntity>(
    context: container.viewContext,
    for: NSPredicate(format: "isDone == NO"),
    sort: [NSSortDescriptor(key: "createdAt", ascending: false)]
)

repo.items
    .sink { tasks in /* update view */ }
    .store(in: &cancellables)
```

Predicate can be updated at any time — the pipeline re-fetches immediately:

```swift
repo.fetch(for: NSPredicate(format: "isDone == YES"))
```

**Pipeline internals:**
- Triggered by `refresher` notification (default: `.managedContextChanged`)
- `prepend` fires one immediate fetch on subscription — no empty initial state
- `combineLatest` with the predicate subject — predicate changes also trigger refetch
- `throttle(0.3s)` on a background scheduler coalesces rapid saves
- `switchToLatest` cancels in-flight fetches when a new trigger arrives
- Task cancellation propagated back into `fetchAsync` via `handleEvents(receiveCancel:)`
- Result delivered on `DispatchQueue.main`

---

### `DataCounter<Entity>`

Counts entities across multiple named predicates simultaneously.  
Useful for badges, tab counts, or any UI that needs several counts kept in sync.

```swift
let counter = DataCounter<TaskEntity>(
    context: container.viewContext,
    for: [
        "active": NSPredicate(format: "isDone == NO"),
        "done":   NSPredicate(format: "isDone == YES"),
        "urgent": NSPredicate(format: "priority == 2")
    ]
)

counter.items
    .sink { counts in
        let active = counts["active"] ?? 0
        let urgent = counts["urgent"] ?? 0
    }
    .store(in: &cancellables)
```

Predicates can be replaced at runtime:

```swift
counter.count(for: ["overdue": overduePredicate])
```

**Pipeline:** same notification + `combineLatest` pattern as `DataRepo`,
using `performAndWait` and sync `count()` per predicate.

---

### Predicates convenience

```swift
NSPredicate.truePredicate   // NSPredicate(value: true)
NSPredicate.falsePredicate  // NSPredicate(value: false)
```

`falsePredicate` is used as the default state in both `DataRepo` and `DataCounter` —
nothing is fetched until a real predicate is provided.

---

### Custom refresh notification

Both `DataRepo` and `DataCounter` accept a custom `refresher: Notification.Name`.
The default is `.managedContextChanged`, posted automatically by `saveChanges`.

If you manage Core Data saves elsewhere, post this notification manually:

```swift
NotificationCenter.default.post(name: .managedContextChanged, object: nil)
```

Or pass your own notification name to keep different repos on separate channels.

---

## Where it fits well

- **SwiftUI apps** with no UIKit layer
- **Domain-driven architecture** — repos as plain Swift objects, no view coupling
- **Long-lived contexts** — main context + background merge, widget + app group setups
- **Apps where simplicity matters more than diff accuracy** — no index paths,
  no `NSFetchedResultsControllerDelegate`, no move/insert/delete bookkeeping

## Where it fits less well

- Tables or collections that rely on animated row-level diffing
- Very large datasets where full refetch per change is too expensive

## Requirements

- iOS 15+ / macOS 12+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Darktau/CoreDataRepo", from: "1.0.0")
]
```

## License

MIT
