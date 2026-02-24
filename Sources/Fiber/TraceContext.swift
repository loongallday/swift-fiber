import Foundation

// MARK: - TraceContext

/// TaskLocal-based distributed tracing. Auto-propagated through async call chains.
///
/// ```swift
/// // Trace ID is auto-generated per request by Fiber.
/// let id = TraceContext.traceID  // "A1B2C3D4-..."
///
/// // Add custom metadata:
/// try await TraceContext.$metadata.withValue(["userId": "123"]) {
///     let res = try await fiber.get("/profile")
/// }
/// ```
public enum TraceContext: Sendable {
    @TaskLocal public static var traceID: String = ""
    @TaskLocal public static var spanID: String = ""
    @TaskLocal public static var parentSpanID: String = ""
    @TaskLocal public static var metadata: [String: String] = [:]
}

// MARK: - Span

/// A timing span within a trace.
///
/// ```swift
/// let span = Span(name: "fetchUsers")
/// // ... do work ...
/// let finished = span.finish()
/// print("Duration: \(finished.durationMs ?? 0)ms")
/// ```
public struct Span: Sendable {
    public let id: String
    public let name: String
    public let traceID: String
    public let parentID: String?
    public let startTime: Date
    public var endTime: Date?
    public var attributes: [String: String]
    public var events: [SpanEvent]

    public init(
        name: String,
        traceID: String = TraceContext.traceID,
        parentID: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.traceID = traceID
        self.parentID = parentID
        self.startTime = Date()
        self.endTime = nil
        self.attributes = attributes
        self.events = []
    }

    /// Returns a finished copy of this span.
    public func finish(attributes: [String: String] = [:]) -> Span {
        var copy = self
        copy.endTime = Date()
        copy.attributes.merge(attributes) { _, new in new }
        return copy
    }

    /// Duration in milliseconds, or nil if not finished.
    public var durationMs: Double? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime) * 1000
    }
}

// MARK: - SpanEvent

public struct SpanEvent: Sendable {
    public let name: String
    public let timestamp: Date
    public let attributes: [String: String]

    public init(name: String, attributes: [String: String] = [:]) {
        self.name = name; self.timestamp = Date(); self.attributes = attributes
    }
}

// MARK: - TraceExporter

/// Protocol for exporting trace data to your backend.
///
/// ```swift
/// struct ConsoleExporter: TraceExporter {
///     func export(_ spans: [Span]) async {
///         for s in spans { print("[\(s.traceID)] \(s.name): \(s.durationMs ?? 0)ms") }
///     }
/// }
/// ```
public protocol TraceExporter: Sendable {
    func export(_ spans: [Span]) async
}

/// In-memory span collector for debugging and testing.
public actor InMemoryTraceExporter: TraceExporter {
    public private(set) var spans: [Span] = []
    public init() {}
    public func export(_ newSpans: [Span]) { spans.append(contentsOf: newSpans) }
    public func reset() { spans.removeAll() }
}
