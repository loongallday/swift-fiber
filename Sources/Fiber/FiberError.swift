import Foundation

// MARK: - FiberError

/// Rich error type carrying full context for debugging.
///
/// ```swift
/// do {
///     let users = try await fiber.get("/users").decode([User].self)
/// } catch let error as FiberError {
///     print(error.localizedDescription)
///     if let status = error.statusCode { print("Status: \(status)") }
/// }
/// ```
public enum FiberError: Error, Sendable {
    case httpError(statusCode: Int, data: Data, response: FiberResponse)
    case networkError(underlying: any Error & Sendable)
    case decodingError(underlying: any Error & Sendable, data: Data)
    case encodingError(underlying: any Error & Sendable)
    case timeout(request: FiberRequest)
    case cancelled
    case interceptor(name: String, underlying: any Error & Sendable)
    case invalidURL(String)
}

extension FiberError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let data, _):
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            return "HTTP \(code): \(body)"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .decodingError(let e, _): return "Decoding error: \(e.localizedDescription)"
        case .encodingError(let e): return "Encoding error: \(e.localizedDescription)"
        case .timeout(let req): return "Timeout: \(req.httpMethod.rawValue) \(req.url)"
        case .cancelled: return "Request cancelled"
        case .interceptor(let name, let e): return "Interceptor '\(name)': \(e.localizedDescription)"
        case .invalidURL(let s): return "Invalid URL: \(s)"
        }
    }
}

extension FiberError {
    public var statusCode: Int? {
        if case .httpError(let code, _, _) = self { return code }
        return nil
    }

    public var responseData: Data? {
        switch self {
        case .httpError(_, let d, _): return d
        case .decodingError(_, let d): return d
        default: return nil
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .networkError(let e): return e
        case .decodingError(let e, _): return e
        case .encodingError(let e): return e
        case .interceptor(_, let e): return e
        default: return nil
        }
    }
}
