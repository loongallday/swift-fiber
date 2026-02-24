import Testing
import Foundation
@testable import FiberValidation

// MARK: - Test Domain Models

private struct Address: Sendable {
    let street: String
    let city: String
    let zipCode: String
}

private struct User: Sendable {
    let name: String
    let email: String
    let age: Int
    let address: Address
    let tags: [String]
    let isAdmin: Bool
    let adminCode: String?
}

// MARK: - Validator Tests

@Suite("Validator — Composed Validation")
struct ValidatorTests {

    // MARK: - Basic composed validation

    @Test("Validator validates all fields")
    func validatesAllFields() {
        let validator = Validator<User> {
            Validate(\.name, label: "name") {
                ValidationRule.notEmpty()
            }
            Validate(\.email, label: "email") {
                ValidationRule.email()
            }
        }

        let invalidUser = User(
            name: "", email: "bad",
            age: 25, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(invalidUser)
        #expect(!result.isValid)
        #expect(result.errorItems.count == 2)
    }

    @Test("Validator reports multiple errors per field")
    func reportsMultipleErrors() {
        let validator = Validator<User> {
            Validate(\.name, label: "name") {
                ValidationRule.notEmpty()
                ValidationRule.minLength(3)
            }
        }

        let user = User(
            name: "", email: "a@b.com",
            age: 25, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(user)
        // Empty string fails both notEmpty and minLength
        #expect(result.errorItems.count == 2)
    }

    @Test("Validator passes valid model")
    func passesValidModel() {
        let validator = Validator<User> {
            Validate(\.name, label: "name") {
                ValidationRule.notEmpty()
                ValidationRule.minLength(2)
            }
            Validate(\.email, label: "email") {
                ValidationRule.email()
            }
            Validate(\.age, label: "age") {
                ValidationRule.range(18...120)
            }
        }

        let user = User(
            name: "Alice", email: "alice@example.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: ["swift"], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(user)
        #expect(result.isValid)
        #expect(result.isClean)
    }

    // MARK: - Nested validation

    @Test("Nested validator prefixes paths correctly")
    func nestedValidation() {
        let addressValidator = Validator<Address> {
            Validate(\.street, label: "street") {
                ValidationRule.notEmpty()
            }
            Validate(\.zipCode, label: "zipCode") {
                ValidationRule.minLength(5)
            }
        }

        let validator = Validator<User> {
            Validate(\.address, label: "address", validator: addressValidator)
        }

        let user = User(
            name: "Alice", email: "a@b.com",
            age: 30, address: Address(street: "", city: "NYC", zipCode: "123"),
            tags: [], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(user)
        #expect(!result.isValid)
        #expect(result.errors.count == 2)
        #expect(result.errors.contains { $0.path == "address.street" })
        #expect(result.errors.contains { $0.path == "address.zipCode" })
    }

    // MARK: - Collection validation

    @Test("ValidateEach validates each element")
    func collectionValidation() {
        let validator = Validator<User> {
            ValidateEach(\.tags, label: "tags") {
                ValidationRule.notEmpty()
            }
        }

        let user = User(
            name: "Alice", email: "a@b.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: ["swift", "", "fiber"], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(user)
        #expect(!result.isValid)
        #expect(result.errorItems.count == 1)
    }

    @Test("ValidateEach reports correct indexed paths")
    func collectionPaths() {
        let validator = Validator<User> {
            ValidateEach(\.tags, label: "tags") {
                ValidationRule.minLength(2)
            }
        }

        let user = User(
            name: "Alice", email: "a@b.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: ["ok", "x", "good", "y"], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(user)
        #expect(result.errorItems.count == 2)
        #expect(result.errors.contains { $0.path == "tags[1]" })
        #expect(result.errors.contains { $0.path == "tags[3]" })
    }

    @Test("ValidateEach passes when all elements valid")
    func collectionAllValid() {
        let validator = Validator<User> {
            ValidateEach(\.tags, label: "tags") {
                ValidationRule.notEmpty()
            }
        }

        let user = User(
            name: "Alice", email: "a@b.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: ["a", "b", "c"], isAdmin: false, adminCode: nil
        )
        #expect(validator.validate(user).isValid)
    }

    // MARK: - Conditional validation

    @Test("ValidateIf applies when condition is true")
    func conditionalApplies() {
        let validator = Validator<User> {
            ValidateIf({ $0.isAdmin }) {
                Validate(\.adminCode, label: "adminCode") {
                    ValidationRule.notNil(message: "Admin code required")
                }
            }
        }

        let adminUser = User(
            name: "Admin", email: "a@b.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: true, adminCode: nil
        )
        let result = validator.validate(adminUser)
        #expect(!result.isValid)
        #expect(result.errors[0].path == "adminCode")
    }

    @Test("ValidateIf skips when condition is false")
    func conditionalSkips() {
        let validator = Validator<User> {
            ValidateIf({ $0.isAdmin }) {
                Validate(\.adminCode, label: "adminCode") {
                    ValidationRule.notNil(message: "Admin code required")
                }
            }
        }

        let regularUser = User(
            name: "User", email: "a@b.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(regularUser)
        #expect(result.isValid)
    }

    @Test("ValidateIf passes when condition true and rules pass")
    func conditionalPassesWhenValid() {
        let validator = Validator<User> {
            ValidateIf({ $0.isAdmin }) {
                Validate(\.adminCode, label: "adminCode") {
                    ValidationRule.notNil()
                }
            }
        }

        let adminUser = User(
            name: "Admin", email: "a@b.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: true, adminCode: "ADMIN123"
        )
        #expect(validator.validate(adminUser).isValid)
    }

    // MARK: - Async validation

    @Test("Async validator runs async rules")
    func asyncValidation() async {
        let validator = Validator<User> {
            Validate(\.email, label: "email") {
                ValidationRule.asyncCustom(message: "Email already taken") { email in
                    // Simulate async API check
                    email != "taken@example.com"
                }
            }
        }

        let validUser = User(
            name: "Alice", email: "alice@example.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: false, adminCode: nil
        )
        let validResult = await validator.validateAsync(validUser)
        #expect(validResult.isValid)

        let takenUser = User(
            name: "Alice", email: "taken@example.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: false, adminCode: nil
        )
        let takenResult = await validator.validateAsync(takenUser)
        #expect(!takenResult.isValid)
    }

    // MARK: - failOnWarnings

    @Test("failOnWarnings causes warnings to fail validation")
    func failOnWarnings() {
        let validator = Validator<User> {
            Validate(\.name, label: "name") {
                ValidationRule.minLength(10, severity: .warning)
            }
        }

        let user = User(
            name: "Al", email: "a@b.com",
            age: 30, address: Address(street: "1 Main", city: "NYC", zipCode: "10001"),
            tags: [], isAdmin: false, adminCode: nil
        )
        let result = validator.validate(user)
        #expect(result.isValid)
        #expect(result.hasWarnings)
        #expect(!result.isValid(failOnWarnings: true))
    }

    // MARK: - Full DSL

    @Test("Full DSL example compiles and runs correctly")
    func fullDSLExample() {
        let addressValidator = Validator<Address> {
            Validate(\.street, label: "street") { ValidationRule.notEmpty() }
            Validate(\.city, label: "city") { ValidationRule.notEmpty() }
            Validate(\.zipCode, label: "zipCode") { ValidationRule.pattern(#"^\d{5}$"#) }
        }

        let userValidator = Validator<User> {
            Validate(\.name, label: "name") {
                ValidationRule.notEmpty(message: "Name is required")
                ValidationRule.minLength(2)
                ValidationRule.maxLength(100)
            }
            Validate(\.email, label: "email") {
                ValidationRule.notEmpty()
                ValidationRule.email()
            }
            Validate(\.age, label: "age") {
                ValidationRule.range(18...120)
            }
            Validate(\.address, label: "address", validator: addressValidator)
            ValidateEach(\.tags, label: "tags") {
                ValidationRule.notEmpty()
                ValidationRule.maxLength(50)
            }
            ValidateIf({ $0.isAdmin }) {
                Validate(\.adminCode, label: "adminCode") {
                    ValidationRule.notNil(message: "Admin code required")
                }
            }
        }

        // Valid user
        let validUser = User(
            name: "Alice Johnson", email: "alice@example.com",
            age: 30, address: Address(street: "123 Main St", city: "NYC", zipCode: "10001"),
            tags: ["swift", "fiber"], isAdmin: false, adminCode: nil
        )
        #expect(userValidator.validate(validUser).isValid)

        // Invalid user — multiple failures
        let invalidUser = User(
            name: "", email: "bad",
            age: 10, address: Address(street: "", city: "", zipCode: "abc"),
            tags: ["ok", ""], isAdmin: true, adminCode: nil
        )
        let result = userValidator.validate(invalidUser)
        #expect(!result.isValid)
        // name: notEmpty + minLength, email: notEmpty passes but email fails,
        // age: range, address: street + city + zipCode, tags[1]: notEmpty, adminCode: notNil
        #expect(result.errorItems.count >= 7)
    }
}
