import Foundation
import Fiber
import Dependencies

// MARK: - FiberHTTPClient + DependencyKey

extension FiberHTTPClient: TestDependencyKey {
    /// Test value that reports an issue if any method is called without being overridden.
    public static let testValue = FiberHTTPClient(
        send: { _ in _reportUnimplemented("FiberHTTPClient.send"); return .empty },
        get: { _, _, _ in _reportUnimplemented("FiberHTTPClient.get"); return .empty },
        post: { _, _, _ in _reportUnimplemented("FiberHTTPClient.post"); return .empty },
        put: { _, _, _ in _reportUnimplemented("FiberHTTPClient.put"); return .empty },
        patch: { _, _, _ in _reportUnimplemented("FiberHTTPClient.patch"); return .empty },
        delete: { _, _ in _reportUnimplemented("FiberHTTPClient.delete"); return .empty }
    )

    /// Preview value that returns empty 200 responses.
    public static let previewValue = FiberHTTPClient(
        send: { _ in .empty },
        get: { _, _, _ in .empty },
        post: { _, _, _ in .empty },
        put: { _, _, _ in .empty },
        patch: { _, _, _ in .empty },
        delete: { _, _ in .empty }
    )
}

extension DependencyValues {
    /// Access the Fiber HTTP client via `@Dependency(\.fiberHTTPClient)`.
    ///
    /// ```swift
    /// @Dependency(\.fiberHTTPClient) var httpClient
    /// let response = try await httpClient.get("/users", [:], [:])
    ///
    /// // Override in tests:
    /// withDependencies {
    ///     $0.fiberHTTPClient.get = { _, _, _ in
    ///         FiberResponse.empty
    ///     }
    /// } operation: { ... }
    /// ```
    public var fiberHTTPClient: FiberHTTPClient {
        get { self[FiberHTTPClient.self] }
        set { self[FiberHTTPClient.self] = newValue }
    }
}

// MARK: - FiberResponse Helpers

extension FiberResponse {
    /// An empty 200 response for testing/preview use.
    public static let empty = FiberResponse(
        data: Data(),
        statusCode: 200,
        headers: [:],
        request: FiberRequest(url: URL(string: "https://test.local")!, method: .get),
        duration: 0,
        traceID: "test"
    )
}

@Sendable
internal func _reportUnimplemented(_ method: String) {
    #if DEBUG
    print("⚠️ \(method) called on unimplemented FiberHTTPClient. Override in withDependencies or provide a liveValue.")
    #endif
}
