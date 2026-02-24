import Foundation
import Fiber

// MARK: - FiberHTTPClient

/// Struct-of-closures HTTP client for use with swift-dependencies.
///
/// ```swift
/// @Dependency(\.fiberHTTPClient) var httpClient
///
/// let response = try await httpClient.get("/users", [:], [:])
/// let users: [User] = try response.decode()
/// ```
public struct FiberHTTPClient: Sendable {
    public var send: @Sendable (FiberRequest) async throws -> FiberResponse
    public var get: @Sendable (_ path: String, _ query: [String: String], _ headers: [String: String]) async throws -> FiberResponse
    public var post: @Sendable (_ path: String, _ data: Data?, _ headers: [String: String]) async throws -> FiberResponse
    public var put: @Sendable (_ path: String, _ data: Data?, _ headers: [String: String]) async throws -> FiberResponse
    public var patch: @Sendable (_ path: String, _ data: Data?, _ headers: [String: String]) async throws -> FiberResponse
    public var delete: @Sendable (_ path: String, _ headers: [String: String]) async throws -> FiberResponse

    public init(
        send: @escaping @Sendable (FiberRequest) async throws -> FiberResponse,
        get: @escaping @Sendable (_ path: String, _ query: [String: String], _ headers: [String: String]) async throws -> FiberResponse,
        post: @escaping @Sendable (_ path: String, _ data: Data?, _ headers: [String: String]) async throws -> FiberResponse,
        put: @escaping @Sendable (_ path: String, _ data: Data?, _ headers: [String: String]) async throws -> FiberResponse,
        patch: @escaping @Sendable (_ path: String, _ data: Data?, _ headers: [String: String]) async throws -> FiberResponse,
        delete: @escaping @Sendable (_ path: String, _ headers: [String: String]) async throws -> FiberResponse
    ) {
        self.send = send
        self.get = get
        self.post = post
        self.put = put
        self.patch = patch
        self.delete = delete
    }
}
