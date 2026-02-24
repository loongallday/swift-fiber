import Foundation
import Fiber
import Sharing

// MARK: - Ergonomic SharedReaderKey Extensions

extension SharedReaderKey {
    /// Create an API response key for declarative cached fetching.
    ///
    /// ```swift
    /// @SharedReader(.api("/users", as: [User].self))
    /// var users: CachedResponse<[User]>
    ///
    /// @SharedReader(.api("/users", as: [User].self, policy: .aggressive))
    /// var users: CachedResponse<[User]>
    /// ```
    public static func api<Value: Codable & Sendable>(
        _ path: String,
        as type: Value.Type,
        query: [String: String] = [:],
        policy: CachePolicy = .default,
        decoder: JSONDecoder = JSONDecoder(),
        fiber: SharedFiber = SharedFiber()
    ) -> Self where Self == APIResponseKey<Value> {
        APIResponseKey<Value>(
            path: path,
            query: query,
            policy: policy,
            decoder: decoder,
            sharedFiber: fiber
        )
    }

    /// Shorthand for API response key with custom TTL and storage mode.
    ///
    /// ```swift
    /// @SharedReader(.cachedAPI("/config", as: AppConfig.self, ttl: 3600, storage: .disk))
    /// var config: CachedResponse<AppConfig>
    /// ```
    public static func cachedAPI<Value: Codable & Sendable>(
        _ path: String,
        as type: Value.Type,
        ttl: TimeInterval,
        storage: CachePolicy.StorageMode = .memoryAndDisk,
        decoder: JSONDecoder = JSONDecoder(),
        fiber: SharedFiber = SharedFiber()
    ) -> Self where Self == APIResponseKey<Value> {
        let policy = CachePolicy(ttl: ttl, storageMode: storage)
        return APIResponseKey<Value>(
            path: path,
            policy: policy,
            decoder: decoder,
            sharedFiber: fiber
        )
    }
}
