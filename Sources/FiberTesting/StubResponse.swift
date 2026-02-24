import Foundation
import Fiber

// MARK: - StubResponse

/// Builder for creating mock HTTP responses. Chainable like FiberRequest.
///
/// ```swift
/// // Simple
/// let stub = StubResponse(statusCode: 200, body: #"{"ok": true}"#)
///
/// // Chainable
/// let stub = StubResponse.ok()
///     .header("X-Request-Id", "abc123")
///     .body(#"{"users": []}"#)
///
/// // From Encodable
/// let stub = StubResponse.ok().jsonBody(User(id: 1, name: "Alice"))
///
/// // Error responses
/// let stub = StubResponse.notFound()
/// let stub = StubResponse.serverError()
/// let stub = StubResponse(statusCode: 429, body: "rate limited")
///     .header("Retry-After", "60")
/// ```
public struct StubResponse: Sendable {
    public var statusCode: Int
    public var data: Data
    public var headers: [String: String]

    public init(statusCode: Int = 200, data: Data = Data(), headers: [String: String] = [:]) {
        self.statusCode = statusCode; self.data = data; self.headers = headers
    }

    public init(statusCode: Int, body: String, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = Data(body.utf8)
        self.headers = headers
    }
}

// MARK: - Chainable Combinators

extension StubResponse {
    public func header(_ name: String, _ value: String) -> StubResponse {
        var c = self; c.headers[name] = value; return c
    }

    public func body(_ string: String) -> StubResponse {
        var c = self; c.data = Data(string.utf8); return c
    }

    public func body(_ data: Data) -> StubResponse {
        var c = self; c.data = data; return c
    }

    public func jsonBody<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) -> StubResponse {
        var c = self
        c.data = (try? encoder.encode(value)) ?? Data()
        c.headers["Content-Type"] = "application/json"
        return c
    }

    public func status(_ code: Int) -> StubResponse {
        var c = self; c.statusCode = code; return c
    }
}

// MARK: - Factory Methods

extension StubResponse {
    public static func ok(body: String = "") -> StubResponse {
        StubResponse(statusCode: 200, body: body)
    }

    public static func created(body: String = "") -> StubResponse {
        StubResponse(statusCode: 201, body: body)
    }

    public static func noContent() -> StubResponse {
        StubResponse(statusCode: 204)
    }

    public static func badRequest(body: String = #"{"error": "bad request"}"#) -> StubResponse {
        StubResponse(statusCode: 400, body: body)
    }

    public static func unauthorized(body: String = #"{"error": "unauthorized"}"#) -> StubResponse {
        StubResponse(statusCode: 401, body: body)
    }

    public static func notFound(body: String = #"{"error": "not found"}"#) -> StubResponse {
        StubResponse(statusCode: 404, body: body)
    }

    public static func serverError(body: String = #"{"error": "internal server error"}"#) -> StubResponse {
        StubResponse(statusCode: 500, body: body)
    }
}

// MARK: - Foundation Conversion

extension StubResponse {
    /// Convert to Foundation types for use by MockTransport.
    public func toFoundation(for request: URLRequest) -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://mock")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (data, response)
    }
}
