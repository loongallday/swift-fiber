import Foundation

// MARK: - Interceptor

/// A function that can observe/transform requests and responses in the pipeline.
/// Like Axios interceptors — simple protocol, or use AnyInterceptor for closures.
///
/// ```swift
/// // As a struct:
/// struct AuthInterceptor: Interceptor {
///     let token: String
///     func intercept(_ request: FiberRequest, next: Next) async throws -> FiberResponse {
///         let authed = request.header("Authorization", "Bearer \(token)")
///         return try await next(authed)
///     }
/// }
///
/// // As a closure:
/// let logging = AnyInterceptor("logging") { request, next in
///     print("→ \(request.httpMethod) \(request.url)")
///     let response = try await next(request)
///     print("← \(response.statusCode)")
///     return response
/// }
/// ```
public protocol Interceptor: Sendable {
    /// Human-readable name for tracing and error reporting.
    var name: String { get }

    /// Process the request. Call `next` to continue the chain, or short-circuit.
    func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse
}

// MARK: - AnyInterceptor (closure-based)

/// Wrap a closure as an interceptor — the most concise way.
///
/// ```swift
/// let timer = AnyInterceptor("timer") { req, next in
///     let start = Date()
///     let res = try await next(req)
///     print("Took \(Date().timeIntervalSince(start))s")
///     return res
/// }
/// ```
public struct AnyInterceptor: Interceptor {
    public let name: String
    private let _intercept: @Sendable (
        FiberRequest,
        @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse

    public init(
        _ name: String = "anonymous",
        _ handler: @escaping @Sendable (
            FiberRequest,
            @Sendable (FiberRequest) async throws -> FiberResponse
        ) async throws -> FiberResponse
    ) {
        self.name = name
        self._intercept = handler
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        try await _intercept(request, next)
    }
}

// MARK: - InterceptorChain

/// Builds a composed function from interceptors + terminal transport.
/// First interceptor is outermost (runs first on request, last on response).
public enum InterceptorChain {
    public static func build(
        interceptors: [any Interceptor],
        transport: @escaping @Sendable (FiberRequest) async throws -> FiberResponse
    ) -> @Sendable (FiberRequest) async throws -> FiberResponse {
        var next = transport
        for interceptor in interceptors.reversed() {
            let current = next
            next = { @Sendable request in
                try await interceptor.intercept(request, next: current)
            }
        }
        return next
    }
}
