import Foundation

// MARK: - ValidationSeverity

/// Severity level for validation issues.
///
/// ```swift
/// let error = ValidationError(path: "email", message: "Invalid", severity: .error)
/// let warning = ValidationError(path: "name", message: "Too short", severity: .warning)
/// ```
public enum ValidationSeverity: Int, Sendable, Comparable, Hashable, CustomStringConvertible {
    case warning = 0
    case error = 1

    public static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .warning: "warning"
        case .error: "error"
        }
    }
}
