import Foundation

// MARK: - ValidationRule

/// A single validation check on a value of type `Value`.
///
/// ```swift
/// let rule = ValidationRule<String>.notEmpty(message: "Name is required")
/// let result = rule.validate("", path: "name")
/// #expect(!result.isValid)
/// ```
public struct ValidationRule<Value: Sendable>: Sendable {
    private let _validate: @Sendable (Value, String) -> ValidationResult
    private let _validateAsync: (@Sendable (Value, String) async -> ValidationResult)?

    /// Create a synchronous validation rule.
    public init(validate: @escaping @Sendable (Value, String) -> ValidationResult) {
        self._validate = validate
        self._validateAsync = nil
    }

    /// Create an async validation rule (e.g. check uniqueness against an API).
    public init(validateAsync: @escaping @Sendable (Value, String) async -> ValidationResult) {
        self._validate = { _, _ in .valid }
        self._validateAsync = validateAsync
    }

    /// Validate a value synchronously, producing errors scoped to the given path.
    public func validate(_ value: Value, path: String) -> ValidationResult {
        _validate(value, path)
    }

    /// Validate a value asynchronously. Falls back to sync if no async logic.
    public func validateAsync(_ value: Value, path: String) async -> ValidationResult {
        if let asyncValidate = _validateAsync {
            return await asyncValidate(value, path)
        }
        return _validate(value, path)
    }

    /// Whether this rule has async validation logic.
    public var isAsync: Bool { _validateAsync != nil }
}

// MARK: - Optional Rules

extension ValidationRule {
    /// Value must not be nil.
    public static func notNil<Wrapped: Sendable>(
        message: String? = nil,
        code: String = "notNil",
        severity: ValidationSeverity = .error
    ) -> ValidationRule where Value == Optional<Wrapped> {
        ValidationRule { value, path in
            guard value != nil else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must not be nil",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }
}

// MARK: - Collection Rules

extension ValidationRule where Value: Collection & Sendable {
    /// Collection must not be empty.
    public static func notEmpty(
        message: String? = nil,
        code: String = "notEmpty",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard !value.isEmpty else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must not be empty",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }

    /// Collection count must be >= min.
    public static func minLength(
        _ min: Int,
        message: String? = nil,
        code: String = "minLength",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard value.count >= min else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must have at least \(min) items",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }

    /// Collection count must be <= max.
    public static func maxLength(
        _ max: Int,
        message: String? = nil,
        code: String = "maxLength",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard value.count <= max else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must have at most \(max) items",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }

    /// Collection count must be within range.
    public static func lengthRange(
        _ range: ClosedRange<Int>,
        message: String? = nil,
        code: String = "lengthRange",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard range.contains(value.count) else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Length must be between \(range.lowerBound) and \(range.upperBound)",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }
}

// MARK: - String Rules

extension ValidationRule where Value == String {
    /// String must match the given regex pattern.
    public static func pattern(
        _ regexPattern: String,
        message: String? = nil,
        code: String = "pattern",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard let regex = try? NSRegularExpression(pattern: regexPattern),
                  regex.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..., in: value)
                  ) != nil
            else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must match pattern \(regexPattern)",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }

    /// String must be a valid email format.
    public static func email(
        message: String? = nil,
        code: String = "email",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        .pattern(
            #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#,
            message: message ?? "Must be a valid email address",
            code: code,
            severity: severity
        )
    }

    /// String must be a valid URL.
    public static func url(
        message: String? = nil,
        code: String = "url",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard URL(string: value) != nil, value.contains("://") else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must be a valid URL",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }
}

// MARK: - Comparable Rules

extension ValidationRule where Value: Comparable {
    /// Value must be within the given closed range.
    public static func range(
        _ range: ClosedRange<Value>,
        message: String? = nil,
        code: String = "range",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard range.contains(value) else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must be between \(range.lowerBound) and \(range.upperBound)",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }
}

// MARK: - Equatable Rules

extension ValidationRule where Value: Equatable {
    /// Value must equal the expected value.
    public static func equals(
        _ expected: Value,
        message: String? = nil,
        code: String = "equals",
        severity: ValidationSeverity = .error
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard value == expected else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Must equal \(expected)",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }
}

// MARK: - Custom Rules

extension ValidationRule {
    /// Custom synchronous validation via closure.
    public static func custom(
        message: String? = nil,
        code: String = "custom",
        severity: ValidationSeverity = .error,
        _ predicate: @escaping @Sendable (Value) -> Bool
    ) -> ValidationRule {
        ValidationRule { value, path in
            guard predicate(value) else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Validation failed",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        }
    }

    /// Custom async validation (e.g., check uniqueness against an API).
    public static func asyncCustom(
        message: String? = nil,
        code: String = "asyncCustom",
        severity: ValidationSeverity = .error,
        _ predicate: @escaping @Sendable (Value) async -> Bool
    ) -> ValidationRule {
        ValidationRule(validateAsync: { value, path in
            guard await predicate(value) else {
                return .invalid(ValidationError(
                    path: path,
                    message: message ?? "Validation failed",
                    code: code,
                    severity: severity
                ))
            }
            return .valid
        })
    }
}
