import Foundation

// MARK: - ValidateIf

/// Applies nested validators only when a condition is met.
///
/// ```swift
/// ValidateIf({ $0.isAdmin }) {
///     Validate(\.adminCode, label: "adminCode") {
///         .notNil(message: "Admin code required for admin users")
///     }
/// }
/// ```
public struct ValidateIf<Root: Sendable> {
    public let fieldValidator: AnyFieldValidator<Root>

    public init(
        _ condition: @escaping @Sendable (Root) -> Bool,
        @ValidatorBuilder<Root> validators: () -> [AnyFieldValidator<Root>]
    ) {
        self.fieldValidator = AnyFieldValidator<Root>(
            condition: condition,
            validators: validators()
        )
    }
}
