import Foundation

// MARK: - FiberTransport

/// Lowest-level abstraction: sends a URLRequest and returns raw data.
/// Swap for testing or custom networking stacks.
///
/// ```swift
/// // Default
/// let transport = URLSessionTransport()
///
/// // Custom session config
/// let config = URLSessionConfiguration.default
/// config.timeoutIntervalForRequest = 30
/// let transport = URLSessionTransport(session: URLSession(configuration: config))
/// ```
public protocol FiberTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - URLSessionTransport

/// Default transport using URLSession.
public struct URLSessionTransport: FiberTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
