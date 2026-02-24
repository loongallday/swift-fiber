import Foundation
import Fiber

// MARK: - TestTraceCollector

/// Collects trace spans and log messages for test assertions.
///
/// ```swift
/// let tracer = TestTraceCollector()
///
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [tracer.interceptor()]
/// }
///
/// try await fiber.get("/users")
///
/// #expect(tracer.spans.count == 1)
/// #expect(tracer.spans[0].name == "HTTP")
/// #expect(tracer.spans[0].durationMs! > 0)
/// ```
public final class TestTraceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _spans: [Span] = []
    private var _logs: [FiberLogMessage] = []

    public init() {}

    public var spans: [Span] {
        lock.lock(); defer { lock.unlock() }; return _spans
    }

    public var logs: [FiberLogMessage] {
        lock.lock(); defer { lock.unlock() }; return _logs
    }

    public func addSpan(_ span: Span) {
        lock.lock(); _spans.append(span); lock.unlock()
    }

    public func addLog(_ message: FiberLogMessage) {
        lock.lock(); _logs.append(message); lock.unlock()
    }

    public func reset() {
        lock.lock(); _spans.removeAll(); _logs.removeAll(); lock.unlock()
    }

    /// Creates an interceptor that records a span for each request.
    public func interceptor() -> AnyInterceptor {
        AnyInterceptor("traceCollector") { [weak self] request, next in
            var span = Span(name: "HTTP", attributes: [
                "method": request.httpMethod.rawValue,
                "url": request.url.absoluteString
            ])

            do {
                let response = try await next(request)
                span = span.finish(attributes: [
                    "statusCode": "\(response.statusCode)",
                    "responseSize": "\(response.data.count)"
                ])
                self?.addSpan(span)
                return response
            } catch {
                span = span.finish(attributes: ["error": "\(error)"])
                self?.addSpan(span)
                throw error
            }
        }
    }

    /// Creates a logger that records all messages.
    public func logger() -> TestLogger {
        TestLogger(collector: self)
    }
}

// MARK: - TestLogger

public struct TestLogger: FiberLogger {
    private let collector: TestTraceCollector

    init(collector: TestTraceCollector) { self.collector = collector }

    public func log(_ message: FiberLogMessage) {
        collector.addLog(message)
    }
}
