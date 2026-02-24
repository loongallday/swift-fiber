import Testing
import Foundation
import Fiber
import FiberTesting
import TestServer

// MARK: - Response Models

struct EchoResponse: Codable, Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let query: [String: String]
    let body: String
}

struct TokenResponse: Codable, Sendable {
    let token: String
}

struct AuthMessage: Codable, Sendable {
    let message: String
}

// MARK: - Helpers

actor TokenStore {
    var token: String
    init(_ initial: String) { self.token = initial }
    func setToken(_ t: String) { token = t }
}

// MARK: - Tests

@Suite("E2E")
struct E2ETests {

    // MARK: - HTTP Methods

    @Test("GET /echo")
    func getEcho() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.get("/echo")
        #expect(response.statusCode == 200)

        let echo: EchoResponse = try response.decode()
        #expect(echo.method == "GET")
    }

    @Test("POST /echo with body")
    func postEcho() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let body = ["greeting": "hello"]
        let response = try await client.post("/echo", body: body)
        #expect(response.statusCode == 200)

        let echo: EchoResponse = try response.decode()
        #expect(echo.method == "POST")
        #expect(echo.body.contains("hello"))
    }

    @Test("PUT /echo")
    func putEcho() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.put("/echo", body: ["key": "value"])
        let echo: EchoResponse = try response.decode()
        #expect(echo.method == "PUT")
    }

    @Test("PATCH /echo")
    func patchEcho() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.patch("/echo", body: ["key": "value"])
        let echo: EchoResponse = try response.decode()
        #expect(echo.method == "PATCH")
    }

    @Test("DELETE /echo")
    func deleteEcho() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.delete("/echo")
        let echo: EchoResponse = try response.decode()
        #expect(echo.method == "DELETE")
    }

    // MARK: - Request / Response

    @Test("Custom headers sent")
    func headersSent() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.get("/headers", headers: ["X-Custom": "test-value"])
        #expect(response.statusCode == 200)

        let headers: [String: String] = try response.decode()
        // Header name casing may vary
        let value = headers["X-Custom"] ?? headers["x-custom"]
        #expect(value == "test-value")
    }

    @Test("Query parameters")
    func queryParams() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.get("/echo", query: ["foo": "bar", "baz": "qux"])
        let echo: EchoResponse = try response.decode()
        #expect(echo.query["foo"] == "bar")
        #expect(echo.query["baz"] == "qux")
    }

    @Test("JSON round-trip")
    func jsonRoundTrip() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        struct Item: Codable, Sendable, Equatable {
            let name: String
            let count: Int
        }

        let input = Item(name: "widget", count: 42)
        let response = try await client.post("/json", body: input)
        #expect(response.statusCode == 200)
        #expect(response.header("Content-Type")?.contains("application/json") == true)

        let output: Item = try response.decode()
        #expect(input == output)
    }

    @Test("Status codes")
    func statusCodes() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let r201 = try await client.get("/status/201")
        #expect(r201.statusCode == 201)

        let r404 = try await client.get("/status/404")
        #expect(r404.statusCode == 404)

        let r500 = try await client.get("/status/500")
        #expect(r500.statusCode == 500)
    }

    @Test("Response properties")
    func responseProperties() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.get("/echo")
        #expect(response.duration > 0)
        #expect(!response.headers.isEmpty)
        #expect(response.text != nil)
    }

    // MARK: - Interceptors

    @Test("Auth interceptor with refresh")
    func authRefresh() async throws {
        try await TestServer.shared.ensureStarted()
        let baseURL = await TestServer.shared.baseURL

        let store = TokenStore("expired-token")
        let auth = AuthInterceptor(
            tokenProvider: { await store.token },
            tokenRefresher: {
                // Make a real HTTP call to refresh the token
                let url = URL(string: "\(baseURL)/auth/refresh")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                let (data, _) = try await URLSession.shared.data(for: req)
                let result = try JSONDecoder().decode(TokenResponse.self, from: data)
                await store.setToken(result.token)
                return result.token
            }
        )

        let client = Fiber(baseURL) { $0.interceptors = [auth] }
        let response = try await client.get("/auth/protected")
        #expect(response.statusCode == 200)

        let body: AuthMessage = try response.decode()
        #expect(body.message == "authenticated")
    }

    @Test("Retry interceptor against flaky endpoint")
    func retryFlaky() async throws {
        try await TestServer.shared.ensureStarted()
        let baseURL = await TestServer.shared.baseURL

        let retry = RetryInterceptor(
            maxRetries: 3,
            baseDelay: 0.05,
            retryableStatusCodes: [500],
            retryableMethods: [.get]
        )

        let client = Fiber(baseURL) { $0.interceptors = [retry] }

        // Unique key per test run to avoid collision
        let key = UUID().uuidString
        let response = try await client.get("/flaky", query: ["fail": "2", "key": key])
        #expect(response.statusCode == 200)
        #expect(response.text == "OK")
    }

    @Test("Cache interceptor serves from cache")
    func cacheInterceptor() async throws {
        try await TestServer.shared.ensureStarted()
        let baseURL = await TestServer.shared.baseURL

        actor Counter {
            var count = 0
            func increment() { count += 1 }
        }

        let networkCounter = Counter()
        let countingInterceptor = AnyInterceptor("counter") { request, next in
            await networkCounter.increment()
            return try await next(request)
        }

        let cache = CacheInterceptor(ttl: 60)
        let client = Fiber(baseURL) {
            $0.interceptors = [cache, countingInterceptor]
        }

        let first = try await client.get("/cache")
        #expect(first.statusCode == 200)
        #expect(first.text == "cached-content")

        let second = try await client.get("/cache")
        #expect(second.statusCode == 200)
        #expect(second.text == "cached-content")

        let count = await networkCounter.count
        #expect(count == 1, "Expected only 1 network request, got \(count)")
    }

    @Test("Logging and Metrics interceptors")
    func loggingAndMetrics() async throws {
        try await TestServer.shared.ensureStarted()
        let baseURL = await TestServer.shared.baseURL

        let tracer = TestTraceCollector()
        let metricsCollector = InMemoryMetricsCollector()

        let client = Fiber(baseURL) {
            $0.interceptors = [
                tracer.interceptor(),
                LoggingInterceptor(logger: tracer.logger()),
                MetricsInterceptor(collector: metricsCollector),
            ]
        }

        _ = try await client.get("/echo")

        #expect(tracer.spans.count == 1)
        #expect(tracer.spans[0].durationMs! > 0)
        #expect(!tracer.logs.isEmpty)

        let metrics = await metricsCollector.metrics
        #expect(metrics.count == 1)
        #expect(metrics[0].success)
        #expect(metrics[0].durationMs > 0)
    }

    // MARK: - Edge Cases

    @Test("Timeout on slow endpoint")
    func timeout() async throws {
        try await TestServer.shared.ensureStarted()
        let baseURL = await TestServer.shared.baseURL

        let client = Fiber(baseURL)
        let req = FiberRequest(url: URL(string: "\(baseURL)/delay/5000")!, timeout: 0.1)

        do {
            _ = try await client.send(req)
            Issue.record("Expected timeout error")
        } catch {
            // Expected — URLSession throws URLError.timedOut
        }
    }

    @Test("Parallel requests")
    func parallelRequests() async throws {
        try await TestServer.shared.ensureStarted()
        let baseURL = await TestServer.shared.baseURL
        let client = Fiber(baseURL)

        try await withThrowingTaskGroup(of: FiberResponse.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await client.get("/echo")
                }
            }
            var count = 0
            for try await response in group {
                #expect(response.statusCode == 200)
                count += 1
            }
            #expect(count == 10)
        }
    }

    @Test("Large response body")
    func largeResponse() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        let response = try await client.get("/bytes/100000")
        #expect(response.statusCode == 200)
        #expect(response.data.count == 100000)
    }

    // MARK: - Endpoint Protocol

    @Test("Type-safe Endpoint")
    func typeSafeEndpoint() async throws {
        try await TestServer.shared.ensureStarted()
        let client = Fiber(await TestServer.shared.baseURL)

        struct GetEcho: Endpoint {
            typealias Response = EchoResponse
            var path: String { "/echo" }
            var method: HTTPMethod { .get }
        }

        let echo = try await client.request(GetEcho())
        #expect(echo.method == "GET")
        #expect(echo.path == "/echo")
    }
}
