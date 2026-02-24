import Testing
import Foundation
import CryptoKit
@testable import Fiber
@testable import FiberTesting

// Helper actor for collecting values in Sendable closures
private actor OrderCollector {
    var items: [String] = []
    func append(_ item: String) { items.append(item) }
}

private actor StringHolder {
    var value: String = ""
    func set(_ v: String) { value = v }
}

@Suite("Interceptors")
struct InterceptorTests {

    let baseURL = URL(string: "https://api.example.com")!

    // MARK: - Interceptor Chain

    @Test("Interceptors execute in order")
    func interceptorOrder() async throws {
        let order = OrderCollector()

        let first = AnyInterceptor("first") { req, next in
            await order.append("first-before")
            let res = try await next(req)
            await order.append("first-after")
            return res
        }
        let second = AnyInterceptor("second") { req, next in
            await order.append("second-before")
            let res = try await next(req)
            await order.append("second-after")
            return res
        }

        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [first, second], transport: mock)
        _ = try await fiber.get("/test")

        let items = await order.items
        #expect(items == ["first-before", "second-before", "second-after", "first-after"])
    }

    @Test("Interceptor can short-circuit")
    func interceptorShortCircuit() async throws {
        let cached = AnyInterceptor("cached") { req, _ in
            FiberResponse(data: Data("cached".utf8), statusCode: 200, request: req)
        }

        let mock = MockTransport()
        let fiber = Fiber(baseURL: baseURL, interceptors: [cached], transport: mock)
        let response = try await fiber.get("/test")

        #expect(response.text == "cached")
        #expect(mock.requests.isEmpty)
    }

    @Test("Interceptor can modify request")
    func interceptorModifiesRequest() async throws {
        let addHeader = AnyInterceptor("addHeader") { req, next in
            try await next(req.header("X-Injected", "yes"))
        }

        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [addHeader], transport: mock)
        _ = try await fiber.get("/test")

        #expect(mock.lastRequest?.value(forHTTPHeaderField: "X-Injected") == "yes")
    }

    // MARK: - Auth Interceptor

    @Test("AuthInterceptor injects token")
    func authInjectsToken() async throws {
        let auth = AuthInterceptor(tokenProvider: { "my-token" })

        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [auth], transport: mock)
        _ = try await fiber.get("/secure")

        let authHeader = mock.lastRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(authHeader == "Bearer my-token")
    }

    // MARK: - Logging Interceptor

    @Test("LoggingInterceptor logs request and response")
    func loggingInterceptor() async throws {
        let collector = TestTraceCollector()
        let logging = LoggingInterceptor(logger: collector.logger())

        let mock = MockTransport()
        mock.stubAll(.ok(body: "hello"))

        let fiber = Fiber(baseURL: baseURL, interceptors: [logging], transport: mock)
        _ = try await fiber.get("/test")

        let logs = collector.logs
        #expect(logs.count >= 2)
    }

    // MARK: - Metrics Interceptor

    @Test("MetricsInterceptor collects metrics")
    func metricsCollection() async throws {
        let metricsCollector = InMemoryMetricsCollector()
        let metrics = MetricsInterceptor(collector: metricsCollector)

        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [metrics], transport: mock)
        _ = try await fiber.get("/test")

        let collected = await metricsCollector.metrics
        #expect(collected.count == 1)
        #expect(collected[0].method == "GET")
        #expect(collected[0].success == true)
        #expect(collected[0].durationMs >= 0)
    }

    // MARK: - Cache Interceptor

    @Test("CacheInterceptor caches GET responses")
    func cacheInterceptor() async throws {
        let cache = CacheInterceptor(ttl: 60)

        let mock = MockTransport()
        mock.stubAll(.ok(body: "fresh"))

        let fiber = Fiber(baseURL: baseURL, interceptors: [cache], transport: mock)

        let r1 = try await fiber.get("/config")
        #expect(r1.text == "fresh")
        #expect(mock.requests.count == 1)

        let r2 = try await fiber.get("/config")
        #expect(r2.text == "fresh")
        #expect(mock.requests.count == 1)
    }

    @Test("CacheInterceptor does not cache POST")
    func cacheDoesNotCachePost() async throws {
        let cache = CacheInterceptor(ttl: 60)

        let mock = MockTransport()
        mock.stubAll(.ok(body: "ok"))

        let fiber = Fiber(baseURL: baseURL, interceptors: [cache], transport: mock)

        _ = try await fiber.post("/data", data: nil)
        _ = try await fiber.post("/data", data: nil)

        #expect(mock.requests.count == 2)
    }

    // MARK: - Encryption Interceptor

    @Test("EncryptionInterceptor encrypts and decrypts")
    func encryptionRoundTrip() async throws {
        let key = SymmetricKey(size: .bits256)
        let provider = AESGCMEncryptionProvider(key: key)
        let encryption = EncryptionInterceptor(provider: provider)

        let mock = MockTransport()
        mock.stub { req in
            let body = req.httpBody ?? Data()
            return StubResponse(statusCode: 200, data: body)
        }

        let fiber = Fiber(baseURL: baseURL, interceptors: [encryption], transport: mock)
        let original = "hello world"
        let req = try FiberRequest(url: baseURL.appendingPathComponent("/echo"), method: .post)
            .jsonBody(original, encoder: JSONEncoder())
        let response = try await fiber.send(req)

        let decoded: String = try response.decode()
        #expect(decoded == original)
    }

    // MARK: - Trace Context

    @Test("TraceContext propagates trace ID")
    func traceContextPropagation() async throws {
        let holder = StringHolder()

        let capturer = AnyInterceptor("capturer") { req, next in
            await holder.set(TraceContext.traceID)
            return try await next(req)
        }

        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [capturer], transport: mock)
        let response = try await fiber.get("/test")

        let captured = await holder.value
        #expect(!captured.isEmpty)
        #expect(!response.traceID.isEmpty)
    }
}
