import Foundation
import Fiber

// MARK: - MockTransport

/// A mock transport for testing. Records requests and returns stubbed responses.
///
/// ```swift
/// let mock = MockTransport()
/// mock.stub { req in
///     StubResponse(statusCode: 200, body: #"{"id": 1, "name": "Alice"}"#)
/// }
///
/// let fiber = Fiber(baseURL: url, transport: mock)
/// let response = try await fiber.get("/users/1")
/// #expect(response.statusCode == 200)
/// #expect(mock.requests.count == 1)
/// #expect(mock.requests[0].url.path.contains("users"))
/// ```
public final class MockTransport: FiberTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var _stubs: [(URLRequest) -> (Data, URLResponse)?] = []
    private var _defaultStub: ((URLRequest) -> (Data, URLResponse))?

    public init() {}

    public var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    /// Add a conditional stub. Checked in order; first match wins.
    public func stub(_ handler: @escaping (URLRequest) -> StubResponse?) {
        lock.withLock {
            _stubs.append { req in
                guard let stub = handler(req) else { return nil }
                return stub.toFoundation(for: req)
            }
        }
    }

    /// Set the default response for any unmatched request.
    public func stubDefault(_ handler: @escaping (URLRequest) -> StubResponse) {
        lock.withLock {
            _defaultStub = { req in handler(req).toFoundation(for: req) }
        }
    }

    /// Stub all requests with the same response.
    public func stubAll(_ response: StubResponse) {
        stubDefault { _ in response }
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // Capture stubs + record request synchronously
        let (stubs, defaultStub) = lock.withLock {
            _requests.append(request)
            return (_stubs, _defaultStub)
        }

        for stub in stubs {
            if let result = stub(request) { return result }
        }
        if let result = defaultStub?(request) { return result }

        // No stub matched — return 500
        let url = request.url ?? URL(string: "https://mock")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"error": "No stub matched"}"#.utf8), response)
    }

    /// Reset all stubs and recorded requests.
    public func reset() {
        lock.withLock {
            _requests.removeAll(); _stubs.removeAll(); _defaultStub = nil
        }
    }
}

// MARK: - Request Assertions

extension MockTransport {
    /// Assert that exactly N requests were made.
    public func expectRequestCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        assert(requests.count == count, "Expected \(count) requests, got \(requests.count)", file: file, line: line)
    }

    /// Get the last request made, or nil.
    public var lastRequest: URLRequest? { requests.last }
}
