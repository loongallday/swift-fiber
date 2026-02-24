import Testing
import Foundation
import Fiber
import FiberTesting
import FiberSharing
import Sharing

// MARK: - CachePolicy Tests

@Suite("CachePolicy Tests")
struct CachePolicyTests {

    @Test("Default preset values")
    func defaultPreset() {
        let policy = CachePolicy.default
        #expect(policy.ttl == 300)
        #expect(policy.staleWhileRevalidate == 0)
        #expect(policy.storageMode == .memory)
        #expect(policy.maxEntries == 100)
    }

    @Test("Aggressive preset values")
    func aggressivePreset() {
        let policy = CachePolicy.aggressive
        #expect(policy.ttl == 1800)
        #expect(policy.staleWhileRevalidate == 60)
        #expect(policy.storageMode == .memoryAndDisk)
        #expect(policy.maxEntries == 200)
    }

    @Test("NoCache preset")
    func noCachePreset() {
        let policy = CachePolicy.noCache
        #expect(policy.ttl == 0)
        #expect(policy.maxEntries == 0)
        #expect(policy.isDisabled)
    }

    @Test("Persistent preset values")
    func persistentPreset() {
        let policy = CachePolicy.persistent
        #expect(policy.ttl == 3600)
        #expect(policy.staleWhileRevalidate == 300)
        #expect(policy.storageMode == .disk)
        #expect(policy.maxEntries == 500)
    }

    @Test("Custom policy values")
    func customPolicy() {
        let policy = CachePolicy(ttl: 600, staleWhileRevalidate: 120, storageMode: .memoryAndDisk, maxEntries: 50)
        #expect(policy.ttl == 600)
        #expect(policy.staleWhileRevalidate == 120)
        #expect(policy.storageMode == .memoryAndDisk)
        #expect(policy.maxEntries == 50)
    }

    @Test("Storage mode helpers")
    func storageModeHelpers() {
        #expect(CachePolicy(storageMode: .memory).usesMemory)
        #expect(!CachePolicy(storageMode: .memory).usesDisk)
        #expect(!CachePolicy(storageMode: .disk).usesMemory)
        #expect(CachePolicy(storageMode: .disk).usesDisk)
        #expect(CachePolicy(storageMode: .memoryAndDisk).usesMemory)
        #expect(CachePolicy(storageMode: .memoryAndDisk).usesDisk)
    }

    @Test("isDisabled for zero TTL")
    func isDisabled() {
        #expect(CachePolicy(ttl: 0).isDisabled)
        #expect(CachePolicy(ttl: -1).isDisabled)
        #expect(!CachePolicy(ttl: 1).isDisabled)
    }
}

// MARK: - CachedResponse Tests

@Suite("CachedResponse Tests")
struct CachedResponseTests {

    @Test("Fresh response is not expired")
    func freshResponse() {
        let cached = CachedResponse.from(value: "hello", ttl: 300)
        #expect(cached.isFresh)
        #expect(!cached.isExpired)
        #expect(cached.age < 1)
    }

    @Test("Expired response")
    func expiredResponse() {
        let cached = CachedResponse(
            value: "old",
            cachedAt: Date().addingTimeInterval(-600),
            expiresAt: Date().addingTimeInterval(-300)
        )
        #expect(cached.isExpired)
        #expect(!cached.isFresh)
    }

    @Test("Stale within revalidate window")
    func staleWhileRevalidate() {
        let policy = CachePolicy(ttl: 300, staleWhileRevalidate: 60)
        // Expired 10 seconds ago — within 60s revalidate window
        let cached = CachedResponse(
            value: "stale",
            cachedAt: Date().addingTimeInterval(-310),
            expiresAt: Date().addingTimeInterval(-10)
        )
        #expect(cached.isExpired)
        #expect(cached.isStale(policy: policy))
    }

    @Test("Not stale when beyond revalidate window")
    func notStale() {
        let policy = CachePolicy(ttl: 300, staleWhileRevalidate: 60)
        // Expired 120 seconds ago — beyond 60s window
        let cached = CachedResponse(
            value: "gone",
            cachedAt: Date().addingTimeInterval(-420),
            expiresAt: Date().addingTimeInterval(-120)
        )
        #expect(cached.isExpired)
        #expect(!cached.isStale(policy: policy))
    }

    @Test("Supports conditional request with etag")
    func conditionalWithEtag() {
        let cached = CachedResponse.from(value: 42, ttl: 300, etag: "\"abc123\"")
        #expect(cached.supportsConditionalRequest)
    }

    @Test("Supports conditional request with lastModified")
    func conditionalWithLastModified() {
        let cached = CachedResponse.from(value: 42, ttl: 300, lastModified: "Wed, 21 Oct 2024 07:28:00 GMT")
        #expect(cached.supportsConditionalRequest)
    }

    @Test("No conditional request without headers")
    func noConditional() {
        let cached = CachedResponse.from(value: 42, ttl: 300)
        #expect(!cached.supportsConditionalRequest)
    }

    @Test("Refreshed preserves value and headers")
    func refreshed() {
        let original = CachedResponse.from(value: "test", ttl: 10, etag: "\"v1\"", lastModified: "Mon, 01 Jan 2024")
        let refreshed = original.refreshed(ttl: 300)
        #expect(refreshed.value == "test")
        #expect(refreshed.etag == "\"v1\"")
        #expect(refreshed.lastModified == "Mon, 01 Jan 2024")
        #expect(refreshed.isFresh)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = CachedResponse.from(value: [1, 2, 3], ttl: 300, etag: "\"xyz\"")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CachedResponse<[Int]>.self, from: data)
        #expect(decoded.value == [1, 2, 3])
        #expect(decoded.etag == "\"xyz\"")
    }
}

// MARK: - SharedCacheStore Tests

@Suite("SharedCacheStore Tests")
struct SharedCacheStoreTests {

    @Test("Memory get and set")
    func memoryGetSet() async {
        let store = SharedCacheStore()
        let cached = CachedResponse.from(value: "hello", ttl: 300)
        let policy = CachePolicy.default

        await store.set("test-key", value: cached, policy: policy)
        let result: CachedResponse<String>? = await store.get("test-key", as: String.self)
        #expect(result?.value == "hello")
    }

    @Test("Memory cache miss")
    func memoryCacheMiss() async {
        let store = SharedCacheStore()
        let result: CachedResponse<String>? = await store.get("nonexistent", as: String.self)
        #expect(result == nil)
    }

    @Test("LRU eviction when over capacity")
    func lruEviction() async {
        let store = SharedCacheStore()
        let policy = CachePolicy(maxEntries: 3)

        // Fill to capacity
        for i in 0..<3 {
            let cached = CachedResponse.from(value: i, ttl: 300)
            await store.set("key-\(i)", value: cached, policy: policy)
        }
        #expect(await store.memoryCount == 3)

        // Access key-0 to make it recently used
        let _: CachedResponse<Int>? = await store.get("key-0", as: Int.self)

        // Add one more — should evict least recently used (key-1)
        let newCached = CachedResponse.from(value: 99, ttl: 300)
        await store.set("key-3", value: newCached, policy: policy)
        #expect(await store.memoryCount == 3)

        // key-1 should be evicted (it was least recently accessed)
        let evicted: CachedResponse<Int>? = await store.get("key-1", as: Int.self)
        #expect(evicted == nil)

        // key-0 should still be there (was accessed)
        let kept: CachedResponse<Int>? = await store.get("key-0", as: Int.self)
        #expect(kept?.value == 0)
    }

    @Test("Invalidate specific key")
    func invalidateKey() async {
        let store = SharedCacheStore()
        let cached = CachedResponse.from(value: "data", ttl: 300)
        await store.set("key", value: cached, policy: .default)
        await store.invalidate("key")
        let result: CachedResponse<String>? = await store.get("key", as: String.self)
        #expect(result == nil)
    }

    @Test("Invalidate all")
    func invalidateAll() async {
        let store = SharedCacheStore()
        let policy = CachePolicy.default
        for i in 0..<5 {
            await store.set("key-\(i)", value: CachedResponse.from(value: i, ttl: 300), policy: policy)
        }
        #expect(await store.memoryCount == 5)
        await store.invalidateAll()
        #expect(await store.memoryCount == 0)
    }

    @Test("Invalidate matching prefix")
    func invalidateMatching() async {
        let store = SharedCacheStore()
        let policy = CachePolicy.default
        await store.set("GET:/users", value: CachedResponse.from(value: 1, ttl: 300), policy: policy)
        await store.set("GET:/users/1", value: CachedResponse.from(value: 2, ttl: 300), policy: policy)
        await store.set("GET:/posts", value: CachedResponse.from(value: 3, ttl: 300), policy: policy)

        await store.invalidateMatching("GET:/users")
        #expect(await store.memoryCount == 1)
        let posts: CachedResponse<Int>? = await store.get("GET:/posts", as: Int.self)
        #expect(posts?.value == 3)
    }

    @Test("Disk persistence round-trip")
    func diskRoundTrip() async {
        let store = SharedCacheStore()
        let cached = CachedResponse.from(value: [1, 2, 3], ttl: 300, etag: "\"v1\"")
        let key = "disk-test-key"

        await store.saveToDisk(key, value: cached)
        let loaded: CachedResponse<[Int]>? = await store.loadFromDisk(key, as: [Int].self)
        #expect(loaded?.value == [1, 2, 3])
        #expect(loaded?.etag == "\"v1\"")

        // Cleanup
        await store.removeFromDisk(key)
    }

    @Test("Skip memory storage for disk-only policy")
    func diskOnlyPolicy() async {
        let store = SharedCacheStore()
        let policy = CachePolicy(storageMode: .disk)
        let cached = CachedResponse.from(value: "disk-only", ttl: 300)
        await store.set("disk-key", value: cached, policy: policy)
        #expect(await store.memoryCount == 0)
    }

    @Test("Skip storage for disabled policy")
    func disabledPolicy() async {
        let store = SharedCacheStore()
        let cached = CachedResponse.from(value: "none", ttl: 0)
        await store.set("no-cache", value: cached, policy: .noCache)
        #expect(await store.memoryCount == 0)
    }
}

// MARK: - Cache Key Tests

@Suite("Cache Key Tests")
struct CacheKeyTests {

    @Test("Simple path key")
    func simplePath() {
        let key = SharedFiber.makeCacheKey(path: "/users")
        #expect(key == "GET:/users")
    }

    @Test("Path with query parameters are sorted")
    func pathWithQuery() {
        let key = SharedFiber.makeCacheKey(path: "/users", query: ["page": "2", "limit": "10"])
        #expect(key == "GET:/users?limit=10&page=2")
    }

    @Test("Empty query produces same key as no query")
    func emptyQuery() {
        let key1 = SharedFiber.makeCacheKey(path: "/users")
        let key2 = SharedFiber.makeCacheKey(path: "/users", query: [:])
        #expect(key1 == key2)
    }

    @Test("Different query params produce different keys")
    func differentQueries() {
        let key1 = SharedFiber.makeCacheKey(path: "/users", query: ["page": "1"])
        let key2 = SharedFiber.makeCacheKey(path: "/users", query: ["page": "2"])
        #expect(key1 != key2)
    }
}

// MARK: - SharedFiber getCached Tests

@Suite("SharedFiber getCached Tests", .serialized)
struct SharedFiberCacheTests {

    private func makeSharedFiber(mock: MockTransport) -> SharedFiber {
        SharedFiber { _, config in
            config.transport = mock
        }
    }

    @Test("Cache miss fetches from network")
    func cacheMiss() async throws {
        let mock = MockTransport()
        let userData = Data(#"{"name":"Alice"}"#.utf8)
        mock.stubAll(StubResponse(statusCode: 200, data: userData, headers: ["ETag": "\"v1\""]))

        @Shared(.fiberConfiguration) var config
        $config.withLock { $0 = FiberConfiguration(baseURL: "https://test.local") }

        let fiber = makeSharedFiber(mock: mock)
        // Clear any prior cache state
        await fiber.clearCache()

        let result: CachedResponse<[String: String]> = try await fiber.getCached(
            "/user", as: [String: String].self
        )
        #expect(result.value == ["name": "Alice"])
        #expect(result.etag == "\"v1\"")
        #expect(result.isFresh)
        #expect(mock.requests.count == 1)
    }

    @Test("Cache hit avoids network")
    func cacheHit() async throws {
        let mock = MockTransport()
        let userData = Data(#"{"name":"Alice"}"#.utf8)
        mock.stubAll(StubResponse(statusCode: 200, data: userData))

        @Shared(.fiberConfiguration) var config
        $config.withLock { $0 = FiberConfiguration(baseURL: "https://test.local") }

        let fiber = makeSharedFiber(mock: mock)
        await fiber.clearCache()

        // First call — cache miss
        let _: CachedResponse<[String: String]> = try await fiber.getCached(
            "/user", as: [String: String].self
        )
        #expect(mock.requests.count == 1)

        // Second call — cache hit
        let result: CachedResponse<[String: String]> = try await fiber.getCached(
            "/user", as: [String: String].self
        )
        #expect(result.value == ["name": "Alice"])
        #expect(mock.requests.count == 1) // No additional network call
    }

    @Test("Conditional request sends If-None-Match header")
    func conditionalEtag() async throws {
        let mock = MockTransport()

        // First response has ETag
        mock.stub { req in
            if req.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return StubResponse(statusCode: 304)
            }
            return StubResponse(statusCode: 200, body: #"{"id":1}"#, headers: ["ETag": "\"v1\""])
        }

        @Shared(.fiberConfiguration) var config
        $config.withLock { $0 = FiberConfiguration(baseURL: "https://test.local") }

        let fiber = makeSharedFiber(mock: mock)
        await fiber.clearCache()

        // First call — gets data + ETag
        let first: CachedResponse<[String: Int]> = try await fiber.getCached(
            "/item", as: [String: Int].self, policy: CachePolicy(ttl: 0) // immediate expiration
        )
        #expect(first.value == ["id": 1])

        // Manually store with short TTL so it expires but keeps etag
        let store = SharedCacheStore.shared
        let expiredCached = CachedResponse(
            value: ["id": 1],
            cachedAt: Date().addingTimeInterval(-10),
            expiresAt: Date().addingTimeInterval(-1),
            etag: "\"v1\""
        )
        await store.set(
            SharedFiber.makeCacheKey(path: "/item"),
            value: expiredCached,
            policy: .default
        )

        // Second call — sends If-None-Match, gets 304
        let second: CachedResponse<[String: Int]> = try await fiber.getCached(
            "/item", as: [String: Int].self
        )
        #expect(second.value == ["id": 1]) // Same data
        #expect(second.isFresh)            // But refreshed TTL

        // Verify the conditional header was sent
        let lastReq = mock.requests.last
        #expect(lastReq?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    }

    @Test("No-cache policy always fetches")
    func noCachePolicy() async throws {
        let mock = MockTransport()
        var callCount = 0
        mock.stub { _ in
            callCount += 1
            return StubResponse(statusCode: 200, body: #"{"n":\#(callCount)}"#)
        }

        @Shared(.fiberConfiguration) var config
        $config.withLock { $0 = FiberConfiguration(baseURL: "https://test.local") }

        let fiber = makeSharedFiber(mock: mock)

        let first: CachedResponse<[String: Int]> = try await fiber.getCached(
            "/counter", as: [String: Int].self, policy: .noCache
        )
        let second: CachedResponse<[String: Int]> = try await fiber.getCached(
            "/counter", as: [String: Int].self, policy: .noCache
        )

        #expect(first.value["n"] == 1)
        #expect(second.value["n"] == 2)
        #expect(mock.requests.count == 2) // Both went to network
    }

    @Test("Cache invalidation clears entry")
    func cacheInvalidation() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse(statusCode: 200, body: #"{"ok":true}"#))

        @Shared(.fiberConfiguration) var config
        $config.withLock { $0 = FiberConfiguration(baseURL: "https://test.local") }

        let fiber = makeSharedFiber(mock: mock)
        await fiber.clearCache()

        // Populate cache
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached(
            "/data", as: [String: Bool].self
        )
        #expect(mock.requests.count == 1)

        // Invalidate
        await fiber.invalidateCache(for: "/data")

        // Should fetch again
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached(
            "/data", as: [String: Bool].self
        )
        #expect(mock.requests.count == 2)
    }

    @Test("Prefix invalidation clears matching entries")
    func prefixInvalidation() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse(statusCode: 200, body: #"{"ok":true}"#))

        @Shared(.fiberConfiguration) var config
        $config.withLock { $0 = FiberConfiguration(baseURL: "https://test.local") }

        let fiber = makeSharedFiber(mock: mock)
        await fiber.clearCache()

        // Populate multiple cache entries
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/users", as: [String: Bool].self)
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/users/1", as: [String: Bool].self)
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/posts", as: [String: Bool].self)
        #expect(mock.requests.count == 3)

        // Invalidate all /users paths
        await fiber.invalidateCacheMatching("GET:/users")

        // /users should refetch, /posts should be cached
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/users", as: [String: Bool].self)
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/posts", as: [String: Bool].self)

        #expect(mock.requests.count == 4) // Only /users refetched
    }

    @Test("Clear cache removes everything")
    func clearAllCache() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse(statusCode: 200, body: #"{"ok":true}"#))

        @Shared(.fiberConfiguration) var config
        $config.withLock { $0 = FiberConfiguration(baseURL: "https://test.local") }

        let fiber = makeSharedFiber(mock: mock)
        await fiber.clearCache()

        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/a", as: [String: Bool].self)
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/b", as: [String: Bool].self)
        #expect(mock.requests.count == 2)

        await fiber.clearCache()

        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/a", as: [String: Bool].self)
        let _: CachedResponse<[String: Bool]> = try await fiber.getCached("/b", as: [String: Bool].self)
        #expect(mock.requests.count == 4) // Both refetched
    }
}
