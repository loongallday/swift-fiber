import Foundation
import CryptoKit

// MARK: - SharedCacheStore

/// Actor-based centralized cache manager with LRU eviction and optional disk persistence.
///
/// ```swift
/// let store = SharedCacheStore.shared
/// let cached = CachedResponse.from(value: users, ttl: 300)
/// await store.set("GET:/users", value: cached, policy: .default)
/// let hit: CachedResponse<[User]>? = await store.get("GET:/users", as: [User].self)
/// ```
public actor SharedCacheStore {
    public static let shared = SharedCacheStore()

    // In-memory cache: key -> (data: Data, accessOrder: Int)
    private var memoryCache: [String: MemoryEntry] = [:]
    private var accessCounter: Int = 0

    private struct MemoryEntry {
        let data: Data
        let policy: CachePolicy
        var lastAccessed: Int
    }

    public init() {}

    // MARK: - Memory Cache

    /// Retrieve a cached response from memory.
    public func get<T: Codable & Sendable>(_ key: String, as type: T.Type) -> CachedResponse<T>? {
        guard var entry = memoryCache[key] else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedResponse<T>.self, from: entry.data) else {
            memoryCache.removeValue(forKey: key)
            return nil
        }
        // Update access order for LRU
        accessCounter += 1
        entry.lastAccessed = accessCounter
        memoryCache[key] = entry
        return cached
    }

    /// Store a cached response in memory with LRU eviction.
    public func set<T: Codable & Sendable>(_ key: String, value: CachedResponse<T>, policy: CachePolicy) {
        guard policy.usesMemory, !policy.isDisabled else { return }
        guard let data = try? JSONEncoder().encode(value) else { return }

        // Evict LRU entries if over capacity
        while memoryCache.count >= policy.maxEntries && !memoryCache.isEmpty {
            let lru = memoryCache.min { $0.value.lastAccessed < $1.value.lastAccessed }
            if let lruKey = lru?.key {
                memoryCache.removeValue(forKey: lruKey)
            }
        }

        accessCounter += 1
        memoryCache[key] = MemoryEntry(data: data, policy: policy, lastAccessed: accessCounter)
    }

    /// Remove a specific key from memory cache.
    public func invalidate(_ key: String) {
        memoryCache.removeValue(forKey: key)
    }

    /// Remove all entries from memory cache.
    public func invalidateAll() {
        memoryCache.removeAll()
    }

    /// Remove all entries whose keys start with the given prefix.
    public func invalidateMatching(_ prefix: String) {
        let keysToRemove = memoryCache.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            memoryCache.removeValue(forKey: key)
        }
    }

    /// Current number of entries in memory.
    public var memoryCount: Int {
        memoryCache.count
    }

    // MARK: - Disk Cache

    /// Load a cached response from disk.
    public func loadFromDisk<T: Codable & Sendable>(_ key: String, as type: T.Type) -> CachedResponse<T>? {
        let fileURL = diskURL(for: key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedResponse<T>.self, from: data)
    }

    /// Save a cached response to disk.
    public func saveToDisk<T: Codable & Sendable>(_ key: String, value: CachedResponse<T>) {
        let fileURL = diskURL(for: key)
        ensureCacheDirectory()
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Remove a specific key from disk cache.
    public func removeFromDisk(_ key: String) {
        let fileURL = diskURL(for: key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Remove all files from the disk cache directory.
    public func clearDisk() {
        guard let dir = cacheDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Disk Helpers

    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("FiberCache", isDirectory: true)
    }

    private func ensureCacheDirectory() {
        guard let dir = cacheDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func diskURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return (cacheDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(filename)
            .appendingPathExtension("json")
    }
}
