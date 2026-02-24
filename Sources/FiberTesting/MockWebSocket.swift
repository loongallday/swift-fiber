import Foundation
import Fiber
import FiberWebSocket

// MARK: - MockWebSocket

/// Paired fake WebSockets for testing. Messages sent on one appear on the other.
///
/// ```swift
/// let (client, server) = MockWebSocket.pair()
///
/// // Simulate server sending a message
/// Task {
///     try await server.send(.text("hello from server"))
/// }
///
/// // Client receives it
/// for await event in client.events {
///     if case .message(.text(let t)) = event {
///         #expect(t == "hello from server")
///     }
/// }
/// ```
public final class MockWebSocket: FiberWebSocketProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private struct MutableState {
        var connectionState: WebSocketState = .connected
        var eventContinuation: AsyncStream<WebSocketEvent>.Continuation?
        var peer: MockWebSocket?
        var sentMessages: [WebSocketMessage] = []
    }
    private var mutableState: MutableState

    public let events: AsyncStream<WebSocketEvent>

    public var state: WebSocketState {
        lock.withLock { mutableState.connectionState }
    }

    /// All messages sent through this socket.
    public var sentMessages: [WebSocketMessage] {
        lock.withLock { mutableState.sentMessages }
    }

    private init() {
        var cont: AsyncStream<WebSocketEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.mutableState = MutableState(eventContinuation: cont)
    }

    /// Create a connected pair of mock WebSockets.
    public static func pair() -> (client: MockWebSocket, server: MockWebSocket) {
        let client = MockWebSocket()
        let server = MockWebSocket()
        client.lock.withLock { client.mutableState.peer = server }
        server.lock.withLock { server.mutableState.peer = client }

        _ = client.lock.withLock { client.mutableState.eventContinuation?.yield(.connected) }
        _ = server.lock.withLock { server.mutableState.eventContinuation?.yield(.connected) }

        return (client, server)
    }

    public func send(_ message: WebSocketMessage) async throws {
        let peer: MockWebSocket? = lock.withLock {
            guard mutableState.connectionState == .connected else { return nil }
            mutableState.sentMessages.append(message)
            return mutableState.peer
        }

        guard let peer else { throw WebSocketError.notConnected }
        peer.receive(message)
    }

    /// Simulate receiving a message (called by peer or test code).
    public func receive(_ message: WebSocketMessage) {
        _ = lock.withLock {
            mutableState.eventContinuation?.yield(.message(message))
        }
    }

    /// Simulate an error event.
    public func simulateError(_ error: any Error & Sendable) {
        _ = lock.withLock {
            mutableState.eventContinuation?.yield(.error(error))
        }
    }

    public func close(code: Int? = 1000, reason: String? = nil) {
        let peer: MockWebSocket? = lock.withLock {
            mutableState.connectionState = .disconnected
            mutableState.eventContinuation?.yield(.disconnected(code: code, reason: reason))
            mutableState.eventContinuation?.finish()
            let p = mutableState.peer
            mutableState.peer = nil
            return p
        }

        peer?.lock.withLock {
            peer?.mutableState.connectionState = .disconnected
            peer?.mutableState.eventContinuation?.yield(.disconnected(code: code, reason: reason))
            peer?.mutableState.eventContinuation?.finish()
            peer?.mutableState.peer = nil
        }
    }
}
