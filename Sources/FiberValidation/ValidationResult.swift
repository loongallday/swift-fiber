import Foundation

// MARK: - ValidationResult

/// The aggregated outcome of one or more validation checks.
///
/// ```swift
/// let result = validator.validate(user)
/// if result.isValid {
///     print("All good!")
/// } else {
///     for error in result.errorItems {
///         print("\(error.path): \(error.message)")
///     }
/// }
/// ```
public struct ValidationResult: Sendable {
    /// All validation issues found (both errors and warnings).
    public let errors: [ValidationError]

    public init(errors: [ValidationError] = []) {
        self.errors = errors
    }
}

// MARK: - Status Checks

extension ValidationResult {
    /// True if no issues with severity `.error` exist.
    public var isValid: Bool {
        !errors.contains { $0.severity == .error }
    }

    /// True if no issues at all (neither errors nor warnings).
    public var isClean: Bool {
        errors.isEmpty
    }

    /// True if valid but has warnings.
    public var hasWarnings: Bool {
        isValid && errors.contains { $0.severity == .warning }
    }

    /// Only the issues with severity `.error`.
    public var errorItems: [ValidationError] {
        errors.filter { $0.severity == .error }
    }

    /// Only the issues with severity `.warning`.
    public var warningItems: [ValidationError] {
        errors.filter { $0.severity == .warning }
    }

    /// Returns true if valid considering the `failOnWarnings` flag.
    public func isValid(failOnWarnings: Bool) -> Bool {
        failOnWarnings ? isClean : isValid
    }
}

// MARK: - Merging

extension ValidationResult {
    /// Merge two results, combining all errors.
    public func merging(_ other: ValidationResult) -> ValidationResult {
        ValidationResult(errors: errors + other.errors)
    }
}

// MARK: - Factories

extension ValidationResult {
    /// A successful result with no issues.
    public static let valid = ValidationResult()

    /// Create a failure result from a single error.
    public static func invalid(_ error: ValidationError) -> ValidationResult {
        ValidationResult(errors: [error])
    }

    /// Create a failure result from multiple errors.
    public static func invalid(_ errors: [ValidationError]) -> ValidationResult {
        ValidationResult(errors: errors)
    }
}
