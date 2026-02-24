import Foundation

// MARK: - CachePolicy

/// Configurable caching behavior for API responses.
///
/// ```swift
/// // Use a preset
/// let policy = CachePolicy.aggressive
///
/// // Or customize
/// let policy = CachePolicy(ttl: 600, staleWhileRevalidate: 120, storageMode: .memoryAndDisk)
/// ```
public struct CachePolicy: Sendable, Hashable {
    /// Time-to-live in seconds before the cached response is considered expired.
    public var ttl: TimeInterval

    /// Grace period after expiration during which stale data may be served
    /// while a background revalidation occurs.
    public var staleWhileRevalidate: TimeInterval

    /// Where to store cached responses.
    public var storageMode: StorageMode

    /// Maximum number of entries in memory before LRU eviction kicks in.
    public var maxEntries: Int

    public enum StorageMode: Sendable, Hashable {
        case memory
        case disk
        case memoryAndDisk
    }

    public init(
        ttl: TimeInterval = 300,
        staleWhileRevalidate: TimeInterval = 0,
        storageMode: StorageMode = .memory,
        maxEntries: Int = 100
    ) {
        self.ttl = ttl
        self.staleWhileRevalidate = staleWhileRevalidate
        self.storageMode = storageMode
        self.maxEntries = maxEntries
    }
}

// MARK: - Presets

extension CachePolicy {
    /// Default: 5-minute TTL, memory-only, 100 entries.
    public static let `default` = CachePolicy()

    /// Aggressive: 30-minute TTL, memory + disk, 60s stale-while-revalidate.
    public static let aggressive = CachePolicy(
        ttl: 1800,
        staleWhileRevalidate: 60,
        storageMode: .memoryAndDisk,
        maxEntries: 200
    )

    /// No caching — always fetches from network.
    public static let noCache = CachePolicy(ttl: 0, maxEntries: 0)

    /// Persistent: 1-hour TTL, disk-backed, 5-minute stale-while-revalidate.
    public static let persistent = CachePolicy(
        ttl: 3600,
        staleWhileRevalidate: 300,
        storageMode: .disk,
        maxEntries: 500
    )
}

// MARK: - Helpers

extension CachePolicy {
    /// Whether this policy stores in memory.
    public var usesMemory: Bool {
        storageMode == .memory || storageMode == .memoryAndDisk
    }

    /// Whether this policy stores on disk.
    public var usesDisk: Bool {
        storageMode == .disk || storageMode == .memoryAndDisk
    }

    /// Whether caching is effectively disabled.
    public var isDisabled: Bool {
        ttl <= 0
    }
}
