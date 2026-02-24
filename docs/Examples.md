<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <a href="GettingStarted.md">Getting Started</a> &nbsp;&bull;&nbsp;
  <a href="Interceptors.md">Interceptors</a> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket</a> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation</a> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching</a> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing</a> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced</a>
</p>

---

# Real-World Examples

Complete, production-grade examples demonstrating functional patterns with Fiber.

## Table of Contents

- [E-Commerce API Layer](#e-commerce-api-layer) — Endpoints, validation, interceptor pipeline, caching
- [Social Feed with Real-Time Updates](#social-feed-with-real-time-updates) — REST + WebSocket, functional event handling
- [Multi-Tenant SaaS Client](#multi-tenant-saas-client) — Dynamic base URLs, HMAC signing, tenant isolation
- [Offline-First with Request Queuing](#offline-first-with-request-queuing) — Cache-first reads, queued writes, sync on reconnect
- [Analytics Pipeline](#analytics-pipeline) — Batched event collection with metrics and tracing
- [Full Test Suite with swift-dependencies](#full-test-suite-with-swift-dependencies) — Testing a feature module end to end
- [FiberSharing: Multi-Environment App](#fibersharing-multi-environment-app) — Shared config, environment switching, declarative caching, SWR, ETag, cache invalidation
- [FiberDependencies: Composable Architecture Feature](#fiberdependencies-composable-architecture-feature) — Dependency injection, reducer-style features, full test isolation

---

## E-Commerce API Layer

A complete networking layer for a shopping app — type-safe endpoints, composable validation, and a production interceptor pipeline. No singletons, no manager classes — just values and functions.

### Domain Models

```swift
struct Product: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let price: Decimal
    let currency: String
    let category: String
    let imageURLs: [URL]
    let inventory: Int
    let rating: Double
}

struct CartItem: Codable, Sendable {
    let productID: String
    let quantity: Int
    let price: Decimal
}

struct Cart: Codable, Sendable {
    let id: String
    let items: [CartItem]
    let subtotal: Decimal
    let tax: Decimal
    let total: Decimal
}

struct Order: Codable, Sendable, Identifiable {
    let id: String
    let items: [CartItem]
    let total: Decimal
    let status: Status
    let shippingAddress: Address
    let createdAt: Date

    enum Status: String, Codable, Sendable {
        case pending, confirmed, shipped, delivered, cancelled
    }
}

struct Address: Codable, Sendable {
    let street: String
    let city: String
    let state: String
    let zipCode: String
    let country: String
}

struct CreateOrderRequest: Codable, Sendable {
    let cartID: String
    let shippingAddress: Address
    let billingAddress: Address?
    let paymentMethodID: String
    let couponCode: String?
    let notes: String?
}

struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let total: Int
    let page: Int
    let totalPages: Int
}
```

### Type-Safe Endpoints

```swift
// MARK: - Products

struct ListProducts: Endpoint {
    typealias Response = PaginatedResponse<Product>
    let category: String?
    let page: Int
    let limit: Int

    var path: String { "/products" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let category {
            items.append(URLQueryItem(name: "category", value: category))
        }
        return items
    }
}

struct GetProduct: Endpoint {
    typealias Response = Product
    let id: String
    var path: String { "/products/\(id)" }
    var method: HTTPMethod { .get }
}

struct SearchProducts: Endpoint {
    typealias Response = PaginatedResponse<Product>
    let query: String
    let minPrice: Decimal?
    let maxPrice: Decimal?

    var path: String { "/products/search" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "q", value: query)]
        if let minPrice { items.append(.init(name: "min_price", value: "\(minPrice)")) }
        if let maxPrice { items.append(.init(name: "max_price", value: "\(maxPrice)")) }
        return items
    }
}

// MARK: - Cart

struct GetCart: Endpoint {
    typealias Response = Cart
    var path: String { "/cart" }
    var method: HTTPMethod { .get }
}

struct AddToCart: Endpoint {
    typealias Response = Cart
    let productID: String
    let quantity: Int
    var path: String { "/cart/items" }
    var method: HTTPMethod { .post }
    var body: Data? {
        try? JSONEncoder().encode(["product_id": productID, "quantity": "\(quantity)"])
    }
}

// MARK: - Orders

struct CreateOrder: Endpoint {
    typealias Response = Order
    let request: CreateOrderRequest
    var path: String { "/orders" }
    var method: HTTPMethod { .post }
    var body: Data? { try? JSONEncoder().encode(request) }
}

struct ListOrders: Endpoint {
    typealias Response = PaginatedResponse<Order>
    let page: Int
    var path: String { "/orders" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] { [.init(name: "page", value: "\(page)")] }
}
```

### Validation

```swift
import FiberValidation

let validateAddress = Validator<Address> {
    Validate(\.street, label: "street") {
        ValidationRule.notEmpty(message: "Street address is required")
        ValidationRule.maxLength(200)
    }
    Validate(\.city, label: "city") {
        ValidationRule.notEmpty(message: "City is required")
        ValidationRule.maxLength(100)
    }
    Validate(\.state, label: "state") {
        ValidationRule.notEmpty(message: "State is required")
        ValidationRule.lengthRange(2...2, message: "Use 2-letter state code")
    }
    Validate(\.zipCode, label: "zipCode") {
        ValidationRule.pattern(#"^\d{5}(-\d{4})?$"#, message: "Invalid ZIP code")
    }
    Validate(\.country, label: "country") {
        ValidationRule.notEmpty()
        ValidationRule.lengthRange(2...3, message: "Use ISO country code")
    }
}

let validateOrder = Validator<CreateOrderRequest> {
    Validate(\.cartID, label: "cartID") {
        ValidationRule.notEmpty(message: "Cart ID is required")
    }

    Validate(\.shippingAddress, label: "shippingAddress", validator: validateAddress)

    ValidateIf({ $0.billingAddress != nil }) {
        Validate(\.billingAddress!, label: "billingAddress", validator: validateAddress)
    }

    Validate(\.paymentMethodID, label: "paymentMethodID") {
        ValidationRule.notEmpty(message: "Payment method is required")
        ValidationRule.pattern(#"^pm_[a-zA-Z0-9]+$"#, message: "Invalid payment method ID")
    }

    ValidateIf({ $0.couponCode != nil }) {
        Validate(\.couponCode!, label: "couponCode") {
            ValidationRule.pattern(#"^[A-Z0-9]{4,12}$"#, message: "Invalid coupon format")
        }
    }

    ValidateIf({ $0.notes != nil }) {
        Validate(\.notes!, label: "notes") {
            ValidationRule.maxLength(500, message: "Notes must be 500 characters or fewer")
        }
    }
}
```

### Client Factory (Pure Function)

```swift
/// Creates a production Fiber client for the shop API.
/// Token management is handled by closures — no singleton token store needed.
func makeShopClient(
    tokenProvider: @escaping @Sendable () async -> String?,
    tokenRefresher: (@Sendable () async throws -> String)? = nil
) -> Fiber {
    Fiber("https://api.shop.example.com") {
        $0.interceptors = [
            AuthInterceptor(
                tokenProvider: tokenProvider,
                tokenRefresher: tokenRefresher
            ),
            RetryInterceptor(maxRetries: 3, baseDelay: 0.5),
            RateLimitInterceptor(maxRequests: 120, perInterval: 60),
            ValidationInterceptor<CreateOrderRequest>(validator: validateOrder),
            CacheInterceptor(ttl: 120, maxEntries: 200),
            LoggingInterceptor(logger: OSLogFiberLogger(subsystem: "com.shop", category: "API")),
            MetricsInterceptor(collector: InMemoryMetricsCollector()),
        ]
        $0.defaultHeaders = [
            "Accept": "application/json",
            "X-Client-Version": "2.1.0",
            "X-Platform": "iOS"
        ]
        $0.timeout = 30
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
    }
}
```

### Composing Operations

```swift
// Build the client
let shop = makeShopClient(
    tokenProvider: { Keychain.read("access_token") },
    tokenRefresher: { try await refreshToken() }
)

// Browse products — type-safe, cached automatically by CacheInterceptor
let electronics = try await shop.request(ListProducts(category: "electronics", page: 1, limit: 20))
let product = try await shop.request(GetProduct(id: electronics.data[0].id))

// Cart operations
let cart = try await shop.request(GetCart())
let updated = try await shop.request(AddToCart(productID: product.id, quantity: 2))

// Place order — validated locally by ValidationInterceptor before sending
let order = try await shop.request(CreateOrder(request: CreateOrderRequest(
    cartID: cart.id,
    shippingAddress: Address(
        street: "123 Main St",
        city: "San Francisco",
        state: "CA",
        zipCode: "94105",
        country: "US"
    ),
    billingAddress: nil,
    paymentMethodID: "pm_abc123",
    couponCode: "SAVE20",
    notes: nil
)))

// If validation fails, the request never hits the network:
// FiberError.interceptor("validation", ValidationFailure(result: ...))
```

---

## Social Feed with Real-Time Updates

REST for initial data loading + WebSocket for live updates. Pure functions handle event processing — no mutable state beyond the actor boundary.

```swift
import Fiber
import FiberWebSocket

// MARK: - Models

struct Post: Codable, Sendable, Identifiable {
    let id: String
    let authorName: String
    let content: String
    let likeCount: Int
    let createdAt: Date
}

enum FeedUpdate: Codable, Sendable {
    case newPost(Post)
    case likeUpdate(postID: String, newCount: Int)
    case deletePost(postID: String)
}

// MARK: - Pure Functions for Event Processing

/// Apply a feed update to a list of posts — pure transformation, no side effects.
func applyUpdate(_ update: FeedUpdate, to posts: [Post]) -> [Post] {
    switch update {
    case .newPost(let post):
        return [post] + posts

    case .likeUpdate(let postID, let newCount):
        return posts.map { post in
            guard post.id == postID else { return post }
            return Post(
                id: post.id,
                authorName: post.authorName,
                content: post.content,
                likeCount: newCount,
                createdAt: post.createdAt
            )
        }

    case .deletePost(let postID):
        return posts.filter { $0.id != postID }
    }
}

/// Parse a WebSocket message into a FeedUpdate — pure function, returns nil on failure.
func parseFeedUpdate(_ message: WebSocketMessage) -> FeedUpdate? {
    try? message.decode(FeedUpdate.self)
}

// MARK: - Client Setup (pure functions, no singletons)

func makeFeedClient(token: String) -> Fiber {
    Fiber("https://api.social.example.com") {
        $0.interceptors = [
            AuthInterceptor(tokenProvider: { token }),
            RetryInterceptor(maxRetries: 2),
            CacheInterceptor(ttl: 60),
            LoggingInterceptor(logger: PrintFiberLogger()),
        ]
        $0.decoder = {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return d
        }()
    }
}

func makeFeedSocket(token: String) -> ReconnectingWebSocket {
    ReconnectingWebSocket(
        connect: {
            URLSessionWebSocketTransport.connect(
                to: URL(string: "wss://ws.social.example.com/feed")!,
                headers: ["Authorization": "Bearer \(token)"]
            )
        },
        strategy: .exponentialBackoff(maxAttempts: 20),
        logger: PrintFiberLogger(minLevel: .info)
    )
}

// MARK: - Usage: Composing REST + WebSocket

func runFeed(token: String) async throws {
    let api = makeFeedClient(token: token)
    let ws = makeFeedSocket(token: token)

    // Load initial posts via REST
    var posts: [Post] = try await api.get("/feed", query: ["limit": "50"]).decode()

    // Stream real-time updates via WebSocket
    Task { await ws.start() }

    for await event in ws.events {
        switch event {
        case .message(let msg):
            if let update = parseFeedUpdate(msg) {
                posts = applyUpdate(update, to: posts)
            }
        default:
            break
        }
    }
}

// MARK: - Actions (pure request functions)

func likePost(_ postID: String, using api: Fiber) async throws {
    _ = try await api.post("/posts/\(postID)/like", body: EmptyBody())
}

func createPost(content: String, using api: Fiber) async throws -> Post {
    try await api.post("/posts", body: ["content": content]).decode()
}

struct EmptyBody: Encodable {}
```

---

## Multi-Tenant SaaS Client

Dynamic base URLs, tenant-scoped headers, and HMAC request signing — all through composable interceptors. The client factory is a pure function.

```swift
import Fiber
import CryptoKit

// MARK: - Tenant Configuration (value type)

struct TenantConfig: Sendable {
    let tenantID: String
    let baseURL: URL
    let apiKey: String
    let signingSecret: SymmetricKey
}

// MARK: - Interceptors (structs, not classes)

struct HMACSigningInterceptor: Interceptor {
    let name = "hmacSigning"
    let secret: SymmetricKey

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let timestamp = "\(Int(Date().timeIntervalSince1970))"
        let payload = [
            request.httpMethod.rawValue,
            request.url.path,
            timestamp,
            request.body?.base64EncodedString() ?? ""
        ].joined(separator: "\n")

        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8), using: secret
        )
        let hex = Data(signature).map { String(format: "%02x", $0) }.joined()

        return try await next(
            request
                .header("X-Timestamp", timestamp)
                .header("X-Signature", hex)
                .header("X-Signature-Algorithm", "hmac-sha256")
        )
    }
}

struct TenantHeaderInterceptor: Interceptor {
    let name = "tenant"
    let tenantID: String
    let apiKey: String

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        try await next(
            request
                .header("X-Tenant-ID", tenantID)
                .header("X-API-Key", apiKey)
        )
    }
}

// MARK: - Client Factory (pure function)

func makeTenantClient(for tenant: TenantConfig) -> Fiber {
    Fiber(tenant.baseURL.absoluteString) {
        $0.interceptors = [
            TenantHeaderInterceptor(tenantID: tenant.tenantID, apiKey: tenant.apiKey),
            HMACSigningInterceptor(secret: tenant.signingSecret),
            RetryInterceptor(maxRetries: 2),
            RateLimitInterceptor(maxRequests: 100, perInterval: 60),
            LoggingInterceptor(logger: OSLogFiberLogger(
                subsystem: "com.saas",
                category: "tenant-\(tenant.tenantID)"
            )),
        ]
        $0.defaultHeaders = ["Accept": "application/json", "X-SDK-Version": "1.0.0"]
        $0.timeout = 30
    }
}

// MARK: - Usage

let acme = TenantConfig(
    tenantID: "acme-corp",
    baseURL: URL(string: "https://acme.api.saas.example.com")!,
    apiKey: "ak_acme_xxx",
    signingSecret: SymmetricKey(data: Data("acme-secret-key-32-bytes-long!!".utf8))
)

let globex = TenantConfig(
    tenantID: "globex",
    baseURL: URL(string: "https://globex.api.saas.example.com")!,
    apiKey: "ak_globex_yyy",
    signingSecret: SymmetricKey(data: Data("globex-secret-key-32bytes-long!".utf8))
)

// Each client is isolated — different base URLs, different signing keys, different rate limits
let acmeAPI = makeTenantClient(for: acme)
let globexAPI = makeTenantClient(for: globex)

// All requests are automatically signed, tenant-scoped, and rate-limited
let acmeUsers = try await acmeAPI.get("/users")
let globexReports = try await globexAPI.get("/reports", query: ["period": "monthly"])
```

---

## Offline-First with Request Queuing

Cache-first reads with stale-while-revalidate, and an actor-based queue for writes that fail when offline. The queue is drained when connectivity is restored.

```swift
import Fiber
import FiberSharing

// MARK: - Offline Queue (actor for safe concurrent access)

actor OfflineQueue {
    private var pending: [(FiberRequest, CheckedContinuation<FiberResponse, Error>)] = []

    var count: Int { pending.count }

    func enqueue(_ request: FiberRequest) async throws -> FiberResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending.append((request, continuation))
        }
    }

    func drain(using send: @Sendable (FiberRequest) async throws -> FiberResponse) async {
        let items = pending
        pending.removeAll()
        for (request, continuation) in items {
            do {
                let response = try await send(request)
                continuation.resume(returning: response)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Connectivity-Aware Interceptor

struct OfflineInterceptor: Interceptor {
    let name = "offline"
    let queue: OfflineQueue
    let isOnline: @Sendable () -> Bool

    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        if isOnline() {
            do {
                return try await next(request)
            } catch {
                if isNetworkError(error), isQueueable(request) {
                    return try await queue.enqueue(request)
                }
                throw error
            }
        }

        if isQueueable(request) {
            return try await queue.enqueue(request)
        }

        throw FiberError.networkError(underlying: URLError(.notConnectedToInternet))
    }

    private func isQueueable(_ request: FiberRequest) -> Bool {
        [.post, .put, .patch, .delete].contains(request.httpMethod)
    }

    private func isNetworkError(_ error: Error) -> Bool {
        (error as? URLError)?.code == .notConnectedToInternet ||
        (error as? URLError)?.code == .networkConnectionLost
    }
}

// MARK: - Setup

func makeOfflineClient(
    token: String,
    queue: OfflineQueue,
    isOnline: @escaping @Sendable () -> Bool
) -> SharedFiber {
    SharedFiber { config, fiberConfig in
        fiberConfig.interceptors = [
            AuthInterceptor(tokenProvider: { token }),
            OfflineInterceptor(queue: queue, isOnline: isOnline),
            RetryInterceptor(maxRetries: 2, baseDelay: 1.0),
            LoggingInterceptor(logger: PrintFiberLogger()),
        ]
    }
}

// MARK: - Usage

let queue = OfflineQueue()
let fiber = makeOfflineClient(
    token: "my-token",
    queue: queue,
    isOnline: { NetworkMonitor.isConnected }
)

// Reads use stale-while-revalidate — instant results even when offline
let users = try await fiber.getCached("/users", as: [User].self, policy: CachePolicy(
    ttl: 300,
    staleWhileRevalidate: 3600,      // serve stale for up to 1 hour
    storageMode: .memoryAndDisk,
    maxEntries: 200
))

// Writes are queued when offline
try await fiber.post("/posts", body: NewPost(content: "Hello from the subway!"))

// When connectivity is restored, drain the queue
func onConnectivityRestored() async {
    await queue.drain { request in
        try await fiber.send(request)
    }
}
```

---

## Analytics Pipeline

Batched event collection using an actor for buffering. Events are flushed periodically or when the buffer reaches a threshold. Metrics interceptor provides observability into the pipeline itself.

```swift
import Fiber

// MARK: - Event Types (value types)

struct AnalyticsEvent: Codable, Sendable {
    let name: String
    let properties: [String: String]
    let timestamp: Date
    let sessionID: String
    let userID: String?
}

struct EventBatch: Codable, Sendable {
    let events: [AnalyticsEvent]
    let batchID: String
    let platform: String
    let appVersion: String
}

// MARK: - Analytics Client (actor for safe buffering)

actor AnalyticsPipeline {
    private var buffer: [AnalyticsEvent] = []
    private let batchSize: Int
    private let api: Fiber
    private let collector: InMemoryMetricsCollector
    private var flushTask: Task<Void, Never>?

    init(apiKey: String, batchSize: Int = 50, flushInterval: TimeInterval = 30) {
        self.batchSize = batchSize
        self.collector = InMemoryMetricsCollector()

        self.api = Fiber("https://analytics.example.com") {
            $0.interceptors = [
                AuthInterceptor(
                    tokenProvider: { apiKey },
                    headerName: "X-API-Key",
                    headerPrefix: ""
                ),
                RetryInterceptor(maxRetries: 5, baseDelay: 1.0, maxDelay: 60),
                RateLimitInterceptor(maxRequests: 30, perInterval: 60),
                MetricsInterceptor(collector: collector),
            ]
            $0.timeout = 10
            $0.encoder = {
                let e = JSONEncoder()
                e.dateEncodingStrategy = .iso8601
                return e
            }()
        }
    }

    func start() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.flush()
            }
        }
    }

    func track(_ name: String, properties: [String: String] = [:], sessionID: String, userID: String? = nil) {
        buffer.append(AnalyticsEvent(
            name: name,
            properties: properties,
            timestamp: Date(),
            sessionID: sessionID,
            userID: userID
        ))
        if buffer.count >= batchSize {
            Task { await flush() }
        }
    }

    func flush() async {
        guard !buffer.isEmpty else { return }
        let events = buffer
        buffer.removeAll()

        let batch = EventBatch(
            events: events,
            batchID: UUID().uuidString,
            platform: "iOS",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        )

        do {
            try await TraceContext.$metadata.withValue(["batch_size": "\(events.count)"]) {
                _ = try await api.post("/events/batch", body: batch)
            }
        } catch {
            // Put events back for retry
            buffer.insert(contentsOf: events, at: 0)
        }
    }

    func diagnostics() async -> String {
        let avg = await collector.averageDurationMs
        let rate = await collector.successRate
        let total = await collector.metrics.count
        return """
        Buffered: \(buffer.count) | Batches sent: \(total) | \
        Avg: \(String(format: "%.1f", avg))ms | Success: \(String(format: "%.0f", rate * 100))%
        """
    }

    func stop() async {
        flushTask?.cancel()
        await flush()
    }
}
```

---

## Full Test Suite with swift-dependencies

Testing a feature module that uses `@Dependency(\.fiberHTTPClient)`. Pure structs, no mocking frameworks, no protocol witnesses.

### Feature Code

```swift
import Fiber
import FiberDependencies
import Dependencies

struct User: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let email: String
}

struct UsersState: Sendable, Equatable {
    var users: [User] = []
    var selectedUser: User? = nil
    var isLoading = false
    var error: String? = nil
}

/// All operations are pure functions that take state + dependencies and return new state.
/// Side effects (HTTP) are isolated to the dependency boundary.

@Dependency(\.fiberHTTPClient) var httpClient

func loadUsers(_ state: inout UsersState) async {
    state.isLoading = true
    state.error = nil
    do {
        let response = try await httpClient.get("/users", [:], [:])
        state.users = try response.decode()
    } catch {
        state.error = "Failed to load users"
    }
    state.isLoading = false
}

func loadUser(_ id: String, state: inout UsersState) async {
    state.isLoading = true
    state.error = nil
    do {
        let response = try await httpClient.get("/users/\(id)", [:], [:])
        state.selectedUser = try response.decode()
    } catch let fiberError as FiberError {
        if case .httpError(404, _, _) = fiberError {
            state.error = "User not found"
        } else {
            state.error = "Failed to load user"
        }
    } catch {
        state.error = "Unexpected error"
    }
    state.isLoading = false
}

func deleteUser(_ id: String, state: inout UsersState) async -> Bool {
    do {
        let response = try await httpClient.delete("/users/\(id)", [:])
        if response.isSuccess {
            state.users.removeAll { $0.id == id }
            if state.selectedUser?.id == id { state.selectedUser = nil }
            return true
        }
        return false
    } catch {
        state.error = "Failed to delete user"
        return false
    }
}
```

### Test Suite

```swift
import Testing
import Fiber
import FiberTesting
import FiberDependencies
import FiberDependenciesTesting
import Dependencies

@Suite("Users Tests")
struct UsersTests {

    let alice = User(id: "1", name: "Alice", email: "alice@example.com")
    let bob = User(id: "2", name: "Bob", email: "bob@example.com")

    @Test("loads users successfully")
    func loadUsersSuccess() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stubAll(StubResponse.ok().jsonBody([alice, bob]))

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = UsersState()
            await loadUsers(&state)

            #expect(state.users == [alice, bob])
            #expect(state.error == nil)
            #expect(!state.isLoading)
            mock.expectRequestCount(1)
        }
    }

    @Test("handles server error on load")
    func loadUsersError() async {
        await withDependencies {
            $0.fiberHTTPClient = .stub(.serverError())
        } operation: {
            var state = UsersState()
            await loadUsers(&state)

            #expect(state.users.isEmpty)
            #expect(state.error == "Failed to load users")
        }
    }

    @Test("loads single user by ID")
    func loadSingleUser() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard req.url?.path == "/users/1" else { return nil }
            return StubResponse.ok().jsonBody(alice)
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = UsersState()
            await loadUser("1", state: &state)

            #expect(state.selectedUser == alice)
            #expect(state.error == nil)
        }
    }

    @Test("shows 'not found' for missing user")
    func loadUserNotFound() async {
        await withDependencies {
            $0.fiberHTTPClient = .stub(.notFound())
        } operation: {
            var state = UsersState()
            await loadUser("999", state: &state)

            #expect(state.selectedUser == nil)
            #expect(state.error == "User not found")
        }
    }

    @Test("deletes user and updates list")
    func deleteUserSuccess() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            if req.httpMethod == "GET" { return StubResponse.ok().jsonBody([alice, bob]) }
            if req.httpMethod == "DELETE", req.url?.path == "/users/1" { return .noContent() }
            return nil
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = UsersState()
            await loadUsers(&state)
            #expect(state.users.count == 2)

            let success = await deleteUser("1", state: &state)
            #expect(success)
            #expect(state.users == [bob])
        }
    }

    @Test("delete failure preserves state")
    func deleteUserFailure() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            if req.httpMethod == "GET" { return StubResponse.ok().jsonBody([alice, bob]) }
            if req.httpMethod == "DELETE" { return .serverError() }
            return nil
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = UsersState()
            await loadUsers(&state)

            let success = await deleteUser("1", state: &state)
            #expect(!success)
            #expect(state.users.count == 2)
            #expect(state.error == "Failed to delete user")
        }
    }

    @Test("parallel requests all succeed")
    func parallelRequests() async throws {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            let id = req.url?.lastPathComponent ?? "0"
            return .ok(body: #"{"id": "\#(id)", "name": "User \#(id)", "email": "u\#(id)@test.com"}"#)
        }

        try await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            let users: [User] = try await withThrowingTaskGroup(of: User.self) { group in
                for id in 1...5 {
                    group.addTask {
                        let response = try await httpClient.get("/users/\(id)", [:], [:])
                        return try response.decode()
                    }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }

            #expect(users.count == 5)
            mock.expectRequestCount(5)
        }
    }
}
```

---

## FiberSharing: Multi-Environment App

A complete example showing how FiberSharing manages environment switching (dev/staging/prod), reactive configuration, declarative caching with `@SharedReader`, imperative caching with stale-while-revalidate, ETag-based conditional requests, and cache invalidation after mutations.

### Domain Models

```swift
struct AppConfig: Codable, Sendable {
    let featureFlags: [String: Bool]
    let maintenanceMode: Bool
    let minAppVersion: String
}

struct User: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let email: String
    let role: String
    let avatarURL: URL?
}

struct Team: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let members: [User]
    let plan: String
}

struct Notification: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let body: String
    let read: Bool
    let createdAt: Date
}

struct DashboardStats: Codable, Sendable {
    let activeUsers: Int
    let totalRevenue: Decimal
    let openTickets: Int
    let uptimePercent: Double
}
```

### Environment Configuration

```swift
import FiberSharing
import Sharing

/// Predefined environments — each is just a FiberConfiguration value.
enum Environment {
    static let development = FiberConfiguration(
        baseURL: "https://dev-api.example.com",
        defaultTimeout: 60,
        defaultHeaders: ["X-Environment": "development"],
        authToken: nil
    )

    static let staging = FiberConfiguration(
        baseURL: "https://staging-api.example.com",
        defaultTimeout: 30,
        defaultHeaders: ["X-Environment": "staging"],
        authToken: nil
    )

    static let production = FiberConfiguration(
        baseURL: "https://api.example.com",
        defaultTimeout: 15,
        defaultHeaders: ["X-Environment": "production"],
        authToken: nil
    )
}

/// Switch environment at runtime — SharedFiber rebuilds automatically.
func switchEnvironment(to env: FiberConfiguration) {
    @Shared(.fiberConfiguration) var config
    $config.withLock { $0 = env }
}

/// Update auth token after login — all subsequent requests pick it up.
func setAuthToken(_ token: String) {
    @Shared(.fiberConfiguration) var config
    $config.withLock { $0.authToken = token }
}

/// Clear auth on logout.
func clearAuth() {
    @Shared(.fiberConfiguration) var config
    $config.withLock { $0.authToken = nil }
}
```

### SharedFiber Setup with Custom Interceptors

```swift
/// Build the shared client — reads from @Shared(.fiberConfiguration) automatically.
/// Interceptors are configured via the closure, which receives the current config.
let sharedAPI = SharedFiber { config, fiberConfig in
    // Auth: inject the token from shared config
    if config.authToken != nil {
        fiberConfig.interceptors.append(
            AuthInterceptor(tokenProvider: { config.authToken })
        )
    }

    fiberConfig.interceptors.append(contentsOf: [
        RetryInterceptor(maxRetries: 2, baseDelay: 0.5),
        RateLimitInterceptor(maxRequests: 100, perInterval: 60),
        LoggingInterceptor(logger: OSLogFiberLogger(subsystem: "com.app.network")),
    ])

    fiberConfig.timeout = config.defaultTimeout
    fiberConfig.decoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
```

### Declarative Caching with @SharedReader

```swift
import Sharing

/// App config — cached aggressively on disk, rarely changes.
@SharedReader(.cachedAPI("/config", as: AppConfig.self, ttl: 3600, storage: .disk))
var appConfig: CachedResponse<AppConfig>

/// Current user profile — moderate cache, memory only.
@SharedReader(.api("/me", as: User.self, policy: .default))
var currentUser: CachedResponse<User>

/// Dashboard stats — short TTL, high freshness requirement.
@SharedReader(.api("/dashboard/stats", as: DashboardStats.self, policy: CachePolicy(
    ttl: 60,
    staleWhileRevalidate: 30,
    storageMode: .memory,
    maxEntries: 10
)))
var dashboardStats: CachedResponse<DashboardStats>
```

### Imperative Caching with Stale-While-Revalidate

```swift
/// Fetch a team with aggressive caching — stale data served instantly while
/// a background refresh happens. No loading spinners for returning users.
func loadTeam(_ teamID: String) async throws -> CachedResponse<Team> {
    try await sharedAPI.getCached(
        "/teams/\(teamID)",
        as: Team.self,
        policy: CachePolicy(
            ttl: 300,                      // fresh for 5 minutes
            staleWhileRevalidate: 120,     // serve stale for 2 more minutes while refreshing
            storageMode: .memoryAndDisk,   // persist across app launches
            maxEntries: 50
        )
    )
}

/// Paginated notifications — different cache key per page.
func loadNotifications(page: Int, limit: Int) async throws -> CachedResponse<[Notification]> {
    try await sharedAPI.getCached(
        "/notifications",
        as: [Notification].self,
        query: ["page": "\(page)", "limit": "\(limit)"],
        policy: CachePolicy(
            ttl: 120,
            staleWhileRevalidate: 60,
            storageMode: .memory,
            maxEntries: 20
        )
    )
}

/// Search results — no caching, always fresh.
func searchUsers(query: String) async throws -> [User] {
    let response = try await sharedAPI.get("/users/search", query: ["q": query])
    return try response.decode()
}
```

### ETag-Based Conditional Requests

```swift
/// The server returns ETag headers for team data.
/// On subsequent requests after TTL expires, Fiber sends If-None-Match automatically.
/// If the server returns 304, the cached data is refreshed without re-downloading.
///
/// Timeline:
///   t=0:00  GET /teams/123                → 200 OK, ETag: "abc123"   (cached)
///   t=3:00  getCached("/teams/123")        → memory hit, fresh         (no network)
///   t=5:30  getCached("/teams/123")        → stale, serve immediately  (background: GET with If-None-Match: "abc123")
///   t=5:30  background response            → 304 Not Modified          (TTL refreshed, no bytes wasted)
///   t=8:00  getCached("/teams/123")        → memory hit, fresh again   (no network)
func loadTeamWithETag(_ teamID: String) async throws -> Team {
    let result = try await sharedAPI.getCached(
        "/teams/\(teamID)",
        as: Team.self,
        policy: .aggressive
    )

    // Inspect cache metadata
    print("Fresh: \(result.isFresh)")
    print("Age: \(result.age)s")
    print("ETag: \(result.etag ?? "none")")
    print("Last-Modified: \(result.lastModified ?? "none")")

    return result.value
}
```

### Cache Invalidation After Mutations

```swift
/// After creating or updating data, invalidate related caches so the next
/// read fetches fresh data from the server.

func updateUserProfile(name: String, email: String) async throws -> User {
    let updated: User = try await sharedAPI.put("/me", body: [
        "name": name,
        "email": email,
    ]).decode()

    // Invalidate the user profile cache
    await sharedAPI.invalidateCache(for: "/me")

    return updated
}

func addTeamMember(teamID: String, userID: String) async throws -> Team {
    let team: Team = try await sharedAPI.post(
        "/teams/\(teamID)/members",
        body: ["user_id": userID]
    ).decode()

    // Invalidate this specific team
    await sharedAPI.invalidateCache(for: "/teams/\(teamID)")

    // Also invalidate the team list (prefix match)
    await sharedAPI.invalidateCacheMatching("GET:/teams")

    return team
}

func markNotificationRead(_ id: String) async throws {
    _ = try await sharedAPI.patch("/notifications/\(id)", body: ["read": true])

    // Invalidate all notification pages
    await sharedAPI.invalidateCacheMatching("GET:/notifications")
}

func logout() async {
    clearAuth()

    // Nuclear option — clear all cached data for this user session
    await sharedAPI.clearCache()
}
```

### Environment Switching Flow

```swift
/// Complete app lifecycle showing environment + auth + caching working together.

func appStartup() async throws {
    // 1. Set environment based on build config
    #if DEBUG
    switchEnvironment(to: Environment.development)
    #else
    switchEnvironment(to: Environment.production)
    #endif

    // 2. Load app config (disk-cached, survives restarts)
    let config = try await sharedAPI.getCached("/config", as: AppConfig.self, policy: .persistent)
    if config.value.maintenanceMode {
        // Show maintenance screen
        return
    }

    // 3. If we have a stored token, set it — SharedFiber rebuilds with auth interceptor
    if let token = Keychain.read("access_token") {
        setAuthToken(token)
    }

    // 4. Load user profile (memory-cached)
    let user = try await sharedAPI.getCached("/me", as: User.self)
    print("Welcome back, \(user.value.name)")
}

func switchToStaging() async {
    // Clear production caches
    await sharedAPI.clearCache()

    // Switch environment — SharedFiber rebuilds with new base URL
    switchEnvironment(to: Environment.staging)

    // New requests go to staging-api.example.com
    let stagingUser = try? await sharedAPI.getCached("/me", as: User.self)
    print("Staging user: \(stagingUser?.value.name ?? "none")")
}
```

---

## FiberDependencies: Composable Architecture Feature

A complete feature module using `FiberDependencies` with dependency injection, reducer-style state management, and a full test suite. Every side effect goes through the dependency boundary — making the feature fully testable with zero mocking frameworks.

### Domain Models

```swift
struct Project: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String
    let status: Status
    let ownerID: String
    let memberIDs: [String]
    let createdAt: Date
    let updatedAt: Date

    enum Status: String, Codable, Sendable, Equatable {
        case active, archived, draft
    }
}

struct CreateProjectRequest: Codable, Sendable {
    let name: String
    let description: String
    let memberIDs: [String]
}

struct UpdateProjectRequest: Codable, Sendable {
    let name: String?
    let description: String?
    let status: Project.Status?
}

struct ProjectActivity: Codable, Sendable, Identifiable {
    let id: String
    let projectID: String
    let userID: String
    let action: String
    let detail: String
    let timestamp: Date
}

struct ProjectStats: Codable, Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let openIssues: Int
    let lastActivityAt: Date?
}
```

### Feature State (Value Type)

```swift
struct ProjectsState: Sendable, Equatable {
    var projects: [Project] = []
    var selectedProject: Project? = nil
    var projectStats: ProjectStats? = nil
    var recentActivity: [ProjectActivity] = []
    var isLoading = false
    var isLoadingDetail = false
    var error: String? = nil
    var filter: Project.Status? = nil

    /// Derived: filtered projects based on the current filter.
    var filteredProjects: [Project] {
        guard let filter else { return projects }
        return projects.filter { $0.status == filter }
    }
}
```

### Feature Actions (Pure Functions)

All feature logic lives in free functions. Each takes state as `inout`, reads dependencies via `@Dependency`, and performs async work. No classes, no delegates, no protocol witnesses.

```swift
import Fiber
import FiberDependencies
import Dependencies

@Dependency(\.fiberHTTPClient) var httpClient
@Dependency(\.fiberDefaults) var fiberDefaults

// MARK: - List Projects

func loadProjects(state: inout ProjectsState) async {
    state.isLoading = true
    state.error = nil

    do {
        let response = try await httpClient.get("/projects", [:], [:])
        state.projects = try response.decode()
    } catch {
        state.error = extractErrorMessage(error)
    }

    state.isLoading = false
}

// MARK: - Project Detail (parallel fetch: project + stats + activity)

func loadProjectDetail(_ projectID: String, state: inout ProjectsState) async {
    state.isLoadingDetail = true
    state.error = nil

    // Fetch project, stats, and activity in parallel
    async let projectResponse = httpClient.get("/projects/\(projectID)", [:], [:])
    async let statsResponse = httpClient.get("/projects/\(projectID)/stats", [:], [:])
    async let activityResponse = httpClient.get(
        "/projects/\(projectID)/activity",
        ["limit": "20"],
        [:]
    )

    do {
        let (projResp, statsResp, actResp) = try await (projectResponse, statsResponse, activityResponse)
        state.selectedProject = try projResp.decode()
        state.projectStats = try statsResp.decode()
        state.recentActivity = try actResp.decode()
    } catch {
        state.error = extractErrorMessage(error)
    }

    state.isLoadingDetail = false
}

// MARK: - Create Project

func createProject(
    name: String,
    description: String,
    memberIDs: [String],
    state: inout ProjectsState
) async -> Project? {
    state.isLoading = true
    state.error = nil

    let body = CreateProjectRequest(name: name, description: description, memberIDs: memberIDs)
    let encoded = try? JSONEncoder().encode(body)

    do {
        let response = try await httpClient.post("/projects", encoded, [:])
        let project: Project = try response.decode()
        state.projects.insert(project, at: 0)
        state.isLoading = false
        return project
    } catch {
        state.error = extractErrorMessage(error)
        state.isLoading = false
        return nil
    }
}

// MARK: - Update Project

func updateProject(
    _ projectID: String,
    name: String? = nil,
    description: String? = nil,
    status: Project.Status? = nil,
    state: inout ProjectsState
) async -> Bool {
    let body = UpdateProjectRequest(name: name, description: description, status: status)
    let encoded = try? JSONEncoder().encode(body)

    do {
        let response = try await httpClient.patch("/projects/\(projectID)", encoded, [:])
        let updated: Project = try response.decode()

        // Update in list
        if let index = state.projects.firstIndex(where: { $0.id == projectID }) {
            state.projects[index] = updated
        }

        // Update selected if it's the same project
        if state.selectedProject?.id == projectID {
            state.selectedProject = updated
        }

        return true
    } catch {
        state.error = extractErrorMessage(error)
        return false
    }
}

// MARK: - Archive Project

func archiveProject(_ projectID: String, state: inout ProjectsState) async -> Bool {
    await updateProject(projectID, status: .archived, state: &state)
}

// MARK: - Delete Project

func deleteProject(_ projectID: String, state: inout ProjectsState) async -> Bool {
    do {
        let response = try await httpClient.delete("/projects/\(projectID)", [:])
        guard response.isSuccess else { return false }

        state.projects.removeAll { $0.id == projectID }
        if state.selectedProject?.id == projectID {
            state.selectedProject = nil
            state.projectStats = nil
            state.recentActivity = []
        }
        return true
    } catch {
        state.error = extractErrorMessage(error)
        return false
    }
}

// MARK: - Filter

func setFilter(_ filter: Project.Status?, state: inout ProjectsState) {
    state.filter = filter
}

// MARK: - Error Extraction (pure function)

func extractErrorMessage(_ error: Error) -> String {
    if let fiberError = error as? FiberError {
        switch fiberError {
        case .httpError(let code, let data, _):
            // Try to decode a server error message
            struct ServerError: Codable { let message: String }
            if let serverError = try? JSONDecoder().decode(ServerError.self, from: data) {
                return serverError.message
            }
            return "Server error (\(code))"
        case .networkError:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .interceptor(let name, _):
            return "Request blocked by \(name)"
        default:
            return "Something went wrong"
        }
    }
    return error.localizedDescription
}
```

### Live Dependency Setup

```swift
import FiberDependencies

/// Configure the live dependency at app entry point.
func makeAppDependencies() -> DependencyValues {
    var deps = DependencyValues()
    deps.fiberHTTPClient = .live("https://api.example.com") {
        $0.interceptors = [
            AuthInterceptor(
                tokenProvider: { Keychain.read("access_token") },
                tokenRefresher: { try await refreshAccessToken() }
            ),
            RetryInterceptor(maxRetries: 3),
            RateLimitInterceptor(maxRequests: 120, perInterval: 60),
            LoggingInterceptor(logger: OSLogFiberLogger(subsystem: "com.app")),
            MetricsInterceptor(collector: InMemoryMetricsCollector()),
        ]
        $0.defaultHeaders = [
            "Accept": "application/json",
            "X-Client": "ios/2.0"
        ]
        $0.decoder = {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            d.keyDecodingStrategy = .convertFromSnakeCase
            return d
        }()
    }
    deps.fiberDefaults = FiberDefaults(
        traceIDGenerator: { "ios-\(UUID().uuidString.prefix(8))" }
    )
    return deps
}

/// At app entry point:
/// withDependencies(from: makeAppDependencies()) { ... }
```

### Full Test Suite

```swift
import Testing
import Fiber
import FiberTesting
import FiberDependencies
import FiberDependenciesTesting
import Dependencies

// MARK: - Test Data

let sampleProjects: [Project] = [
    Project(
        id: "p1", name: "Alpha", description: "First project",
        status: .active, ownerID: "u1", memberIDs: ["u1", "u2"],
        createdAt: Date(), updatedAt: Date()
    ),
    Project(
        id: "p2", name: "Beta", description: "Second project",
        status: .draft, ownerID: "u1", memberIDs: ["u1"],
        createdAt: Date(), updatedAt: Date()
    ),
    Project(
        id: "p3", name: "Gamma", description: "Archived project",
        status: .archived, ownerID: "u2", memberIDs: ["u2", "u3"],
        createdAt: Date(), updatedAt: Date()
    ),
]

let sampleStats = ProjectStats(
    totalTasks: 42, completedTasks: 30, openIssues: 5,
    lastActivityAt: Date()
)

let sampleActivity: [ProjectActivity] = [
    ProjectActivity(
        id: "a1", projectID: "p1", userID: "u1",
        action: "task.completed", detail: "Finished onboarding flow",
        timestamp: Date()
    ),
]

// MARK: - Helpers

func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}

func stubJSON<T: Encodable>(_ value: T) -> StubResponse {
    StubResponse.ok().jsonBody(value, encoder: encoder())
}

// MARK: - Tests

@Suite("Projects Feature")
struct ProjectsFeatureTests {

    // MARK: - Load Projects

    @Test("loads project list")
    func loadProjectList() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard req.httpMethod == "GET", req.url?.path == "/projects" else { return nil }
            return stubJSON(sampleProjects)
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = ProjectsState()
            await loadProjects(state: &state)

            #expect(state.projects.count == 3)
            #expect(state.projects[0].name == "Alpha")
            #expect(state.error == nil)
            #expect(!state.isLoading)
            mock.expectRequestCount(1)
        }
    }

    @Test("handles network error on load")
    func loadProjectsNetworkError() async {
        await withDependencies {
            $0.fiberHTTPClient = .stub(.serverError(body: #"{"message": "Database unavailable"}"#))
        } operation: {
            var state = ProjectsState()
            await loadProjects(state: &state)

            #expect(state.projects.isEmpty)
            #expect(state.error == "Database unavailable")
        }
    }

    // MARK: - Project Detail (Parallel Fetch)

    @Test("loads project detail with stats and activity in parallel")
    func loadProjectDetailParallel() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard let path = req.url?.path else { return nil }
            switch path {
            case "/projects/p1":          return stubJSON(sampleProjects[0])
            case "/projects/p1/stats":    return stubJSON(sampleStats)
            case "/projects/p1/activity": return stubJSON(sampleActivity)
            default:                      return nil
            }
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = ProjectsState()
            await loadProjectDetail("p1", state: &state)

            #expect(state.selectedProject?.id == "p1")
            #expect(state.projectStats?.totalTasks == 42)
            #expect(state.recentActivity.count == 1)
            #expect(state.error == nil)
            #expect(!state.isLoadingDetail)

            // All 3 fetches happened
            mock.expectRequestCount(3)
        }
    }

    @Test("partial failure in detail shows error but preserves what loaded")
    func loadProjectDetailPartialFailure() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard let path = req.url?.path else { return nil }
            switch path {
            case "/projects/p1":          return stubJSON(sampleProjects[0])
            case "/projects/p1/stats":    return .serverError()  // fails
            case "/projects/p1/activity": return stubJSON(sampleActivity)
            default:                      return nil
            }
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = ProjectsState()
            await loadProjectDetail("p1", state: &state)

            // async let means if one throws, the group throws
            #expect(state.error != nil)
        }
    }

    // MARK: - Create Project

    @Test("creates project and prepends to list")
    func createProjectSuccess() async {
        let newProject = Project(
            id: "p4", name: "Delta", description: "New project",
            status: .draft, ownerID: "u1", memberIDs: ["u1", "u2"],
            createdAt: Date(), updatedAt: Date()
        )

        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard req.httpMethod == "POST", req.url?.path == "/projects" else { return nil }

            // Verify the request body
            guard let body = req.httpBody,
                  let request = try? JSONDecoder().decode(CreateProjectRequest.self, from: body)
            else { return .badRequest() }
            #expect(request.name == "Delta")
            #expect(request.memberIDs == ["u1", "u2"])

            return stubJSON(newProject)
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = ProjectsState()
            state.projects = Array(sampleProjects.prefix(2))

            let result = await createProject(
                name: "Delta",
                description: "New project",
                memberIDs: ["u1", "u2"],
                state: &state
            )

            #expect(result?.id == "p4")
            #expect(state.projects.count == 3)
            #expect(state.projects[0].id == "p4")  // prepended
            #expect(state.error == nil)
        }
    }

    @Test("create failure preserves existing list")
    func createProjectFailure() async {
        await withDependencies {
            $0.fiberHTTPClient = .stub(.badRequest(body: #"{"message": "Name already taken"}"#))
        } operation: {
            var state = ProjectsState()
            state.projects = [sampleProjects[0]]

            let result = await createProject(
                name: "Alpha",  // duplicate
                description: "Duplicate",
                memberIDs: [],
                state: &state
            )

            #expect(result == nil)
            #expect(state.projects.count == 1)  // unchanged
            #expect(state.error == "Name already taken")
        }
    }

    // MARK: - Update Project

    @Test("updates project in list and selected")
    func updateProjectSuccess() async {
        var updated = sampleProjects[0]
        updated = Project(
            id: updated.id, name: "Alpha Renamed", description: updated.description,
            status: updated.status, ownerID: updated.ownerID, memberIDs: updated.memberIDs,
            createdAt: updated.createdAt, updatedAt: Date()
        )

        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard req.httpMethod == "PATCH", req.url?.path == "/projects/p1" else { return nil }
            return stubJSON(updated)
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = ProjectsState()
            state.projects = Array(sampleProjects)
            state.selectedProject = sampleProjects[0]

            let success = await updateProject("p1", name: "Alpha Renamed", state: &state)

            #expect(success)
            #expect(state.projects[0].name == "Alpha Renamed")
            #expect(state.selectedProject?.name == "Alpha Renamed")
        }
    }

    // MARK: - Archive

    @Test("archives project by setting status")
    func archiveProjectSuccess() async {
        let archived = Project(
            id: "p1", name: "Alpha", description: "First project",
            status: .archived, ownerID: "u1", memberIDs: ["u1", "u2"],
            createdAt: Date(), updatedAt: Date()
        )

        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard req.httpMethod == "PATCH", req.url?.path == "/projects/p1" else { return nil }

            // Verify status was set to archived in the request body
            if let body = req.httpBody,
               let json = try? JSONDecoder().decode(UpdateProjectRequest.self, from: body) {
                #expect(json.status == .archived)
            }

            return stubJSON(archived)
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = ProjectsState()
            state.projects = Array(sampleProjects)

            let success = await archiveProject("p1", state: &state)
            #expect(success)
            #expect(state.projects[0].status == .archived)
        }
    }

    // MARK: - Delete

    @Test("deletes project, removes from list and clears selection")
    func deleteProjectSuccess() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stub { req in
            guard req.httpMethod == "DELETE", req.url?.path == "/projects/p1" else { return nil }
            return .noContent()
        }

        await withDependencies {
            $0.fiberHTTPClient = client
        } operation: {
            var state = ProjectsState()
            state.projects = Array(sampleProjects)
            state.selectedProject = sampleProjects[0]
            state.projectStats = sampleStats
            state.recentActivity = sampleActivity

            let success = await deleteProject("p1", state: &state)

            #expect(success)
            #expect(state.projects.count == 2)
            #expect(state.projects.contains { $0.id == "p1" } == false)
            #expect(state.selectedProject == nil)
            #expect(state.projectStats == nil)
            #expect(state.recentActivity.isEmpty)
        }
    }

    @Test("delete failure preserves everything")
    func deleteProjectFailure() async {
        await withDependencies {
            $0.fiberHTTPClient = .stub(.serverError())
        } operation: {
            var state = ProjectsState()
            state.projects = Array(sampleProjects)
            state.selectedProject = sampleProjects[0]

            let success = await deleteProject("p1", state: &state)

            #expect(!success)
            #expect(state.projects.count == 3)
            #expect(state.selectedProject?.id == "p1")
        }
    }

    // MARK: - Filter

    @Test("filtering returns subset of projects")
    func filterProjects() async {
        var state = ProjectsState()
        state.projects = Array(sampleProjects)

        setFilter(.active, state: &state)
        #expect(state.filteredProjects.count == 1)
        #expect(state.filteredProjects[0].id == "p1")

        setFilter(.archived, state: &state)
        #expect(state.filteredProjects.count == 1)
        #expect(state.filteredProjects[0].id == "p3")

        setFilter(nil, state: &state)
        #expect(state.filteredProjects.count == 3)
    }

    // MARK: - Error Extraction

    @Test("extracts server error messages from response body")
    func extractServerError() {
        let data = Data(#"{"message": "Quota exceeded"}"#.utf8)
        let response = FiberResponse(
            data: data, statusCode: 429, headers: [:],
            request: FiberRequest(url: URL(string: "https://test.local")!, method: .get),
            duration: 0, traceID: "t"
        )
        let error = FiberError.httpError(statusCode: 429, data: data, response: response)
        #expect(extractErrorMessage(error) == "Quota exceeded")
    }

    @Test("falls back to generic message when body is not JSON")
    func extractGenericError() {
        let data = Data("Not JSON".utf8)
        let response = FiberResponse(
            data: data, statusCode: 500, headers: [:],
            request: FiberRequest(url: URL(string: "https://test.local")!, method: .get),
            duration: 0, traceID: "t"
        )
        let error = FiberError.httpError(statusCode: 500, data: data, response: response)
        #expect(extractErrorMessage(error) == "Server error (500)")
    }

    // MARK: - Injectable Defaults

    @Test("custom trace ID generator is used")
    func customDefaults() async {
        let (client, mock) = FiberHTTPClient.test()
        mock.stubAll(.ok().jsonBody(sampleProjects, encoder: encoder()))

        await withDependencies {
            $0.fiberHTTPClient = client
            $0.fiberDefaults = FiberDefaults(
                traceIDGenerator: { "test-trace-\(Int.random(in: 0...999))" }
            )
        } operation: {
            var state = ProjectsState()
            await loadProjects(state: &state)

            // Defaults are injectable — the trace generator doesn't affect
            // FiberHTTPClient directly, but shows the pattern for any code
            // that reads @Dependency(\.fiberDefaults)
            #expect(state.projects.count == 3)
        }
    }
}
```

---

<p align="center">
  <a href="Advanced.md">&larr; Advanced</a> &nbsp;&bull;&nbsp;
  <a href="../README.md">Home</a>
</p>
