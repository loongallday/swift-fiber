import Testing
import Foundation
import Fiber

// MARK: - FiberDefaults Tests

@Suite("FiberDefaults Tests")
struct FiberDefaultsTests {

    @Test("Default values match original hardcoded values")
    func defaultValues() {
        let defaults = FiberDefaults()
        #expect(defaults.jitterFraction == 0.25)
        #expect(defaults.exponentialBackoffBase == 2.0)
        #expect(defaults.loggingSystemName == "HTTP")
        #expect(defaults.logBodyTruncationLimit == 1000)
        #expect(defaults.rateLimitSleepIncrement == 0.1)
        #expect(defaults.jsonContentType == "application/json")
        #expect(defaults.webSocketDefaultCloseCode == 1000)
    }

    @Test("Trace ID generator produces UUID strings by default")
    func traceIDGenerator() {
        let defaults = FiberDefaults()
        let id = defaults.traceIDGenerator()
        #expect(!id.isEmpty)
        #expect(UUID(uuidString: id) != nil)
    }

    @Test("Custom defaults can override all values")
    func customDefaults() {
        let custom = FiberDefaults(
            jitterFraction: 0.5,
            exponentialBackoffBase: 3.0,
            loggingSystemName: "NET",
            logBodyTruncationLimit: 500,
            rateLimitSleepIncrement: 0.2,
            jsonContentType: "application/vnd.api+json",
            traceIDGenerator: { "fixed-id" },
            webSocketDefaultCloseCode: 1001
        )
        #expect(custom.jitterFraction == 0.5)
        #expect(custom.exponentialBackoffBase == 3.0)
        #expect(custom.loggingSystemName == "NET")
        #expect(custom.logBodyTruncationLimit == 500)
        #expect(custom.rateLimitSleepIncrement == 0.2)
        #expect(custom.jsonContentType == "application/vnd.api+json")
        #expect(custom.traceIDGenerator() == "fixed-id")
        #expect(custom.webSocketDefaultCloseCode == 1001)
    }

    @Test("Fiber accepts custom defaults")
    func fiberWithDefaults() async throws {
        let custom = FiberDefaults(traceIDGenerator: { "custom-trace" })
        let fiber = Fiber("https://test.local") {
            $0.defaults = custom
        }
        #expect(fiber.defaults.traceIDGenerator() == "custom-trace")
    }

    @Test("Shared defaults singleton")
    func sharedDefaults() {
        let shared = FiberDefaults.shared
        #expect(shared.jitterFraction == 0.25)
        #expect(shared.exponentialBackoffBase == 2.0)
    }

    @Test("RetryInterceptor accepts custom defaults")
    func retryWithDefaults() {
        let custom = FiberDefaults(jitterFraction: 0.1, exponentialBackoffBase: 3.0)
        let retry = RetryInterceptor(defaults: custom)
        #expect(retry.name == "retry")
    }

    @Test("LoggingInterceptor accepts custom defaults")
    func loggingWithDefaults() {
        let custom = FiberDefaults(loggingSystemName: "NET")
        let logger = PrintFiberLogger(minLevel: .verbose)
        let logging = LoggingInterceptor(logger: logger, defaults: custom)
        #expect(logging.name == "logging")
    }
}
