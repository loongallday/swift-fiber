import Foundation

// MARK: - Fiber (Client)

/// Axios-style HTTP client. Functional, chainable, interceptor-driven.
///
/// ```swift
/// // Create with defaults
/// let fiber = Fiber("https://api.example.com")
///
/// // Configure everything
/// let fiber = Fiber("https://api.example.com") {
///     $0.timeout = 30
///     $0.interceptors = [authInterceptor, loggingInterceptor]
///     $0.transport = URLSessionTransport(session: mySession)
///     $0.decoder = myDecoder
///     $0.validateStatus = { (200..<300).contains($0) }
/// }
///
/// // Axios-style methods
/// let users: [User] = try await fiber.get("/users").decode()
/// let user: User = try await fiber.post("/users", body: newUser).decode()
/// let _ = try await fiber.delete("/users/\(id)")
///
/// // Or build requests manually
/// let req = FiberRequest(url: "https://api.example.com/search")
///     .method(.get)
///     .query("q", "swift")
/// let response = try await fiber.send(req)
/// ```
public final class Fiber: @unchecked Sendable {
    public let baseURL: URL
    public let interceptors: [any Interceptor]
    public let transport: any FiberTransport
    public let defaultHeaders: [String: String]
    public let defaultTimeout: TimeInterval
    public let decoder: JSONDecoder
    public let encoder: JSONEncoder
    public let logger: (any FiberLogger)?
    public let validateStatus: @Sendable (Int) -> Bool
    public let defaults: FiberDefaults

    private let chain: @Sendable (FiberRequest) async throws -> FiberResponse

    public init(
        baseURL: URL,
        interceptors: [any Interceptor] = [],
        transport: any FiberTransport = URLSessionTransport(),
        defaultHeaders: [String: String] = [:],
        defaultTimeout: TimeInterval = 60,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        logger: (any FiberLogger)? = nil,
        validateStatus: @escaping @Sendable (Int) -> Bool = { (200..<300).contains($0) },
        defaults: FiberDefaults = .shared
    ) {
        self.baseURL = baseURL
        self.interceptors = interceptors
        self.transport = transport
        self.defaultHeaders = defaultHeaders
        self.defaultTimeout = defaultTimeout
        self.decoder = decoder
        self.encoder = encoder
        self.logger = logger
        self.validateStatus = validateStatus
        self.defaults = defaults

        let capturedTransport = transport
        self.chain = InterceptorChain.build(
            interceptors: interceptors,
            transport: { request in
                let start = Date()
                let traceID = TraceContext.traceID
                let urlRequest = request.toURLRequest()
                let (data, urlResponse) = try await capturedTransport.send(urlRequest)
                let duration = Date().timeIntervalSince(start)
                return FiberResponse.from(
                    data: data, urlResponse: urlResponse,
                    request: request, duration: duration, traceID: traceID
                )
            }
        )
    }

    /// Builder-style initializer.
    public convenience init(_ baseURLString: String, configure: ((inout Config) -> Void)? = nil) {
        guard let url = URL(string: baseURLString) else {
            preconditionFailure("Invalid base URL: \(baseURLString)")
        }
        var config = Config()
        configure?(&config)
        self.init(
            baseURL: url, interceptors: config.interceptors, transport: config.transport,
            defaultHeaders: config.defaultHeaders, defaultTimeout: config.timeout,
            decoder: config.decoder, encoder: config.encoder,
            logger: config.logger, validateStatus: config.validateStatus,
            defaults: config.defaults
        )
    }

    /// Mutable configuration for builder-style init.
    public struct Config: Sendable {
        public var interceptors: [any Interceptor] = []
        public var transport: any FiberTransport = URLSessionTransport()
        public var defaultHeaders: [String: String] = [:]
        public var timeout: TimeInterval = 60
        public var decoder: JSONDecoder = JSONDecoder()
        public var encoder: JSONEncoder = JSONEncoder()
        public var logger: (any FiberLogger)? = nil
        public var validateStatus: @Sendable (Int) -> Bool = { (200..<300).contains($0) }
        public var defaults: FiberDefaults = .shared
    }
}

// MARK: - Core send

extension Fiber {
    /// Send a fully-built request through the interceptor chain.
    public func send(_ request: FiberRequest) async throws -> FiberResponse {
        let traceID = defaults.traceIDGenerator()
        let enriched = request
            .headers(defaultHeaders)
            .timeout(request.timeoutInterval > 0 ? request.timeoutInterval : defaultTimeout)

        return try await TraceContext.$traceID.withValue(traceID) {
            try await self.chain(enriched)
        }
    }

    /// Send and decode.
    public func send<T: Decodable>(_ request: FiberRequest, as type: T.Type, decoder: JSONDecoder? = nil) async throws -> T {
        let response = try await send(request)
        do {
            return try response.decode(T.self, decoder: decoder ?? self.decoder)
        } catch {
            throw FiberError.decodingError(underlying: error, data: response.data)
        }
    }
}

// MARK: - Axios-style convenience methods

extension Fiber {
    /// `let res = try await fiber.get("/users", query: ["page": "1"])`
    public func get(_ path: String, query: [String: String] = [:], headers: [String: String] = [:]) async throws -> FiberResponse {
        var req = FiberRequest(url: baseURL.appendingPathComponent(path), method: .get).headers(headers)
        for (k, v) in query { req = req.query(k, v) }
        return try await send(req)
    }

    /// `let res = try await fiber.post("/users", body: newUser)`
    public func post<T: Encodable>(_ path: String, body: T, headers: [String: String] = [:]) async throws -> FiberResponse {
        let req = try FiberRequest(url: baseURL.appendingPathComponent(path), method: .post)
            .headers(headers).jsonBody(body, encoder: encoder)
        return try await send(req)
    }

    /// POST with raw data.
    public func post(_ path: String, data: Data? = nil, headers: [String: String] = [:]) async throws -> FiberResponse {
        let req = FiberRequest(url: baseURL.appendingPathComponent(path), method: .post)
            .headers(headers).body(data)
        return try await send(req)
    }

    /// PUT request.
    public func put<T: Encodable>(_ path: String, body: T, headers: [String: String] = [:]) async throws -> FiberResponse {
        let req = try FiberRequest(url: baseURL.appendingPathComponent(path), method: .put)
            .headers(headers).jsonBody(body, encoder: encoder)
        return try await send(req)
    }

    /// PATCH request.
    public func patch<T: Encodable>(_ path: String, body: T, headers: [String: String] = [:]) async throws -> FiberResponse {
        let req = try FiberRequest(url: baseURL.appendingPathComponent(path), method: .patch)
            .headers(headers).jsonBody(body, encoder: encoder)
        return try await send(req)
    }

    /// DELETE request.
    public func delete(_ path: String, headers: [String: String] = [:]) async throws -> FiberResponse {
        let req = FiberRequest(url: baseURL.appendingPathComponent(path), method: .delete).headers(headers)
        return try await send(req)
    }
}

// MARK: - Endpoint Protocol

/// Type-safe endpoint. Define your API as value types.
///
/// ```swift
/// struct GetUser: Endpoint {
///     typealias Response = User
///     let id: String
///     var path: String { "/users/\(id)" }
///     var method: HTTPMethod { .get }
/// }
///
/// let user = try await fiber.request(GetUser(id: "123"))
/// ```
public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem] { get }
    var body: Data? { get }
}

extension Endpoint {
    public var headers: [String: String] { [:] }
    public var queryItems: [URLQueryItem] { [] }
    public var body: Data? { nil }
}

extension Fiber {
    /// Send a type-safe endpoint and decode the response.
    public func request<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let req = FiberRequest(
            url: baseURL.appendingPathComponent(endpoint.path),
            method: endpoint.method, headers: endpoint.headers,
            queryItems: endpoint.queryItems, body: endpoint.body
        )
        return try await send(req, as: E.Response.self)
    }
}
