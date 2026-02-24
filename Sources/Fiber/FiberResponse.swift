import Foundation

// MARK: - FiberResponse

/// Immutable response value with functional transforms for decoding and validation.
///
/// ```swift
/// let response = try await fiber.get("/users")
///
/// let users: [User] = try response.decode()
/// let validated = try response.validateStatus().validate { r in
///     guard r.header("X-Custom") != nil else { throw MyError() }
/// }
/// print(response.text ?? "no body")
/// print(response.isSuccess, response.duration)
/// ```
public struct FiberResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let request: FiberRequest
    public let duration: TimeInterval
    public let traceID: String

    public init(
        data: Data,
        statusCode: Int,
        headers: [String: String] = [:],
        request: FiberRequest,
        duration: TimeInterval = 0,
        traceID: String = ""
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.request = request
        self.duration = duration
        self.traceID = traceID
    }
}

// MARK: - Status Checks

extension FiberResponse {
    public var isSuccess: Bool { (200..<300).contains(statusCode) }
    public var isRedirect: Bool { (300..<400).contains(statusCode) }
    public var isClientError: Bool { (400..<500).contains(statusCode) }
    public var isServerError: Bool { (500..<600).contains(statusCode) }
}

// MARK: - Functional Transforms

extension FiberResponse {
    /// Decode response body as JSON.
    public func decode<T: Decodable>(_ type: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(T.self, from: data)
    }

    /// Body as UTF-8 string.
    public var text: String? { String(data: data, encoding: .utf8) }

    /// Case-insensitive header lookup.
    public func header(_ name: String) -> String? {
        let lower = name.lowercased()
        return headers.first { $0.key.lowercased() == lower }?.value
    }

    /// Transform the data payload.
    public func mapData<T>(_ f: (Data) throws -> T) rethrows -> T {
        try f(data)
    }

    /// Validate with a custom closure. Returns self on success.
    public func validate(_ check: (FiberResponse) throws -> Void) rethrows -> FiberResponse {
        try check(self)
        return self
    }

    /// Ensure status code is in range (default 200..<300), or throw FiberError.
    public func validateStatus(in range: Range<Int> = 200..<300) throws -> FiberResponse {
        guard range.contains(statusCode) else {
            throw FiberError.httpError(statusCode: statusCode, data: data, response: self)
        }
        return self
    }

    /// Build from Foundation URLResponse.
    public static func from(
        data: Data,
        urlResponse: URLResponse,
        request: FiberRequest,
        duration: TimeInterval = 0,
        traceID: String = ""
    ) -> FiberResponse {
        let http = urlResponse as? HTTPURLResponse
        return FiberResponse(
            data: data,
            statusCode: http?.statusCode ?? 0,
            headers: (http?.allHeaderFields as? [String: String]) ?? [:],
            request: request,
            duration: duration,
            traceID: traceID
        )
    }
}
