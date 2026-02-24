import Testing
import Foundation
import Fiber
import FiberTesting
import FiberDependencies
import FiberDependenciesTesting
import Dependencies

// MARK: - FiberHTTPClient Tests

@Suite("FiberHTTPClient Tests")
struct FiberHTTPClientTests {

    @Test("Live client GET forwards to Fiber")
    func liveGet() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok(body: #"{"status":"ok"}"#))
        let fiber = Fiber("https://test.local") { $0.transport = mock }
        let client = FiberHTTPClient.live(fiber)

        let response = try await client.get("/health", [:], [:])
        #expect(response.statusCode == 200)
        #expect(response.text == #"{"status":"ok"}"#)
        #expect(mock.requests.count == 1)
    }

    @Test("Live client POST forwards to Fiber")
    func livePost() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.created(body: #"{"id":1}"#))
        let fiber = Fiber("https://test.local") { $0.transport = mock }
        let client = FiberHTTPClient.live(fiber)

        let body = Data(#"{"name":"Alice"}"#.utf8)
        let response = try await client.post("/users", body, [:])
        #expect(response.statusCode == 201)
        #expect(mock.requests.count == 1)
    }

    @Test("Live client DELETE forwards to Fiber")
    func liveDelete() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.noContent())
        let fiber = Fiber("https://test.local") { $0.transport = mock }
        let client = FiberHTTPClient.live(fiber)

        let response = try await client.delete("/users/1", [:])
        #expect(response.statusCode == 204)
    }

    @Test("Live client from base URL string")
    func liveFromString() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())
        let client = FiberHTTPClient.live("https://test.local") { $0.transport = mock }

        let response = try await client.get("/ping", [:], [:])
        #expect(response.statusCode == 200)
    }

    @Test("Test helper creates client and mock")
    func testHelper() async throws {
        let (client, mock) = FiberHTTPClient.test()
        mock.stubAll(StubResponse.ok(body: "hello"))

        let response = try await client.get("/test", [:], [:])
        #expect(response.statusCode == 200)
        #expect(response.text == "hello")
        #expect(mock.requests.count == 1)
    }

    @Test("Stub helper returns fixed response")
    func stubHelper() async throws {
        let client = FiberHTTPClient.stub(.ok(body: "stubbed"))

        let response = try await client.get("/anything", [:], [:])
        #expect(response.statusCode == 200)
        #expect(response.text == "stubbed")
    }

    @Test("Empty response helper")
    func emptyResponse() {
        let empty = FiberResponse.empty
        #expect(empty.statusCode == 200)
        #expect(empty.data.isEmpty)
        #expect(empty.traceID == "test")
    }

    @Test("Preview value returns empty responses")
    func previewValue() async throws {
        let client = FiberHTTPClient.previewValue
        let response = try await client.get("/preview", [:], [:])
        #expect(response.statusCode == 200)
    }
}
