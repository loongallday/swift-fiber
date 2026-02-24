import Testing
import Foundation
@testable import Fiber
@testable import FiberTesting
@testable import FiberValidation

// MARK: - Test Models

private struct CreateUser: Codable, Sendable {
    let name: String
    let email: String
}

private let createUserValidator = Validator<CreateUser> {
    Validate(\.name, label: "name") {
        ValidationRule.notEmpty(message: "Name is required")
        ValidationRule.minLength(2)
    }
    Validate(\.email, label: "email") {
        ValidationRule.notEmpty()
        ValidationRule.email()
    }
}

// MARK: - ValidationInterceptor Tests

@Suite("ValidationInterceptor — Fiber Integration")
struct ValidationInterceptorTests {

    let baseURL = URL(string: "https://api.example.com")!

    @Test("Interceptor passes valid request body")
    func passesValidBody() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok(body: #"{"id":1}"#))

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(validator: createUserValidator)
        ], transport: mock)

        let validUser = CreateUser(name: "Alice", email: "alice@example.com")
        let response = try await fiber.post("/users", body: validUser)
        #expect(response.statusCode == 200)
        #expect(mock.requests.count == 1)
    }

    @Test("Interceptor rejects invalid request body")
    func rejectsInvalidBody() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(validator: createUserValidator)
        ], transport: mock)

        let invalidUser = CreateUser(name: "", email: "bad")
        do {
            _ = try await fiber.post("/users", body: invalidUser)
            #expect(Bool(false), "Should have thrown")
        } catch let error as FiberError {
            if case .interceptor(let name, let underlying) = error {
                #expect(name == "validation")
                #expect(underlying is ValidationFailure)
                let failure = underlying as! ValidationFailure
                #expect(!failure.result.isValid)
                #expect(failure.result.errorItems.count >= 2)
            } else {
                #expect(Bool(false), "Expected interceptor error, got \(error)")
            }
        }
        // Request should not have been sent
        #expect(mock.requests.isEmpty)
    }

    @Test("Interceptor only validates configured methods")
    func onlyConfiguredMethods() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(
                validator: createUserValidator,
                for: [.put]  // Only PUT, not POST
            )
        ], transport: mock)

        // POST should pass through without validation
        let invalidUser = CreateUser(name: "", email: "bad")
        let response = try await fiber.post("/users", body: invalidUser)
        #expect(response.statusCode == 200)
        #expect(mock.requests.count == 1)
    }

    @Test("Interceptor skips GET requests by default")
    func skipsGET() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(validator: createUserValidator)
        ], transport: mock)

        let response = try await fiber.get("/users")
        #expect(response.statusCode == 200)
    }

    @Test("Interceptor skips requests without body")
    func skipsNoBody() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(validator: createUserValidator)
        ], transport: mock)

        // POST without body — should pass through
        let request = FiberRequest(url: baseURL.appendingPathComponent("/users"))
            .method(.post)
        let response = try await fiber.send(request)
        #expect(response.statusCode == 200)
    }

    @Test("Interceptor throws FiberError.interceptor")
    func throwsFiberError() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(validator: createUserValidator)
        ], transport: mock)

        let invalidUser = CreateUser(name: "", email: "")
        do {
            _ = try await fiber.post("/users", body: invalidUser)
            #expect(Bool(false), "Should have thrown")
        } catch let error as FiberError {
            // Verify it's an interceptor error
            #expect(error.underlyingError is ValidationFailure)
        }
    }

    @Test("ValidationFailure error has descriptive message")
    func failureMessage() {
        let result = ValidationResult.invalid([
            ValidationError(path: "name", message: "Must not be empty", code: "notEmpty"),
            ValidationError(path: "email", message: "Invalid email", code: "email"),
        ])
        let failure = ValidationFailure(result: result)
        let description = failure.errorDescription ?? ""
        #expect(description.contains("name"))
        #expect(description.contains("email"))
        #expect(description.contains("Validation failed"))
    }

    @Test("Interceptor with failOnWarnings rejects warnings")
    func failOnWarningsInterceptor() async throws {
        let warningValidator = Validator<CreateUser> {
            Validate(\.name, label: "name") {
                ValidationRule.minLength(10, severity: .warning)
            }
        }

        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(
                validator: warningValidator,
                failOnWarnings: true
            )
        ], transport: mock)

        let user = CreateUser(name: "Al", email: "a@b.com")
        do {
            _ = try await fiber.post("/users", body: user)
            #expect(Bool(false), "Should have thrown due to failOnWarnings")
        } catch is FiberError {
            // Expected
        }
        #expect(mock.requests.isEmpty)
    }

    @Test("Interceptor without failOnWarnings passes warnings")
    func noFailOnWarningsInterceptor() async throws {
        let warningValidator = Validator<CreateUser> {
            Validate(\.name, label: "name") {
                ValidationRule.minLength(10, severity: .warning)
            }
        }

        let mock = MockTransport()
        mock.stubAll(StubResponse.ok())

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            ValidationInterceptor<CreateUser>(
                validator: warningValidator,
                failOnWarnings: false
            )
        ], transport: mock)

        let user = CreateUser(name: "Al", email: "a@b.com")
        let response = try await fiber.post("/users", body: user)
        #expect(response.statusCode == 200)
        #expect(mock.requests.count == 1)
    }

    @Test("Interceptor works in full middleware stack")
    func fullMiddlewareStack() async throws {
        let mock = MockTransport()
        mock.stubAll(StubResponse.ok(body: #"{"id":1}"#))

        let auth = AnyInterceptor("auth") { request, next in
            let authed = request.header("Authorization", "Bearer test-token")
            return try await next(authed)
        }

        let fiber = Fiber(baseURL: baseURL, interceptors: [
            auth,
            ValidationInterceptor<CreateUser>(validator: createUserValidator),
        ], transport: mock)

        let validUser = CreateUser(name: "Alice", email: "alice@example.com")
        let response = try await fiber.post("/users", body: validUser)
        #expect(response.statusCode == 200)
        // Auth header should be present
        #expect(mock.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }
}
