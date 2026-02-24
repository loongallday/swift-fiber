# Fiber

A functional, Axios-style HTTP networking library for Swift. Chainable requests, composable interceptors, distributed tracing, WebSocket support, and first-class testability. Zero third-party dependencies.

```swift
let fiber = Fiber("https://api.example.com") {
    $0.interceptors = [auth, retry, logging, cache]
}

let users: [User] = try await fiber.get("/users", query: ["page": "1"]).decode()
```

## Features

- **Functional & Chainable** -- Immutable value types with composable combinators
- **Interceptor Pipeline** -- Axios-style request/response interceptors
- **7 Built-in Interceptors** -- Auth, retry, cache, logging, metrics, encryption, rate limit
- **Distributed Tracing** -- TaskLocal-based trace propagation with spans
- **WebSocket** -- Protocol-based with auto-reconnection strategies
- **100% Testable** -- MockTransport, StubResponse builders, MockWebSocket pairs
- **Swift 6 Strict Concurrency** -- Sendable throughout, no data races
- **Injectable Defaults** -- All constants centralized in FiberDefaults
- **swift-dependencies** -- Optional Point-Free integration (FiberDependencies)
- **swift-sharing** -- Optional reactive config + declarative API caching (FiberSharing)
- **Zero Core Dependencies** -- Core module uses only Foundation, OSLog, and CryptoKit

## Requirements

- Swift 6.0+
- iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/your-org/swift-fiber.git", from: "1.0.0")
]
```

Add the targets you need:

```swift
.target(name: "MyApp", dependencies: [
    "Fiber",                    // Core HTTP client
    "FiberWebSocket",           // WebSocket support
    "FiberDependencies",        // swift-dependencies integration (optional)
    "FiberSharing",             // swift-sharing integration (optional)
    "FiberTesting",             // Mock infrastructure (test target only)
    "FiberDependenciesTesting", // Test helpers for FiberDependencies (test only)
])
```

## Quick Start

### Basic Requests

```swift
import Fiber

let fiber = Fiber("https://api.example.com")

// GET
let response = try await fiber.get("/users")
let users: [User] = try response.decode()

// POST with Encodable body
let newUser = CreateUser(name: "Alice", email: "alice@example.com")
let created: User = try await fiber.post("/users", body: newUser).decode()

// PUT, PATCH, DELETE
try await fiber.put("/users/1", body: updatedUser)
try await fiber.patch("/users/1", body: PatchUser(name: "Bob"))
try await fiber.delete("/users/1")
```

### Chainable Request Builder

Requests are immutable value types. Every combinator returns a new copy:

```swift
let request = FiberRequest(url: "https://api.example.com/search")
    .method(.post)
    .header("Authorization", "Bearer tok")
    .header("Accept-Language", "en")
    .query("q", "swift")
    .query("page", "1")
    .jsonBody(SearchParams(filter: "active"))
    .timeout(30)
    .meta("cache", "skip")  // arbitrary metadata for interceptors

let response = try await fiber.send(request)
```

The original request is never mutated:

```swift
let base = FiberRequest(url: "https://api.example.com/users")
let withAuth = base.header("Authorization", "Bearer tok")
// base.headers is still empty
```

### Response Handling

```swift
let response = try await fiber.get("/users")

// Decode JSON
let users: [User] = try response.decode()

// Status checks
response.isSuccess      // 200-299
response.isClientError  // 400-499
response.isServerError  // 500-599

// Raw access
response.text           // UTF-8 string
response.data           // Raw Data
response.statusCode     // Int
response.duration       // TimeInterval
response.traceID        // Auto-generated trace ID
response.header("Content-Type")  // Case-insensitive lookup

// Validation chain
let validated = try response
    .validateStatus()  // throws on non-2xx
    .validate { r in   // custom validation
        guard r.header("X-Version") != nil else {
            throw MyError.missingVersion
        }
    }
```

---

## Interceptors

Interceptors are the core extensibility mechanism. They form a pipeline around every request, like Axios interceptors or Express middleware.

```
Request --> [Auth] --> [Retry] --> [Cache] --> [Logging] --> Transport --> Response
                                                               |
Response <-- [Auth] <-- [Retry] <-- [Cache] <-- [Logging] <---+
```

### Writing Interceptors

**As a closure** (quickest):

```swift
let timing = AnyInterceptor("timing") { request, next in
    let start = Date()
    let response = try await next(request)
    print("Request took \(Date().timeIntervalSince(start))s")
    return response
}
```

**As a struct** (reusable):

```swift
struct APIKeyInterceptor: Interceptor {
    let name = "apiKey"
    let key: String

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        try await next(request.header("X-API-Key", key))
    }
}
```

**Short-circuit** (return without calling `next`):

```swift
let cached = AnyInterceptor("offlineCache") { request, next in
    if let cached = OfflineStore.get(request.url) {
        return FiberResponse(data: cached, statusCode: 200, request: request)
    }
    return try await next(request)
}
```

### Built-in Interceptors

#### AuthInterceptor

Injects Bearer tokens and handles automatic 401 refresh:

```swift
let auth = AuthInterceptor(
    tokenProvider: { await tokenStore.accessToken },
    tokenRefresher: { try await tokenStore.refresh() },  // optional
    headerName: "Authorization",     // default
    headerPrefix: "Bearer ",         // default
    isUnauthorized: { $0.statusCode == 401 }  // default
)
```

#### RetryInterceptor

Exponential backoff with jitter for transient failures:

```swift
let retry = RetryInterceptor(
    maxRetries: 3,
    baseDelay: 0.5,        // seconds
    maxDelay: 30,
    retryableStatusCodes: [408, 429, 500, 502, 503, 504],
    retryableMethods: [.get, .head, .options, .put, .delete],
    shouldRetry: { error in
        (error as? URLError)?.code == .timedOut
    }
)
```

#### CacheInterceptor

In-memory TTL cache for GET/HEAD requests:

```swift
let cache = CacheInterceptor(
    ttl: 300,           // 5 minutes
    maxEntries: 100,
    cacheableMethods: [.get, .head]
)

// Programmatic eviction
await cache.clear()
await cache.evict(url: "/config")
```

#### LoggingInterceptor

Structured request/response logging:

```swift
let logging = LoggingInterceptor(logger: OSLogFiberLogger(subsystem: "com.myapp"))
```

Output:
```
[→ GET /users] trace=A1B2C3
[← 200 OK] 42ms trace=A1B2C3
```

#### MetricsInterceptor

Performance metrics collection:

```swift
let collector = InMemoryMetricsCollector()
let metrics = MetricsInterceptor(collector: collector)

// After requests...
let avg = await collector.averageDurationMs
let rate = await collector.successRate
let all = await collector.metrics  // [RequestMetrics]
```

Implement `MetricsCollector` for custom backends:

```swift
struct DataDogCollector: MetricsCollector {
    func collect(_ metrics: RequestMetrics) async {
        // Send to DataDog, Prometheus, etc.
    }
}
```

#### EncryptionInterceptor

Encrypts request bodies, decrypts response bodies:

```swift
import CryptoKit

// Built-in AES-GCM
let key = SymmetricKey(size: .bits256)
let encryption = EncryptionInterceptor(
    provider: AESGCMEncryptionProvider(key: key),
    encryptRequest: true,
    decryptResponse: true
)

// Or plug in your own
struct ChaChaEncryption: EncryptionProvider {
    func encrypt(_ data: Data) throws -> Data { /* ... */ }
    func decrypt(_ data: Data) throws -> Data { /* ... */ }
}
```

#### RateLimitInterceptor

Client-side token bucket rate limiting:

```swift
let rateLimit = RateLimitInterceptor(
    maxRequests: 60,
    perInterval: 60.0,   // 60 requests per minute
    maxWait: 30.0        // wait up to 30s for a slot, then throw
)
```

### Composing Interceptors

Pass interceptors in the order you want them to execute. The first interceptor is outermost (processes the request first, the response last):

```swift
let fiber = Fiber("https://api.example.com") {
    $0.interceptors = [
        auth,         // 1st: inject token
        retry,        // 2nd: retry on failure
        rateLimit,    // 3rd: throttle
        cache,        // 4th: return cached if available
        logging,      // 5th: log the final request/response
        metrics,      // 6th: collect timing
    ]
}
```

---

## Type-Safe Endpoints

Define your API surface as value types:

```swift
struct GetUser: Endpoint {
    typealias Response = User
    let id: String
    var path: String { "/users/\(id)" }
    var method: HTTPMethod { .get }
}

struct CreateUser: Endpoint {
    typealias Response = User
    let body: Data?

    var path: String { "/users" }
    var method: HTTPMethod { .post }

    init(name: String, email: String) {
        self.body = try? JSONEncoder().encode(["name": name, "email": email])
    }
}

struct SearchUsers: Endpoint {
    typealias Response = [User]
    let query: String
    var path: String { "/users" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] { [URLQueryItem(name: "q", value: query)] }
}

// Usage
let user = try await fiber.request(GetUser(id: "123"))
let results = try await fiber.request(SearchUsers(query: "alice"))
```

---

## Distributed Tracing

Every request gets an auto-generated trace ID, propagated through Swift's `TaskLocal` system:

```swift
let response = try await fiber.get("/users")
print(response.traceID)  // "A1B2C3D4-..."
```

Access the current trace ID inside interceptors:

```swift
let logger = AnyInterceptor("logger") { request, next in
    let traceID = TraceContext.traceID
    print("[\(traceID)] \(request.httpMethod) \(request.url)")
    return try await next(request)
}
```

### Spans

Measure sub-operations within a trace:

```swift
var span = Span(name: "parseResponse")
// ... do work ...
let finished = span.finish()
print("Took \(finished.durationMs ?? 0)ms")
```

### Custom Metadata

Attach arbitrary context to the trace:

```swift
try await TraceContext.$metadata.withValue(["userId": "123", "feature": "search"]) {
    let response = try await fiber.get("/search")
}
```

### Trace Export

Implement `TraceExporter` to ship spans to your observability backend:

```swift
struct JaegerExporter: TraceExporter {
    func export(_ spans: [Span]) async {
        for span in spans {
            // Send to Jaeger, Zipkin, OTLP, etc.
        }
    }
}
```

---

## WebSocket

### Protocol

```swift
import FiberWebSocket

let ws = URLSessionWebSocketTransport.connect(to: URL(string: "wss://ws.example.com")!)

for await event in ws.events {
    switch event {
    case .connected:
        try await ws.send(.text("hello"))
    case .message(.text(let text)):
        print("Received: \(text)")
    case .message(.binary(let data)):
        print("Binary: \(data.count) bytes")
    case .disconnected(let code, let reason):
        print("Disconnected: \(code ?? 0) \(reason ?? "")")
    case .error(let error):
        print("Error: \(error)")
    }
}
```

### Typed Messages

```swift
struct ChatMessage: Codable {
    let user: String
    let text: String
}

// Send as JSON
try await ws.send(.json(ChatMessage(user: "alice", text: "hello")))

// Decode received
if case .message(let msg) = event {
    let chat: ChatMessage = try msg.decode()
}
```

### Auto-Reconnection

```swift
let ws = ReconnectingWebSocket(
    connect: { URLSessionWebSocketTransport.connect(to: myURL) },
    strategy: .exponentialBackoff(baseDelay: 1, maxDelay: 30, maxAttempts: 10)
)

Task { await ws.start() }

for await event in ws.events {
    // Automatically reconnects on disconnection
}

// Built-in strategies:
ReconnectionStrategy.exponentialBackoff()     // 1s, 2s, 4s, 8s... + jitter
ReconnectionStrategy.fixedDelay(5.0)          // 5s, 5s, 5s...
ReconnectionStrategy.linearBackoff()          // 1s, 2s, 3s, 4s...
ReconnectionStrategy.none                     // no reconnection
```

---

## Injectable Defaults (FiberDefaults)

All hardcoded constants are centralized in `FiberDefaults`. Override them globally or per-component:

```swift
// Override globally at app startup
FiberDefaults.shared = FiberDefaults(
    jitterFraction: 0.5,
    exponentialBackoffBase: 3.0,
    loggingSystemName: "NET",
    logBodyTruncationLimit: 2000,
    rateLimitSleepIncrement: 0.2,
    jsonContentType: "application/vnd.api+json",
    traceIDGenerator: { UUID().uuidString.lowercased() },
    webSocketDefaultCloseCode: 1001
)

// Or per-component
let retry = RetryInterceptor(
    maxRetries: 3,
    defaults: FiberDefaults(exponentialBackoffBase: 3.0)
)

// Or via the builder
let fiber = Fiber("https://api.example.com") {
    $0.defaults = FiberDefaults(traceIDGenerator: { "custom-\(Date())" })
}
```

| Constant | Default | Used In |
|----------|---------|---------|
| `jitterFraction` | 0.25 | RetryInterceptor, ReconnectionStrategy |
| `exponentialBackoffBase` | 2.0 | RetryInterceptor, ReconnectionStrategy |
| `loggingSystemName` | "HTTP" | LoggingInterceptor |
| `logBodyTruncationLimit` | 1000 | LoggingInterceptor |
| `rateLimitSleepIncrement` | 0.1 | RateLimitInterceptor |
| `jsonContentType` | "application/json" | FiberRequest.jsonBody() |
| `traceIDGenerator` | UUID().uuidString | Fiber.send() |
| `webSocketDefaultCloseCode` | 1000 | WebSocket close methods |

---

## swift-dependencies Integration (FiberDependencies)

Optional integration with [Point-Free's swift-dependencies](https://github.com/pointfreeco/swift-dependencies).

### Struct-of-Closures Client

```swift
import FiberDependencies

// In your feature:
@Dependency(\.fiberHTTPClient) var httpClient

let response = try await httpClient.get("/users", [:], [:])
let users: [User] = try response.decode()
```

### Overriding in Tests

```swift
withDependencies {
    $0.fiberHTTPClient.get = { path, query, headers in
        FiberResponse.empty  // or build a custom response
    }
} operation: {
    // your code under test
}
```

### Live Client Setup

```swift
// From an existing Fiber instance
let client = FiberHTTPClient.live(myFiber)

// Or directly from a base URL
let client = FiberHTTPClient.live("https://api.example.com") {
    $0.interceptors = [authInterceptor, retryInterceptor]
}
```

### Full Fiber as Dependency

```swift
@Dependency(\.fiber) var fiber

// Configure at app startup:
withDependencies {
    $0.fiber = Fiber("https://api.example.com") {
        $0.interceptors = [auth, retry, logging]
    }
} operation: {
    // app code
}
```

### FiberDefaults as Dependency

```swift
@Dependency(\.fiberDefaults) var defaults

// Override in tests:
withDependencies {
    $0.fiberDefaults = FiberDefaults(traceIDGenerator: { "fixed-trace-id" })
} operation: { ... }
```

### Test Helpers (FiberDependenciesTesting)

```swift
import FiberDependenciesTesting

// Client backed by MockTransport
let (client, mock) = FiberHTTPClient.test()
mock.stubAll(StubResponse.ok(body: "{\"ok\": true}"))
let response = try await client.get("/health", [:], [:])

// Simple stub client
let client = FiberHTTPClient.stub(.ok(body: "stubbed"))
```

---

## swift-sharing Integration (FiberSharing)

Optional integration with [Point-Free's swift-sharing](https://github.com/pointfreeco/swift-sharing) for reactive configuration and declarative API caching.

### Shared Configuration

```swift
import FiberSharing
import Sharing

@Shared(.fiberConfiguration) var config

// Update config from anywhere:
$config.withLock { $0.baseURL = "https://staging.api.com" }
$config.withLock { $0.authToken = "new-token" }
```

### SharedFiber — Reactive Client

```swift
let shared = SharedFiber()

// Reads current @Shared(.fiberConfiguration) and builds a Fiber client.
// Automatically rebuilds when config changes.
let response = try await shared.get("/users")
```

### Custom Configuration Hook

```swift
let shared = SharedFiber { config, fiberConfig in
    fiberConfig.interceptors = [
        AuthInterceptor(tokenProvider: { config.authToken })
    ]
    fiberConfig.timeout = config.defaultTimeout
}
```

### Declarative API Caching

Bridge Fiber HTTP into swift-sharing's `@SharedReader` for reactive, cache-first data fetching:

```swift
import FiberSharing
import Sharing

// Declarative — data is fetched and cached automatically.
// Memory -> disk -> network fallback with TTL expiration.
@SharedReader(.api("/users", as: [User].self))
var users: CachedResponse<[User]>

// With custom cache policy
@SharedReader(.api("/users", as: [User].self, policy: .aggressive))
var aggressiveUsers: CachedResponse<[User]>

// Shorthand with custom TTL and storage
@SharedReader(.cachedAPI("/config", as: AppConfig.self, ttl: 3600, storage: .disk))
var config: CachedResponse<AppConfig>
```

Access cache metadata on responses:

```swift
if let users = users {
    print(users.value)       // [User] — the decoded data
    print(users.isFresh)     // true if within TTL
    print(users.isExpired)   // true if past TTL
    print(users.age)         // seconds since cached
    print(users.etag)        // ETag header, if server sent one
}
```

### Imperative Cached Fetching

For view models and one-off requests:

```swift
let fiber = SharedFiber()

// Cache-first fetch: memory -> disk -> network
let result = try await fiber.getCached("/users", as: [User].self)
print(result.value)   // [User]
print(result.isFresh) // true

// With custom policy
let config = try await fiber.getCached(
    "/config", as: AppConfig.self,
    policy: .persistent  // 1hr TTL, disk-backed
)

// With query parameters
let page = try await fiber.getCached(
    "/users", as: [User].self,
    query: ["page": "2", "limit": "20"],
    policy: .aggressive
)
```

### Cache Policies

Built-in presets for common scenarios:

| Preset | TTL | Stale-While-Revalidate | Storage | Max Entries |
|--------|-----|----------------------|---------|-------------|
| `.default` | 5 min | 0 | Memory | 100 |
| `.aggressive` | 30 min | 60s | Memory + Disk | 200 |
| `.noCache` | 0 | 0 | -- | 0 |
| `.persistent` | 1 hr | 5 min | Disk | 500 |

Create custom policies:

```swift
let custom = CachePolicy(
    ttl: 600,                           // 10 minutes
    staleWhileRevalidate: 120,          // serve stale for 2 more min while refreshing
    storageMode: .memoryAndDisk,
    maxEntries: 50
)
```

### Conditional Requests (ETag / Last-Modified)

When a server returns `ETag` or `Last-Modified` headers, subsequent requests automatically include `If-None-Match` or `If-Modified-Since`. On `304 Not Modified`, the cache TTL is refreshed without re-downloading data:

```swift
// First request: server returns ETag: "v1"
let users = try await fiber.getCached("/users", as: [User].self)
// users.etag == "\"v1\""

// Second request (after TTL expires): sends If-None-Match: "v1"
// Server returns 304 -> cached data is refreshed, no bandwidth wasted
let refreshed = try await fiber.getCached("/users", as: [User].self)
```

### Stale-While-Revalidate

Serve expired data immediately while refreshing in the background:

```swift
let policy = CachePolicy(
    ttl: 300,                    // Fresh for 5 minutes
    staleWhileRevalidate: 60     // Serve stale for 1 more minute while refreshing
)

// If cache is 6 minutes old (expired but within stale window):
// - Returns stale data immediately
// - Kicks off background refresh
// - Next access gets fresh data
let result = try await fiber.getCached("/feed", as: [FeedItem].self, policy: policy)
```

### Cache Invalidation

```swift
let fiber = SharedFiber()

// Invalidate a specific path
await fiber.invalidateCache(for: "/users")

// Invalidate with query params
await fiber.invalidateCache(for: "/users", query: ["page": "1"])

// Invalidate all paths matching a prefix
await fiber.invalidateCacheMatching("GET:/users")  // /users, /users/1, /users?page=2

// Clear everything (memory + disk)
await fiber.clearCache()
```

### SharedCacheStore

The centralized cache manager is an actor shared between declarative and imperative APIs:

```swift
let store = SharedCacheStore.shared

// Direct access (advanced usage)
let cached: CachedResponse<[User]>? = await store.get("GET:/users", as: [User].self)
await store.invalidateAll()
await store.clearDisk()
print(await store.memoryCount)
```

---

## Testing

Fiber ships with `FiberTesting`, a dedicated module for writing tests against your networking code without hitting real servers.

### MockTransport

Drop-in replacement for URLSession:

```swift
import FiberTesting

let mock = MockTransport()
mock.stubAll(.ok(body: #"{"id": 1, "name": "Alice"}"#))

let fiber = Fiber(baseURL: URL(string: "https://api.example.com")!, transport: mock)
let response = try await fiber.get("/users/1")

#expect(response.statusCode == 200)
#expect(mock.requests.count == 1)
#expect(mock.lastRequest?.url?.path == "/users/1")
```

### Conditional Stubs

```swift
mock.stub { req in
    if req.url?.path == "/users" {
        return .ok(body: #"[{"id": 1}]"#)
    }
    return nil  // fall through to next stub
}

mock.stub { req in
    if req.httpMethod == "DELETE" {
        return .noContent()
    }
    return nil
}

// Default fallback for unmatched requests
mock.stubDefault { _ in .notFound() }
```

### StubResponse Builder

Chainable, like everything else:

```swift
let stub = StubResponse.ok()
    .header("X-Request-Id", "abc123")
    .header("Content-Type", "application/json")
    .body(#"{"users": []}"#)

// From Encodable
let stub = StubResponse.ok().jsonBody(User(id: 1, name: "Alice"))

// Factory methods
StubResponse.ok()           // 200
StubResponse.created()      // 201
StubResponse.noContent()    // 204
StubResponse.badRequest()   // 400
StubResponse.unauthorized() // 401
StubResponse.notFound()     // 404
StubResponse.serverError()  // 500
```

### MockWebSocket

Paired fakes for WebSocket testing:

```swift
let (client, server) = MockWebSocket.pair()

// Simulate server sending a message
try await server.send(.text("hello from server"))

// Client receives it
for await event in client.events {
    if case .message(.text(let text)) = event {
        #expect(text == "hello from server")
    }
}

// Test disconnection
client.close(code: 1000, reason: "done")
#expect(client.state == .disconnected)
#expect(server.state == .disconnected)
```

### Testing Interceptors

```swift
@Test func authInterceptorInjectsToken() async throws {
    let auth = AuthInterceptor(tokenProvider: { "my-token" })
    let mock = MockTransport()
    mock.stubAll(.ok())

    let fiber = Fiber(baseURL: url, interceptors: [auth], transport: mock)
    _ = try await fiber.get("/secure")

    let header = mock.lastRequest?.value(forHTTPHeaderField: "Authorization")
    #expect(header == "Bearer my-token")
}
```

### Testing Tracing

```swift
let collector = TestTraceCollector()
let logging = LoggingInterceptor(logger: collector.logger())

let fiber = Fiber(baseURL: url, interceptors: [logging], transport: mock)
_ = try await fiber.get("/test")

#expect(collector.logs.count >= 2)  // request + response logged
```

---

## Custom Transport

Swap the underlying HTTP transport for any environment:

```swift
struct MyCustomTransport: FiberTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // Your custom networking implementation
    }
}

let fiber = Fiber("https://api.example.com") {
    $0.transport = MyCustomTransport()
}
```

---

## Configuration

```swift
let fiber = Fiber("https://api.example.com") {
    $0.interceptors = [auth, retry, logging]
    $0.transport = URLSessionTransport(session: mySession)
    $0.defaultHeaders = [
        "Accept": "application/json",
        "X-Client-Version": "1.0.0"
    ]
    $0.timeout = 30
    $0.decoder = myDecoder    // custom JSONDecoder
    $0.encoder = myEncoder    // custom JSONEncoder
    $0.logger = OSLogFiberLogger(subsystem: "com.myapp.fiber")
    $0.validateStatus = { (200..<400).contains($0) }  // treat 3xx as success
}
```

---

## Error Handling

```swift
do {
    let user: User = try await fiber.get("/users/1").decode()
} catch let error as FiberError {
    switch error {
    case .httpError(let statusCode, let data, let response):
        print("HTTP \(statusCode): \(String(data: data, encoding: .utf8) ?? "")")
    case .decodingError(let underlying, let data):
        print("Failed to decode: \(underlying)")
        print("Raw response: \(String(data: data, encoding: .utf8) ?? "")")
    case .networkError(let underlying):
        print("Network failure: \(underlying.localizedDescription)")
    case .timeout:
        print("Request timed out")
    case .cancelled:
        print("Request was cancelled")
    case .interceptor(let name, let underlying):
        print("Interceptor '\(name)' failed: \(underlying)")
    case .invalidURL(let string):
        print("Bad URL: \(string)")
    case .encodingError(let underlying):
        print("Encoding failed: \(underlying)")
    }
}
```

---

## Architecture

```
swift-fiber/
├── Sources/
│   ├── Fiber/                          # Core HTTP client (zero dependencies)
│   │   ├── FiberClient.swift               # Fiber class + Endpoint protocol
│   │   ├── FiberDefaults.swift             # Injectable constants
│   │   ├── FiberRequest.swift              # Immutable request + combinators
│   │   ├── FiberResponse.swift             # Response + decode/validate
│   │   ├── FiberTransport.swift            # Transport protocol + URLSession
│   │   ├── Interceptor.swift               # Interceptor protocol + chain
│   │   ├── FiberError.swift                # Typed errors
│   │   ├── FiberLogger.swift               # Logger protocol + implementations
│   │   ├── TraceContext.swift              # TaskLocal tracing + spans
│   │   ├── Auth/Retry/Cache/Logging/Metrics/Encryption/RateLimit Interceptors
│   ├── FiberWebSocket/                 # WebSocket support
│   │   ├── FiberWebSocket.swift            # Protocol + events
│   │   ├── WebSocketMessage.swift          # Typed messages
│   │   ├── URLSessionWebSocket.swift       # URLSession transport
│   │   └── ReconnectionStrategy.swift      # Auto-reconnect
│   ├── FiberDependencies/              # swift-dependencies integration
│   │   ├── FiberHTTPClient.swift           # Struct-of-closures client
│   │   ├── FiberHTTPClient+Live.swift      # Live implementation
│   │   ├── FiberHTTPClient+DependencyKey.swift
│   │   ├── FiberClient+DependencyKey.swift
│   │   └── FiberDefaults+DependencyKey.swift
│   ├── FiberSharing/                   # swift-sharing integration + caching
│   │   ├── FiberConfiguration.swift        # Shared config value type
│   │   ├── FiberConfigurationKey.swift     # SharedReaderKey for config
│   │   ├── SharedFiber.swift               # Reactive client
│   │   ├── SharedFiber+Cache.swift         # Imperative cached fetching
│   │   ├── CachePolicy.swift              # Configurable cache behavior
│   │   ├── CachedResponse.swift           # Response wrapper with metadata
│   │   ├── SharedCacheStore.swift         # Actor-based LRU cache + disk
│   │   ├── APIResponseKey.swift           # SharedReaderKey for API data
│   │   └── APIResponseKey+Extensions.swift # .api() / .cachedAPI() syntax
│   ├── FiberDependenciesTesting/       # Test helpers
│   │   └── FiberHTTPClient+Testing.swift
│   └── FiberTesting/                   # Test infrastructure
│       ├── MockTransport.swift             # Request recording + stubs
│       ├── StubResponse.swift              # Response builders
│       ├── MockWebSocket.swift             # Paired fakes
│       └── TestTraceCollector.swift        # Trace assertions
└── Tests/
    ├── FiberTests/                     # 35 core tests
    └── FiberIntegrationTests/          # 57 integration tests (92 total)
```

## License

MIT
