import Foundation

// MARK: - CacheInterceptor

/// In-memory TTL cache for GET requests. Like Axios cache adapter.
///
/// ```swift
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [CacheInterceptor(ttl: 300, maxEntries: 100)]
/// }
///
/// let a = try await fiber.get("/config")  // network
/// let b = try await fiber.get("/config")  // cached!
/// ```
public actor CacheInterceptor: Interceptor {
    public nonisolated let name = "cache"
    private let ttl: TimeInterval
    private let maxEntries: Int
    private let cacheableMethods: Set<HTTPMethod>
    private var cache: [String: CacheEntry] = [:]

    private struct CacheEntry {
        let response: FiberResponse
        let expiresAt: Date
        var isValid: Bool { Date() < expiresAt }
    }

    public init(ttl: TimeInterval = 300, maxEntries: Int = 100, cacheableMethods: Set<HTTPMethod> = [.get, .head]) {
        self.ttl = ttl; self.maxEntries = maxEntries; self.cacheableMethods = cacheableMethods
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        guard cacheableMethods.contains(request.httpMethod) else {
            return try await next(request)
        }

        let key = cacheKey(for: request)

        if let entry = cache[key], entry.isValid {
            return entry.response
        }

        let response = try await next(request)

        if response.isSuccess {
            if cache.count >= maxEntries {
                let oldest = cache.min { $0.value.expiresAt < $1.value.expiresAt }
                if let oldestKey = oldest?.key { cache.removeValue(forKey: oldestKey) }
            }
            cache[key] = CacheEntry(response: response, expiresAt: Date().addingTimeInterval(ttl))
        }

        return response
    }

    public func clear() { cache.removeAll() }

    public func evict(url: String) { cache.removeValue(forKey: url) }

    private func cacheKey(for request: FiberRequest) -> String {
        var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
        if !request.queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + request.queryItems
        }
        return "\(request.httpMethod.rawValue):\(components.url?.absoluteString ?? request.url.absoluteString)"
    }
}
