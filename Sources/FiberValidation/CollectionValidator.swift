import Foundation

// MARK: - ValidateEach

/// Validates each element of a collection property, producing indexed paths.
///
/// ```swift
/// ValidateEach(\.tags, label: "tags") {
///     .notEmpty()
///     .maxLength(50)
/// }
/// // Errors: "tags[0]: Must not be empty", "tags[2]: Must have at most 50 items"
/// ```
public struct ValidateEach<Root: Sendable, C: Collection & Sendable> where C.Element: Sendable {
    public let fieldValidator: AnyFieldValidator<Root>

    public init(
        _ keyPath: KeyPath<Root, C> & Sendable,
        label: String,
        @RuleBuilder<C.Element> rules: () -> [ValidationRule<C.Element>]
    ) {
        let capturedRules = rules()
        let hasAsync = capturedRules.contains { $0.isAsync }
        self.fieldValidator = AnyFieldValidator<Root>(
            hasAsync: hasAsync,
            validate: { root in
                let collection = root[keyPath: keyPath]
                var result = ValidationResult.valid
                for (index, element) in collection.enumerated() {
                    let elementPath = "\(label)[\(index)]"
                    for rule in capturedRules {
                        result = result.merging(rule.validate(element, path: elementPath))
                    }
                }
                return result
            },
            validateAsync: { root in
                let collection = root[keyPath: keyPath]
                var result = ValidationResult.valid
                for (index, element) in collection.enumerated() {
                    let elementPath = "\(label)[\(index)]"
                    for rule in capturedRules {
                        let ruleResult = await rule.validateAsync(element, path: elementPath)
                        result = result.merging(ruleResult)
                    }
                }
                return result
            }
        )
    }
}
