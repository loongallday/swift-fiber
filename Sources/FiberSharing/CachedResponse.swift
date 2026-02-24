import Foundation

// MARK: - CachedResponse

/// A cached API response wrapping a decoded value with cache metadata.
///
/// ```swift
/// let cached: CachedResponse<[User]> = try await sharedFiber.getCached("/users", as: [User].self)
/// print(cached.value)       // [User]
/// print(cached.age)         // seconds since cached
/// print(cached.isExpired)   // true if past expiresAt
/// ```
public struct CachedResponse<Value: Codable & Sendable>: Codable, Sendable {
    /// The decoded response value.
    public let value: Value

    /// When the response was originally cached.
    public let cachedAt: Date

    /// When the cached response expires (based on TTL at cache time).
    public let expiresAt: Date

    /// ETag header from the server, if present. Used for conditional requests.
    public let etag: String?

    /// Last-Modified header from the server, if present. Used for conditional requests.
    public let lastModified: String?

    public init(
        value: Value,
        cachedAt: Date = Date(),
        expiresAt: Date,
        etag: String? = nil,
        lastModified: String? = nil
    ) {
        self.value = value
        self.cachedAt = cachedAt
        self.expiresAt = expiresAt
        self.etag = etag
        self.lastModified = lastModified
    }
}

// MARK: - Cache Status

extension CachedResponse {
    /// Whether the cache entry has passed its expiration time.
    public var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Seconds since the response was cached.
    public var age: TimeInterval {
        Date().timeIntervalSince(cachedAt)
    }

    /// Whether the entry is stale but within the stale-while-revalidate window.
    public func isStale(policy: CachePolicy) -> Bool {
        let now = Date()
        return now >= expiresAt && now < expiresAt.addingTimeInterval(policy.staleWhileRevalidate)
    }

    /// Whether the entry is still fresh (not expired).
    public var isFresh: Bool {
        !isExpired
    }

    /// Whether this entry has conditional request headers available.
    public var supportsConditionalRequest: Bool {
        etag != nil || lastModified != nil
    }
}

// MARK: - Factory

extension CachedResponse {
    /// Create a cached response from a network response with a given TTL.
    public static func from(
        value: Value,
        ttl: TimeInterval,
        etag: String? = nil,
        lastModified: String? = nil
    ) -> CachedResponse {
        let now = Date()
        return CachedResponse(
            value: value,
            cachedAt: now,
            expiresAt: now.addingTimeInterval(ttl),
            etag: etag,
            lastModified: lastModified
        )
    }

    /// Create a new entry with refreshed TTL (used after 304 Not Modified).
    public func refreshed(ttl: TimeInterval) -> CachedResponse {
        CachedResponse(
            value: value,
            cachedAt: Date(),
            expiresAt: Date().addingTimeInterval(ttl),
            etag: etag,
            lastModified: lastModified
        )
    }
}
