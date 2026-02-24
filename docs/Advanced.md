<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <a href="GettingStarted.md">Getting Started</a> &nbsp;&bull;&nbsp;
  <a href="Interceptors.md">Interceptors</a> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket</a> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation</a> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching</a> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing</a> &nbsp;&bull;&nbsp;
  <b>Advanced</b>
</p>

---

# Advanced Topics

This guide covers advanced features: distributed tracing, encryption, custom transports, metrics collection, injectable defaults, and swift-dependencies/swift-sharing integrations.

## Table of Contents

- [Distributed Tracing](#distributed-tracing)
- [Encryption](#encryption)
- [Custom Transports](#custom-transports)
- [Metrics Collection](#metrics-collection)
- [Injectable Defaults](#injectable-defaults)
- [swift-dependencies Integration](#swift-dependencies-integration)
- [swift-sharing Integration](#swift-sharing-integration)

---

## Distributed Tracing

Every request in Fiber gets an auto-generated trace ID, propagated through Swift's `TaskLocal` system. This enables end-to-end request correlation across your app.

### Automatic Trace IDs

```swift
let response = try await api.get("/users")
print(response.traceID)  // "A1B2C3D4-E5F6-7890-..."
```

The trace ID is:
- Generated before the interceptor chain runs
- Available inside every interceptor via `TraceContext.traceID`
- Attached to the `FiberResponse`
- Logged by `LoggingInterceptor`

### Accessing Trace Context

```swift
// Inside an interceptor
let myInterceptor = AnyInterceptor("context") { request, next in
    let traceID = TraceContext.traceID
    let spanID = TraceContext.spanID
    let metadata = TraceContext.metadata

    print("[\(traceID)] Processing \(request.httpMethod) \(request.url)")
    return try await next(request)
}
```

### Custom Metadata

Attach arbitrary context to the current trace:

```swift
try await TraceContext.$metadata.withValue([
    "userId": "user_123",
    "feature": "checkout",
    "experiment": "new-flow-v2"
]) {
    // All requests within this scope carry the metadata
    let cart = try await api.get("/cart")
    let order = try await api.post("/orders", body: checkout)
}
```

### Spans

Measure sub-operations within a trace:

```swift
var parseSpan = Span(name: "parseResponse")
let users = try JSONDecoder().decode([User].self, from: response.data)
let finished = parseSpan.finish()
print("Parsing took \(finished.durationMs ?? 0)ms")
```

Spans carry:
- `id` — unique span ID
- `name` — human-readable name
- `traceID` — linked to the current trace
- `parentID` — for nested spans
- `startTime` / `endTime`
- `attributes` — key-value metadata
- `events` — timestamped events within the span

### Trace Export

Ship spans to your observability backend by implementing `TraceExporter`:

```swift
struct JaegerExporter: TraceExporter {
    let endpoint: URL

    func export(_ spans: [Span]) async {
        for span in spans {
            let payload = JaegerSpan(
                traceID: span.traceID,
                spanID: span.id,
                operationName: span.name,
                startTime: span.startTime,
                duration: span.durationMs ?? 0,
                tags: span.attributes
            )
            // Send to Jaeger/Zipkin/OTLP collector
            try? await URLSession.shared.data(for: makeRequest(payload))
        }
    }
}

// In-memory collector for tests
let collector = InMemoryTraceExporter()
// ... make requests ...
let spans = await collector.spans
```

### Custom Trace ID Generator

Override the default UUID-based generator:

```swift
let api = Fiber("https://api.example.com") {
    $0.defaults = FiberDefaults(
        traceIDGenerator: {
            // Use a shorter, more readable format
            let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
            return String((0..<12).map { _ in chars.randomElement()! })
        }
    )
}
```

---

## Encryption

The `EncryptionInterceptor` provides end-to-end encryption for request and response bodies.

### Built-in AES-GCM

```swift
import CryptoKit

let key = SymmetricKey(size: .bits256)
let encryption = EncryptionInterceptor(
    provider: AESGCMEncryptionProvider(key: key),
    encryptRequest: true,
    decryptResponse: true
)

let api = Fiber("https://api.example.com") {
    $0.interceptors = [encryption, logging]  // encryption before logging
}
```

### Initialize from Raw Key Data

```swift
let keyData = Data(base64Encoded: storedKeyString)!
let provider = AESGCMEncryptionProvider(keyData: keyData)
```

### Custom Encryption Provider

Implement `EncryptionProvider` for any algorithm:

```swift
struct ChaChaPolyProvider: EncryptionProvider {
    let key: SymmetricKey

    func encrypt(_ data: Data) throws -> Data {
        let sealed = try ChaChaPoly.seal(data, using: key)
        return sealed.combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: data)
        return try ChaChaPoly.open(box, using: key)
    }
}
```

### Selective Encryption

Encrypt only requests or only responses:

```swift
// Encrypt outgoing bodies, but server responds in plaintext
let sendEncrypted = EncryptionInterceptor(
    provider: AESGCMEncryptionProvider(key: key),
    encryptRequest: true,
    decryptResponse: false
)

// Server sends encrypted, we decrypt
let receiveEncrypted = EncryptionInterceptor(
    provider: AESGCMEncryptionProvider(key: key),
    encryptRequest: false,
    decryptResponse: true
)
```

---

## Custom Transports

The `FiberTransport` protocol abstracts the underlying HTTP mechanism. Swap it for testing, custom implementations, or alternative networking stacks.

```swift
public protocol FiberTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}
```

### Default: URLSession

```swift
let api = Fiber("https://api.example.com") {
    $0.transport = URLSessionTransport(session: .shared)
}
```

### Custom Session Configuration

```swift
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 60
config.httpAdditionalHeaders = ["X-Custom": "value"]
config.waitsForConnectivity = true

let session = URLSession(configuration: config)
let api = Fiber("https://api.example.com") {
    $0.transport = URLSessionTransport(session: session)
}
```

### Custom Transport Example: Logging Transport

```swift
struct LoggingTransport: FiberTransport {
    let wrapped: any FiberTransport

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        print("[Transport] \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
        let start = Date()
        let (data, response) = try await wrapped.send(request)
        let elapsed = Date().timeIntervalSince(start)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[Transport] \(status) in \(elapsed)s (\(data.count) bytes)")
        return (data, response)
    }
}
```

---

## Metrics Collection

### Built-in Collector

```swift
let collector = InMemoryMetricsCollector()
let metrics = MetricsInterceptor(collector: collector)

let api = Fiber("https://api.example.com") {
    $0.interceptors = [metrics]
}

// Make some requests...
try await api.get("/users")
try await api.post("/orders", body: order)

// Query metrics
let avg = await collector.averageDurationMs      // 142.5
let rate = await collector.successRate            // 0.95
let all = await collector.metrics                 // [RequestMetrics]

for m in all {
    print("\(m.method) \(m.url) → \(m.statusCode) in \(m.durationMs)ms")
}
```

### Custom Metrics Backend

```swift
struct PrometheusCollector: MetricsCollector {
    func collect(_ metrics: RequestMetrics) async {
        Prometheus.histogram(
            "http_request_duration_ms",
            value: metrics.durationMs,
            labels: [
                "method": metrics.method,
                "status": "\(metrics.statusCode)",
                "path": extractPath(metrics.url)
            ]
        )
        Prometheus.counter(
            "http_requests_total",
            labels: [
                "method": metrics.method,
                "status": "\(metrics.statusCode)"
            ]
        )
    }
}
```

### RequestMetrics Fields

| Field | Type | Description |
|-------|------|-------------|
| `traceID` | `String` | Trace ID for correlation |
| `method` | `String` | HTTP method ("GET", "POST") |
| `url` | `String` | Full request URL |
| `statusCode` | `Int` | HTTP status code |
| `requestSize` | `Int` | Request body size in bytes |
| `responseSize` | `Int` | Response body size in bytes |
| `durationMs` | `Double` | Request duration in ms |
| `timestamp` | `Date` | When the request was made |
| `success` | `Bool` | True for 2xx responses |

---

## Injectable Defaults

All hardcoded constants in Fiber are centralized in `FiberDefaults`. This makes every behavior configurable and testable.

### Global Override

```swift
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
```

### Per-Component Override

```swift
let retry = RetryInterceptor(
    maxRetries: 3,
    defaults: FiberDefaults(exponentialBackoffBase: 3.0)
)
```

### Per-Client Override

```swift
let api = Fiber("https://api.example.com") {
    $0.defaults = FiberDefaults(
        traceIDGenerator: { "app-\(UUID().uuidString.prefix(8))" }
    )
}
```

### Reference

| Property | Default | Used By |
|----------|---------|---------|
| `jitterFraction` | 0.25 | RetryInterceptor, ReconnectionStrategy |
| `exponentialBackoffBase` | 2.0 | RetryInterceptor, ReconnectionStrategy |
| `loggingSystemName` | "HTTP" | LoggingInterceptor |
| `logBodyTruncationLimit` | 1000 | LoggingInterceptor |
| `rateLimitSleepIncrement` | 0.1s | RateLimitInterceptor |
| `jsonContentType` | "application/json" | FiberRequest.jsonBody() |
| `traceIDGenerator` | UUID().uuidString | Fiber.send() |
| `webSocketDefaultCloseCode` | 1000 | WebSocket close methods |

---

## swift-dependencies Integration

`FiberDependencies` integrates with [Point-Free's swift-dependencies](https://github.com/pointfreeco/swift-dependencies) for dependency injection.

### Dependency Keys

Three dependency keys are provided:

```swift
import FiberDependencies

// 1. Struct-of-closures HTTP client (most flexible for testing)
@Dependency(\.fiberHTTPClient) var httpClient

// 2. Full Fiber instance
@Dependency(\.fiber) var fiber

// 3. Injectable defaults
@Dependency(\.fiberDefaults) var defaults
```

### FiberHTTPClient

A struct-of-closures design that's easy to stub in tests:

```swift
@Dependency(\.fiberHTTPClient) var httpClient

func fetchUsers() async throws -> [User] {
    let response = try await httpClient.get("/users", [:], [:])
    return try response.decode()
}
```

### Live Client Setup

```swift
// From an existing Fiber instance
let client = FiberHTTPClient.live(myFiber)

// From a base URL with configuration
let client = FiberHTTPClient.live("https://api.example.com") {
    $0.interceptors = [auth, retry, logging]
}
```

### Full Fiber as Dependency

```swift
@Dependency(\.fiber) var fiber

func fetchUsers() async throws -> [User] {
    try await fiber.get("/users").decode()
}

// Configure at app entry point
withDependencies {
    $0.fiber = Fiber("https://api.example.com") {
        $0.interceptors = [auth, retry, logging]
    }
} operation: {
    // All code using @Dependency(\.fiber) gets this instance
}
```

### Testing with Dependencies

```swift
import FiberDependenciesTesting

@Test func featureLoadsUsers() async throws {
    await withDependencies {
        $0.fiberHTTPClient = .stub(.ok(body: #"[{"id": 1, "name": "Alice"}]"#))
    } operation: {
        let feature = UsersFeature()
        await feature.load()
        #expect(feature.users.count == 1)
    }
}

@Test func featureHandlesError() async throws {
    await withDependencies {
        $0.fiberHTTPClient = .stub(.serverError())
    } operation: {
        let feature = UsersFeature()
        await feature.load()
        #expect(feature.error != nil)
    }
}
```

---

## swift-sharing Integration

`FiberSharing` integrates with [Point-Free's swift-sharing](https://github.com/pointfreeco/swift-sharing) for reactive configuration and declarative API caching.

### Shared Configuration

```swift
import FiberSharing
import Sharing

@Shared(.fiberConfiguration) var config

// Read
print(config.baseURL)
print(config.authToken)

// Update
$config.withLock {
    $0.baseURL = URL(string: "https://staging.api.com")!
    $0.authToken = newToken
    $0.defaultTimeout = 60
    $0.defaultHeaders["X-Feature"] = "new-ui"
}
```

### SharedFiber (Reactive Client)

```swift
let fiber = SharedFiber()

// Automatically uses current @Shared(.fiberConfiguration)
// Rebuilds when config changes
let response = try await fiber.get("/users")
```

### Declarative API Caching

```swift
import Sharing

@SharedReader(.api("/users", as: [User].self))
var users: CachedResponse<[User]>

@SharedReader(.cachedAPI("/config", as: AppConfig.self, ttl: 3600, storage: .disk))
var config: CachedResponse<AppConfig>
```

For a complete caching guide, see [Caching](Caching.md).

---

<p align="center">
  <a href="Testing.md">&larr; Testing</a> &nbsp;&bull;&nbsp;
  <a href="Examples.md">Real-World Examples &rarr;</a>
</p>
