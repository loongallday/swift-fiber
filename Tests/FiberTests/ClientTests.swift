import Testing
import Foundation
@testable import Fiber
@testable import FiberTesting

// MARK: - FiberClient Tests

@Suite("Fiber Client")
struct ClientTests {

    let baseURL = URL(string: "https://api.example.com")!

    @Test("GET request through mock transport")
    func getRequest() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok(body: #"{"id":1,"name":"Alice"}"#))

        let fiber = Fiber(baseURL: baseURL, transport: mock)
        let response = try await fiber.get("/users/1")

        #expect(response.statusCode == 200)
        #expect(response.isSuccess)
        #expect(mock.requests.count == 1)
        #expect(mock.lastRequest?.httpMethod == "GET")
    }

    @Test("POST with Encodable body")
    func postWithBody() async throws {
        struct CreateUser: Codable { let name: String }

        let mock = MockTransport()
        mock.stubAll(StubResponse.created(body: #"{"id":2,"name":"Bob"}"#))

        let fiber = Fiber(baseURL: baseURL, transport: mock)
        let response = try await fiber.post("/users", body: CreateUser(name: "Bob"))

        #expect(response.statusCode == 201)
        #expect(mock.requests.count == 1)

        let sentBody = mock.lastRequest?.httpBody
        #expect(sentBody != nil)
        let decoded = try JSONDecoder().decode(CreateUser.self, from: sentBody!)
        #expect(decoded.name == "Bob")
    }

    @Test("DELETE request")
    func deleteRequest() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.noContent())

        let fiber = Fiber(baseURL: baseURL, transport: mock)
        let response = try await fiber.delete("/users/1")

        #expect(response.statusCode == 204)
        #expect(mock.lastRequest?.httpMethod == "DELETE")
    }

    @Test("Default headers are applied")
    func defaultHeaders() async throws {
        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(
            baseURL: baseURL,
            transport: mock,
            defaultHeaders: ["X-API-Key": "secret"]
        )
        _ = try await fiber.get("/test")

        let apiKey = mock.lastRequest?.value(forHTTPHeaderField: "X-API-Key")
        #expect(apiKey == "secret")
    }

    @Test("Query parameters are appended")
    func queryParameters() async throws {
        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber(baseURL: baseURL, transport: mock)
        _ = try await fiber.get("/search", query: ["q": "swift", "page": "1"])

        let url = mock.lastRequest?.url?.absoluteString ?? ""
        #expect(url.contains("q=swift"))
        #expect(url.contains("page=1"))
    }

    @Test("Response decode")
    func responseDecode() async throws {
        struct User: Codable { let id: Int; let name: String }

        let mock = MockTransport()
        mock.stubAll(StubResponse.ok(body: #"{"id":1,"name":"Alice"}"#))

        let fiber = Fiber(baseURL: baseURL, transport: mock)
        let response = try await fiber.get("/users/1")
        let user: User = try response.decode()

        #expect(user.id == 1)
        #expect(user.name == "Alice")
    }

    @Test("Endpoint protocol")
    func endpointProtocol() async throws {
        struct User: Codable, Sendable { let id: Int; let name: String }
        struct GetUser: Endpoint {
            typealias Response = User
            let id: String
            var path: String { "/users/\(id)" }
            var method: HTTPMethod { .get }
        }

        let mock = MockTransport()
        mock.stubAll(StubResponse.ok(body: #"{"id":1,"name":"Alice"}"#))

        let fiber = Fiber(baseURL: baseURL, transport: mock)
        let user = try await fiber.request(GetUser(id: "1"))

        #expect(user.id == 1)
        #expect(user.name == "Alice")
    }

    @Test("Builder-style initializer")
    func builderInit() async throws {
        let mock = MockTransport()
        mock.stubAll(.ok())

        let fiber = Fiber("https://api.example.com") {
            $0.transport = mock
            $0.defaultHeaders = ["Accept": "application/json"]
            $0.timeout = 15
        }

        _ = try await fiber.get("/test")
        #expect(mock.requests.count == 1)
        #expect(mock.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
    }
}
