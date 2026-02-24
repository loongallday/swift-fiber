import Foundation

// MARK: - AnyFieldValidator (type-erased wrapper)

/// Type-erased validator for a field of `Root`. Avoids parameterized existentials
/// which require macOS 13+.
public struct AnyFieldValidator<Root: Sendable>: Sendable {
    private let _validate: @Sendable (Root) -> ValidationResult
    private let _validateAsync: @Sendable (Root) async -> ValidationResult
    private let _hasAsyncRules: Bool

    public init<V: Sendable>(
        keyPath: KeyPath<Root, V> & Sendable,
        label: String,
        rules: [ValidationRule<V>]
    ) {
        self._hasAsyncRules = rules.contains { $0.isAsync }
        self._validate = { root in
            let value = root[keyPath: keyPath]
            var result = ValidationResult.valid
            for rule in rules {
                result = result.merging(rule.validate(value, path: label))
            }
            return result
        }
        self._validateAsync = { root in
            let value = root[keyPath: keyPath]
            var result = ValidationResult.valid
            for rule in rules {
                let ruleResult = await rule.validateAsync(value, path: label)
                result = result.merging(ruleResult)
            }
            return result
        }
    }

    /// Create from raw closures (for `ValidateEach` and other custom validators).
    public init(
        hasAsync: Bool,
        validate: @escaping @Sendable (Root) -> ValidationResult,
        validateAsync: @escaping @Sendable (Root) async -> ValidationResult
    ) {
        self._hasAsyncRules = hasAsync
        self._validate = validate
        self._validateAsync = validateAsync
    }

    /// Create from a condition and nested validators (for `ValidateIf`).
    init(
        condition: @escaping @Sendable (Root) -> Bool,
        validators: [AnyFieldValidator<Root>]
    ) {
        self._hasAsyncRules = validators.contains { $0.hasAsyncRules }
        self._validate = { root in
            guard condition(root) else { return .valid }
            var result = ValidationResult.valid
            for v in validators {
                result = result.merging(v.validate(root))
            }
            return result
        }
        self._validateAsync = { root in
            guard condition(root) else { return .valid }
            var result = ValidationResult.valid
            for v in validators {
                let r = await v.validateAsync(root)
                result = result.merging(r)
            }
            return result
        }
    }

    /// Whether any contained rules require async execution.
    public var hasAsyncRules: Bool { _hasAsyncRules }

    /// Validate the root object synchronously.
    public func validate(_ root: Root) -> ValidationResult {
        _validate(root)
    }

    /// Validate the root object asynchronously.
    public func validateAsync(_ root: Root) async -> ValidationResult {
        await _validateAsync(root)
    }
}

// MARK: - Validate

/// Validates a specific property of `Root` via KeyPath, applying one or more rules.
///
/// ```swift
/// Validate(\.name, label: "name") {
///     .notEmpty(message: "Name is required")
///     .minLength(2)
/// }
/// ```
public struct Validate<Root: Sendable, Value: Sendable> {
    public let fieldValidator: AnyFieldValidator<Root>

    /// Create a property validator with inline rules via `@RuleBuilder`.
    public init(
        _ keyPath: KeyPath<Root, Value> & Sendable,
        label: String,
        @RuleBuilder<Value> rules: () -> [ValidationRule<Value>]
    ) {
        self.fieldValidator = AnyFieldValidator(
            keyPath: keyPath, label: label, rules: rules()
        )
    }

    /// Create a property validator using a nested `Validator<Value>`.
    public init(
        _ keyPath: KeyPath<Root, Value> & Sendable,
        label: String,
        validator: Validator<Value>
    ) {
        let nestedRule = ValidationRule<Value> { value, path in
            validator.validate(value, parentPath: path)
        }
        self.fieldValidator = AnyFieldValidator(
            keyPath: keyPath, label: label, rules: [nestedRule]
        )
    }
}
