<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <b>Getting Started</b> &nbsp;&bull;&nbsp;
  <a href="Interceptors.md">Interceptors</a> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket</a> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation</a> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching</a> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing</a> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced</a>
</p>

---

# Getting Started

This guide walks you through installing Fiber, making your first request, and understanding the core concepts.

## Table of Contents

- [Installation](#installation)
- [Minimum Requirements](#minimum-requirements)
- [Creating a Client](#creating-a-client)
- [Making Requests](#making-requests)
- [Reading Responses](#reading-responses)
- [Request Builder](#request-builder)
- [Type-Safe Endpoints](#type-safe-endpoints)
- [Error Handling](#error-handling)
- [Configuration](#configuration)
- [Next Steps](#next-steps)

---

## Installation

### Swift Package Manager

Add Fiber to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/swift-fiber.git", from: "1.0.0")
]
```

Then add the modules you need to your target:

```swift
.target(name: "MyApp", dependencies: [
    "Fiber",                    // Core HTTP client (required)
    "FiberWebSocket",           // WebSocket support
    "FiberValidation",          // Domain model validation DSL
    "FiberDependencies",        // swift-dependencies integration
    "FiberSharing",             // swift-sharing + declarative caching
]),
.testTarget(name: "MyAppTests", dependencies: [
    "FiberTesting",             // MockTransport, StubResponse, MockWebSocket
    "FiberDependenciesTesting", // Test helpers for FiberDependencies
]),
```

### Xcode

1. **File** > **Add Package Dependencies...**
2. Enter the repository URL
3. Select the modules you need

### Module Overview

| Module | Purpose | Dependencies |
|--------|---------|--------------|
| `Fiber` | Core HTTP client, interceptors, tracing | None (Foundation only) |
| `FiberWebSocket` | WebSocket protocol + auto-reconnection | `Fiber` |
| `FiberValidation` | Domain model validation DSL | None |
| `FiberTesting` | Mock transport, stubs, WebSocket fakes | `Fiber`, `FiberWebSocket` |
| `FiberDependencies` | swift-dependencies integration | `Fiber`, `swift-dependencies` |
| `FiberSharing` | swift-sharing + declarative caching | `Fiber`, `swift-sharing` |
| `FiberDependenciesTesting` | Test helpers for dependency clients | `FiberDependencies`, `FiberTesting` |

> **Tip:** The core `Fiber` module has **zero third-party dependencies** — it only uses Foundation, OSLog, and CryptoKit from the Apple SDK. Optional modules bring in third-party dependencies only when you opt in.

---

## Minimum Requirements

| Platform | Minimum Version |
|----------|----------------|
| Swift | 6.0+ |
| iOS | 15.0+ |
| macOS | 12.0+ |
| tvOS | 15.0+ |
| watchOS | 8.0+ |

---

## Creating a Client

The `Fiber` class is the main entry point. Create one with a base URL:

```swift
import Fiber

// Minimal — just a base URL
let api = Fiber("https://api.example.com")

// With configuration
let api = Fiber("https://api.example.com") {
    $0.defaultHeaders = ["Accept": "application/json"]
    $0.timeout = 30
    $0.logger = OSLogFiberLogger(subsystem: "com.myapp")
}
```

You typically create one `Fiber` instance per API host and reuse it throughout your app.

---

## Making Requests

Fiber provides Axios-style convenience methods for every HTTP verb:

```swift
// GET
let response = try await api.get("/users")

// GET with query parameters
let response = try await api.get("/users", query: ["page": "1", "limit": "20"])

// POST with an Encodable body
let newUser = CreateUserRequest(name: "Alice", email: "alice@example.com")
let response = try await api.post("/users", body: newUser)

// PUT
try await api.put("/users/42", body: updatedUser)

// PATCH
try await api.patch("/users/42", body: PatchUser(name: "Bob"))

// DELETE
try await api.delete("/users/42")
```

All methods are `async throws` and return a `FiberResponse`.

---

## Reading Responses

`FiberResponse` gives you everything about the HTTP response:

```swift
let response = try await api.get("/users")

// Decode JSON into Swift types
let users: [User] = try response.decode()

// Status information
response.statusCode     // 200
response.isSuccess      // true (200-299)
response.isClientError  // false (400-499)
response.isServerError  // false (500-599)

// Headers
response.header("Content-Type")  // "application/json"

// Raw data
response.data           // Raw Data bytes
response.text           // UTF-8 String

// Diagnostics
response.duration       // 0.142 (seconds)
response.traceID        // "A1B2C3D4-E5F6-..."
```

### Response Validation Chain

Chain validation calls for expressive error handling:

```swift
let users: [User] = try response
    .validateStatus()           // throws on non-2xx
    .validate { r in            // custom validation
        guard r.header("X-API-Version") == "2" else {
            throw APIError.unsupportedVersion
        }
    }
    .decode()                   // decode JSON
```

---

## Request Builder

For complex requests, use the chainable `FiberRequest` builder. Every method returns a **new immutable copy** — the original is never mutated:

```swift
let request = FiberRequest(url: "https://api.example.com/search")
    .method(.post)
    .header("Authorization", "Bearer my-token")
    .header("Accept-Language", "en-US")
    .query("q", "swift concurrency")
    .query("page", "1")
    .jsonBody(SearchParams(filter: "active"))
    .timeout(30)
    .meta("cache", "skip")          // metadata for interceptors

let response = try await api.send(request)
```

**Immutability in action:**

```swift
let base = FiberRequest(url: "https://api.example.com/users")
let withAuth = base.header("Authorization", "Bearer token")

// base.headers is still empty — withAuth has the header
```

This makes it easy to create request templates:

```swift
let adminRequest = FiberRequest(url: "https://api.example.com")
    .header("X-Admin", "true")
    .header("Authorization", "Bearer admin-token")

// Reuse the template for different endpoints
let users = try await api.send(adminRequest.method(.get).query("path", "/users"))
let logs  = try await api.send(adminRequest.method(.get).query("path", "/logs"))
```

---

## Type-Safe Endpoints

Define your API surface as value types that conform to the `Endpoint` protocol:

```swift
struct GetUser: Endpoint {
    typealias Response = User
    let id: String

    var path: String { "/users/\(id)" }
    var method: HTTPMethod { .get }
}

struct ListUsers: Endpoint {
    typealias Response = [User]
    let page: Int

    var path: String { "/users" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "page", value: "\(page)")]
    }
}

struct CreateUser: Endpoint {
    typealias Response = User
    let name: String
    let email: String

    var path: String { "/users" }
    var method: HTTPMethod { .post }
    var body: Data? {
        try? JSONEncoder().encode(["name": name, "email": email])
    }
}
```

Then call them with full type inference:

```swift
let user = try await api.request(GetUser(id: "42"))        // User
let users = try await api.request(ListUsers(page: 1))      // [User]
let created = try await api.request(CreateUser(name: "Alice", email: "a@b.com"))  // User
```

---

## Error Handling

All Fiber errors are typed through `FiberError`:

```swift
do {
    let user: User = try await api.get("/users/1").decode()
} catch let error as FiberError {
    switch error {
    case .httpError(let statusCode, let data, _):
        // Server returned a non-success status (e.g., 404, 500)
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        print("HTTP \(statusCode): \(message)")

    case .networkError(let underlying):
        // Connection failure, DNS resolution, etc.
        print("Network error: \(underlying.localizedDescription)")

    case .decodingError(let underlying, let data):
        // JSON decoding failed
        print("Decoding failed: \(underlying)")
        print("Raw response: \(String(data: data, encoding: .utf8) ?? "")")

    case .timeout(let request):
        print("Request timed out: \(request.url)")

    case .cancelled:
        print("Request was cancelled")

    case .interceptor(let name, let underlying):
        // An interceptor threw (e.g., rate limit exceeded, validation failed)
        print("Interceptor '\(name)' error: \(underlying)")

    case .invalidURL(let string):
        print("Invalid URL: \(string)")

    case .encodingError(let underlying):
        print("Body encoding failed: \(underlying)")
    }
}
```

### Convenience Properties

```swift
catch let error as FiberError {
    error.statusCode       // Int? — HTTP status code, if applicable
    error.responseData     // Data? — response body, if available
    error.underlyingError  // Error? — wrapped error
}
```

---

## Configuration

Full configuration reference for the `Fiber` builder:

```swift
let api = Fiber("https://api.example.com") {
    // Middleware pipeline (see Interceptors guide)
    $0.interceptors = [auth, retry, cache, logging]

    // Custom URLSession transport
    $0.transport = URLSessionTransport(session: myCustomSession)

    // Default headers sent with every request
    $0.defaultHeaders = [
        "Accept": "application/json",
        "X-Client-Version": "2.1.0",
        "X-Platform": "iOS"
    ]

    // Default timeout for all requests (seconds)
    $0.timeout = 30

    // Custom JSON decoder/encoder
    $0.decoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    $0.encoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // Structured logging
    $0.logger = OSLogFiberLogger(subsystem: "com.myapp.networking")

    // Custom status validation (default: 200-299 are success)
    $0.validateStatus = { (200..<400).contains($0) }  // treat redirects as success

    // Injectable defaults for retry jitter, backoff, etc.
    $0.defaults = FiberDefaults(
        jitterFraction: 0.3,
        traceIDGenerator: { UUID().uuidString.lowercased() }
    )
}
```

---

## Next Steps

You now know the basics. Dive deeper into specific topics:

| Guide | What You'll Learn |
|-------|-------------------|
| **[Interceptors](Interceptors.md)** | Build middleware pipelines with auth, retry, caching, rate limiting, encryption |
| **[WebSocket](WebSocket.md)** | Real-time communication with auto-reconnection |
| **[Validation](Validation.md)** | Composable domain model validation with result builders |
| **[Caching](Caching.md)** | Declarative and imperative caching with stale-while-revalidate |
| **[Testing](Testing.md)** | MockTransport, StubResponse, MockWebSocket, and testing patterns |
| **[Advanced](Advanced.md)** | Distributed tracing, encryption, custom transports, metrics, injectable defaults |
| **[Real-World Examples](Examples.md)** | Complete production patterns for common app architectures |
