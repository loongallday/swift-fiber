import Foundation
import OSLog

// MARK: - FiberLogLevel

public enum FiberLogLevel: Int, Sendable, Comparable, CaseIterable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5

    public static func < (lhs: FiberLogLevel, rhs: FiberLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .verbose: "VERBOSE"
        case .debug:   "DEBUG"
        case .info:    "INFO"
        case .warning: "WARNING"
        case .error:   "ERROR"
        case .none:    "NONE"
        }
    }
}

// MARK: - FiberLogMessage

public struct FiberLogMessage: Sendable {
    public let level: FiberLogLevel
    public let message: String
    public let system: String
    public let fileID: String
    public let function: String
    public let line: UInt
    public let timestamp: Date
    public var metadata: [String: String]

    public init(
        level: FiberLogLevel, message: String, system: String = "Fiber",
        fileID: String = #fileID, function: String = #function, line: UInt = #line,
        metadata: [String: String] = [:]
    ) {
        self.level = level; self.message = message; self.system = system
        self.fileID = fileID; self.function = function; self.line = line
        self.timestamp = Date(); self.metadata = metadata
    }
}

// MARK: - FiberLogger Protocol

/// Conform to route Fiber logs to your system.
///
/// ```swift
/// struct MyLogger: FiberLogger {
///     func log(_ message: FiberLogMessage) {
///         print("[\(message.level.label)] \(message.message)")
///     }
/// }
/// ```
public protocol FiberLogger: Sendable {
    func log(_ message: FiberLogMessage)
}

// MARK: - Convenience Methods

extension FiberLogger {
    public func verbose(_ msg: @autoclosure () -> String, system: String = "Fiber", metadata: [String: String] = [:], fileID: String = #fileID, function: String = #function, line: UInt = #line) {
        log(FiberLogMessage(level: .verbose, message: msg(), system: system, fileID: fileID, function: function, line: line, metadata: metadata))
    }
    public func debug(_ msg: @autoclosure () -> String, system: String = "Fiber", metadata: [String: String] = [:], fileID: String = #fileID, function: String = #function, line: UInt = #line) {
        log(FiberLogMessage(level: .debug, message: msg(), system: system, fileID: fileID, function: function, line: line, metadata: metadata))
    }
    public func info(_ msg: @autoclosure () -> String, system: String = "Fiber", metadata: [String: String] = [:], fileID: String = #fileID, function: String = #function, line: UInt = #line) {
        log(FiberLogMessage(level: .info, message: msg(), system: system, fileID: fileID, function: function, line: line, metadata: metadata))
    }
    public func warning(_ msg: @autoclosure () -> String, system: String = "Fiber", metadata: [String: String] = [:], fileID: String = #fileID, function: String = #function, line: UInt = #line) {
        log(FiberLogMessage(level: .warning, message: msg(), system: system, fileID: fileID, function: function, line: line, metadata: metadata))
    }
    public func error(_ msg: @autoclosure () -> String, system: String = "Fiber", metadata: [String: String] = [:], fileID: String = #fileID, function: String = #function, line: UInt = #line) {
        log(FiberLogMessage(level: .error, message: msg(), system: system, fileID: fileID, function: function, line: line, metadata: metadata))
    }
}

// MARK: - PrintLogger

/// Simple stdout logger for development.
/// ```swift
/// let fiber = Fiber("https://api.example.com") { $0.logger = PrintFiberLogger() }
/// ```
public struct PrintFiberLogger: FiberLogger {
    public let minLevel: FiberLogLevel
    public init(minLevel: FiberLogLevel = .debug) { self.minLevel = minLevel }
    public func log(_ message: FiberLogMessage) {
        guard message.level >= minLevel else { return }
        let meta = message.metadata.isEmpty ? "" : " \(message.metadata)"
        print("[\(message.level.label)] [\(message.system)] \(message.message)\(meta)")
    }
}

// MARK: - OSLog Logger

/// Routes to Apple's unified logging system.
/// ```swift
/// let fiber = Fiber("https://api.example.com") {
///     $0.logger = OSLogFiberLogger(subsystem: "com.app", category: "network")
/// }
/// ```
public struct OSLogFiberLogger: FiberLogger {
    private let logger: os.Logger
    public let minLevel: FiberLogLevel

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.fiber", category: String = "Fiber", minLevel: FiberLogLevel = .debug) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
        self.minLevel = minLevel
    }

    public func log(_ message: FiberLogMessage) {
        guard message.level >= minLevel else { return }
        let formatted = "[\(message.system)] \(message.message)"
        switch message.level {
        case .verbose: logger.trace("\(formatted, privacy: .public)")
        case .debug:   logger.debug("\(formatted, privacy: .public)")
        case .info:    logger.info("\(formatted, privacy: .public)")
        case .warning: logger.warning("\(formatted, privacy: .public)")
        case .error:   logger.error("\(formatted, privacy: .public)")
        case .none:    break
        }
    }
}
