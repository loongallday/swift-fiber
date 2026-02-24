import Foundation
import Fiber

// MARK: - FiberConfiguration

/// Shared configuration value type for use with swift-sharing.
///
/// ```swift
/// @Shared(.fiberConfiguration) var config
/// config.baseURL = "https://staging.api.com"
/// config.authToken = "new-token"
/// ```
public struct FiberConfiguration: Codable, Hashable, Sendable {
    public var baseURL: String
    public var defaultTimeout: TimeInterval
    public var defaultHeaders: [String: String]
    public var authToken: String?

    public init(
        baseURL: String = "https://localhost",
        defaultTimeout: TimeInterval = 60,
        defaultHeaders: [String: String] = [:],
        authToken: String? = nil
    ) {
        self.baseURL = baseURL
        self.defaultTimeout = defaultTimeout
        self.defaultHeaders = defaultHeaders
        self.authToken = authToken
    }
}
