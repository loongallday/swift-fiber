import Foundation
import Fiber
import Dependencies

// MARK: - Fiber + DependencyKey

private enum FiberKey: DependencyKey {
    static let liveValue: Fiber = Fiber("https://localhost")
    static let testValue: Fiber = Fiber("https://test.local") {
        $0.transport = FailingTransport()
    }
    static let previewValue: Fiber = Fiber("https://preview.local")
}

extension DependencyValues {
    /// Access the full `Fiber` client via `@Dependency(\.fiber)`.
    ///
    /// Configure the live value early in app startup:
    /// ```swift
    /// withDependencies {
    ///     $0.fiber = Fiber("https://api.example.com") {
    ///         $0.interceptors = [authInterceptor, retryInterceptor]
    ///     }
    /// } operation: {
    ///     // app code
    /// }
    /// ```
    public var fiber: Fiber {
        get { self[FiberKey.self] }
        set { self[FiberKey.self] = newValue }
    }
}

// MARK: - FailingTransport

/// Transport that always fails — used for test dependency to catch untested network calls.
private struct FailingTransport: FiberTransport, Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        fatalError("Fiber.send called on test dependency without override. Use withDependencies to provide a mock transport.")
    }
}
