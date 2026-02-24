import Testing
import Foundation
@testable import FiberValidation

// MARK: - ValidationRule Tests

@Suite("ValidationRule — Built-in Rules")
struct ValidationRuleTests {

    // MARK: - notEmpty

    @Test("notEmpty fails for empty string")
    func notEmptyFailsEmptyString() {
        let rule = ValidationRule<String>.notEmpty()
        let result = rule.validate("", path: "name")
        #expect(!result.isValid)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].path == "name")
        #expect(result.errors[0].code == "notEmpty")
    }

    @Test("notEmpty succeeds for non-empty string")
    func notEmptySucceedsNonEmpty() {
        let rule = ValidationRule<String>.notEmpty()
        let result = rule.validate("hello", path: "name")
        #expect(result.isValid)
        #expect(result.isClean)
    }

    @Test("notEmpty fails for empty array")
    func notEmptyFailsEmptyArray() {
        let rule = ValidationRule<[Int]>.notEmpty()
        let result = rule.validate([], path: "items")
        #expect(!result.isValid)
        #expect(result.errors[0].path == "items")
    }

    @Test("notEmpty succeeds for non-empty array")
    func notEmptySucceedsNonEmptyArray() {
        let rule = ValidationRule<[Int]>.notEmpty()
        let result = rule.validate([1, 2], path: "items")
        #expect(result.isValid)
    }

    // MARK: - minLength / maxLength

    @Test("minLength fails when too short")
    func minLengthFails() {
        let rule = ValidationRule<String>.minLength(3)
        let result = rule.validate("ab", path: "field")
        #expect(!result.isValid)
        #expect(result.errors[0].code == "minLength")
    }

    @Test("minLength succeeds at boundary")
    func minLengthSucceedsAtBoundary() {
        let rule = ValidationRule<String>.minLength(3)
        let result = rule.validate("abc", path: "field")
        #expect(result.isValid)
    }

    @Test("maxLength fails when too long")
    func maxLengthFails() {
        let rule = ValidationRule<String>.maxLength(3)
        let result = rule.validate("abcd", path: "field")
        #expect(!result.isValid)
        #expect(result.errors[0].code == "maxLength")
    }

    @Test("maxLength succeeds at boundary")
    func maxLengthSucceedsAtBoundary() {
        let rule = ValidationRule<String>.maxLength(3)
        let result = rule.validate("abc", path: "field")
        #expect(result.isValid)
    }

    @Test("lengthRange validates correctly")
    func lengthRange() {
        let rule = ValidationRule<String>.lengthRange(2...5)
        #expect(rule.validate("a", path: "f").isValid == false)
        #expect(rule.validate("ab", path: "f").isValid == true)
        #expect(rule.validate("abcde", path: "f").isValid == true)
        #expect(rule.validate("abcdef", path: "f").isValid == false)
    }

    // MARK: - pattern / email / url

    @Test("pattern matches valid input")
    func patternMatches() {
        let rule = ValidationRule<String>.pattern(#"^\d{3}-\d{4}$"#)
        let result = rule.validate("123-4567", path: "phone")
        #expect(result.isValid)
    }

    @Test("pattern rejects invalid input")
    func patternRejects() {
        let rule = ValidationRule<String>.pattern(#"^\d{3}-\d{4}$"#)
        let result = rule.validate("abc", path: "phone")
        #expect(!result.isValid)
        #expect(result.errors[0].code == "pattern")
    }

    @Test("email validates correct format")
    func emailValid() {
        let rule = ValidationRule<String>.email()
        #expect(rule.validate("user@example.com", path: "email").isValid)
        #expect(rule.validate("test.user+tag@domain.co.uk", path: "email").isValid)
    }

    @Test("email rejects invalid format")
    func emailInvalid() {
        let rule = ValidationRule<String>.email()
        #expect(!rule.validate("notanemail", path: "email").isValid)
        #expect(!rule.validate("@domain.com", path: "email").isValid)
        #expect(!rule.validate("user@", path: "email").isValid)
    }

    @Test("url validates correct format")
    func urlValid() {
        let rule = ValidationRule<String>.url()
        #expect(rule.validate("https://example.com", path: "url").isValid)
        #expect(rule.validate("http://localhost:8080/path", path: "url").isValid)
    }

    @Test("url rejects invalid format")
    func urlInvalid() {
        let rule = ValidationRule<String>.url()
        #expect(!rule.validate("not a url", path: "url").isValid)
        #expect(!rule.validate("example.com", path: "url").isValid)
    }

    // MARK: - range

    @Test("range succeeds within bounds")
    func rangeSucceeds() {
        let rule = ValidationRule<Int>.range(1...100)
        #expect(rule.validate(1, path: "age").isValid)
        #expect(rule.validate(50, path: "age").isValid)
        #expect(rule.validate(100, path: "age").isValid)
    }

    @Test("range fails outside bounds")
    func rangeFails() {
        let rule = ValidationRule<Int>.range(1...100)
        #expect(!rule.validate(0, path: "age").isValid)
        #expect(!rule.validate(101, path: "age").isValid)
    }

    // MARK: - notNil

    @Test("notNil fails for nil")
    func notNilFails() {
        let rule = ValidationRule<String?>.notNil()
        let result = rule.validate(nil, path: "token")
        #expect(!result.isValid)
        #expect(result.errors[0].code == "notNil")
    }

    @Test("notNil succeeds for non-nil")
    func notNilSucceeds() {
        let rule = ValidationRule<String?>.notNil()
        let result = rule.validate("value", path: "token")
        #expect(result.isValid)
    }

    // MARK: - equals

    @Test("equals succeeds when equal")
    func equalsSucceeds() {
        let rule = ValidationRule<String>.equals("expected")
        #expect(rule.validate("expected", path: "f").isValid)
    }

    @Test("equals fails when not equal")
    func equalsFails() {
        let rule = ValidationRule<String>.equals("expected")
        let result = rule.validate("other", path: "f")
        #expect(!result.isValid)
        #expect(result.errors[0].code == "equals")
    }

    // MARK: - custom

    @Test("custom rule with closure")
    func customRule() {
        let rule = ValidationRule<Int>.custom(message: "Must be even") { $0 % 2 == 0 }
        #expect(rule.validate(4, path: "num").isValid)
        #expect(!rule.validate(3, path: "num").isValid)
    }

    // MARK: - asyncCustom

    @Test("async custom rule")
    func asyncCustomRule() async {
        let rule = ValidationRule<String>.asyncCustom(message: "Already taken") { value in
            // Simulate async lookup
            value != "taken"
        }
        let valid = await rule.validateAsync("available", path: "username")
        #expect(valid.isValid)
        let invalid = await rule.validateAsync("taken", path: "username")
        #expect(!invalid.isValid)
    }

    // MARK: - Severity

    @Test("warning severity does not cause isValid to be false")
    func warningSeverity() {
        let rule = ValidationRule<String>.minLength(5, severity: .warning)
        let result = rule.validate("ab", path: "f")
        #expect(result.isValid)
        #expect(result.hasWarnings)
        #expect(result.warningItems.count == 1)
    }

    @Test("error severity causes isValid to be false")
    func errorSeverity() {
        let rule = ValidationRule<String>.minLength(5, severity: .error)
        let result = rule.validate("ab", path: "f")
        #expect(!result.isValid)
        #expect(result.errorItems.count == 1)
    }

    // MARK: - Custom messages and codes

    @Test("custom error message is used")
    func customMessage() {
        let rule = ValidationRule<String>.notEmpty(message: "Please enter your name")
        let result = rule.validate("", path: "name")
        #expect(result.errors[0].message == "Please enter your name")
    }

    @Test("custom code is used")
    func customCode() {
        let rule = ValidationRule<String>.notEmpty(code: "field.required")
        let result = rule.validate("", path: "name")
        #expect(result.errors[0].code == "field.required")
    }

    // MARK: - ValidationResult merging

    @Test("merging combines errors from both results")
    func resultMerging() {
        let r1 = ValidationResult.invalid(ValidationError(path: "a", message: "err1"))
        let r2 = ValidationResult.invalid(ValidationError(path: "b", message: "err2"))
        let merged = r1.merging(r2)
        #expect(merged.errors.count == 2)
        #expect(!merged.isValid)
    }

    @Test("valid merged with valid is valid")
    func validMergeValid() {
        let merged = ValidationResult.valid.merging(.valid)
        #expect(merged.isValid)
        #expect(merged.isClean)
    }

    @Test("valid merged with invalid is invalid")
    func validMergeInvalid() {
        let invalid = ValidationResult.invalid(ValidationError(path: "a", message: "err"))
        let merged = ValidationResult.valid.merging(invalid)
        #expect(!merged.isValid)
    }

    // MARK: - ValidationResult.isValid(failOnWarnings:)

    @Test("isValid with failOnWarnings true rejects warnings")
    func failOnWarningsTrue() {
        let result = ValidationResult(errors: [
            ValidationError(path: "f", message: "warn", severity: .warning)
        ])
        #expect(result.isValid)
        #expect(!result.isValid(failOnWarnings: true))
    }

    @Test("isValid with failOnWarnings false allows warnings")
    func failOnWarningsFalse() {
        let result = ValidationResult(errors: [
            ValidationError(path: "f", message: "warn", severity: .warning)
        ])
        #expect(result.isValid(failOnWarnings: false))
    }
}
