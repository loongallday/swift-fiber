import Foundation

// MARK: - RateLimitInterceptor

/// Client-side rate limiting with token bucket algorithm.
///
/// ```swift
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [RateLimitInterceptor(maxRequests: 10, perInterval: 1.0)]
/// }
/// // Requests beyond the limit wait until a slot opens.
/// ```
public actor RateLimitInterceptor: Interceptor {
    public nonisolated let name = "rateLimit"
    private let maxRequests: Int
    private let interval: TimeInterval
    private let maxWait: TimeInterval
    private let defaults: FiberDefaults
    private var timestamps: [Date] = []

    public init(maxRequests: Int = 60, perInterval interval: TimeInterval = 60.0, maxWait: TimeInterval = 30.0, defaults: FiberDefaults = .shared) {
        self.maxRequests = maxRequests; self.interval = interval; self.maxWait = maxWait; self.defaults = defaults
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let waitStart = Date()

        while true {
            pruneOldTimestamps()

            if timestamps.count < maxRequests {
                timestamps.append(Date())
                return try await next(request)
            }

            let elapsed = Date().timeIntervalSince(waitStart)
            if elapsed >= maxWait {
                throw FiberError.interceptor(
                    name: name,
                    underlying: RateLimitError.exceeded(limit: maxRequests, interval: interval)
                )
            }

            if let oldest = timestamps.first {
                let waitTime = oldest.addingTimeInterval(interval).timeIntervalSince(Date())
                if waitTime > 0 {
                    try await Task.sleep(nanoseconds: UInt64(min(waitTime, defaults.rateLimitSleepIncrement) * 1_000_000_000))
                }
            }
        }
    }

    private func pruneOldTimestamps() {
        let cutoff = Date().addingTimeInterval(-interval)
        timestamps.removeAll { $0 < cutoff }
    }
}

public enum RateLimitError: Error, Sendable, LocalizedError {
    case exceeded(limit: Int, interval: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .exceeded(let limit, let interval):
            return "Rate limit exceeded: \(limit) requests per \(interval)s"
        }
    }
}
