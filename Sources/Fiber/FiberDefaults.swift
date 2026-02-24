import Foundation

// MARK: - FiberDefaults

/// Centralized, injectable constants for the Fiber library.
/// Every previously hardcoded value is exposed here for customization.
///
/// ```swift
/// // Override globally at app launch:
/// FiberDefaults.shared = FiberDefaults(
///     jitterFraction: 0.5,
///     jsonContentType: "application/vnd.api+json",
///     traceIDGenerator: { "W3C-\(UUID().uuidString)" }
/// )
///
/// // Or per-interceptor:
/// let retry = RetryInterceptor(maxRetries: 3, defaults: myDefaults)
/// ```
public struct FiberDefaults: Sendable {
    /// Jitter as a fraction of delay for exponential backoff (default: 0.25 = 25%).
    public var jitterFraction: Double

    /// Base multiplier for exponential backoff (default: 2.0).
    public var exponentialBackoffBase: Double

    /// System name used in LoggingInterceptor log messages (default: "HTTP").
    public var loggingSystemName: String

    /// Max characters of response body to log (default: 1000).
    public var logBodyTruncationLimit: Int

    /// Sleep granularity in seconds when waiting for a rate-limit slot (default: 0.1).
    public var rateLimitSleepIncrement: TimeInterval

    /// Content-Type header set by `jsonBody()` (default: "application/json").
    public var jsonContentType: String

    /// Factory producing trace IDs. Default: `UUID().uuidString`.
    public var traceIDGenerator: @Sendable () -> String

    /// Default close code for WebSocket connections (default: 1000).
    public var webSocketDefaultCloseCode: Int

    public init(
        jitterFraction: Double = 0.25,
        exponentialBackoffBase: Double = 2.0,
        loggingSystemName: String = "HTTP",
        logBodyTruncationLimit: Int = 1000,
        rateLimitSleepIncrement: TimeInterval = 0.1,
        jsonContentType: String = "application/json",
        traceIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        webSocketDefaultCloseCode: Int = 1000
    ) {
        self.jitterFraction = jitterFraction
        self.exponentialBackoffBase = exponentialBackoffBase
        self.loggingSystemName = loggingSystemName
        self.logBodyTruncationLimit = logBodyTruncationLimit
        self.rateLimitSleepIncrement = rateLimitSleepIncrement
        self.jsonContentType = jsonContentType
        self.traceIDGenerator = traceIDGenerator
        self.webSocketDefaultCloseCode = webSocketDefaultCloseCode
    }

    /// Library-wide defaults. Set once at app launch before any Fiber usage.
    public nonisolated(unsafe) static var shared = FiberDefaults()
}
