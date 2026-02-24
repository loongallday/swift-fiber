<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <a href="GettingStarted.md">Getting Started</a> &nbsp;&bull;&nbsp;
  <b>Interceptors</b> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket</a> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation</a> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching</a> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing</a> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced</a>
</p>

---

# Interceptors

Interceptors are the core extensibility mechanism in Fiber. They form a bidirectional middleware pipeline around every HTTP request — like Axios interceptors, Express middleware, or OkHttp interceptors.

## Table of Contents

- [How Interceptors Work](#how-interceptors-work)
- [Writing Custom Interceptors](#writing-custom-interceptors)
- [Built-in Interceptors](#built-in-interceptors)
  - [AuthInterceptor](#authinterceptor)
  - [RetryInterceptor](#retryinterceptor)
  - [CacheInterceptor](#cacheinterceptor)
  - [LoggingInterceptor](#logginginterceptor)
  - [MetricsInterceptor](#metricsinterceptor)
  - [EncryptionInterceptor](#encryptioninterceptor)
  - [RateLimitInterceptor](#ratelimitinterceptor)
- [Composing Interceptors](#composing-interceptors)
- [Recommended Pipeline Order](#recommended-pipeline-order)
- [Advanced Patterns](#advanced-patterns)

---

## How Interceptors Work

Every request flows through the interceptor chain before reaching the network transport. Each interceptor can modify the request, modify the response, short-circuit the chain, or add side effects.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Interceptor Chain                        │
│                                                                 │
│  Request ──► [Auth] ──► [Retry] ──► [Cache] ──► [Logging] ──►  │
│                                                         │       │
│                                                    Transport    │
│                                                         │       │
│  Response ◄── [Auth] ◄── [Retry] ◄── [Cache] ◄── [Logging] ◄  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key concept:** Each interceptor receives the request and a `next` function. Calling `next(request)` passes the request to the next interceptor in the chain. The final interceptor in the chain calls the transport to make the actual HTTP request.

```swift
public protocol Interceptor: Sendable {
    var name: String { get }
    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse
}
```

---

## Writing Custom Interceptors

### Closure-Based (Quick & Simple)

Use `AnyInterceptor` for one-off interceptors:

```swift
let timing = AnyInterceptor("timing") { request, next in
    let start = Date()
    let response = try await next(request)
    let elapsed = Date().timeIntervalSince(start)
    print("[\(request.httpMethod.rawValue) \(request.url.path)] \(elapsed)s")
    return response
}
```

### Struct-Based (Reusable & Configurable)

For production interceptors, implement the `Interceptor` protocol:

```swift
struct APIKeyInterceptor: Interceptor {
    let name = "apiKey"
    let key: String

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let modified = request.header("X-API-Key", key)
        return try await next(modified)
    }
}
```

### Common Patterns

**Modify the request** (add headers, query params, etc.):

```swift
let addCorrelationID = AnyInterceptor("correlationID") { request, next in
    let modified = request.header("X-Correlation-ID", UUID().uuidString)
    return try await next(modified)
}
```

**Modify the response** (transform data, add metadata):

```swift
let unwrapEnvelope = AnyInterceptor("unwrap") { request, next in
    let response = try await next(request)
    // Unwrap { "data": ... } envelope
    struct Envelope: Decodable { let data: AnyCodable }
    if let envelope = try? JSONDecoder().decode(Envelope.self, from: response.data) {
        return FiberResponse(
            data: envelope.data.rawData,
            statusCode: response.statusCode,
            headers: response.headers,
            request: response.request,
            duration: response.duration,
            traceID: response.traceID
        )
    }
    return response
}
```

**Short-circuit** (return without calling `next`):

```swift
let maintenanceMode = AnyInterceptor("maintenance") { request, next in
    if AppState.isInMaintenance {
        throw AppError.maintenanceMode
    }
    return try await next(request)
}
```

**Retry on failure** (call `next` multiple times):

```swift
let simpleRetry = AnyInterceptor("simpleRetry") { request, next in
    do {
        return try await next(request)
    } catch {
        // One retry on any failure
        return try await next(request)
    }
}
```

---

## Built-in Interceptors

Fiber ships with 7 production-ready interceptors.

### AuthInterceptor

Injects authentication tokens into every request and handles automatic token refresh on 401 responses.

```swift
let auth = AuthInterceptor(
    tokenProvider: { await tokenStore.accessToken },
    tokenRefresher: { try await tokenStore.refresh() },
    headerName: "Authorization",                          // default
    headerPrefix: "Bearer ",                              // default
    isUnauthorized: { $0.statusCode == 401 }              // default
)
```

**How it works:**

1. Before every request, calls `tokenProvider` to get the current token
2. Injects it as `Authorization: Bearer <token>`
3. If the response matches `isUnauthorized` (401 by default):
   - Calls `tokenRefresher` to get a new token
   - Retries the original request with the new token
   - If refresh fails, throws the original error

**Customizing for API key auth:**

```swift
let apiKeyAuth = AuthInterceptor(
    tokenProvider: { Keychain.apiKey },
    headerName: "X-API-Key",
    headerPrefix: ""                    // no prefix
)
```

---

### RetryInterceptor

Automatically retries failed requests with exponential backoff and jitter.

```swift
let retry = RetryInterceptor(
    maxRetries: 3,                                              // default: 3
    baseDelay: 0.5,                                             // default: 0.5s
    maxDelay: 30,                                               // default: 30s
    retryableStatusCodes: [408, 429, 500, 502, 503, 504],      // default
    retryableMethods: [.get, .head, .options, .put, .delete],   // default (safe methods)
    shouldRetry: { error in                                     // custom error filter
        (error as? URLError)?.code == .timedOut
    }
)
```

**Backoff formula:**

```
delay = min(baseDelay * 2^attempt, maxDelay) * (1 ± jitter)
```

**Safety:** By default, only idempotent methods are retried. POST is excluded because retrying a non-idempotent request could create duplicate resources. Override `retryableMethods` if your POST endpoints are idempotent.

| Attempt | Base Delay | With Jitter (±25%) |
|---------|-----------|-------------------|
| 1 | 0.5s | 0.38s – 0.63s |
| 2 | 1.0s | 0.75s – 1.25s |
| 3 | 2.0s | 1.50s – 2.50s |

---

### CacheInterceptor

In-memory TTL cache for GET and HEAD requests with LRU eviction.

```swift
let cache = CacheInterceptor(
    ttl: 300,                          // 5 minutes (default)
    maxEntries: 100,                   // LRU eviction limit (default)
    cacheableMethods: [.get, .head]    // default
)
```

**How it works:**

1. On a cacheable request, checks if a valid (non-expired) entry exists
2. If found, returns the cached response immediately (no network call)
3. If not found, calls `next`, caches the response, and returns it

**Programmatic eviction:**

```swift
// Clear a specific URL
await cache.evict(url: "/users/42")

// Clear the entire cache
await cache.clear()
```

> **Note:** For more advanced caching (disk persistence, stale-while-revalidate, ETag support), see the [Caching guide](Caching.md) which covers `FiberSharing`'s `SharedCacheStore`.

---

### LoggingInterceptor

Structured request/response logging with trace ID propagation.

```swift
let logging = LoggingInterceptor(
    logger: OSLogFiberLogger(subsystem: "com.myapp"),
    logBody: false          // default — set to true for debugging
)
```

**Output:**

```
[HTTP] [→ GET /users] trace=A1B2C3D4
[HTTP] [← 200 OK] 42ms trace=A1B2C3D4
```

**With body logging enabled:**

```
[HTTP] [→ POST /users] trace=E5F6G7H8
[HTTP]   Body: {"name":"Alice","email":"alice@example.com"}
[HTTP] [← 201 Created] 89ms trace=E5F6G7H8
[HTTP]   Body: {"id":42,"name":"Alice","email":"alice@examp...
```

Bodies are truncated at `FiberDefaults.logBodyTruncationLimit` (default: 1000 characters).

---

### MetricsInterceptor

Collects performance metrics for every request.

```swift
let collector = InMemoryMetricsCollector()
let metrics = MetricsInterceptor(collector: collector)

// After making requests...
let avgDuration = await collector.averageDurationMs   // 142.5
let successRate = await collector.successRate          // 0.95
let allMetrics  = await collector.metrics              // [RequestMetrics]
```

**RequestMetrics fields:**

```swift
public struct RequestMetrics: Sendable {
    public let traceID: String
    public let method: String       // "GET"
    public let url: String          // "https://api.example.com/users"
    public let statusCode: Int      // 200
    public let requestSize: Int     // bytes
    public let responseSize: Int    // bytes
    public let durationMs: Double   // 142.5
    public let timestamp: Date
    public let success: Bool        // true for 2xx
}
```

**Custom backends** — implement `MetricsCollector` for production observability:

```swift
struct DataDogCollector: MetricsCollector {
    func collect(_ metrics: RequestMetrics) async {
        DataDog.track(
            metric: "http.request.duration",
            value: metrics.durationMs,
            tags: [
                "method:\(metrics.method)",
                "status:\(metrics.statusCode)",
                "success:\(metrics.success)"
            ]
        )
    }
}
```

---

### EncryptionInterceptor

End-to-end encryption for request/response bodies using pluggable encryption providers.

```swift
import CryptoKit

// Built-in AES-GCM encryption
let key = SymmetricKey(size: .bits256)
let encryption = EncryptionInterceptor(
    provider: AESGCMEncryptionProvider(key: key),
    encryptRequest: true,          // encrypt outgoing bodies
    decryptResponse: true          // decrypt incoming bodies
)
```

**Custom encryption provider:**

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

---

### RateLimitInterceptor

Client-side token bucket rate limiter that prevents your app from exceeding API rate limits.

```swift
let rateLimit = RateLimitInterceptor(
    maxRequests: 60,          // 60 requests
    perInterval: 60.0,        // per 60 seconds
    maxWait: 30.0             // wait up to 30s for a slot, then throw
)
```

**Behavior:**

- If a request slot is available, the request proceeds immediately
- If all slots are used, the interceptor waits (up to `maxWait`) for a slot to free up
- If `maxWait` is exceeded, throws `RateLimitError.exceeded`

```swift
do {
    let response = try await api.get("/resource")
} catch let error as RateLimitError {
    // RateLimitError.exceeded(limit: 60, interval: 60.0)
    print("Rate limited: \(error)")
}
```

---

## Composing Interceptors

Pass interceptors in the order you want them to execute. The **first** interceptor is outermost — it processes the request first and the response last:

```swift
let api = Fiber("https://api.example.com") {
    $0.interceptors = [
        auth,         // 1. Inject auth token
        retry,        // 2. Retry on transient failures
        rateLimit,    // 3. Throttle to stay within limits
        cache,        // 4. Return cached response if available
        logging,      // 5. Log the final request/response
        metrics,      // 6. Collect performance metrics
    ]
}
```

### Execution Order Visualization

```
Request enters:  auth → retry → rateLimit → cache → logging → metrics → [Network]
Response exits:  auth ← retry ← rateLimit ← cache ← logging ← metrics ← [Network]
```

---

## Recommended Pipeline Order

| Position | Interceptor | Reason |
|----------|-------------|--------|
| 1 | **Auth** | Injects token before other interceptors see the request |
| 2 | **Retry** | Wraps everything below — retries include cache misses |
| 3 | **Rate Limit** | Throttles before hitting cache or network |
| 4 | **Validation** | Catches invalid request bodies before sending |
| 5 | **Cache** | Returns cached responses before logging or metrics |
| 6 | **Encryption** | Encrypts after all modifications are done |
| 7 | **Logging** | Logs the final request/response |
| 8 | **Metrics** | Innermost — measures actual transport duration |

This order is a recommendation. Adjust based on your specific requirements.

---

## Advanced Patterns

### HMAC Request Signing

```swift
import CryptoKit

struct HMACSigner: Interceptor {
    let name = "hmacSigner"
    let secret: SymmetricKey

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let payload = "\(request.httpMethod.rawValue):\(request.url.path):\(request.body?.base64EncodedString() ?? "")"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: secret
        )
        let hex = signature.map { String(format: "%02x", $0) }.joined()

        return try await next(
            request
                .header("X-Signature", hex)
                .header("X-Timestamp", "\(Int(Date().timeIntervalSince1970))")
        )
    }
}
```

### Offline Request Queue

```swift
actor OfflineQueue: Interceptor {
    nonisolated let name = "offlineQueue"
    private var queue: [FiberRequest] = []

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        do {
            return try await next(request)
        } catch {
            if isNetworkError(error) {
                queue.append(request)
                throw error
            }
            throw error
        }
    }

    func flush(using transport: @Sendable (FiberRequest) async throws -> FiberResponse) async {
        let pending = queue
        queue.removeAll()
        for request in pending {
            _ = try? await transport(request)
        }
    }

    private func isNetworkError(_ error: Error) -> Bool {
        (error as? URLError)?.code == .notConnectedToInternet
    }
}
```

### Request Deduplication

```swift
actor Deduplicator: Interceptor {
    nonisolated let name = "dedup"
    private var inflight: [String: Task<FiberResponse, Error>] = [:]

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let key = "\(request.httpMethod.rawValue):\(request.url.absoluteString)"

        if let existing = inflight[key] {
            return try await existing.value
        }

        let task = Task { try await next(request) }
        inflight[key] = task

        defer { inflight[key] = nil }
        return try await task.value
    }
}
```

---

<p align="center">
  <a href="GettingStarted.md">&larr; Getting Started</a> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket &rarr;</a>
</p>
