import Foundation
import Fiber
import FiberDependencies
import FiberTesting

// MARK: - FiberHTTPClient Testing Helpers

extension FiberHTTPClient {
    /// Create a test client backed by a MockTransport.
    ///
    /// ```swift
    /// let (client, mock) = FiberHTTPClient.test(baseURL: "https://test.local")
    /// mock.stubAll(StubResponse(statusCode: 200, body: userData))
    /// let response = try await client.get("/users", [:], [:])
    /// ```
    public static func test(
        baseURL: String = "https://test.local",
        configure: ((inout Fiber.Config) -> Void)? = nil
    ) -> (client: FiberHTTPClient, mock: MockTransport) {
        let mock = MockTransport()
        let fiber = Fiber(baseURL) { config in
            config.transport = mock
            configure?(&config)
        }
        return (client: .live(fiber), mock: mock)
    }

    /// Create a stub client that always returns the given response.
    ///
    /// ```swift
    /// let client = FiberHTTPClient.stub(.ok(body: userData))
    /// let response = try await client.get("/anything", [:], [:])
    /// // response.statusCode == 200
    /// ```
    public static func stub(_ stub: StubResponse) -> FiberHTTPClient {
        let mock = MockTransport()
        mock.stubAll(stub)
        let fiber = Fiber("https://stub.local") { config in
            config.transport = mock
        }
        return .live(fiber)
    }
}
