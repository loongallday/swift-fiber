import Foundation
import Fiber
import Sharing

// MARK: - SharedFiber

/// Reactive Fiber client that rebuilds when shared configuration changes.
///
/// ```swift
/// let shared = SharedFiber()
///
/// // Update config anywhere:
/// @Shared(.fiberConfiguration) var config
/// config.baseURL = "https://staging.api.com"
/// config.authToken = "new-token"
///
/// // SharedFiber automatically picks up changes on next request:
/// let response = try await shared.get("/users")
/// ```
public final class SharedFiber: @unchecked Sendable {
    @Shared(.fiberConfiguration) private var config

    private let lock = NSLock()
    private var cachedClient: Fiber?
    private var cachedConfig: FiberConfiguration?
    private let configure: (@Sendable (FiberConfiguration, inout Fiber.Config) -> Void)?

    public init(configure: (@Sendable (FiberConfiguration, inout Fiber.Config) -> Void)? = nil) {
        self.configure = configure
    }

    /// Returns the current Fiber client, rebuilding if config has changed.
    public var client: Fiber {
        lock.lock()
        defer { lock.unlock() }

        let currentConfig = config
        if let cached = cachedClient, cachedConfig == currentConfig {
            return cached
        }

        let newClient = Fiber(currentConfig.baseURL) { [configure] cfg in
            cfg.timeout = currentConfig.defaultTimeout
            var headers = currentConfig.defaultHeaders
            if let token = currentConfig.authToken {
                headers["Authorization"] = "Bearer \(token)"
            }
            cfg.defaultHeaders = headers
            configure?(currentConfig, &cfg)
        }

        cachedClient = newClient
        cachedConfig = currentConfig
        return newClient
    }

    // MARK: - Forwarding Methods

    public func send(_ request: FiberRequest) async throws -> FiberResponse {
        try await client.send(request)
    }

    public func get(_ path: String, query: [String: String] = [:], headers: [String: String] = [:]) async throws -> FiberResponse {
        try await client.get(path, query: query, headers: headers)
    }

    public func post<T: Encodable>(_ path: String, body: T, headers: [String: String] = [:]) async throws -> FiberResponse {
        try await client.post(path, body: body, headers: headers)
    }

    public func post(_ path: String, data: Data? = nil, headers: [String: String] = [:]) async throws -> FiberResponse {
        try await client.post(path, data: data, headers: headers)
    }

    public func put<T: Encodable>(_ path: String, body: T, headers: [String: String] = [:]) async throws -> FiberResponse {
        try await client.put(path, body: body, headers: headers)
    }

    public func patch<T: Encodable>(_ path: String, body: T, headers: [String: String] = [:]) async throws -> FiberResponse {
        try await client.patch(path, body: body, headers: headers)
    }

    public func delete(_ path: String, headers: [String: String] = [:]) async throws -> FiberResponse {
        try await client.delete(path, headers: headers)
    }
}
