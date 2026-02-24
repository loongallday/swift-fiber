import Foundation
import Fiber
import Sharing

// MARK: - APIResponseKey

/// A custom `SharedReaderKey` that bridges Fiber HTTP networking into swift-sharing.
///
/// Implements a cache-first strategy: memory → disk → network.
/// Supports conditional requests (ETag / Last-Modified) and stale-while-revalidate.
///
/// ```swift
/// @SharedReader(.api("/users", as: [User].self, policy: .aggressive))
/// var users: CachedResponse<[User]>
/// ```
public struct APIResponseKey<Value: Codable & Sendable>: SharedReaderKey, Hashable {
    public let path: String
    public let query: [String: String]
    public let policy: CachePolicy

    // Non-hashable stored properties excluded from Hashable via manual conformance
    private let _decoderID: ObjectIdentifier
    private let _fiberID: ObjectIdentifier

    public let decoder: JSONDecoder
    public let sharedFiber: SharedFiber

    var cacheKey: String {
        SharedFiber.makeCacheKey(path: path, query: query)
    }

    public init(
        path: String,
        query: [String: String] = [:],
        policy: CachePolicy = .default,
        decoder: JSONDecoder = JSONDecoder(),
        sharedFiber: SharedFiber = SharedFiber()
    ) {
        self.path = path
        self.query = query
        self.policy = policy
        self.decoder = decoder
        self.sharedFiber = sharedFiber
        self._decoderID = ObjectIdentifier(decoder)
        self._fiberID = ObjectIdentifier(sharedFiber)
    }

    // MARK: - Hashable

    public static func == (lhs: APIResponseKey, rhs: APIResponseKey) -> Bool {
        lhs.path == rhs.path && lhs.query == rhs.query && lhs.policy == rhs.policy
            && lhs._decoderID == rhs._decoderID && lhs._fiberID == rhs._fiberID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(query)
        hasher.combine(policy)
        hasher.combine(_decoderID)
        hasher.combine(_fiberID)
    }

    // MARK: - SharedReaderKey Conformance

    public func load(
        context: LoadContext<CachedResponse<Value>>,
        continuation: LoadContinuation<CachedResponse<Value>>
    ) {
        let key = cacheKey
        let policy = self.policy

        // Synchronous cache-first: if we have a valid memory or disk entry, use it.
        // We need to run the actor-isolated calls in a Task since load() is synchronous.
        Task {
            let store = SharedCacheStore.shared

            // Check memory cache
            if policy.usesMemory,
               let cached: CachedResponse<Value> = await store.get(key, as: Value.self),
               cached.isFresh {
                continuation.resume(returning: cached)
                return
            }

            // Check disk cache
            if policy.usesDisk,
               let cached: CachedResponse<Value> = await store.loadFromDisk(key, as: Value.self),
               cached.isFresh {
                // Promote to memory
                if policy.usesMemory {
                    await store.set(key, value: cached, policy: policy)
                }
                continuation.resume(returning: cached)
                return
            }

            // No valid cache — return initial value
            continuation.resumeReturningInitialValue()
        }
    }

    public func subscribe(
        context: LoadContext<CachedResponse<Value>>,
        subscriber: SharedSubscriber<CachedResponse<Value>>
    ) -> SharedSubscription {
        let key = cacheKey
        let path = self.path
        let query = self.query
        let policy = self.policy
        let decoder = self.decoder
        let fiber = self.sharedFiber

        let task = Task {
            let store = SharedCacheStore.shared

            // Check for existing cached value for conditional requests
            var existing: CachedResponse<Value>? = await store.get(key, as: Value.self)
            if existing == nil && policy.usesDisk {
                existing = await store.loadFromDisk(key, as: Value.self)
            }

            // If we have a stale-but-revalidatable entry, yield it immediately
            if let existing, existing.isStale(policy: policy) {
                subscriber.yield(existing)
            }

            // Build headers for conditional request
            var headers: [String: String] = [:]
            if let etag = existing?.etag {
                headers["If-None-Match"] = etag
            }
            if let lastModified = existing?.lastModified {
                headers["If-Modified-Since"] = lastModified
            }

            do {
                let response = try await fiber.get(path, query: query, headers: headers)

                if response.statusCode == 304, let existing {
                    // Not Modified — refresh TTL
                    let refreshed = existing.refreshed(ttl: policy.ttl)
                    await store.set(key, value: refreshed, policy: policy)
                    if policy.usesDisk {
                        await store.saveToDisk(key, value: refreshed)
                    }
                    subscriber.yield(refreshed)
                } else if response.isSuccess {
                    // New data — decode and cache
                    let value = try decoder.decode(Value.self, from: response.data)
                    let etag = response.header("ETag")
                    let lastModified = response.header("Last-Modified")
                    let cached = CachedResponse<Value>.from(
                        value: value,
                        ttl: policy.ttl,
                        etag: etag,
                        lastModified: lastModified
                    )
                    await store.set(key, value: cached, policy: policy)
                    if policy.usesDisk {
                        await store.saveToDisk(key, value: cached)
                    }
                    subscriber.yield(cached)
                } else {
                    // Non-success, non-304 — if we have stale data, keep it
                    if let existing {
                        subscriber.yield(existing)
                    }
                }
            } catch {
                // Network error — serve stale data if available, otherwise propagate
                if let existing {
                    subscriber.yield(existing)
                } else {
                    subscriber.yield(throwing: error)
                }
            }
        }

        return SharedSubscription {
            task.cancel()
        }
    }
}
