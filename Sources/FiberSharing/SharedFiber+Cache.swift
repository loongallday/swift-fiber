import Foundation
import Fiber

// MARK: - SharedFiber Cache Extensions

extension SharedFiber {

    // MARK: - Cache Key

    /// Generate a consistent cache key from path and query parameters.
    ///
    /// Format: `GET:path?sorted_query_string`
    public static func makeCacheKey(path: String, query: [String: String] = [:]) -> String {
        if query.isEmpty {
            return "GET:\(path)"
        }
        let sorted = query.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "GET:\(path)?\(sorted)"
    }

    // MARK: - Imperative Cached Fetch

    /// Fetch with caching: checks memory → disk → network.
    ///
    /// ```swift
    /// let fiber = SharedFiber()
    /// let result = try await fiber.getCached("/users", as: [User].self, policy: .aggressive)
    /// print(result.value)     // [User]
    /// print(result.isFresh)   // true
    /// ```
    public func getCached<T: Codable & Sendable>(
        _ path: String,
        as type: T.Type,
        query: [String: String] = [:],
        policy: CachePolicy = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> CachedResponse<T> {
        let key = SharedFiber.makeCacheKey(path: path, query: query)
        let store = SharedCacheStore.shared

        // Return no-cache policy immediately
        guard !policy.isDisabled else {
            return try await fetchAndCache(
                path: path, query: query, key: key,
                existing: nil, policy: policy, decoder: decoder, store: store
            )
        }

        // Check memory cache
        if policy.usesMemory,
           let cached: CachedResponse<T> = await store.get(key, as: T.self),
           cached.isFresh {
            return cached
        }

        // Check disk cache
        if policy.usesDisk,
           let cached: CachedResponse<T> = await store.loadFromDisk(key, as: T.self),
           cached.isFresh {
            // Promote to memory
            if policy.usesMemory {
                await store.set(key, value: cached, policy: policy)
            }
            return cached
        }

        // Get existing stale entry for conditional requests
        var existing: CachedResponse<T>? = await store.get(key, as: T.self)
        if existing == nil && policy.usesDisk {
            existing = await store.loadFromDisk(key, as: T.self)
        }

        return try await fetchAndCache(
            path: path, query: query, key: key,
            existing: existing, policy: policy, decoder: decoder, store: store
        )
    }

    private func fetchAndCache<T: Codable & Sendable>(
        path: String,
        query: [String: String],
        key: String,
        existing: CachedResponse<T>?,
        policy: CachePolicy,
        decoder: JSONDecoder,
        store: SharedCacheStore
    ) async throws -> CachedResponse<T> {
        // Build conditional request headers
        var headers: [String: String] = [:]
        if let etag = existing?.etag {
            headers["If-None-Match"] = etag
        }
        if let lastModified = existing?.lastModified {
            headers["If-Modified-Since"] = lastModified
        }

        let response = try await get(path, query: query, headers: headers)

        // 304 Not Modified — refresh TTL on existing
        if response.statusCode == 304, let existing {
            let refreshed = existing.refreshed(ttl: policy.ttl)
            if policy.usesMemory {
                await store.set(key, value: refreshed, policy: policy)
            }
            if policy.usesDisk {
                await store.saveToDisk(key, value: refreshed)
            }
            return refreshed
        }

        // Decode new response
        let value = try decoder.decode(T.self, from: response.data)
        let etag = response.header("ETag")
        let lastModified = response.header("Last-Modified")
        let cached = CachedResponse<T>.from(
            value: value,
            ttl: policy.ttl,
            etag: etag,
            lastModified: lastModified
        )

        if !policy.isDisabled {
            if policy.usesMemory {
                await store.set(key, value: cached, policy: policy)
            }
            if policy.usesDisk {
                await store.saveToDisk(key, value: cached)
            }
        }

        return cached
    }

    // MARK: - Cache Invalidation

    /// Invalidate cache for a specific path and query combination.
    public func invalidateCache(for path: String, query: [String: String] = [:]) async {
        let key = SharedFiber.makeCacheKey(path: path, query: query)
        let store = SharedCacheStore.shared
        await store.invalidate(key)
        await store.removeFromDisk(key)
    }

    /// Invalidate all cache entries whose keys match a path prefix.
    ///
    /// ```swift
    /// await fiber.invalidateCacheMatching("GET:/users")  // clears /users, /users/1, /users?page=2
    /// ```
    public func invalidateCacheMatching(_ pathPrefix: String) async {
        let store = SharedCacheStore.shared
        await store.invalidateMatching(pathPrefix)
    }

    /// Clear all cached data (memory and disk).
    public func clearCache() async {
        let store = SharedCacheStore.shared
        await store.invalidateAll()
        await store.clearDisk()
    }
}
