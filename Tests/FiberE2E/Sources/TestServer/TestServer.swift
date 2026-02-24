import Foundation
import Hummingbird

/// Actor that tracks per-key request counts for the /flaky endpoint.
public actor FlakyCounter {
    private var counts: [String: Int] = [:]

    public init() {}

    public func increment(_ key: String) -> Int {
        let count = (counts[key] ?? 0) + 1
        counts[key] = count
        return count
    }
}

/// In-process Hummingbird test server. Singleton, idempotent start.
public actor TestServer {
    public static let shared = TestServer()

    private var started = false
    private let port = 8932

    public var baseURL: String { "http://127.0.0.1:\(port)" }

    private init() {}

    public func ensureStarted() async throws {
        guard !started else { return }
        started = true

        let flakyCounter = FlakyCounter()
        let router = Router()

        // MARK: - /echo (GET, POST, PUT, PATCH, DELETE)

        let echoHandler: @Sendable (Request, BasicRequestContext) async throws -> Response = { request, _ in
            let buffer = try await request.body.collect(upTo: .max)
            let bodyString = String(decoding: buffer.readableBytesView, as: UTF8.self)

            var headersDict: [String: String] = [:]
            for field in request.headers {
                headersDict[field.name.rawName] = field.value
            }

            var queryDict: [String: String] = [:]
            for (key, value) in request.uri.queryParameters {
                queryDict[String(key)] = String(value)
            }

            let echo: [String: Any] = [
                "method": request.method.rawValue,
                "path": request.uri.path,
                "headers": headersDict,
                "query": queryDict,
                "body": bodyString,
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: echo)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: jsonString))
            )
        }

        router.on("echo", method: .get, use: echoHandler)
        router.on("echo", method: .post, use: echoHandler)
        router.on("echo", method: .put, use: echoHandler)
        router.on("echo", method: .patch, use: echoHandler)
        router.on("echo", method: .delete, use: echoHandler)

        // MARK: - /status/:code

        router.get("status/:code") { _, context -> Response in
            let code = try context.parameters.require("code", as: Int.self)
            return Response(status: .init(code: code))
        }

        // MARK: - /delay/:ms

        router.get("delay/:ms") { _, context -> Response in
            let ms = try context.parameters.require("ms", as: Int.self)
            try await Task.sleep(for: .milliseconds(ms))
            return Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: "OK")))
        }

        // MARK: - /json (POST - echoes JSON body)

        router.post("json") { request, _ -> Response in
            let buffer = try await request.body.collect(upTo: .max)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: buffer)
            )
        }

        // MARK: - /headers (GET - returns request headers as JSON)

        router.get("headers") { request, _ -> Response in
            var headersDict: [String: String] = [:]
            for field in request.headers {
                headersDict[field.name.rawName] = field.value
            }
            let jsonData = try JSONSerialization.data(withJSONObject: headersDict)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: jsonString))
            )
        }

        // MARK: - /auth/protected (GET - 200 with valid token, 401 otherwise)

        router.get("auth/protected") { request, _ -> Response in
            if request.headers[.authorization] == "Bearer valid-token" {
                let body = #"{"message":"authenticated"}"#
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(string: body))
                )
            }
            return Response(status: .unauthorized)
        }

        // MARK: - /auth/refresh (POST - returns new token)

        router.post("auth/refresh") { _, _ -> Response in
            let body = #"{"token":"valid-token"}"#
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: body))
            )
        }

        // MARK: - /flaky (GET - fails N times per key, then succeeds)

        router.get("flaky") { request, _ -> Response in
            let key = request.uri.queryParameters["key"].map(String.init) ?? "default"
            let failCount = request.uri.queryParameters["fail"].flatMap { Int(String($0)) } ?? 0
            let count = await flakyCounter.increment(key)
            if count <= failCount {
                return Response(
                    status: .internalServerError,
                    body: .init(byteBuffer: ByteBuffer(string: "error"))
                )
            }
            return Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: "OK")))
        }

        // MARK: - /cache (GET - ETag + If-None-Match support)

        router.get("cache") { request, _ -> Response in
            let body = "cached-content"
            let etag = #""etag-12345""#
            let lastModified = "Wed, 01 Jan 2025 00:00:00 GMT"

            if let ifNoneMatch = request.headers[.ifNoneMatch], ifNoneMatch == etag {
                return Response(status: .notModified)
            }

            var headers = HTTPFields()
            headers[.contentType] = "text/plain"
            headers[.eTag] = etag
            headers[.lastModified] = lastModified

            return Response(
                status: .ok,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(string: body))
            )
        }

        // MARK: - /bytes/:count (GET - returns N bytes)

        router.get("bytes/:count") { _, context -> Response in
            let count = try context.parameters.require("count", as: Int.self)
            let bytes = (0..<count).map { UInt8($0 % 256) }
            var buffer = ByteBufferAllocator().buffer(capacity: count)
            buffer.writeBytes(bytes)
            return Response(
                status: .ok,
                headers: [.contentType: "application/octet-stream"],
                body: .init(byteBuffer: buffer)
            )
        }

        // Start server in background task
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        Task { try await app.runService() }

        // Wait for server to bind
        try await Task.sleep(for: .milliseconds(500))
    }
}
