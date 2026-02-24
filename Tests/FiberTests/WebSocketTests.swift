import Testing
import Foundation
@testable import Fiber
@testable import FiberWebSocket
@testable import FiberTesting

@Suite("WebSocket")
struct WebSocketTests {

    @Test("MockWebSocket pair sends messages between peers")
    func pairCommunication() async throws {
        let (_, server) = MockWebSocket.pair()

        try await server.send(.text("hello from server"))

        #expect(server.sentMessages.count == 1)
        #expect(server.sentMessages[0] == .text("hello from server"))
    }

    @Test("MockWebSocket close propagates to peer")
    func closePropagatesToPeer() async throws {
        let (client, server) = MockWebSocket.pair()

        client.close(code: 1000, reason: "test")

        #expect(client.state == .disconnected)
        #expect(server.state == .disconnected)
    }

    @Test("WebSocketMessage JSON encoding/decoding")
    func messageJson() throws {
        struct Payload: Codable, Equatable { let action: String }

        let msg = try WebSocketMessage.json(Payload(action: "subscribe"))
        #expect(msg.text != nil)

        let decoded: Payload? = try msg.decode()
        #expect(decoded?.action == "subscribe")
    }

    @Test("WebSocketMessage text and binary")
    func messageTypes() {
        let text = WebSocketMessage.text("hello")
        #expect(text.text == "hello")
        #expect(text.data == Data("hello".utf8))

        let binary = WebSocketMessage.binary(Data([0x01, 0x02]))
        #expect(binary.text == nil)
        #expect(binary.data == Data([0x01, 0x02]))
    }

    @Test("ReconnectionStrategy exponential backoff")
    func exponentialBackoff() {
        let strategy = ReconnectionStrategy.exponentialBackoff(
            baseDelay: 1.0, maxDelay: 10.0, maxAttempts: 5
        )

        #expect(strategy.maxAttempts == 5)
        let delay0 = strategy.delayForAttempt(0)
        let delay3 = strategy.delayForAttempt(3)
        #expect(delay0 >= 1.0)
        #expect(delay0 <= 1.25) // 1.0 + up to 25% jitter
        #expect(delay3 >= 8.0)
        #expect(delay3 <= 12.5) // min(1*2^3, 10) + jitter, capped at 10+jitter
    }

    @Test("ReconnectionStrategy fixed delay")
    func fixedDelay() {
        let strategy = ReconnectionStrategy.fixedDelay(2.0, maxAttempts: 3)
        #expect(strategy.maxAttempts == 3)
        #expect(strategy.delayForAttempt(0) == 2.0)
        #expect(strategy.delayForAttempt(5) == 2.0)
    }
}
