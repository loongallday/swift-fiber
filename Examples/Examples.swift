// Examples.swift
// Real-world usage patterns for Fiber.
// These are not compiled as part of the package — they serve as documentation.

import Foundation
import Fiber
import FiberValidation
import FiberWebSocket
import CryptoKit

// MARK: - 1. Basic REST Client

/// The simplest setup — just a base URL.
func basicUsage() async throws {
    let api = Fiber("https://jsonplaceholder.typicode.com")

    // GET a list
    let posts: [Post] = try await api.get("/posts", query: ["userId": "1"]).decode()

    // GET a single item
    let post: Post = try await api.get("/posts/1").decode()

    // POST — body is auto-encoded as JSON
    let newPost = CreatePost(title: "Hello", body: "World", userId: 1)
    let created: Post = try await api.post("/posts", body: newPost).decode()

    // PUT — full replace
    let updated: Post = try await api.put("/posts/1", body: newPost).decode()

    // PATCH — partial update
    let patched: Post = try await api.patch("/posts/1", body: PatchPost(title: "Updated")).decode()

    // DELETE
    _ = try await api.delete("/posts/1")

    _ = (posts, post, created, updated, patched) // silence unused warnings
}

// MARK: - 2. Production Client with Full Middleware Stack

/// A real-world client with auth, retry, caching, logging, and metrics.
func productionClient() async throws {
    let tokenStore = TokenStore()
    let metricsCollector = InMemoryMetricsCollector()

    let api = Fiber("https://api.myapp.com") {
        $0.timeout = 30
        $0.defaultHeaders = [
            "Accept": "application/json",
            "X-Client-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]
        $0.interceptors = [
            // 1. Auth — outermost so retry gets the refreshed token
            AuthInterceptor(
                tokenProvider: { await tokenStore.accessToken },
                tokenRefresher: { try await tokenStore.refresh() }
            ),
            // 2. Retry — retries auth-refreshed requests
            RetryInterceptor(maxRetries: 3, baseDelay: 0.5),
            // 3. Rate limit — prevent hammering the API
            RateLimitInterceptor(maxRequests: 60, perInterval: 60),
            // 4. Cache — avoid redundant GETs
            CacheInterceptor(ttl: 120, maxEntries: 50),
            // 5. Logging
            LoggingInterceptor(logger: PrintFiberLogger()),
            // 6. Metrics
            MetricsInterceptor(collector: metricsCollector),
        ]
    }

    // Use it
    let profile: UserProfile = try await api.get("/me").decode()
    let feed: [FeedItem] = try await api.get("/feed", query: ["limit": "20"]).decode()

    // Check metrics
    let avgDuration = await metricsCollector.averageDurationMs
    let successRate = await metricsCollector.successRate
    print("Avg response: \(avgDuration)ms, Success rate: \(successRate * 100)%")

    _ = (profile, feed) // silence unused warnings
}

// MARK: - 3. Type-Safe Endpoints

/// Define your entire API surface as value types. No stringly-typed paths.

struct API {
    // GET /users/:id
    struct GetUser: Endpoint {
        typealias Response = User
        let id: String
        var path: String { "/users/\(id)" }
        var method: HTTPMethod { .get }
    }

    // GET /users?q=...&page=...
    struct SearchUsers: Endpoint {
        typealias Response = PaginatedResponse<User>
        let query: String
        let page: Int

        var path: String { "/users" }
        var method: HTTPMethod { .get }
        var queryItems: [URLQueryItem] {
            [URLQueryItem(name: "q", value: query),
             URLQueryItem(name: "page", value: "\(page)")]
        }
    }

    // POST /users
    struct CreateUser: Endpoint {
        typealias Response = User
        let name: String
        let email: String

        var path: String { "/users" }
        var method: HTTPMethod { .post }
        var body: Data? {
            try? JSONEncoder().encode(["name": name, "email": email])
        }
        var headers: [String: String] { ["Content-Type": "application/json"] }
    }

    // DELETE /users/:id
    struct DeleteUser: Endpoint {
        typealias Response = EmptyResponse
        let id: String
        var path: String { "/users/\(id)" }
        var method: HTTPMethod { .delete }
    }
}

func typeSafeUsage() async throws {
    let api = Fiber("https://api.myapp.com")

    let user = try await api.request(API.GetUser(id: "123"))
    let results = try await api.request(API.SearchUsers(query: "alice", page: 1))
    let created = try await api.request(API.CreateUser(name: "Bob", email: "bob@example.com"))
    _ = try await api.request(API.DeleteUser(id: "456"))

    _ = (user, results, created) // silence unused warnings
}

// MARK: - 4. Custom Interceptor: Request Signing

/// Sign every request with HMAC for API authentication.
struct HMACSigningInterceptor: Interceptor {
    let name = "hmacSigning"
    let secretKey: SymmetricKey
    let headerName: String

    init(secret: String, headerName: String = "X-Signature") {
        self.secretKey = SymmetricKey(data: Data(secret.utf8))
        self.headerName = headerName
    }

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let payload = "\(request.httpMethod.rawValue):\(request.url.path)"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8), using: secretKey
        )
        let hex = signature.map { String(format: "%02x", $0) }.joined()
        return try await next(request.header(headerName, hex))
    }
}

// MARK: - 5. Custom Interceptor: Offline Queue

/// Queue requests when offline and replay when connectivity returns.
/// This is a pattern sketch — you'd add real Reachability monitoring.
actor OfflineQueueInterceptor: Interceptor {
    nonisolated let name = "offlineQueue"
    private var queue: [(FiberRequest, CheckedContinuation<FiberResponse, any Error>)] = []
    private var isOnline = true

    func setOnline(_ online: Bool) {
        isOnline = online
    }

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        if isOnline {
            return try await next(request)
        }

        // Park the request until we're back online
        return try await withCheckedThrowingContinuation { continuation in
            queue.append((request, continuation))
        }
    }

    /// Call this when connectivity is restored.
    func flush(using send: @Sendable (FiberRequest) async throws -> FiberResponse) async {
        isOnline = true
        let pending = queue
        queue.removeAll()

        for (request, continuation) in pending {
            do {
                let response = try await send(request)
                continuation.resume(returning: response)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - 6. Encrypted Communication

/// End-to-end encrypted API communication using AES-GCM.
func encryptedClient() async throws {
    // Both client and server share this key
    let key = SymmetricKey(size: .bits256)

    let api = Fiber("https://secure-api.example.com") {
        $0.interceptors = [
            EncryptionInterceptor(provider: AESGCMEncryptionProvider(key: key))
        ]
    }

    // Request body is encrypted before sending, response is decrypted after receiving
    let secret: SecretData = try await api.post("/vault/store", body: payload).decode()
    _ = secret // silence unused warnings
}

// MARK: - 7. Distributed Tracing

/// Full tracing with custom metadata for observability.
func tracingExample() async throws {
    let exporter = InMemoryTraceExporter()

    let api = Fiber("https://api.myapp.com") {
        $0.interceptors = [
            LoggingInterceptor(logger: PrintFiberLogger())
        ]
    }

    // Attach user context to the trace
    try await TraceContext.$metadata.withValue(["userId": "user-123", "feature": "checkout"]) {
        let cart: Cart = try await api.get("/cart").decode()

        // Create sub-spans for detailed timing
        var validateSpan = Span(name: "validateCart")
        try validateCart(cart)
        let finishedValidate = validateSpan.finish()

        var checkoutSpan = Span(name: "processCheckout")
        let order: Order = try await api.post("/orders", body: CheckoutRequest(cartId: cart.id)).decode()
        let finishedCheckout = checkoutSpan.finish()

        // Export spans to your backend
        await exporter.export([finishedValidate, finishedCheckout])

        _ = order // silence unused warnings
    }
}

// MARK: - 8. WebSocket Chat Client

/// Real-time chat using WebSocket with auto-reconnection.
func chatClient() async throws {
    let ws = ReconnectingWebSocket(
        connect: {
            URLSessionWebSocketTransport.connect(to: URL(string: "wss://chat.example.com/ws")!)
        },
        strategy: .exponentialBackoff(baseDelay: 1, maxDelay: 30, maxAttempts: 10),
        logger: PrintFiberLogger()
    )

    // Start connection in background
    Task { await ws.start() }

    // Send a message
    try await ws.send(.json(ChatMessage(type: "join", room: "general", text: nil)))

    // Listen for events
    for await event in ws.events {
        switch event {
        case .connected:
            print("Connected to chat")
        case .message(let msg):
            if let chat: ChatMessage = try? msg.decode() {
                print("[\(chat.room ?? "?")] \(chat.text ?? "")")
            }
        case .disconnected(_, let reason):
            print("Disconnected: \(reason ?? "unknown") — reconnecting...")
        case .error(let error):
            print("WebSocket error: \(error)")
        }
    }
}

// MARK: - 9. Parallel Requests

/// Fire multiple requests concurrently with async let or TaskGroup.
func parallelRequests() async throws {
    let api = Fiber("https://api.myapp.com")

    // async let — fixed number of concurrent requests
    async let profile: UserProfile = api.get("/me").decode()
    async let notifications: [Notification] = api.get("/notifications").decode()
    async let settings: Settings = api.get("/settings").decode()

    let (p, n, s) = try await (profile, notifications, settings)
    _ = (p, n, s) // silence unused warnings

    // TaskGroup — dynamic number of concurrent requests
    let userIds = ["1", "2", "3", "4", "5"]
    let users = try await withThrowingTaskGroup(of: User.self) { group in
        for id in userIds {
            group.addTask {
                try await api.get("/users/\(id)").decode()
            }
        }
        var results: [User] = []
        for try await user in group {
            results.append(user)
        }
        return results
    }
    _ = users // silence unused warnings
}

// MARK: - 10. Testing Example

/// How to write tests for code that uses Fiber.

// Your app code:
struct UserService {
    let fiber: Fiber

    func getUser(id: String) async throws -> User {
        try await fiber.get("/users/\(id)").decode()
    }

    func createUser(name: String, email: String) async throws -> User {
        try await fiber.post("/users", body: ["name": name, "email": email]).decode()
    }
}

// Your test code:
/*
import Testing
import FiberTesting

@Test func testGetUser() async throws {
    let mock = MockTransport()
    mock.stubAll(.ok(body: #"{"id": "123", "name": "Alice", "email": "alice@test.com"}"#))

    let fiber = Fiber(baseURL: URL(string: "https://api.test.com")!, transport: mock)
    let service = UserService(fiber: fiber)

    let user = try await service.getUser(id: "123")

    #expect(user.name == "Alice")
    #expect(mock.requests.count == 1)
    #expect(mock.lastRequest?.url?.path == "/users/123")
}

@Test func testCreateUser() async throws {
    let mock = MockTransport()
    mock.stubAll(.created().jsonBody(User(id: "456", name: "Bob", email: "bob@test.com")))

    let fiber = Fiber(baseURL: URL(string: "https://api.test.com")!, transport: mock)
    let service = UserService(fiber: fiber)

    let user = try await service.createUser(name: "Bob", email: "bob@test.com")

    #expect(user.id == "456")
    #expect(mock.lastRequest?.httpMethod == "POST")
}

@Test func testHandles404() async throws {
    let mock = MockTransport()
    mock.stubAll(.notFound())

    let fiber = Fiber(
        baseURL: URL(string: "https://api.test.com")!,
        transport: mock,
        validateStatus: { (200..<300).contains($0) }
    )

    // The request succeeds (transport returns 404), but decode/validate would fail
    let response = try await fiber.get("/users/nonexistent")
    #expect(response.statusCode == 404)
    #expect(response.isClientError)
}

@Test func testWebSocketCommunication() async throws {
    let (client, server) = MockWebSocket.pair()

    // Simulate server push
    try await server.send(.json(ServerEvent(type: "update", data: "new data")))

    // Verify client receives it
    for await event in client.events {
        if case .message(let msg) = event {
            let decoded: ServerEvent = try msg.decode()
            #expect(decoded.type == "update")
            break
        }
    }
}
*/


// MARK: - 14. Declarative Cached API Fetching

/// Use @SharedReader with Fiber's caching layer for reactive, cache-first data.
/// Data flows: memory cache -> disk cache -> network, with automatic TTL management.
/*
import FiberSharing
import Sharing

struct UserListView {
    // Declarative: data is fetched and cached automatically.
    // Cache policy controls TTL, storage mode, and stale-while-revalidate behavior.
    @SharedReader(.api("/users", as: [User].self))
    var users: CachedResponse<[User]>

    // Aggressive caching: 30-min TTL, memory + disk, serves stale data for 60s while refreshing
    @SharedReader(.api("/users/featured", as: [User].self, policy: .aggressive))
    var featuredUsers: CachedResponse<[User]>

    // Custom TTL shorthand: 1 hour, disk-backed
    @SharedReader(.cachedAPI("/config", as: AppConfig.self, ttl: 3600, storage: .disk))
    var appConfig: CachedResponse<AppConfig>

    // With query parameters
    @SharedReader(.api("/users", as: PaginatedResponse<User>.self, query: ["page": "1", "limit": "20"]))
    var paginatedUsers: CachedResponse<PaginatedResponse<User>>

    func display() {
        if let users {
            print("Got \(users.value.count) users")
            print("Cached \(users.age) seconds ago")
            print("Fresh: \(users.isFresh), Expired: \(users.isExpired)")

            if let etag = users.etag {
                print("ETag: \(etag) — next fetch will use If-None-Match")
            }
        }
    }
}
*/

// MARK: - 15. Imperative Cached Fetching

/// Use SharedFiber.getCached() for view models and one-off requests.
/// Same cache-first strategy as declarative, but with imperative control.
/*
import FiberSharing

func imperativeCaching() async throws {
    let fiber = SharedFiber { config, fiberConfig in
        fiberConfig.interceptors = [
            AuthInterceptor(tokenProvider: { config.authToken }),
            RetryInterceptor(),
        ]
    }

    // Basic cache-first fetch (5-min TTL, memory-only by default)
    let users: CachedResponse<[User]> = try await fiber.getCached(
        "/users", as: [User].self
    )
    print(users.value)    // [User]
    print(users.isFresh)  // true — just fetched

    // Second call hits memory cache — no network request
    let cached: CachedResponse<[User]> = try await fiber.getCached(
        "/users", as: [User].self
    )
    print(cached.age)  // ~0 seconds — served from cache

    // Aggressive policy: 30-min TTL, memory + disk
    let feed: CachedResponse<[FeedItem]> = try await fiber.getCached(
        "/feed", as: [FeedItem].self,
        policy: .aggressive
    )
    _ = feed

    // Persistent policy: 1-hour TTL, disk-backed, 5-min stale-while-revalidate
    let config: CachedResponse<AppConfig> = try await fiber.getCached(
        "/config", as: AppConfig.self,
        policy: .persistent
    )
    _ = config

    // No-cache policy: always fetches from network
    let realtime: CachedResponse<[Notification]> = try await fiber.getCached(
        "/notifications", as: [Notification].self,
        policy: .noCache
    )
    _ = realtime

    // Custom policy
    let custom = CachePolicy(
        ttl: 600,                           // 10 minutes
        staleWhileRevalidate: 120,          // Serve stale for 2 more minutes
        storageMode: .memoryAndDisk,
        maxEntries: 50
    )
    let search: CachedResponse<[User]> = try await fiber.getCached(
        "/users", as: [User].self,
        query: ["q": "alice", "page": "1"],
        policy: custom
    )
    _ = search
}
*/

// MARK: - 16. Conditional Requests & ETag Handling

/// Fiber's caching layer automatically uses conditional HTTP requests
/// (If-None-Match / If-Modified-Since) to save bandwidth.
/*
import FiberSharing

func conditionalRequestDemo() async throws {
    let fiber = SharedFiber()

    // First request: server returns ETag header
    // GET /users -> 200 OK, ETag: "v1"
    let first: CachedResponse<[User]> = try await fiber.getCached(
        "/users", as: [User].self
    )
    print(first.etag ?? "no etag")           // "v1"
    print(first.lastModified ?? "no date")   // "Wed, 21 Oct 2024 07:28:00 GMT"

    // Wait for TTL to expire, then fetch again:
    // GET /users, If-None-Match: "v1"
    //
    // If data hasn't changed:
    //   Server returns: 304 Not Modified (no body)
    //   Cache refreshes TTL without re-downloading
    //
    // If data has changed:
    //   Server returns: 200 OK with new data + new ETag
    //   Cache stores the new response

    let second: CachedResponse<[User]> = try await fiber.getCached(
        "/users", as: [User].self
    )
    print(second.isFresh)  // true — TTL was refreshed
    // If 304: second.value == first.value (same data, no bandwidth wasted)
    // If 200: second.value is the new data
}
*/

// MARK: - 17. Cache Invalidation Patterns

/// Patterns for keeping cached data fresh after mutations.
/*
import FiberSharing

func cacheInvalidationPatterns() async throws {
    let fiber = SharedFiber()

    // Load users (cached)
    let _: CachedResponse<[User]> = try await fiber.getCached(
        "/users", as: [User].self
    )

    // After creating a user, invalidate the users list cache
    _ = try await fiber.post("/users", body: ["name": "Alice", "email": "alice@test.com"])
    await fiber.invalidateCache(for: "/users")
    // Next getCached("/users") will fetch from network

    // Invalidate with specific query params
    await fiber.invalidateCache(for: "/users", query: ["page": "1"])

    // Prefix invalidation — clears all matching paths
    // Matches: GET:/users, GET:/users/1, GET:/users?page=2
    await fiber.invalidateCacheMatching("GET:/users")

    // Nuclear option: clear everything
    await fiber.clearCache()

    // Direct SharedCacheStore access (advanced)
    let store = SharedCacheStore.shared
    print(await store.memoryCount)  // current entries in memory
    await store.invalidateAll()     // memory only
    await store.clearDisk()         // disk only
}

// Pattern: Invalidate-on-mutate wrapper
extension SharedFiber {
    func postAndInvalidate<T: Encodable>(
        _ path: String,
        body: T,
        invalidating cachePaths: [String]
    ) async throws -> FiberResponse {
        let response = try await post(path, body: body)
        for path in cachePaths {
            await invalidateCacheMatching("GET:\(path)")
        }
        return response
    }
}

// Usage:
// try await fiber.postAndInvalidate("/users", body: newUser, invalidating: ["/users"])
*/

// MARK: - 18. Domain Validation — Basic Usage

/// Validate any model with composable rules via a declarative DSL.
func basicValidation() {
    // Define a validator for your model
    let userValidator = Validator<UserForm> {
        Validate(\.name, label: "name") {
            ValidationRule.notEmpty(message: "Name is required")
            ValidationRule.minLength(2)
            ValidationRule.maxLength(100)
        }
        Validate(\.email, label: "email") {
            ValidationRule.notEmpty()
            ValidationRule.email()
        }
        Validate(\.age, label: "age") {
            ValidationRule.range(18...120)
        }
    }

    // Validate a model
    let form = UserForm(name: "", email: "bad", age: 10)
    let result = userValidator.validate(form)

    if !result.isValid {
        for error in result.errorItems {
            print("\(error.path): \(error.message) [code: \(error.code)]")
            // "name: Name is required [code: notEmpty]"
            // "name: Must be at least 2 characters [code: minLength]"
            // "email: Invalid email format [code: email]"
            // "age: Must be between 18 and 120 [code: range]"
        }
    }

    // Valid model passes cleanly
    let validForm = UserForm(name: "Alice", email: "alice@example.com", age: 30)
    let validResult = userValidator.validate(validForm)
    print(validResult.isValid)  // true
    print(validResult.isClean)  // true (no errors or warnings)
}

// MARK: - 19. Nested & Collection Validation

/// Validate nested objects and collections with automatic path prefixing.
func nestedAndCollectionValidation() {
    // Nested validator for addresses
    let addressValidator = Validator<AddressForm> {
        Validate(\.street, label: "street") {
            ValidationRule.notEmpty()
        }
        Validate(\.city, label: "city") {
            ValidationRule.notEmpty()
        }
        Validate(\.zipCode, label: "zipCode") {
            ValidationRule.pattern(#"^\d{5}$"#, message: "Must be a 5-digit ZIP code")
        }
    }

    // Compose into a parent validator
    let orderValidator = Validator<OrderForm> {
        Validate(\.customerName, label: "customerName") {
            ValidationRule.notEmpty()
            ValidationRule.minLength(2)
        }
        // Nested: errors have paths like "shippingAddress.street"
        Validate(\.shippingAddress, label: "shippingAddress", validator: addressValidator)

        // Collection: errors have paths like "items[0]", "items[2]"
        ValidateEach(\.items, label: "items") {
            ValidationRule.notEmpty()
        }
    }

    let order = OrderForm(
        customerName: "",
        shippingAddress: AddressForm(street: "", city: "NYC", zipCode: "abc"),
        items: ["Widget", "", "Gadget"]
    )

    let result = orderValidator.validate(order)
    for error in result.errorItems {
        print("\(error.path): \(error.message)")
        // "customerName: Must not be empty"
        // "customerName: Must be at least 2 characters"
        // "shippingAddress.street: Must not be empty"
        // "shippingAddress.zipCode: Must be a 5-digit ZIP code"
        // "items[1]: Must not be empty"
    }
}

// MARK: - 20. Conditional & Severity Validation

/// Rules that only apply when a condition is met, plus warning-level severity.
func conditionalAndSeverityValidation() {
    let registrationValidator = Validator<RegistrationForm> {
        Validate(\.username, label: "username") {
            ValidationRule.notEmpty()
            ValidationRule.minLength(3)
        }
        Validate(\.password, label: "password") {
            ValidationRule.notEmpty()
            ValidationRule.minLength(8, message: "Password must be at least 8 characters")
        }
        // Warning: a suggestion, not a hard requirement
        Validate(\.password, label: "password") {
            ValidationRule.minLength(12, severity: .warning, message: "Consider using a longer password")
        }

        // Only validate company fields when registering as a business
        ValidateIf({ $0.isBusiness }) {
            Validate(\.companyName, label: "companyName") {
                ValidationRule.notNil(message: "Company name required for business accounts")
            }
            Validate(\.taxId, label: "taxId") {
                ValidationRule.notNil(message: "Tax ID required for business accounts")
            }
        }
    }

    // Personal registration — company fields are skipped
    let personal = RegistrationForm(
        username: "alice", password: "secret12",
        isBusiness: false, companyName: nil, taxId: nil
    )
    let personalResult = registrationValidator.validate(personal)
    print(personalResult.isValid)        // true — no errors
    print(personalResult.hasWarnings)    // true — password is < 12 chars
    print(personalResult.isValid(failOnWarnings: true))  // false

    // Business registration — company fields are required
    let business = RegistrationForm(
        username: "bob", password: "corporate-pass",
        isBusiness: true, companyName: nil, taxId: nil
    )
    let bizResult = registrationValidator.validate(business)
    print(bizResult.isValid)  // false — missing companyName and taxId
}

// MARK: - 21. Async Validation

/// Rules that require async operations like API calls.
func asyncValidation() async {
    let signupValidator = Validator<SignupForm> {
        Validate(\.email, label: "email") {
            ValidationRule.email()
            // Check uniqueness against a remote API
            ValidationRule.asyncCustom(message: "Email already registered") { email in
                // Simulate API call
                try? await Task.sleep(for: .milliseconds(100))
                return email != "taken@example.com"
            }
        }
        Validate(\.username, label: "username") {
            ValidationRule.notEmpty()
            ValidationRule.asyncCustom(message: "Username is taken") { username in
                try? await Task.sleep(for: .milliseconds(100))
                return !["admin", "root", "system"].contains(username)
            }
        }
    }

    // Must use validateAsync for validators with async rules
    let form = SignupForm(email: "taken@example.com", username: "admin")
    let result = await signupValidator.validateAsync(form)
    print(result.isValid)  // false
    for error in result.errorItems {
        print("\(error.path): \(error.message)")
        // "email: Email already registered"
        // "username: Username is taken"
    }
}

// MARK: - 22. Validation Interceptor — Fiber Integration

/// Validate request bodies automatically before they reach the network.
func validationInterceptor() async throws {
    // Define a validator for the request body type
    let createUserValidator = Validator<CreateUserRequest> {
        Validate(\.name, label: "name") {
            ValidationRule.notEmpty(message: "Name is required")
            ValidationRule.minLength(2)
        }
        Validate(\.email, label: "email") {
            ValidationRule.notEmpty()
            ValidationRule.email()
        }
    }

    let api = Fiber("https://api.example.com") {
        $0.interceptors = [
            // Validates POST/PUT/PATCH bodies as CreateUserRequest
            ValidationInterceptor<CreateUserRequest>(
                validator: createUserValidator
            ),
        ]
    }

    // Valid body — proceeds to network
    let validUser = CreateUserRequest(name: "Alice", email: "alice@example.com")
    let response = try await api.post("/users", body: validUser)
    print(response.statusCode)  // 200

    // Invalid body — throws before hitting the network
    let invalidUser = CreateUserRequest(name: "", email: "bad")
    do {
        _ = try await api.post("/users", body: invalidUser)
    } catch let error as FiberError {
        if case .interceptor(let name, let underlying) = error {
            print(name)  // "validation"
            let failure = underlying as! ValidationFailure
            for error in failure.result.errorItems {
                print("\(error.path): \(error.message)")
            }
        }
    }
}

// MARK: - 23. Full Validation Stack

/// Production-ready example combining validation with auth, retry, and logging.
func fullValidationStack() async throws {
    let addressValidator = Validator<AddressForm> {
        Validate(\.street, label: "street") { ValidationRule.notEmpty() }
        Validate(\.city, label: "city") { ValidationRule.notEmpty() }
        Validate(\.zipCode, label: "zipCode") { ValidationRule.pattern(#"^\d{5}$"#) }
    }

    let createOrderValidator = Validator<CreateOrderRequest> {
        Validate(\.customerName, label: "customerName") {
            ValidationRule.notEmpty(message: "Customer name is required")
            ValidationRule.minLength(2)
            ValidationRule.maxLength(200)
        }
        Validate(\.customerEmail, label: "customerEmail") {
            ValidationRule.email()
        }
        Validate(\.shippingAddress, label: "shippingAddress", validator: addressValidator)
        ValidateEach(\.lineItems, label: "lineItems") {
            ValidationRule.notEmpty()
        }
        Validate(\.lineItems, label: "lineItems") {
            ValidationRule.notEmpty(message: "At least one item required")
        }
    }

    let api = Fiber("https://api.myshop.com") {
        $0.interceptors = [
            AuthInterceptor(tokenProvider: { "my-token" }),
            ValidationInterceptor<CreateOrderRequest>(
                validator: createOrderValidator,
                for: [.post]
            ),
            RetryInterceptor(maxRetries: 2),
            LoggingInterceptor(logger: PrintFiberLogger()),
        ]
    }

    let order = CreateOrderRequest(
        customerName: "Alice Johnson",
        customerEmail: "alice@example.com",
        shippingAddress: AddressForm(street: "123 Main St", city: "NYC", zipCode: "10001"),
        lineItems: ["Widget Pro", "Gadget Deluxe"]
    )

    // Auth injects token → Validation passes → Retry wraps → Logger logs
    let response = try await api.post("/orders", body: order)
    print(response.statusCode)  // 201

    _ = response // silence unused warnings
}

// MARK: - Validation Example Models

private struct UserForm: Sendable {
    let name: String
    let email: String
    let age: Int
}

private struct AddressForm: Sendable {
    let street: String
    let city: String
    let zipCode: String
}

private struct OrderForm: Sendable {
    let customerName: String
    let shippingAddress: AddressForm
    let items: [String]
}

private struct RegistrationForm: Sendable {
    let username: String
    let password: String
    let isBusiness: Bool
    let companyName: String?
    let taxId: String?
}

private struct SignupForm: Sendable {
    let email: String
    let username: String
}

private struct CreateUserRequest: Codable, Sendable {
    let name: String
    let email: String
}

private struct CreateOrderRequest: Codable, Sendable {
    let customerName: String
    let customerEmail: String
    let shippingAddress: AddressForm
    let lineItems: [String]
}

extension AddressForm: Codable {}

// MARK: - Supporting Types

struct Post: Codable, Sendable { let id: Int?; let title: String; let body: String; let userId: Int }
struct CreatePost: Codable, Sendable { let title: String; let body: String; let userId: Int }
struct PatchPost: Codable, Sendable { let title: String }
struct User: Codable, Sendable { let id: String; let name: String; let email: String }
struct UserProfile: Codable, Sendable { let id: String; let name: String }
struct FeedItem: Codable, Sendable { let id: String; let title: String }
struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable where T: Equatable {
    let items: [T]; let total: Int; let page: Int
}
struct EmptyResponse: Codable, Sendable {}
struct AppConfig: Codable, Sendable { let version: String; let features: [String] }
struct SecretData: Codable, Sendable { let key: String }
struct Cart: Codable, Sendable { let id: String }
struct Order: Codable, Sendable { let id: String }
struct CheckoutRequest: Codable, Sendable { let cartId: String }
struct Settings: Codable, Sendable {}
struct Notification: Codable, Sendable { let id: String }
struct ChatMessage: Codable, Sendable { let type: String; let room: String?; let text: String? }
struct ServerEvent: Codable, Sendable { let type: String; let data: String }

// Placeholder for examples
actor TokenStore {
    var accessToken: String? { "stored-token" }
    func refresh() async throws -> String { "new-token" }
}
let payload = SecretData(key: "secret")
func validateCart(_ cart: Cart) throws {}

// MARK: - 11. swift-dependencies Integration

/// Use Fiber with Point-Free's swift-dependencies for testable dependency injection.
/*
import FiberDependencies
import Dependencies

// Define a feature that uses the HTTP client dependency:
struct UserFeature {
    @Dependency(\.fiberHTTPClient) var httpClient

    func loadUsers() async throws -> [User] {
        let response = try await httpClient.get("/users", [:], [:])
        return try response.decode()
    }

    func createUser(name: String, email: String) async throws -> User {
        let body = try JSONEncoder().encode(["name": name, "email": email])
        let response = try await httpClient.post("/users", body, ["Content-Type": "application/json"])
        return try response.decode()
    }
}

// Configure in your app:
func appSetup() {
    withDependencies {
        $0.fiberHTTPClient = .live("https://api.myapp.com") {
            $0.interceptors = [
                AuthInterceptor(tokenProvider: { "my-token" }),
                RetryInterceptor(),
                LoggingInterceptor(logger: PrintFiberLogger()),
            ]
        }
    } operation: {
        // App runs here with the live client
    }
}

// Test your feature without any network:
import Testing
import FiberDependenciesTesting

@Test func testLoadUsers() async throws {
    let feature = withDependencies {
        $0.fiberHTTPClient.get = { path, _, _ in
            FiberResponse(
                data: Data(#"[{"id":"1","name":"Alice","email":"a@b.com"}]"#.utf8),
                statusCode: 200,
                request: FiberRequest(url: URL(string: "https://test.local\(path)")!)
            )
        }
    } operation: {
        UserFeature()
    }

    let users = try await feature.loadUsers()
    #expect(users.count == 1)
    #expect(users[0].name == "Alice")
}

// Or use the test helper for a full mock transport:
@Test func testWithMockTransport() async throws {
    let (client, mock) = FiberHTTPClient.test()
    mock.stubAll(.ok(body: #"[{"id":"1","name":"Bob","email":"b@c.com"}]"#))

    let feature = withDependencies {
        $0.fiberHTTPClient = client
    } operation: {
        UserFeature()
    }

    let users = try await feature.loadUsers()
    #expect(users.count == 1)
    #expect(mock.requests.count == 1)
}
*/

// MARK: - 12. swift-sharing Integration

/// Use Fiber with Point-Free's swift-sharing for reactive configuration.
/*
import FiberSharing
import Sharing

// SharedFiber reads from @Shared(.fiberConfiguration) and rebuilds the client
// whenever the configuration changes.

func sharedFiberExample() async throws {
    // Create a SharedFiber with custom interceptor setup
    let shared = SharedFiber { config, fiberConfig in
        fiberConfig.interceptors = [
            AuthInterceptor(tokenProvider: { config.authToken }),
            RetryInterceptor(),
        ]
    }

    // Make requests using the current config
    let users: [User] = try await shared.get("/users").decode()
    _ = users

    // Change config from anywhere in the app:
    @Shared(.fiberConfiguration) var config
    $config.withLock {
        $0.baseURL = "https://staging.api.com"
        $0.authToken = "staging-token"
        $0.defaultHeaders["X-Environment"] = "staging"
    }

    // Next request automatically uses the new config
    let stagingUsers: [User] = try await shared.get("/users").decode()
    _ = stagingUsers
}

// Great for environment switching, A/B testing, feature flags:
func switchEnvironment(to env: String) {
    @Shared(.fiberConfiguration) var config
    $config.withLock { c in
        switch env {
        case "production":
            c.baseURL = "https://api.myapp.com"
        case "staging":
            c.baseURL = "https://staging.api.myapp.com"
        case "local":
            c.baseURL = "http://localhost:8080"
        default:
            break
        }
    }
}
*/

// MARK: - 13. Injectable Defaults

/// Customize all internal constants without subclassing or forking.
func customDefaultsExample() async throws {
    // Override global defaults at app startup
    FiberDefaults.shared = FiberDefaults(
        jitterFraction: 0.5,               // More aggressive jitter
        exponentialBackoffBase: 3.0,        // Steeper backoff curve
        loggingSystemName: "MyApp.Network", // Custom log system name
        logBodyTruncationLimit: 2000,       // Log more of the body
        traceIDGenerator: {
            // Custom trace ID format
            "trace-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8))"
        }
    )

    // Or configure per-component for fine-grained control
    let aggressiveRetry = RetryInterceptor(
        maxRetries: 5,
        baseDelay: 0.2,
        defaults: FiberDefaults(
            exponentialBackoffBase: 1.5,  // Gentler backoff for this retry only
            jitterFraction: 0.1
        )
    )

    let verboseLogging = LoggingInterceptor(
        logger: PrintFiberLogger(minLevel: .verbose),
        logBody: true,
        defaults: FiberDefaults(
            loggingSystemName: "Debug",
            logBodyTruncationLimit: 5000
        )
    )

    let api = Fiber("https://api.example.com") {
        $0.interceptors = [aggressiveRetry, verboseLogging]
        $0.defaults = FiberDefaults(
            traceIDGenerator: { "req-\(Int(Date().timeIntervalSince1970))" }
        )
    }

    _ = try await api.get("/health")
}
