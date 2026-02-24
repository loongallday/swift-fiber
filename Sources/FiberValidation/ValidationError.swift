import Foundation

// MARK: - ValidationError

/// Rich error context for a single validation failure.
///
/// ```swift
/// let error = ValidationError(
///     path: "user.address.zipCode",
///     message: "Must be 5 digits",
///     code: "pattern",
///     severity: .error
/// )
/// print(error)  // "[error] user.address.zipCode: Must be 5 digits"
/// ```
public struct ValidationError: Sendable, Hashable, CustomStringConvertible {
    /// Dot-separated field path, e.g. "user.address.zipCode".
    public let path: String

    /// Human-readable error message.
    public let message: String

    /// Machine-readable code for localization lookup, e.g. "notEmpty", "minLength".
    public let code: String

    /// Severity level of this validation issue.
    public let severity: ValidationSeverity

    public init(
        path: String,
        message: String,
        code: String = "",
        severity: ValidationSeverity = .error
    ) {
        self.path = path
        self.message = message
        self.code = code
        self.severity = severity
    }

    public var description: String {
        "[\(severity)] \(path): \(message)"
    }
}
