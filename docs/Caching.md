<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <a href="GettingStarted.md">Getting Started</a> &nbsp;&bull;&nbsp;
  <a href="Interceptors.md">Interceptors</a> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket</a> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation</a> &nbsp;&bull;&nbsp;
  <b>Caching</b> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing</a> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced</a>
</p>

---

# Caching

Fiber provides two levels of caching:

1. **`CacheInterceptor`** — Simple in-memory TTL cache (part of core `Fiber`)
2. **`FiberSharing`** — Advanced caching with disk persistence, stale-while-revalidate, ETag support, and declarative SwiftUI integration

This guide focuses on the advanced caching system in `FiberSharing`.

```swift
import FiberSharing
```

## Table of Contents

- [Cache Policies](#cache-policies)
- [Imperative Caching](#imperative-caching)
- [Declarative Caching](#declarative-caching)
- [Stale-While-Revalidate](#stale-while-revalidate)
- [Conditional Requests (ETag)](#conditional-requests-etag)
- [Cache Invalidation](#cache-invalidation)
- [SharedCacheStore](#sharedcachestore)
- [SharedFiber (Reactive Client)](#sharedfiberclient)
- [Shared Configuration](#shared-configuration)

---

## Cache Policies

`CachePolicy` controls how responses are cached and served:

```swift
let policy = CachePolicy(
    ttl: 300,                        // Time-to-live in seconds
    staleWhileRevalidate: 60,        // Serve stale for N seconds while refreshing
    storageMode: .memoryAndDisk,     // Where to store
    maxEntries: 100                  // LRU eviction limit
)
```

### Built-in Presets

| Preset | TTL | Stale-While-Revalidate | Storage | Max Entries | Use Case |
|--------|-----|----------------------|---------|-------------|----------|
| `.default` | 5 min | 0 | Memory | 100 | General API responses |
| `.aggressive` | 30 min | 60s | Memory + Disk | 200 | Semi-static data (config, feature flags) |
| `.persistent` | 1 hr | 5 min | Disk | 500 | Reference data, catalogs |
| `.noCache` | 0 | 0 | — | 0 | Always fetch fresh |

```swift
// Use a preset
let result = try await fiber.getCached("/users", as: [User].self, policy: .aggressive)

// Or create custom
let custom = CachePolicy(
    ttl: 600,
    staleWhileRevalidate: 120,
    storageMode: .memoryAndDisk,
    maxEntries: 50
)
```

### Storage Modes

| Mode | Behavior |
|------|----------|
| `.memory` | Fast, cleared on app restart |
| `.disk` | Persists across launches, slower |
| `.memoryAndDisk` | Memory-first with disk fallback |

---

## Imperative Caching

Use `SharedFiber` for imperative cached fetching in view models and services:

```swift
let fiber = SharedFiber()

// Basic cached GET — memory → disk → network
let result = try await fiber.getCached("/users", as: [User].self)

// With custom policy
let config = try await fiber.getCached(
    "/config",
    as: AppConfig.self,
    policy: .persistent
)

// With query parameters
let page = try await fiber.getCached(
    "/users",
    as: [User].self,
    query: ["page": "2", "limit": "20"],
    policy: .aggressive
)
```

### CachedResponse Metadata

Every cached response includes metadata about its freshness:

```swift
let result = try await fiber.getCached("/users", as: [User].self)

result.value        // [User] — the decoded data
result.isFresh      // true if within TTL
result.isExpired    // true if past TTL
result.age          // TimeInterval since cached
result.etag         // ETag header from server (if any)
result.lastModified // Last-Modified header (if any)
```

---

## Declarative Caching

Bridge HTTP responses into swift-sharing's `@SharedReader` for reactive, cache-first data fetching in SwiftUI:

```swift
import FiberSharing
import Sharing

struct UsersView: View {
    @SharedReader(.api("/users", as: [User].self))
    var users: CachedResponse<[User]>

    var body: some View {
        List(users?.value ?? []) { user in
            Text(user.name)
        }
        .overlay {
            if users?.isExpired == true {
                ProgressView("Refreshing...")
            }
        }
    }
}
```

### With Custom Policy

```swift
@SharedReader(.api("/users", as: [User].self, policy: .aggressive))
var users: CachedResponse<[User]>
```

### Shorthand with Inline Options

```swift
@SharedReader(.cachedAPI("/config", as: AppConfig.self, ttl: 3600, storage: .disk))
var config: CachedResponse<AppConfig>
```

---

## Stale-While-Revalidate

SWR serves expired data immediately while refreshing in the background, eliminating loading states for returning users:

```swift
let policy = CachePolicy(
    ttl: 300,                    // Fresh for 5 minutes
    staleWhileRevalidate: 60     // Serve stale for 1 more minute while refreshing
)
```

**Timeline:**

```
0:00  — Request → Network fetch → Cache (fresh)
3:00  — Request → Cache hit (fresh, age=3min)
5:30  — Request → Cache hit (stale, age=5.5min) + background refresh
6:01  — Request → Cache hit (stale expired, age=6min) → Network fetch
```

```
  Fresh          Stale (SWR)     Expired
├──────────────┼──────────────┼──────────────►
0             TTL         TTL+SWR          time
              5min           6min
```

In the stale window:
- Returns cached data **immediately** (no loading state)
- Kicks off a background network request
- Next access gets the fresh data

---

## Conditional Requests (ETag)

When a server returns `ETag` or `Last-Modified` headers, subsequent requests automatically include validation headers:

```swift
// First request
let users = try await fiber.getCached("/users", as: [User].self)
// Server responds: 200 OK, ETag: "v1", body: [...]
// users.etag == "\"v1\""

// After TTL expires, second request sends:
// GET /users
// If-None-Match: "v1"

// Server responds: 304 Not Modified (no body)
// Cache is refreshed with a new TTL — no bandwidth wasted
```

This happens transparently. You don't need to manage ETags manually.

---

## Cache Invalidation

```swift
let fiber = SharedFiber()

// Invalidate a specific path
await fiber.invalidateCache(for: "/users")

// Invalidate with specific query params
await fiber.invalidateCache(for: "/users", query: ["page": "1"])

// Invalidate all paths matching a prefix
await fiber.invalidateCacheMatching("GET:/users")
// Matches: /users, /users/1, /users?page=2, etc.

// Nuclear option — clear everything
await fiber.clearCache()
```

### Invalidation After Mutations

A common pattern is to invalidate related caches after a write operation:

```swift
// Create a new user
try await fiber.post("/users", body: newUser)

// Invalidate the users list cache so the next fetch gets fresh data
await fiber.invalidateCacheMatching("GET:/users")
```

---

## SharedCacheStore

The centralized cache actor powering both declarative and imperative caching:

```swift
let store = SharedCacheStore.shared

// Direct access (advanced)
let cached: CachedResponse<[User]>? = await store.get("GET:/users", as: [User].self)

// Set a value manually
await store.set("GET:/users", value: users, policy: .default)

// Invalidation
await store.invalidateAll()
await store.clearDisk()

// Diagnostics
let count = await store.memoryCount
```

In most cases, you won't interact with `SharedCacheStore` directly — use `SharedFiber` or `@SharedReader` instead.

---

## SharedFiber (Reactive Client)

`SharedFiber` reads the shared `FiberConfiguration` and automatically rebuilds the underlying `Fiber` client when configuration changes:

```swift
let fiber = SharedFiber()

// Uses the current @Shared(.fiberConfiguration) values
let response = try await fiber.get("/users")
```

### Custom Configuration Hook

```swift
let fiber = SharedFiber { config, fiberConfig in
    fiberConfig.interceptors = [
        AuthInterceptor(tokenProvider: { config.authToken }),
        RetryInterceptor(),
        LoggingInterceptor(logger: PrintFiberLogger()),
    ]
    fiberConfig.timeout = config.defaultTimeout
}
```

### All SharedFiber Methods

```swift
// Standard HTTP methods
try await fiber.send(request)
try await fiber.get("/path")
try await fiber.post("/path", body: encodable)
try await fiber.put("/path", body: encodable)
try await fiber.patch("/path", body: encodable)
try await fiber.delete("/path")

// Cached methods
try await fiber.getCached("/path", as: Type.self, policy: .default)
await fiber.invalidateCache(for: "/path")
await fiber.invalidateCacheMatching("GET:/users")
await fiber.clearCache()
```

---

## Shared Configuration

`FiberConfiguration` is a shared value type that controls the base URL, auth token, timeout, and default headers:

```swift
import FiberSharing
import Sharing

@Shared(.fiberConfiguration) var config

// Read current values
print(config.baseURL)
print(config.authToken)

// Update from anywhere
$config.withLock {
    $0.baseURL = URL(string: "https://staging.api.com")!
    $0.authToken = "new-token"
    $0.defaultTimeout = 60
    $0.defaultHeaders["X-Feature-Flag"] = "new-ui"
}
```

Changes propagate automatically to all `SharedFiber` instances.

---

<p align="center">
  <a href="Validation.md">&larr; Validation</a> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing &rarr;</a>
</p>
