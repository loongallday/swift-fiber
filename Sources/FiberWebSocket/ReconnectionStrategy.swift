import Foundation
import Fiber

// MARK: - ReconnectionStrategy

/// Defines how and when to reconnect a WebSocket.
///
/// ```swift
/// let strategy = ReconnectionStrategy.exponentialBackoff(baseDelay: 1, maxDelay: 30, maxAttempts: 10)
///
/// let custom = ReconnectionStrategy(maxAttempts: 5) { attempt in
///     Double(attempt) * 2.0  // linear
/// }
/// ```
public struct ReconnectionStrategy: Sendable {
    public let maxAttempts: Int
    public let delayForAttempt: @Sendable (Int) -> TimeInterval

    public init(maxAttempts: Int, delayForAttempt: @escaping @Sendable (Int) -> TimeInterval) {
        self.maxAttempts = maxAttempts; self.delayForAttempt = delayForAttempt
    }

    public static let none = ReconnectionStrategy(maxAttempts: 0) { _ in 0 }

    public static func exponentialBackoff(baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 30.0, maxAttempts: Int = 10, defaults: FiberDefaults = .shared) -> ReconnectionStrategy {
        ReconnectionStrategy(maxAttempts: maxAttempts) { attempt in
            let delay = min(baseDelay * pow(defaults.exponentialBackoffBase, Double(attempt)), maxDelay)
            return delay + Double.random(in: 0...(delay * defaults.jitterFraction))
        }
    }

    public static func fixedDelay(_ delay: TimeInterval, maxAttempts: Int = 10) -> ReconnectionStrategy {
        ReconnectionStrategy(maxAttempts: maxAttempts) { _ in delay }
    }

    public static func linearBackoff(increment: TimeInterval = 1.0, maxDelay: TimeInterval = 30.0, maxAttempts: Int = 10) -> ReconnectionStrategy {
        ReconnectionStrategy(maxAttempts: maxAttempts) { attempt in min(increment * Double(attempt + 1), maxDelay) }
    }
}

// MARK: - ReconnectingWebSocket

/// Auto-reconnecting WebSocket wrapper.
///
/// ```swift
/// let ws = ReconnectingWebSocket(
///     connect: { URLSessionWebSocketTransport.connect(to: myURL) },
///     strategy: .exponentialBackoff()
/// )
///
/// Task { await ws.start() }
/// for await event in ws.events { ... }
/// ```
public actor ReconnectingWebSocket {
    private let connectFactory: @Sendable () async throws -> any FiberWebSocketProtocol
    private let strategy: ReconnectionStrategy
    private let logger: (any FiberLogger)?
    private var currentSocket: (any FiberWebSocketProtocol)?
    private var attempt = 0
    private var isActive = true

    private let eventContinuation: AsyncStream<WebSocketEvent>.Continuation
    public nonisolated let events: AsyncStream<WebSocketEvent>

    public init(
        connect: @escaping @Sendable () async throws -> any FiberWebSocketProtocol,
        strategy: ReconnectionStrategy = .exponentialBackoff(),
        logger: (any FiberLogger)? = nil
    ) {
        self.connectFactory = connect; self.strategy = strategy; self.logger = logger
        var cont: AsyncStream<WebSocketEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.eventContinuation = cont
    }

    public func start() async {
        while isActive && attempt <= strategy.maxAttempts {
            do {
                let socket = try await connectFactory()
                currentSocket = socket; attempt = 0
                eventContinuation.yield(.connected)
                logger?.info("WebSocket connected", system: "WS")

                for await event in socket.events {
                    switch event {
                    case .message(let msg): eventContinuation.yield(.message(msg))
                    case .disconnected(let c, let r):
                        eventContinuation.yield(.disconnected(code: c, reason: r))
                        logger?.warning("Disconnected: \(c ?? 0)", system: "WS")
                    case .error(let e):
                        eventContinuation.yield(.error(e))
                        logger?.error("Error: \(e)", system: "WS")
                    case .connected: break
                    }
                }

                if isActive {
                    attempt += 1
                    let delay = strategy.delayForAttempt(attempt)
                    logger?.info("Reconnecting in \(delay)s (\(attempt)/\(strategy.maxAttempts))", system: "WS")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                attempt += 1
                if attempt > strategy.maxAttempts { eventContinuation.yield(.error(error)); break }
                let delay = strategy.delayForAttempt(attempt)
                logger?.warning("Failed, retry in \(delay)s: \(error)", system: "WS")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        eventContinuation.finish()
    }

    public func send(_ message: WebSocketMessage) async throws {
        guard let socket = currentSocket else { throw WebSocketError.notConnected }
        try await socket.send(message)
    }

    public func stop() {
        isActive = false
        currentSocket?.close(code: FiberDefaults.shared.webSocketDefaultCloseCode, reason: "client stop")
        eventContinuation.finish()
    }
}
