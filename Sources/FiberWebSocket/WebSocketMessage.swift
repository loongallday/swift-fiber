import Foundation

// MARK: - WebSocketMessage

/// A typed WebSocket message — text or binary.
///
/// ```swift
/// try await ws.send(.text("hello"))
///
/// let msg = try WebSocketMessage.json(MyPayload(action: "subscribe"))
/// try await ws.send(msg)
///
/// for await message in ws.messages {
///     switch message {
///     case .text(let str): print("Got text: \(str)")
///     case .binary(let data): print("Got \(data.count) bytes")
///     }
/// }
/// ```
public enum WebSocketMessage: Sendable, Hashable {
    case text(String)
    case binary(Data)
}

extension WebSocketMessage {
    /// Encode an Encodable as JSON text.
    public static func json<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> WebSocketMessage {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else { return .binary(data) }
        return .text(string)
    }

    /// Decode as JSON.
    public func decode<T: Decodable>(_ type: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws -> T? {
        switch self {
        case .text(let string):
            guard let data = string.data(using: .utf8) else { return nil }
            return try decoder.decode(T.self, from: data)
        case .binary(let data):
            return try decoder.decode(T.self, from: data)
        }
    }

    public var text: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    public var data: Data {
        switch self {
        case .text(let s): return Data(s.utf8)
        case .binary(let d): return d
        }
    }
}
