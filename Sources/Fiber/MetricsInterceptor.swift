import Foundation

// MARK: - RequestMetrics

/// Collected metrics for a single request.
public struct RequestMetrics: Sendable {
    public let traceID: String
    public let method: String
    public let url: String
    public let statusCode: Int
    public let requestSize: Int
    public let responseSize: Int
    public let durationMs: Double
    public let timestamp: Date
    public let success: Bool
}

// MARK: - MetricsCollector

/// Protocol for receiving request metrics.
///
/// ```swift
/// struct AnalyticsCollector: MetricsCollector {
///     func collect(_ metrics: RequestMetrics) async {
///         analytics.track("http_request", properties: [
///             "url": metrics.url, "duration_ms": metrics.durationMs
///         ])
///     }
/// }
/// ```
public protocol MetricsCollector: Sendable {
    func collect(_ metrics: RequestMetrics) async
}

/// In-memory metrics store for testing/debugging.
public actor InMemoryMetricsCollector: MetricsCollector {
    public private(set) var metrics: [RequestMetrics] = []
    public init() {}
    public func collect(_ metrics: RequestMetrics) { self.metrics.append(metrics) }
    public func reset() { metrics.removeAll() }

    public var averageDurationMs: Double {
        guard !metrics.isEmpty else { return 0 }
        return metrics.reduce(0.0) { $0 + $1.durationMs } / Double(metrics.count)
    }

    public var successRate: Double {
        guard !metrics.isEmpty else { return 0 }
        return Double(metrics.filter(\.success).count) / Double(metrics.count)
    }
}

// MARK: - MetricsInterceptor

/// Collects performance metrics for every request.
///
/// ```swift
/// let collector = InMemoryMetricsCollector()
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [MetricsInterceptor(collector: collector)]
/// }
/// try await fiber.get("/users")
/// let avg = await collector.averageDurationMs
/// ```
public struct MetricsInterceptor: Interceptor {
    public let name = "metrics"
    private let collector: any MetricsCollector

    public init(collector: any MetricsCollector) { self.collector = collector }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let start = Date()
        let traceID = TraceContext.traceID

        do {
            let response = try await next(request)
            let duration = Date().timeIntervalSince(start) * 1000
            await collector.collect(RequestMetrics(
                traceID: traceID, method: request.httpMethod.rawValue, url: request.url.absoluteString,
                statusCode: response.statusCode, requestSize: request.body?.count ?? 0,
                responseSize: response.data.count, durationMs: duration, timestamp: start, success: response.isSuccess
            ))
            return response
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            await collector.collect(RequestMetrics(
                traceID: traceID, method: request.httpMethod.rawValue, url: request.url.absoluteString,
                statusCode: 0, requestSize: request.body?.count ?? 0,
                responseSize: 0, durationMs: duration, timestamp: start, success: false
            ))
            throw error
        }
    }
}
