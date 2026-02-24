import Foundation

// MARK: - LoggingInterceptor

/// Logs request/response details. Like Axios request/response logging.
///
/// ```swift
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [LoggingInterceptor(logger: PrintFiberLogger(minLevel: .verbose))]
/// }
/// // [VERBOSE] [HTTP] → POST https://api.example.com/users
/// // [VERBOSE] [HTTP] ← 201 (42ms) 256 bytes
/// ```
public struct LoggingInterceptor: Interceptor {
    public let name = "logging"
    private let logger: any FiberLogger
    private let logBody: Bool
    private let defaults: FiberDefaults

    public init(logger: any FiberLogger, logBody: Bool = false, defaults: FiberDefaults = .shared) {
        self.logger = logger
        self.logBody = logBody
        self.defaults = defaults
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        let traceID = TraceContext.traceID
        let method = request.httpMethod.rawValue
        let url = request.url.absoluteString

        let system = defaults.loggingSystemName
        logger.verbose("→ \(method) \(url)", system: system, metadata: ["traceID": traceID])

        if logBody, let body = request.body {
            let bodyStr = String(data: body, encoding: .utf8) ?? "<\(body.count) bytes>"
            logger.debug("→ Body: \(bodyStr)", system: system)
        }

        do {
            let response = try await next(request)
            logger.verbose(
                "← \(response.statusCode) (\(Int(response.duration * 1000))ms) \(response.data.count) bytes",
                system: system, metadata: ["traceID": traceID]
            )
            if logBody, let text = response.text {
                logger.debug("← Body: \(text.prefix(defaults.logBodyTruncationLimit))", system: system)
            }
            return response
        } catch {
            logger.error("✗ \(method) \(url) failed: \(error.localizedDescription)", system: system, metadata: ["traceID": traceID])
            throw error
        }
    }
}
