import Foundation
import Fiber

// MARK: - FiberHTTPClient Live

extension FiberHTTPClient {
    /// Create a live HTTP client backed by a `Fiber` instance.
    ///
    /// ```swift
    /// let fiber = Fiber("https://api.example.com") {
    ///     $0.interceptors = [authInterceptor]
    /// }
    /// let client = FiberHTTPClient.live(fiber)
    /// ```
    public static func live(_ fiber: Fiber) -> FiberHTTPClient {
        FiberHTTPClient(
            send: { request in
                try await fiber.send(request)
            },
            get: { path, query, headers in
                try await fiber.get(path, query: query, headers: headers)
            },
            post: { path, data, headers in
                try await fiber.post(path, data: data, headers: headers)
            },
            put: { path, data, headers in
                var req = FiberRequest(url: fiber.baseURL.appendingPathComponent(path), method: .put)
                    .headers(headers)
                if let data { req = req.body(data) }
                return try await fiber.send(req)
            },
            patch: { path, data, headers in
                var req = FiberRequest(url: fiber.baseURL.appendingPathComponent(path), method: .patch)
                    .headers(headers)
                if let data { req = req.body(data) }
                return try await fiber.send(req)
            },
            delete: { path, headers in
                try await fiber.delete(path, headers: headers)
            }
        )
    }

    /// Create a live HTTP client from a base URL string with optional configuration.
    ///
    /// ```swift
    /// let client = FiberHTTPClient.live("https://api.example.com") {
    ///     $0.interceptors = [RetryInterceptor()]
    /// }
    /// ```
    public static func live(_ baseURL: String, configure: ((inout Fiber.Config) -> Void)? = nil) -> FiberHTTPClient {
        live(Fiber(baseURL, configure: configure))
    }
}
