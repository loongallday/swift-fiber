import Foundation
import Fiber

// MARK: - WebSocketEvent

public enum WebSocketEvent: Sendable {
    case connected
    case message(WebSocketMessage)
    case disconnected(code: Int?, reason: String?)
    case error(any Error & Sendable)
}

// MARK: - WebSocketState

public enum WebSocketState: Sendable {
    case connecting
    case connected
    case disconnecting
    case disconnected
}

// MARK: - FiberWebSocketProtocol

/// Protocol for WebSocket connections. Swap implementations for testing.
///
/// ```swift
/// let ws = URLSessionWebSocketTransport.connect(
///     to: URL(string: "wss://echo.websocket.org")!
/// )
///
/// try await ws.send(.text("hello"))
///
/// for await event in ws.events {
///     if case .message(let msg) = event { print("Received: \(msg)") }
/// }
///
/// ws.close(code: 1000, reason: "done")
/// ```
public protocol FiberWebSocketProtocol: AnyObject, Sendable {
    var state: WebSocketState { get }
    var events: AsyncStream<WebSocketEvent> { get }
    func send(_ message: WebSocketMessage) async throws
    func close(code: Int?, reason: String?)
}

// MARK: - Convenience

extension FiberWebSocketProtocol {
    public func send(_ text: String) async throws { try await send(.text(text)) }
    public func send(_ data: Data) async throws { try await send(.binary(data)) }

    public func sendJSON<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) async throws {
        try await send(.json(value, encoder: encoder))
    }

    /// Filtered stream of only message events.
    public var messages: AsyncCompactMapSequence<AsyncStream<WebSocketEvent>, WebSocketMessage> {
        events.compactMap { if case .message(let msg) = $0 { return msg }; return nil }
    }

    public func close() { close(code: FiberDefaults.shared.webSocketDefaultCloseCode, reason: nil) }
}

// MARK: - WebSocketError

public enum WebSocketError: Error, Sendable, LocalizedError {
    case notConnected
    case connectionFailed(underlying: any Error & Sendable)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket is not connected"
        case .connectionFailed(let e): return "Connection failed: \(e.localizedDescription)"
        }
    }
}
