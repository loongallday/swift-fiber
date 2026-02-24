<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <a href="GettingStarted.md">Getting Started</a> &nbsp;&bull;&nbsp;
  <a href="Interceptors.md">Interceptors</a> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket</a> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation</a> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching</a> &nbsp;&bull;&nbsp;
  <b>Testing</b> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced</a>
</p>

---

# Testing

Fiber was built with testability as a first-class concern. The `FiberTesting` module provides everything you need to test networking code without hitting real servers.

```swift
import FiberTesting
```

## Table of Contents

- [MockTransport](#mocktransport)
- [StubResponse Builder](#stubresponse-builder)
- [Conditional Stubs](#conditional-stubs)
- [Request Assertions](#request-assertions)
- [Testing Interceptors](#testing-interceptors)
- [MockWebSocket](#mockwebsocket)
- [TestTraceCollector](#testtracecollector)
- [FiberDependencies Testing](#fiberdependencies-testing)
- [Testing Patterns](#testing-patterns)

---

## MockTransport

`MockTransport` is a drop-in replacement for `URLSessionTransport` that records requests and returns stubbed responses.

```swift
let mock = MockTransport()
mock.stubAll(.ok(body: #"{"id": 1, "name": "Alice"}"#))

let api = Fiber(baseURL: URL(string: "https://api.example.com")!, transport: mock)
let response = try await api.get("/users/1")

#expect(response.statusCode == 200)
#expect(mock.requests.count == 1)
```

### Stubbing Strategies

**Stub all requests with the same response:**

```swift
mock.stubAll(.ok(body: "{}"))
```

**Stub with a default handler:**

```swift
mock.stubDefault { request in
    .notFound(body: #"{"error": "not found"}"#)
}
```

**Conditional stubs (checked in order, first match wins):**

```swift
mock.stub { request in
    if request.url?.path == "/users" { return .ok(body: "[...]") }
    return nil  // fall through to next stub
}

mock.stub { request in
    if request.httpMethod == "DELETE" { return .noContent() }
    return nil
}

// Fallback for unmatched requests
mock.stubDefault { _ in .serverError() }
```

**Reset between tests:**

```swift
mock.reset()  // clears all stubs and recorded requests
```

---

## StubResponse Builder

`StubResponse` provides factory methods and a chainable builder for creating mock responses:

### Factory Methods

```swift
StubResponse.ok()                              // 200
StubResponse.ok(body: #"{"data": []}"#)        // 200 with body
StubResponse.created()                          // 201
StubResponse.created(body: #"{"id": 42}"#)     // 201 with body
StubResponse.noContent()                        // 204
StubResponse.badRequest()                       // 400
StubResponse.unauthorized()                     // 401
StubResponse.notFound()                         // 404
StubResponse.serverError()                      // 500
```

### Chainable Builder

```swift
let stub = StubResponse.ok()
    .header("X-Request-Id", "abc123")
    .header("Content-Type", "application/json")
    .body(#"{"users": [{"id": 1, "name": "Alice"}]}"#)
```

### From Encodable

```swift
struct User: Encodable {
    let id: Int
    let name: String
}

let stub = StubResponse.ok().jsonBody(User(id: 1, name: "Alice"))
// Automatically encodes to JSON and sets Content-Type
```

### Custom Status + Headers

```swift
let stub = StubResponse(statusCode: 429, body: "Rate limited")
    .header("Retry-After", "60")
    .header("X-RateLimit-Remaining", "0")
```

---

## Conditional Stubs

Build realistic mock APIs by matching on method, path, headers, and body:

```swift
let mock = MockTransport()

// GET /users → list
mock.stub { req in
    guard req.httpMethod == "GET", req.url?.path == "/users" else { return nil }
    return .ok(body: #"[{"id": 1, "name": "Alice"}]"#)
}

// GET /users/:id → single user
mock.stub { req in
    guard req.httpMethod == "GET",
          let path = req.url?.path,
          path.hasPrefix("/users/") else { return nil }
    let id = path.replacingOccurrences(of: "/users/", with: "")
    return .ok(body: #"{"id": \#(id), "name": "User \#(id)"}"#)
}

// POST /users → create
mock.stub { req in
    guard req.httpMethod == "POST", req.url?.path == "/users" else { return nil }
    return .created(body: #"{"id": 42}"#)
}

// DELETE → 204
mock.stub { req in
    guard req.httpMethod == "DELETE" else { return nil }
    return .noContent()
}

// Everything else → 404
mock.stubDefault { _ in .notFound() }
```

---

## Request Assertions

`MockTransport` records every request for inspection:

```swift
let mock = MockTransport()
mock.stubAll(.ok())

let api = Fiber(baseURL: URL(string: "https://api.example.com")!, transport: mock)
try await api.post("/users", body: CreateUser(name: "Alice"))

// Assert request count
mock.expectRequestCount(1)

// Inspect the last request
let last = mock.lastRequest!
#expect(last.httpMethod == "POST")
#expect(last.url?.path == "/users")
#expect(last.value(forHTTPHeaderField: "Content-Type") == "application/json")

// Inspect all requests
#expect(mock.requests.count == 1)
#expect(mock.requests[0].url?.path == "/users")

// Decode the request body
let body = try JSONDecoder().decode(CreateUser.self, from: last.httpBody!)
#expect(body.name == "Alice")
```

---

## Testing Interceptors

### Testing Auth Token Injection

```swift
@Test func authInterceptorInjectsToken() async throws {
    let auth = AuthInterceptor(tokenProvider: { "my-secret-token" })
    let mock = MockTransport()
    mock.stubAll(.ok())

    let api = Fiber(
        baseURL: URL(string: "https://api.example.com")!,
        interceptors: [auth],
        transport: mock
    )

    _ = try await api.get("/secure")

    let header = mock.lastRequest?.value(forHTTPHeaderField: "Authorization")
    #expect(header == "Bearer my-secret-token")
}
```

### Testing Retry Behavior

```swift
@Test func retryInterceptorRetriesOnServerError() async throws {
    var callCount = 0
    let mock = MockTransport()
    mock.stubDefault { _ in
        callCount += 1
        if callCount < 3 {
            return .serverError()
        }
        return .ok(body: "success")
    }

    let api = Fiber(
        baseURL: URL(string: "https://api.example.com")!,
        interceptors: [RetryInterceptor(maxRetries: 3, baseDelay: 0.01)],
        transport: mock
    )

    let response = try await api.get("/flaky")
    #expect(response.statusCode == 200)
    #expect(callCount == 3)
}
```

### Testing Rate Limiting

```swift
@Test func rateLimitBlocksExcessRequests() async throws {
    let mock = MockTransport()
    mock.stubAll(.ok())

    let api = Fiber(
        baseURL: URL(string: "https://api.example.com")!,
        interceptors: [RateLimitInterceptor(maxRequests: 2, perInterval: 60, maxWait: 0.1)],
        transport: mock
    )

    _ = try await api.get("/1")
    _ = try await api.get("/2")

    await #expect(throws: RateLimitError.self) {
        _ = try await api.get("/3")  // should throw
    }
}
```

---

## MockWebSocket

`MockWebSocket.pair()` creates two connected fakes — messages sent to one appear on the other:

```swift
@Test func webSocketPairCommunicates() async throws {
    let (client, server) = MockWebSocket.pair()

    // Server sends a message
    try await server.send(.text("hello"))

    // Client receives it
    for await event in client.events {
        if case .message(.text(let text)) = event {
            #expect(text == "hello")
            break
        }
    }
}

@Test func webSocketClosePropagates() async throws {
    let (client, server) = MockWebSocket.pair()

    client.close(code: 1000, reason: "done")

    #expect(client.state == .disconnected)
    #expect(server.state == .disconnected)
}

@Test func webSocketJSONRoundTrip() async throws {
    let (client, server) = MockWebSocket.pair()

    struct Message: Codable, Equatable {
        let text: String
    }

    try await client.send(.json(Message(text: "hello")))

    for await event in server.events {
        if case .message(let msg) = event {
            let decoded: Message? = try? msg.decode()
            #expect(decoded == Message(text: "hello"))
            break
        }
    }
}
```

---

## TestTraceCollector

Capture log messages for assertion:

```swift
@Test func loggingInterceptorCapturesTraceID() async throws {
    let collector = TestTraceCollector()
    let mock = MockTransport()
    mock.stubAll(.ok())

    let api = Fiber(
        baseURL: URL(string: "https://api.example.com")!,
        interceptors: [LoggingInterceptor(logger: collector.logger())],
        transport: mock
    )

    _ = try await api.get("/test")

    #expect(collector.logs.count >= 2)  // request log + response log
    #expect(collector.logs[0].message.contains("GET"))
    #expect(collector.logs[0].message.contains("/test"))
}
```

---

## FiberDependencies Testing

When using `FiberDependencies`, use `FiberDependenciesTesting` for ergonomic test setup:

```swift
import FiberDependenciesTesting

@Test func clientBackedByMock() async throws {
    let (client, mock) = FiberHTTPClient.test()
    mock.stubAll(.ok(body: #"{"ok": true}"#))

    let response = try await client.get("/health", [:], [:])
    #expect(response.statusCode == 200)
    mock.expectRequestCount(1)
}

@Test func stubClient() async throws {
    let client = FiberHTTPClient.stub(.ok(body: "stubbed"))

    let response = try await client.get("/anything", [:], [:])
    #expect(response.text == "stubbed")
}
```

### Overriding in Dependency Tests

```swift
import Dependencies

@Test func featureUsesHTTPClient() async throws {
    await withDependencies {
        $0.fiberHTTPClient = .stub(.ok(body: #"{"users": []}"#))
    } operation: {
        let feature = UserListFeature()
        await feature.loadUsers()
        #expect(feature.users.isEmpty)
    }
}
```

---

## Testing Patterns

### Pattern: Test a Full Request/Response Cycle

```swift
@Test func createUserFlow() async throws {
    let mock = MockTransport()

    mock.stub { req in
        guard req.httpMethod == "POST", req.url?.path == "/users" else { return nil }

        // Verify the request body
        let body = try? JSONDecoder().decode(CreateUser.self, from: req.httpBody ?? Data())
        guard let body, !body.name.isEmpty else {
            return .badRequest(body: #"{"error": "name required"}"#)
        }

        return StubResponse.created()
            .jsonBody(User(id: 42, name: body.name, email: body.email))
    }

    let api = Fiber(baseURL: URL(string: "https://api.example.com")!, transport: mock)
    let user: User = try await api.post("/users", body: CreateUser(name: "Alice", email: "a@b.com")).decode()

    #expect(user.id == 42)
    #expect(user.name == "Alice")
}
```

### Pattern: Test Error Handling

```swift
@Test func handles404Gracefully() async throws {
    let mock = MockTransport()
    mock.stubAll(.notFound(body: #"{"error": "User not found"}"#))

    let api = Fiber(baseURL: URL(string: "https://api.example.com")!, transport: mock)

    do {
        let _: User = try await api.get("/users/999").decode()
        Issue.record("Expected an error")
    } catch let error as FiberError {
        guard case .httpError(let status, _, _) = error else {
            Issue.record("Expected httpError")
            return
        }
        #expect(status == 404)
    }
}
```

### Pattern: Test Parallel Requests

```swift
@Test func parallelRequestsAllSucceed() async throws {
    let mock = MockTransport()
    mock.stub { req in
        let id = req.url?.lastPathComponent ?? "0"
        return .ok(body: #"{"id": \#(id)}"#)
    }

    let api = Fiber(baseURL: URL(string: "https://api.example.com")!, transport: mock)

    let users: [User] = try await withThrowingTaskGroup(of: User.self) { group in
        for id in 1...5 {
            group.addTask {
                try await api.get("/users/\(id)").decode()
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }

    #expect(users.count == 5)
    mock.expectRequestCount(5)
}
```

---

<p align="center">
  <a href="Caching.md">&larr; Caching</a> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced &rarr;</a>
</p>
