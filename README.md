<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0+-F05138?style=flat&logo=swift&logoColor=white" alt="Swift 6.0+" />
  <img src="https://img.shields.io/badge/Platforms-iOS_15+_|_macOS_12+_|_tvOS_15+_|_watchOS_8+-blue?style=flat" alt="Platforms" />
  <img src="https://img.shields.io/badge/SPM-Compatible-brightgreen?style=flat&logo=swift" alt="SPM Compatible" />
  <img src="https://img.shields.io/badge/Dependencies-Zero_(Core)-orange?style=flat" alt="Zero Dependencies" />
  <img src="https://img.shields.io/badge/Concurrency-Sendable_✓-purple?style=flat" alt="Sendable" />
  <img src="https://img.shields.io/badge/License-MIT-lightgrey?style=flat" alt="MIT License" />
</p>

# Fiber

A **functional**, Axios-style HTTP networking library for Swift. Immutable value types, composable interceptors, distributed tracing, WebSocket support, and first-class testability. Zero third-party dependencies in core.

```swift
let fiber = Fiber("https://api.example.com") {
    $0.interceptors = [auth, retry, cache, logging]
}

let users: [User] = try await fiber.get("/users", query: ["page": "1"]).decode()
```

---

<p align="center">
  <a href="#why-fiber">Why Fiber</a> &nbsp;&bull;&nbsp;
  <a href="#quick-start">Quick Start</a> &nbsp;&bull;&nbsp;
  <a href="#features">Features</a> &nbsp;&bull;&nbsp;
  <a href="#installation">Installation</a> &nbsp;&bull;&nbsp;
  <a href="#documentation">Documentation</a> &nbsp;&bull;&nbsp;
  <a href="#comparison">Comparison</a> &nbsp;&bull;&nbsp;
  <a href="#architecture">Architecture</a>
</p>

---

## Why Fiber

Most Swift HTTP libraries are built around mutable objects — session managers, request adapters, response serializers. Fiber takes a different approach: **everything is a value**.

Requests are immutable structs. Interceptors are pure functions. Responses are value types with chainable transforms. No reference semantics, no shared mutable state, no data races.

```swift
// Requests are values — every method returns a new copy
let base = FiberRequest(url: "https://api.example.com/users")
let withAuth = base.header("Authorization", "Bearer tok")
// base.headers is still empty — withAuth has the header

// Interceptors are functions — compose them like middleware
let pipeline = [auth, retry, cache, logging]

// Responses are values — chain transforms without mutation
let users: [User] = try response.validateStatus().decode()
```

### Pros

- **Functional & Immutable** — Value types everywhere. No shared mutable state. No data races. Every combinator returns a new copy.
- **Composable Middleware** — Interceptors compose like functions. Build complex pipelines from small, testable pieces. Auth, retry, cache, rate limit, encryption — all stackable.
- **Zero Core Dependencies** — Core module uses only Foundation, OSLog, and CryptoKit. No dependency tree to manage.
- **Swift 6 Strict Concurrency** — `Sendable` throughout. Actor-based caches and rate limiters. TaskLocal tracing. No `@unchecked` escape hatches in your code.
- **First-Class Testability** — `MockTransport` records requests and returns stubs. `MockWebSocket.pair()` creates paired fakes. No protocol witnesses or heavyweight mocking frameworks needed.
- **Modular** — Use only what you need. Core HTTP, WebSocket, validation, caching, and dependency injection are separate modules.
- **Type-Safe Endpoints** — Define your API as value types. Get compile-time guarantees on response types.
- **Production Interceptors** — 7 built-in interceptors cover auth, retry, cache, logging, metrics, encryption, and rate limiting — all battle-tested patterns.

### Cons

- **iOS 15+ / macOS 12+** — Requires Swift 6.0 and modern Apple platforms. No support for Linux or older OS versions.
- **URLSession Only** — Built on URLSession. If you need custom transport layers (e.g., gRPC, QUIC), you must implement the `FiberTransport` protocol.
- **No Upload/Download Progress** — Focused on JSON API communication. No built-in progress tracking for large file transfers.
- **Young Library** — Newer than Alamofire or Moya. Smaller community and ecosystem.
- **Functional Learning Curve** — If your team is used to OOP networking patterns, the immutable/compositional style may require adjustment.

---

## Quick Start

### Basic Requests

```swift
import Fiber

let api = Fiber("https://api.example.com")

// GET with JSON decoding
let users: [User] = try await api.get("/users").decode()

// POST with Encodable body
let created: User = try await api.post("/users", body: NewUser(name: "Alice")).decode()

// All HTTP verbs
try await api.put("/users/1", body: updated)
try await api.patch("/users/1", body: PatchUser(name: "Bob"))
try await api.delete("/users/1")
```

### Chainable Request Builder

```swift
let request = FiberRequest(url: "https://api.example.com/search")
    .method(.post)
    .header("Authorization", "Bearer tok")
    .query("q", "swift")
    .query("page", "1")
    .jsonBody(SearchParams(filter: "active"))
    .timeout(30)
    .meta("cache", "skip")

let response = try await api.send(request)
```

### Response Handling

```swift
let response = try await api.get("/users")

response.statusCode              // 200
response.isSuccess               // true (200-299)
response.duration                // 0.142s
response.traceID                 // "A1B2C3D4-..."
response.header("Content-Type")  // "application/json"

let validated = try response
    .validateStatus()            // throws on non-2xx
    .decode([User].self)         // decode JSON
```

### Type-Safe Endpoints

```swift
struct GetUser: Endpoint {
    typealias Response = User
    let id: String
    var path: String { "/users/\(id)" }
    var method: HTTPMethod { .get }
}

let user = try await api.request(GetUser(id: "123"))  // User, not FiberResponse
```

### Production Client

```swift
let api = Fiber("https://api.example.com") {
    $0.interceptors = [
        AuthInterceptor(
            tokenProvider: { await tokenStore.accessToken },
            tokenRefresher: { try await tokenStore.refresh() }
        ),
        RetryInterceptor(maxRetries: 3, baseDelay: 0.5),
        RateLimitInterceptor(maxRequests: 60, perInterval: 60),
        CacheInterceptor(ttl: 300, maxEntries: 100),
        LoggingInterceptor(logger: OSLogFiberLogger(subsystem: "com.myapp")),
        MetricsInterceptor(collector: InMemoryMetricsCollector()),
    ]
    $0.defaultHeaders = ["Accept": "application/json"]
    $0.timeout = 30
    $0.decoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
```

---

## Features

| Feature | Description | Module |
|---------|-------------|--------|
| **Chainable Requests** | Immutable request builder with functional combinators | `Fiber` |
| **Interceptor Pipeline** | Composable middleware — modify requests, responses, or short-circuit | `Fiber` |
| **7 Built-in Interceptors** | Auth, retry, cache, logging, metrics, encryption, rate limit | `Fiber` |
| **Type-Safe Endpoints** | Define API as value types with associated response types | `Fiber` |
| **Distributed Tracing** | TaskLocal trace IDs, spans, and pluggable exporters | `Fiber` |
| **Rich Error Types** | Typed errors with status codes, response data, and context | `Fiber` |
| **WebSocket** | Protocol-based with typed messages and AsyncStream events | `FiberWebSocket` |
| **Auto-Reconnection** | Exponential backoff, fixed delay, linear, or custom strategies | `FiberWebSocket` |
| **Domain Validation** | Result-builder DSL for composable model validation | `FiberValidation` |
| **Validation Interceptor** | Validate request bodies before they hit the network | `FiberValidation` |
| **Mock Transport** | Record requests, return stubs, assert on request contents | `FiberTesting` |
| **Mock WebSocket** | Paired fakes for bidirectional WebSocket testing | `FiberTesting` |
| **Declarative Caching** | `@SharedReader`-based cache-first data fetching | `FiberSharing` |
| **Stale-While-Revalidate** | Serve stale data instantly while refreshing in background | `FiberSharing` |
| **ETag / Conditional Requests** | Automatic `If-None-Match` / `304 Not Modified` handling | `FiberSharing` |
| **Shared Configuration** | Reactive config that rebuilds the client on change | `FiberSharing` |
| **Dependency Injection** | Struct-of-closures client for swift-dependencies | `FiberDependencies` |
| **Injectable Defaults** | Every constant centralized and overridable | `Fiber` |

---

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/your-org/swift-fiber.git", from: "1.0.0")
]
```

Add only the modules you need:

```swift
.target(name: "MyApp", dependencies: [
    "Fiber",                    // Core HTTP client (zero third-party deps)
    "FiberWebSocket",           // WebSocket support
    "FiberValidation",          // Domain validation DSL
    "FiberDependencies",        // swift-dependencies integration
    "FiberSharing",             // swift-sharing + declarative caching
]),
.testTarget(name: "MyAppTests", dependencies: [
    "FiberTesting",             // MockTransport, StubResponse, MockWebSocket
    "FiberDependenciesTesting", // Test helpers for dependency injection
]),
```

### Module Dependency Graph

```
Fiber (zero deps)
├── FiberWebSocket
├── FiberValidation (zero deps)
├── FiberTesting
├── FiberDependencies ── swift-dependencies
│   └── FiberDependenciesTesting
└── FiberSharing ── swift-sharing
```

---

## Documentation

Detailed guides for every feature area:

| Guide | Description |
|-------|-------------|
| **[Getting Started](docs/GettingStarted.md)** | Installation, first request, core concepts, configuration reference |
| **[Interceptors](docs/Interceptors.md)** | Writing custom interceptors, all 7 built-ins, composition patterns, recommended pipeline order |
| **[WebSocket](docs/WebSocket.md)** | Connecting, typed messages, AsyncStream events, auto-reconnection strategies |
| **[Validation](docs/Validation.md)** | Result-builder DSL, 12 built-in rules, nested/collection/conditional validation, async rules |
| **[Caching](docs/Caching.md)** | Cache policies, imperative & declarative caching, SWR, ETag, invalidation |
| **[Testing](docs/Testing.md)** | MockTransport, StubResponse, MockWebSocket, testing interceptors, dependency testing |
| **[Advanced](docs/Advanced.md)** | Distributed tracing, encryption, custom transports, metrics, injectable defaults, integrations |
| **[Real-World Examples](docs/Examples.md)** | E-commerce, social feed, multi-tenant SaaS, offline-first, analytics, FiberSharing multi-env, FiberDependencies feature module |

---

## Interceptors at a Glance

Interceptors form a bidirectional pipeline around every request:

```
Request ──► [Auth] ──► [Retry] ──► [Cache] ──► [Logging] ──► Transport
                                                                 │
Response ◄── [Auth] ◄── [Retry] ◄── [Cache] ◄── [Logging] ◄────┘
```

Write one as a closure:

```swift
let timing = AnyInterceptor("timing") { request, next in
    let start = Date()
    let response = try await next(request)
    print("\(request.httpMethod) \(request.url.path) took \(Date().timeIntervalSince(start))s")
    return response
}
```

Or as a reusable struct:

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

### Built-in Interceptors

| Interceptor | What It Does |
|-------------|-------------|
| [`AuthInterceptor`](docs/Interceptors.md#authinterceptor) | Injects Bearer tokens, handles 401 refresh with automatic retry |
| [`RetryInterceptor`](docs/Interceptors.md#retryinterceptor) | Exponential backoff with jitter for transient failures |
| [`CacheInterceptor`](docs/Interceptors.md#cacheinterceptor) | In-memory TTL cache with LRU eviction |
| [`LoggingInterceptor`](docs/Interceptors.md#logginginterceptor) | Structured request/response logging with trace IDs |
| [`MetricsInterceptor`](docs/Interceptors.md#metricsinterceptor) | Collects duration, size, and success rate per request |
| [`EncryptionInterceptor`](docs/Interceptors.md#encryptioninterceptor) | AES-GCM or custom encryption for request/response bodies |
| [`RateLimitInterceptor`](docs/Interceptors.md#ratelimitinterceptor) | Token bucket rate limiter with configurable wait |

[Full Interceptors Guide →](docs/Interceptors.md)

---

## WebSocket

```swift
import FiberWebSocket

let ws = URLSessionWebSocketTransport.connect(to: URL(string: "wss://ws.example.com")!)

for await event in ws.events {
    switch event {
    case .connected:
        try await ws.sendJSON(ChatMessage(user: "alice", text: "hello"))
    case .message(let msg):
        if let chat: ChatMessage = try? msg.decode() { print(chat) }
    case .disconnected(let code, _):
        print("Disconnected: \(code ?? 0)")
    case .error(let error):
        print("Error: \(error)")
    }
}
```

Auto-reconnection with configurable strategies:

```swift
let ws = ReconnectingWebSocket(
    connect: { URLSessionWebSocketTransport.connect(to: myURL) },
    strategy: .exponentialBackoff(baseDelay: 1, maxDelay: 30, maxAttempts: 10)
)
Task { await ws.start() }
```

| Strategy | Delays |
|----------|--------|
| `.exponentialBackoff()` | 1s, 2s, 4s, 8s... + jitter |
| `.fixedDelay(5.0)` | 5s, 5s, 5s... |
| `.linearBackoff()` | 1s, 2s, 3s, 4s... |
| `.none` | No reconnection |

[Full WebSocket Guide →](docs/WebSocket.md)

---

## Validation

Composable, type-safe domain validation with a result-builder DSL:

```swift
import FiberValidation

let validateUser = Validator<User> {
    Validate(\.name, label: "name") {
        ValidationRule.notEmpty(message: "Name is required")
        ValidationRule.minLength(2)
        ValidationRule.maxLength(100)
    }
    Validate(\.email, label: "email") {
        ValidationRule.email()
    }
    Validate(\.age, label: "age") {
        ValidationRule.range(18...120)
    }
}

let result = validateUser.validate(user)
// result.isValid, result.errorItems, result.warningItems
```

Supports nested objects, collections, conditional rules, async validation, and severity levels. Integrates with Fiber's interceptor pipeline via `ValidationInterceptor`.

[Full Validation Guide →](docs/Validation.md)

---

## Caching

Advanced caching via `FiberSharing` with disk persistence, stale-while-revalidate, and ETag support:

```swift
import FiberSharing

let fiber = SharedFiber()

// Cache-first: memory → disk → network
let result = try await fiber.getCached("/users", as: [User].self, policy: .aggressive)
result.value      // [User]
result.isFresh    // true if within TTL
result.age        // seconds since cached

// Declarative with @SharedReader
@SharedReader(.api("/users", as: [User].self))
var users: CachedResponse<[User]>
```

| Preset | TTL | SWR | Storage |
|--------|-----|-----|---------|
| `.default` | 5 min | 0 | Memory |
| `.aggressive` | 30 min | 60s | Memory + Disk |
| `.persistent` | 1 hr | 5 min | Disk |
| `.noCache` | 0 | 0 | — |

[Full Caching Guide →](docs/Caching.md)

---

## Testing

```swift
import FiberTesting

let mock = MockTransport()
mock.stubAll(.ok(body: #"[{"id": 1, "name": "Alice"}]"#))

let api = Fiber(baseURL: URL(string: "https://api.example.com")!, transport: mock)
let users: [User] = try await api.get("/users").decode()

#expect(users.count == 1)
#expect(mock.requests.count == 1)
#expect(mock.lastRequest?.url?.path == "/users")
```

Conditional stubs, chainable `StubResponse` builders, `MockWebSocket.pair()` for bidirectional testing, `TestTraceCollector` for log assertions.

[Full Testing Guide →](docs/Testing.md)

---

## Comparison

| Feature | Fiber | Alamofire | Moya | URLSession |
|---------|-------|-----------|------|------------|
| **Paradigm** | Functional, immutable | OOP, mutable | OOP, enum-based | OOP, delegate |
| **Request type** | Immutable struct | Mutable request | Enum target | Mutable URLRequest |
| **Middleware** | Composable interceptors | RequestAdapter/Retrier | Plugin protocol | None |
| **Built-in interceptors** | 7 (auth, retry, cache, log, metrics, encryption, rate limit) | 2 (retry, auth) | 0 (plugins only) | 0 |
| **WebSocket** | Protocol + reconnection | None | None | Low-level API |
| **Validation DSL** | Result-builder, type-safe | Parameter encoding | None | None |
| **Distributed tracing** | TaskLocal trace IDs + spans | None | None | None |
| **End-to-end encryption** | AES-GCM interceptor | None | None | None |
| **Rate limiting** | Token bucket interceptor | None | None | None |
| **Testability** | MockTransport + StubResponse | URLProtocol subclass | Stub closures | URLProtocol subclass |
| **Caching** | TTL + SWR + ETag + disk | URLCache | URLCache | URLCache |
| **swift-dependencies** | First-class integration | None | None | None |
| **swift-sharing** | Declarative @SharedReader | None | None | None |
| **Swift 6 concurrency** | Sendable throughout | Partial | Partial | Partial |
| **Core dependencies** | 0 (Foundation only) | 0 | Alamofire | 0 |

---

## Architecture

```
swift-fiber/
├── Sources/
│   ├── Fiber/                          Core HTTP client (zero dependencies)
│   │   ├── FiberClient.swift               Fiber client + Endpoint protocol
│   │   ├── FiberRequest.swift              Immutable request + combinators
│   │   ├── FiberResponse.swift             Response + decode/validate
│   │   ├── Interceptor.swift               Interceptor protocol + chain builder
│   │   ├── FiberError.swift                Typed error enum
│   │   ├── FiberTransport.swift            Transport protocol + URLSession
│   │   ├── FiberLogger.swift               Logger protocol + Print/OSLog impls
│   │   ├── FiberDefaults.swift             Injectable constants
│   │   ├── TraceContext.swift              TaskLocal tracing + spans
│   │   └── Interceptors/                   7 built-in interceptors
│   │       ├── AuthInterceptor.swift
│   │       ├── RetryInterceptor.swift
│   │       ├── CacheInterceptor.swift
│   │       ├── LoggingInterceptor.swift
│   │       ├── MetricsInterceptor.swift
│   │       ├── EncryptionInterceptor.swift
│   │       └── RateLimitInterceptor.swift
│   ├── FiberWebSocket/                 WebSocket support
│   │   ├── FiberWebSocket.swift            Protocol + events + state
│   │   ├── WebSocketMessage.swift          text/binary/json messages
│   │   ├── URLSessionWebSocket.swift       URLSession transport
│   │   └── ReconnectionStrategy.swift      Auto-reconnect strategies
│   ├── FiberValidation/                Domain model validation
│   │   ├── Validator.swift                 Composed Validator<T>
│   │   ├── ValidationRule.swift            12 built-in rules
│   │   ├── ValidatorBuilder.swift          @ValidatorBuilder + @RuleBuilder
│   │   ├── PropertyValidator.swift         Validate<Root, Value>
│   │   ├── CollectionValidator.swift       ValidateEach
│   │   ├── ConditionalValidator.swift      ValidateIf
│   │   └── ValidationInterceptor.swift     Fiber integration
│   ├── FiberSharing/                   swift-sharing + caching
│   │   ├── SharedFiber.swift               Reactive client
│   │   ├── CachePolicy.swift              TTL, SWR, storage modes
│   │   ├── CachedResponse.swift           Value + freshness metadata
│   │   ├── SharedCacheStore.swift         Actor-based LRU + disk
│   │   └── APIResponseKey.swift           @SharedReader integration
│   ├── FiberDependencies/              swift-dependencies integration
│   │   ├── FiberHTTPClient.swift           Struct-of-closures client
│   │   └── *+DependencyKey.swift           Dependency keys
│   ├── FiberTesting/                   Test infrastructure
│   │   ├── MockTransport.swift             Request recording + stubs
│   │   ├── StubResponse.swift              Chainable response builder
│   │   ├── MockWebSocket.swift             Paired fakes
│   │   └── TestTraceCollector.swift        Log assertions
│   └── FiberDependenciesTesting/       Dependency test helpers
└── Tests/                              147 tests
    ├── FiberTests/                         35 core tests
    ├── FiberIntegrationTests/              57 integration tests
    └── FiberValidationTests/               55 validation tests
```

---

## License

MIT

---

<p align="center">
  <a href="docs/GettingStarted.md"><b>Get Started →</b></a>
</p>
