import Foundation

// MARK: - HTTPMethod

public struct HTTPMethod: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue.uppercased() }
    public var description: String { rawValue }

    public static let get     = HTTPMethod(rawValue: "GET")
    public static let post    = HTTPMethod(rawValue: "POST")
    public static let put     = HTTPMethod(rawValue: "PUT")
    public static let patch   = HTTPMethod(rawValue: "PATCH")
    public static let delete  = HTTPMethod(rawValue: "DELETE")
    public static let head    = HTTPMethod(rawValue: "HEAD")
    public static let options = HTTPMethod(rawValue: "OPTIONS")
}

// MARK: - FiberRequest

/// Immutable request value. Build and transform with chainable functional combinators — like Axios.
///
/// ```swift
/// let req = FiberRequest(url: "https://api.example.com/users")
///     .method(.post)
///     .header("Authorization", "Bearer tok")
///     .query("page", "1")
///     .jsonBody(newUser)
///     .timeout(30)
/// ```
public struct FiberRequest: Sendable {
    public var url: URL
    public var httpMethod: HTTPMethod
    public var headers: [String: String]
    public var queryItems: [URLQueryItem]
    public var body: Data?
    public var timeoutInterval: TimeInterval
    /// Arbitrary key-value metadata for interceptors to read/write.
    public var metadata: [String: String]

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: TimeInterval = 60,
        metadata: [String: String] = [:]
    ) {
        self.url = url
        self.httpMethod = method
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
        self.timeoutInterval = timeout
        self.metadata = metadata
    }

    public init(url string: String, method: HTTPMethod = .get) {
        guard let url = URL(string: string) else { preconditionFailure("Invalid URL: \(string)") }
        self.init(url: url, method: method)
    }
}

// MARK: - Chainable Combinators

extension FiberRequest {
    public func method(_ m: HTTPMethod) -> FiberRequest {
        var c = self; c.httpMethod = m; return c
    }

    public func header(_ name: String, _ value: String) -> FiberRequest {
        var c = self; c.headers[name] = value; return c
    }

    public func headers(_ h: [String: String]) -> FiberRequest {
        var c = self; c.headers.merge(h) { _, new in new }; return c
    }

    public func query(_ name: String, _ value: String) -> FiberRequest {
        var c = self; c.queryItems.append(URLQueryItem(name: name, value: value)); return c
    }

    public func body(_ data: Data?) -> FiberRequest {
        var c = self; c.body = data; return c
    }

    public func jsonBody<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder(), contentType: String = FiberDefaults.shared.jsonContentType) throws -> FiberRequest {
        var c = self
        c.body = try encoder.encode(value)
        c.headers["Content-Type"] = contentType
        return c
    }

    public func timeout(_ interval: TimeInterval) -> FiberRequest {
        var c = self; c.timeoutInterval = interval; return c
    }

    public func meta(_ key: String, _ value: String) -> FiberRequest {
        var c = self; c.metadata[key] = value; return c
    }

    /// Apply an arbitrary transform.
    public func map(_ f: (FiberRequest) throws -> FiberRequest) rethrows -> FiberRequest {
        try f(self)
    }
}

// MARK: - URLRequest Conversion

extension FiberRequest {
    public func toURLRequest() -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        var req = URLRequest(url: components.url ?? url)
        req.httpMethod = httpMethod.rawValue
        req.timeoutInterval = timeoutInterval
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }
}
