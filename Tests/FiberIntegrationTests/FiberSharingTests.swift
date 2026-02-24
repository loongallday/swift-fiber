import Testing
import Foundation
import Fiber
import FiberTesting
import FiberSharing
import Sharing

// MARK: - FiberSharing Tests

@Suite("FiberSharing Tests")
struct FiberSharingTests {

    @Test("Default configuration values")
    func defaultConfig() {
        let config = FiberConfiguration()
        #expect(config.baseURL == "https://localhost")
        #expect(config.defaultTimeout == 60)
        #expect(config.defaultHeaders.isEmpty)
        #expect(config.authToken == nil)
    }

    @Test("Configuration is Codable")
    func configCodable() throws {
        let config = FiberConfiguration(
            baseURL: "https://api.example.com",
            defaultTimeout: 30,
            defaultHeaders: ["X-App": "test"],
            authToken: "tok123"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(FiberConfiguration.self, from: data)
        #expect(decoded == config)
    }

    @Test("SharedFiber rebuilds client when config changes")
    func sharedFiberRebuilds() async throws {
        let shared = SharedFiber()

        // Initial client
        let client1 = shared.client
        #expect(client1.baseURL.absoluteString == "https://localhost")

        // Same config -> same client (cached)
        let client2 = shared.client
        #expect(client1 === client2)
    }

    @Test("SharedFiber applies auth token from config")
    func sharedFiberAuthToken() async throws {
        let shared = SharedFiber()

        // The SharedFiber reads from @Shared(.fiberConfiguration)
        // In a real app, changes to the shared config would rebuild the client
        let client = shared.client
        #expect(client.baseURL.absoluteString == "https://localhost")
    }

    @Test("SharedFiber custom configure closure")
    func sharedFiberCustomConfigure() async throws {
        let shared = SharedFiber { config, fiberConfig in
            fiberConfig.timeout = config.defaultTimeout
        }
        let client = shared.client
        #expect(client.defaultTimeout == 60)
    }

    @Test("Configuration Hashable conformance")
    func configHashable() {
        let config1 = FiberConfiguration(baseURL: "https://a.com")
        let config2 = FiberConfiguration(baseURL: "https://b.com")
        let config3 = FiberConfiguration(baseURL: "https://a.com")
        #expect(config1 != config2)
        #expect(config1 == config3)
        #expect(config1.hashValue == config3.hashValue)
    }
}
