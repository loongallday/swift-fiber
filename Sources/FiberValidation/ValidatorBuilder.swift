import Foundation

// MARK: - RuleBuilder

/// Result builder for composing validation rules within a property validator.
///
/// ```swift
/// Validate(\.name, label: "name") {
///     .notEmpty()
///     .minLength(2)
///     .maxLength(100)
/// }
/// ```
@resultBuilder
public struct RuleBuilder<Value: Sendable> {
    public static func buildExpression(_ expression: ValidationRule<Value>) -> ValidationRule<Value> {
        expression
    }

    public static func buildBlock(_ components: ValidationRule<Value>...) -> [ValidationRule<Value>] {
        components
    }

    public static func buildOptional(_ component: [ValidationRule<Value>]?) -> [ValidationRule<Value>] {
        component ?? []
    }

    public static func buildEither(first component: [ValidationRule<Value>]) -> [ValidationRule<Value>] {
        component
    }

    public static func buildEither(second component: [ValidationRule<Value>]) -> [ValidationRule<Value>] {
        component
    }

    public static func buildArray(_ components: [[ValidationRule<Value>]]) -> [ValidationRule<Value>] {
        components.flatMap { $0 }
    }
}

// MARK: - ValidatorBuilder

/// Result builder for composing field validators into a `Validator<T>`.
///
/// ```swift
/// let validator = Validator<User> {
///     Validate(\.name, label: "name") { .notEmpty() }
///     Validate(\.email, label: "email") { .email() }
/// }
/// ```
@resultBuilder
public struct ValidatorBuilder<Root: Sendable> {
    public static func buildBlock(_ components: AnyFieldValidator<Root>...) -> [AnyFieldValidator<Root>] {
        components
    }

    public static func buildOptional(_ component: [AnyFieldValidator<Root>]?) -> [AnyFieldValidator<Root>] {
        component ?? []
    }

    public static func buildEither(first component: [AnyFieldValidator<Root>]) -> [AnyFieldValidator<Root>] {
        component
    }

    public static func buildEither(second component: [AnyFieldValidator<Root>]) -> [AnyFieldValidator<Root>] {
        component
    }

    public static func buildArray(_ components: [[AnyFieldValidator<Root>]]) -> [AnyFieldValidator<Root>] {
        components.flatMap { $0 }
    }

    // Allow Validate<Root, Value> to be used directly in the builder
    public static func buildExpression<Value>(_ expression: Validate<Root, Value>) -> AnyFieldValidator<Root> {
        expression.fieldValidator
    }

    // Allow ValidateEach<Root, C> to be used directly in the builder
    public static func buildExpression<C>(_ expression: ValidateEach<Root, C>) -> AnyFieldValidator<Root> {
        expression.fieldValidator
    }

    // Allow ValidateIf<Root> to be used directly in the builder
    public static func buildExpression(_ expression: ValidateIf<Root>) -> AnyFieldValidator<Root> {
        expression.fieldValidator
    }

    // Allow raw AnyFieldValidator directly
    public static func buildExpression(_ expression: AnyFieldValidator<Root>) -> AnyFieldValidator<Root> {
        expression
    }
}
