import Foundation

// MARK: - Validator

/// Composed validator for a model type. Groups multiple field validators
/// using a declarative result builder DSL.
///
/// ```swift
/// let userValidator = Validator<User> {
///     Validate(\.name, label: "name") {
///         .notEmpty(message: "Name is required")
///         .minLength(2)
///     }
///     Validate(\.email, label: "email") {
///         .notEmpty()
///         .email()
///     }
///     Validate(\.age, label: "age") {
///         .range(18...120)
///     }
/// }
///
/// let result = userValidator.validate(user)
/// if !result.isValid {
///     print(result.errorItems)
/// }
/// ```
public struct Validator<T: Sendable>: Sendable {
    private let validators: [AnyFieldValidator<T>]

    /// Create a composed validator using the `@ValidatorBuilder` DSL.
    public init(@ValidatorBuilder<T> _ build: () -> [AnyFieldValidator<T>]) {
        self.validators = build()
    }

    /// Validate synchronously. Async rules use their sync fallback.
    public func validate(_ value: T) -> ValidationResult {
        var result = ValidationResult.valid
        for validator in validators {
            result = result.merging(validator.validate(value))
        }
        return result
    }

    /// Validate with full async support (runs async rules properly).
    public func validateAsync(_ value: T) async -> ValidationResult {
        var result = ValidationResult.valid
        for validator in validators {
            let r = await validator.validateAsync(value)
            result = result.merging(r)
        }
        return result
    }

    /// Validate with a parent path prefix (for nested validators).
    func validate(_ value: T, parentPath: String) -> ValidationResult {
        let result = validate(value)
        let prefixed = result.errors.map { error in
            ValidationError(
                path: parentPath.isEmpty ? error.path : "\(parentPath).\(error.path)",
                message: error.message,
                code: error.code,
                severity: error.severity
            )
        }
        return ValidationResult(errors: prefixed)
    }
}
