import Foundation
import Fiber

// MARK: - ValidationInterceptor

/// Validates request bodies before sending through the Fiber interceptor chain.
///
/// Decodes the request body as `T`, runs the composed `Validator<T>`, and throws
/// `FiberError.interceptor` if validation fails.
///
/// ```swift
/// let fiber = Fiber("https://api.com") { config in
///     config.interceptors = [
///         ValidationInterceptor<CreateUser>(
///             validator: createUserValidator,
///             for: [.post, .put]
///         )
///     ]
/// }
/// ```
public struct ValidationInterceptor<T: Decodable & Sendable>: Interceptor {
    public let name = "validation"
    private let validator: Validator<T>
    private let methods: Set<HTTPMethod>
    private let decoder: JSONDecoder
    private let failOnWarnings: Bool

    /// Create a validation interceptor.
    ///
    /// - Parameters:
    ///   - validator: The composed validator to run against decoded request bodies.
    ///   - methods: HTTP methods to validate (default: POST, PUT, PATCH).
    ///   - decoder: JSON decoder for deserializing request bodies.
    ///   - failOnWarnings: Whether warnings should also cause validation failure.
    public init(
        validator: Validator<T>,
        for methods: Set<HTTPMethod> = [.post, .put, .patch],
        decoder: JSONDecoder = JSONDecoder(),
        failOnWarnings: Bool = false
    ) {
        self.validator = validator
        self.methods = methods
        self.decoder = decoder
        self.failOnWarnings = failOnWarnings
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        // Only validate configured methods
        guard methods.contains(request.httpMethod) else {
            return try await next(request)
        }

        // Only validate if there is a body to decode
        guard let body = request.body else {
            return try await next(request)
        }

        // Decode the body into the model type
        let model: T
        do {
            model = try decoder.decode(T.self, from: body)
        } catch {
            // Decoding failure — let the request proceed (validation is model-level)
            return try await next(request)
        }

        // Run validation (async to support async rules)
        let result = await validator.validateAsync(model)

        // Check if valid
        guard result.isValid(failOnWarnings: failOnWarnings) else {
            throw FiberError.interceptor(
                name: name,
                underlying: ValidationFailure(result: result)
            )
        }

        return try await next(request)
    }
}

// MARK: - ValidationFailure

/// Error type wrapping a `ValidationResult` for use with `FiberError.interceptor`.
public struct ValidationFailure: Error, Sendable, LocalizedError {
    /// The validation result containing all errors and warnings.
    public let result: ValidationResult

    public init(result: ValidationResult) {
        self.result = result
    }

    public var errorDescription: String? {
        let messages = result.errors.map(\.description)
        return "Validation failed: \(messages.joined(separator: "; "))"
    }
}
