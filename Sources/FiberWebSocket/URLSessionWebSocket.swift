import Foundation
import Fiber

// MARK: - URLSessionWebSocketTransport

/// WebSocket backed by URLSessionWebSocketTask.
///
/// ```swift
/// let ws = URLSessionWebSocketTransport.connect(
///     to: URL(string: "wss://api.example.com/ws")!,
///     headers: ["Authorization": "Bearer token"]
/// )
///
/// Task {
///     for await event in ws.events {
///         switch event {
///         case .connected: print("Connected!")
///         case .message(.text(let t)): print("Got: \(t)")
///         case .disconnected(let code, _): print("Closed: \(code ?? 0)")
///         case .error(let e): print("Error: \(e)")
///         default: break
///         }
///     }
/// }
///
/// try await ws.send("hello")
/// ws.close(code: 1000, reason: "bye")
/// ```
public final class URLSessionWebSocketTransport: NSObject, FiberWebSocketProtocol, @unchecked Sendable {
    private struct MutableState {
        var connectionState: WebSocketState = .connecting
        var eventContinuation: AsyncStream<WebSocketEvent>.Continuation?
    }

    private let lock = NSLock()
    private var mutableState = MutableState()
    private let task: URLSessionWebSocketTask
    public let events: AsyncStream<WebSocketEvent>

    public var state: WebSocketState {
        lock.lock(); defer { lock.unlock() }
        return mutableState.connectionState
    }

    private init(task: URLSessionWebSocketTask) {
        self.task = task
        var continuation: AsyncStream<WebSocketEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        super.init()
        lock.lock()
        mutableState.eventContinuation = continuation
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            self?.task.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Connect to a WebSocket URL.
    public static func connect(
        to url: URL,
        headers: [String: String] = [:],
        protocols: [String] = [],
        configuration: URLSessionConfiguration = .default
    ) -> URLSessionWebSocketTransport {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let session = URLSession(configuration: configuration)
        let task = protocols.isEmpty
            ? session.webSocketTask(with: request)
            : session.webSocketTask(with: request.url!, protocols: protocols)

        let transport = URLSessionWebSocketTransport(task: task)
        task.resume()

        transport.lock.lock()
        transport.mutableState.connectionState = .connected
        transport.mutableState.eventContinuation?.yield(.connected)
        transport.lock.unlock()

        transport.startReceiving()
        return transport
    }

    public func send(_ message: WebSocketMessage) async throws {
        let wsMsg: URLSessionWebSocketTask.Message
        switch message {
        case .text(let s): wsMsg = .string(s)
        case .binary(let d): wsMsg = .data(d)
        }
        try await task.send(wsMsg)
    }

    public func close(code: Int? = FiberDefaults.shared.webSocketDefaultCloseCode, reason: String? = nil) {
        lock.lock()
        mutableState.connectionState = .disconnecting
        lock.unlock()

        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code ?? FiberDefaults.shared.webSocketDefaultCloseCode) ?? .normalClosure
        task.cancel(with: closeCode, reason: reason?.data(using: .utf8))

        lock.lock()
        mutableState.connectionState = .disconnected
        mutableState.eventContinuation?.yield(.disconnected(code: code, reason: reason))
        mutableState.eventContinuation?.finish()
        lock.unlock()
    }

    private func startReceiving() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let wsMsg: WebSocketMessage
                switch message {
                case .string(let t): wsMsg = .text(t)
                case .data(let d): wsMsg = .binary(d)
                @unknown default: return
                }
                self.lock.lock()
                self.mutableState.eventContinuation?.yield(.message(wsMsg))
                self.lock.unlock()
                self.startReceiving()

            case .failure(let error):
                self.lock.lock()
                self.mutableState.connectionState = .disconnected
                self.mutableState.eventContinuation?.yield(.error(error))
                self.mutableState.eventContinuation?.finish()
                self.lock.unlock()
            }
        }
    }
}
