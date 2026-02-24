import Foundation

// MARK: - RetryInterceptor

/// Retries failed requests with exponential backoff + jitter. Like Axios retry.
///
/// ```swift
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [
///         RetryInterceptor(maxRetries: 3, baseDelay: 0.5)
///     ]
/// }
/// ```
public struct RetryInterceptor: Interceptor {
    public let name = "retry"
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let retryableStatusCodes: Set<Int>
    public let retryableMethods: Set<HTTPMethod>
    public let shouldRetry: @Sendable (any Error) -> Bool
    private let defaults: FiberDefaults

    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 30,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableMethods: Set<HTTPMethod> = [.get, .head, .options, .put, .delete],
        shouldRetry: @escaping @Sendable (any Error) -> Bool = { error in
            (error as? URLError).map { [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains($0.code) } ?? false
        },
        defaults: FiberDefaults = .shared
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableMethods = retryableMethods
        self.shouldRetry = shouldRetry
        self.defaults = defaults
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        var lastError: (any Error)?
        var lastResponse: FiberResponse?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = min(baseDelay * pow(defaults.exponentialBackoffBase, Double(attempt - 1)), maxDelay)
                let jitter = Double.random(in: 0...(delay * defaults.jitterFraction))
                try await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
                if Task.isCancelled { throw FiberError.cancelled }
            }

            do {
                let response = try await next(request)
                if retryableStatusCodes.contains(response.statusCode),
                   retryableMethods.contains(request.httpMethod),
                   attempt < maxRetries {
                    lastResponse = response
                    continue
                }
                return response
            } catch {
                if shouldRetry(error), attempt < maxRetries {
                    lastError = error
                    continue
                }
                throw error
            }
        }

        if let response = lastResponse { return response }
        throw lastError ?? FiberError.cancelled
    }
}
