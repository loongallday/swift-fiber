import Foundation

// MARK: - AuthInterceptor

/// Injects auth tokens and handles refresh. Like Axios auth interceptors.
///
/// ```swift
/// let auth = AuthInterceptor(
///     tokenProvider: { await tokenStore.accessToken },
///     tokenRefresher: { try await tokenStore.refresh() },
///     isUnauthorized: { $0.statusCode == 401 }
/// )
///
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [auth]
/// }
/// ```
public struct AuthInterceptor: Interceptor {
    public let name = "auth"
    private let tokenProvider: @Sendable () async -> String?
    private let tokenRefresher: (@Sendable () async throws -> String)?
    private let headerName: String
    private let headerPrefix: String
    private let isUnauthorized: @Sendable (FiberResponse) -> Bool

    public init(
        tokenProvider: @escaping @Sendable () async -> String?,
        tokenRefresher: (@Sendable () async throws -> String)? = nil,
        headerName: String = "Authorization",
        headerPrefix: String = "Bearer ",
        isUnauthorized: @escaping @Sendable (FiberResponse) -> Bool = { $0.statusCode == 401 }
    ) {
        self.tokenProvider = tokenProvider
        self.tokenRefresher = tokenRefresher
        self.headerName = headerName
        self.headerPrefix = headerPrefix
        self.isUnauthorized = isUnauthorized
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        var authedRequest = request
        if let token = await tokenProvider() {
            authedRequest = authedRequest.header(headerName, "\(headerPrefix)\(token)")
        }

        let response = try await next(authedRequest)

        // Attempt refresh on 401
        if isUnauthorized(response), let refresher = tokenRefresher {
            let newToken = try await refresher()
            let retryRequest = request.header(headerName, "\(headerPrefix)\(newToken)")
            return try await next(retryRequest)
        }

        return response
    }
}
