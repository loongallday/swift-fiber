import Testing
import Foundation
import CryptoKit
@testable import Fiber
@testable import FiberTesting

@Suite("Integration — Full Stack Examples")
struct IntegrationTests {

    let baseURL = URL(string: "https://api.example.com")!

    // MARK: - Full middleware stack

    @Test("Full middleware stack: logging + metrics + auth + cache")
    func fullMiddlewareStack() async throws {
        let metricsCollector = InMemoryMetricsCollector()
        let traceCollector = TestTraceCollector()

        let fiber = Fiber("https://api.example.com") {
            $0.transport = {
                let m = MockTransport()
                m.stubAll(StubResponse.ok(body: #"{"status":"ok"}"#))
                return m
            }()
            $0.interceptors = [
                AuthInterceptor(tokenProvider: { "test-token" }),
                LoggingInterceptor(logger: traceCollector.logger()),
                MetricsInterceptor(collector: metricsCollector),
                CacheInterceptor(ttl: 60),
                traceCollector.interceptor(),
            ]
        }

        // First request
        let r1 = try await fiber.get("/status")
        #expect(r1.isSuccess)

        // Cached second request
        let r2 = try await fiber.get("/status")
        #expect(r2.isSuccess)

        // Verify metrics
        let metrics = await metricsCollector.metrics
        #expect(metrics.count >= 1)
        #expect(metrics[0].success)

        // Verify traces
        let spans = traceCollector.spans
        #expect(spans.count >= 1)
        #expect(spans[0].name == "HTTP")
        #expect(spans[0].durationMs != nil)

        // Verify logs were collected
        #expect(traceCollector.logs.count >= 2)
    }

    // MARK: - Error handling

    @Test("HTTP error is thrown for non-success status")
    func httpError() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.notFound())

        let fiber = Fiber(baseURL: baseURL, transport: mock)
        let response = try await fiber.get("/missing")

        #expect(response.statusCode == 404)
        #expect(response.isClientError)
        #expect(!response.isSuccess)

        // Using validateStatus throws
        do {
            _ = try response.validateStatus()
            Issue.record("Should have thrown")
        } catch let error as FiberError {
            #expect(error.statusCode == 404)
        }
    }

    @Test("Decoding error provides data context")
    func decodingError() async throws {
        struct User: Codable { let id: Int }

        let mock = MockTransport()
        mock.stubAll(StubResponse.ok(body: "not json"))

        let fiber = Fiber(baseURL: baseURL, transport: mock)

        do {
            let _: User = try await fiber.send(
                FiberRequest(url: baseURL.appendingPathComponent("/users/1")),
                as: User.self
            )
            Issue.record("Should have thrown")
        } catch let error as FiberError {
            #expect(error.responseData != nil)
            #expect(String(data: error.responseData!, encoding: .utf8) == "not json")
        }
    }

    // MARK: - StubResponse examples

    @Test("StubResponse builder pattern")
    func stubResponseBuilder() {
        let stub = StubResponse.ok()
            .header("X-Request-Id", "abc")
            .body(#"{"users":[]}"#)

        #expect(stub.statusCode == 200)
        #expect(stub.headers["X-Request-Id"] == "abc")
        #expect(String(data: stub.data, encoding: .utf8) == #"{"users":[]}"#)
    }

    @Test("StubResponse with Encodable")
    func stubResponseEncodable() {
        struct Item: Codable { let name: String }
        let stub = StubResponse.ok().jsonBody(Item(name: "test"))

        #expect(stub.headers["Content-Type"] == "application/json")
        #expect(!stub.data.isEmpty)
    }

    // MARK: - FiberRequest chaining examples

    @Test("Complex request chaining")
    func requestChaining() async throws {
        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(baseURL: baseURL, transport: mock)

        let req = FiberRequest(url: baseURL.appendingPathComponent("/search"), method: .get)
            .header("Accept", "application/json")
            .header("Accept-Language", "en")
            .query("q", "swift networking")
            .query("page", "1")
            .query("limit", "20")
            .timeout(15)
            .meta("source", "test")

        let response = try await fiber.send(req)
        #expect(response.isSuccess)

        let url = mock.lastRequest?.url?.absoluteString ?? ""
        #expect(url.contains("q=swift"))
        #expect(url.contains("page=1"))
    }

    // MARK: - Encryption round-trip

    @Test("Encrypted request/response round trip")
    func encryptionRoundTrip() async throws {
        let key = SymmetricKey(size: .bits256)
        let provider = AESGCMEncryptionProvider(key: key)

        // Mock server that echoes the encrypted body back
        let mock = MockTransport()
        mock.stub { req in
            StubResponse(statusCode: 200, data: req.httpBody ?? Data())
        }

        let fiber = Fiber(
            baseURL: baseURL,
            interceptors: [EncryptionInterceptor(provider: provider)],
            transport: mock
        )

        let message = "secret message"
        let req = try FiberRequest(url: baseURL.appendingPathComponent("/secure"), method: .post)
            .jsonBody(message)
        let response = try await fiber.send(req)

        let decrypted: String = try response.decode()
        #expect(decrypted == message)
    }
}
