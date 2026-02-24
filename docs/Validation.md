<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <a href="GettingStarted.md">Getting Started</a> &nbsp;&bull;&nbsp;
  <a href="Interceptors.md">Interceptors</a> &nbsp;&bull;&nbsp;
  <a href="WebSocket.md">WebSocket</a> &nbsp;&bull;&nbsp;
  <b>Validation</b> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching</a> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing</a> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced</a>
</p>

---

# Validation

FiberValidation is a composable, type-safe validation system for any domain model. It uses Swift result builders for a declarative DSL and integrates with Fiber's interceptor pipeline to validate request bodies before they hit the network.

```swift
import FiberValidation
```

## Table of Contents

- [Quick Start](#quick-start)
- [Built-in Rules](#built-in-rules)
- [Nested Validation](#nested-validation)
- [Collection Validation](#collection-validation)
- [Conditional Validation](#conditional-validation)
- [Async Validation](#async-validation)
- [Severity Levels](#severity-levels)
- [Merging Results](#merging-results)
- [Custom Rules](#custom-rules)
- [Fiber Interceptor Integration](#fiber-interceptor-integration)

---

## Quick Start

Define a validator using the `@ValidatorBuilder` DSL:

```swift
struct User: Sendable {
    let name: String
    let email: String
    let age: Int
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
        ValidationRule.range(18...120, message: "Must be 18 or older")
    }
}
```

Run it:

```swift
let user = User(name: "", email: "not-an-email", age: 15)
let result = userValidator.validate(user)

if !result.isValid {
    for error in result.errorItems {
        print("\(error.path): \(error.message)")
    }
}
// Output:
// name: Name is required
// email: Invalid email format
// age: Must be 18 or older
```

---

## Built-in Rules

| Rule | Type Constraint | Description |
|------|----------------|-------------|
| `.notNil()` | `Optional<Wrapped>` | Value must not be nil |
| `.notEmpty()` | `Collection` | Collection must not be empty |
| `.minLength(_:)` | `Collection` | Count >= minimum |
| `.maxLength(_:)` | `Collection` | Count <= maximum |
| `.lengthRange(_:)` | `Collection` | Count within closed range |
| `.pattern(_:)` | `String` | Matches regex pattern |
| `.email()` | `String` | Valid email format |
| `.url()` | `String` | Valid URL format |
| `.range(_:)` | `Comparable` | Value within closed range |
| `.equals(_:)` | `Equatable` | Must equal expected value |
| `.custom(_:)` | Any `Sendable` | Custom sync predicate |
| `.asyncCustom(_:)` | Any `Sendable` | Custom async predicate |

Every rule accepts optional parameters:

```swift
ValidationRule.minLength(
    8,
    message: "Password must be at least 8 characters",  // custom message
    code: "password_too_short",                          // error code for API mapping
    severity: .error                                     // .error (default) or .warning
)
```

---

## Nested Validation

Compose validators for nested objects. Error paths are automatically prefixed:

```swift
struct Address: Sendable {
    let street: String
    let city: String
    let zipCode: String
    let country: String
}

struct User: Sendable {
    let name: String
    let address: Address
}

let addressValidator = Validator<Address> {
    Validate(\.street, label: "street") {
        ValidationRule.notEmpty(message: "Street is required")
    }
    Validate(\.city, label: "city") {
        ValidationRule.notEmpty(message: "City is required")
    }
    Validate(\.zipCode, label: "zipCode") {
        ValidationRule.pattern(#"^\d{5}(-\d{4})?$"#, message: "Invalid ZIP code")
    }
    Validate(\.country, label: "country") {
        ValidationRule.notEmpty()
        ValidationRule.lengthRange(2...3, message: "Use ISO country code")
    }
}

let userValidator = Validator<User> {
    Validate(\.name, label: "name") {
        ValidationRule.notEmpty()
    }
    // Nest the address validator — paths become "address.street", "address.city", etc.
    Validate(\.address, label: "address", validator: addressValidator)
}
```

```swift
let result = userValidator.validate(user)
// Errors: "address.zipCode: Invalid ZIP code"
```

---

## Collection Validation

Validate each element in a collection with indexed error paths:

```swift
struct Order: Sendable {
    let items: [OrderItem]
}

struct OrderItem: Sendable {
    let productID: String
    let quantity: Int
    let price: Double
}

let orderValidator = Validator<Order> {
    Validate(\.items, label: "items") {
        ValidationRule.notEmpty(message: "Order must have at least one item")
    }
    ValidateEach(\.items, label: "items") {
        ValidationRule.custom(message: "Product ID required") { item in
            !item.productID.isEmpty
        }
        ValidationRule.custom(message: "Quantity must be positive") { item in
            item.quantity > 0
        }
        ValidationRule.custom(message: "Price must be non-negative") { item in
            item.price >= 0
        }
    }
}
```

```swift
// Error paths include indices: "items[0]: Product ID required", "items[2]: Quantity must be positive"
```

---

## Conditional Validation

Apply rules only when a condition is met:

```swift
struct RegistrationForm: Sendable {
    let userType: UserType
    let name: String
    let companyName: String?
    let taxID: String?

    enum UserType: Sendable { case individual, business }
}

let formValidator = Validator<RegistrationForm> {
    Validate(\.name, label: "name") {
        ValidationRule.notEmpty()
    }

    // Only validate business fields when userType is .business
    ValidateIf({ $0.userType == .business }) {
        Validate(\.companyName, label: "companyName") {
            ValidationRule.notNil(message: "Company name required for business accounts")
        }
        Validate(\.taxID, label: "taxID") {
            ValidationRule.notNil(message: "Tax ID required for business accounts")
        }
    }
}
```

---

## Async Validation

For rules that require network calls (e.g., uniqueness checks, external verification):

```swift
let registrationValidator = Validator<RegistrationForm> {
    Validate(\.email, label: "email") {
        ValidationRule.email()
        ValidationRule.asyncCustom(message: "Email already registered") { email in
            let response = try await api.get("/users/check", query: ["email": email])
            let result: AvailabilityCheck = try response.decode()
            return result.available
        }
    }
    Validate(\.username, label: "username") {
        ValidationRule.minLength(3)
        ValidationRule.pattern(#"^[a-zA-Z0-9_]+$"#, message: "Letters, numbers, and underscores only")
        ValidationRule.asyncCustom(message: "Username taken") { username in
            await UsernameService.isAvailable(username)
        }
    }
}

// Use validateAsync for validators containing async rules
let result = await registrationValidator.validateAsync(form)
```

> **Note:** `validate(_:)` (sync) skips async rules silently. Always use `validateAsync(_:)` when your validator contains `.asyncCustom` rules.

---

## Severity Levels

Rules default to `.error` severity. Use `.warning` for non-blocking advisory issues:

```swift
let passwordValidator = Validator<PasswordForm> {
    Validate(\.password, label: "password") {
        // Errors — block submission
        ValidationRule.notEmpty()
        ValidationRule.minLength(8, message: "Password must be at least 8 characters")

        // Warnings — inform but don't block
        ValidationRule.minLength(12, severity: .warning,
            message: "Consider using 12+ characters for better security")
        ValidationRule.pattern(#"[!@#$%^&*]"#, severity: .warning,
            message: "Consider adding special characters")
    }
}
```

**Checking results:**

```swift
let result = passwordValidator.validate(form)

result.isValid                        // true if no .error items
result.isClean                        // true if no items at all
result.hasWarnings                    // true if any .warning items
result.isValid(failOnWarnings: true)  // false if any warnings exist

result.errorItems                     // [ValidationError] — errors only
result.warningItems                   // [ValidationError] — warnings only
result.errors                         // all items regardless of severity
```

---

## Merging Results

Combine validation results from multiple validators:

```swift
let nameResult = nameValidator.validate(form)
let emailResult = emailValidator.validate(form)
let addressResult = addressValidator.validate(form.address)

let combined = nameResult
    .merging(emailResult)
    .merging(addressResult)

if !combined.isValid {
    // All errors from all validators
}
```

---

## Custom Rules

### Sync Custom Rule

```swift
ValidationRule.custom(message: "Must start with a letter") { value in
    guard let first = value.first else { return false }
    return first.isLetter
}
```

### Async Custom Rule

```swift
ValidationRule.asyncCustom(message: "Domain not reachable") { url in
    let (_, response) = try await URLSession.shared.data(from: URL(string: url)!)
    return (response as? HTTPURLResponse)?.statusCode == 200
}
```

### Composing Complex Validators

```swift
struct CreateOrderRequest: Sendable {
    let customerID: String
    let items: [OrderItem]
    let shippingAddress: Address
    let billingAddress: Address?
    let couponCode: String?
    let notes: String?
}

let createOrderValidator = Validator<CreateOrderRequest> {
    Validate(\.customerID, label: "customerID") {
        ValidationRule.notEmpty(message: "Customer ID is required")
        ValidationRule.pattern(#"^cust_[a-zA-Z0-9]+$"#, message: "Invalid customer ID format")
    }

    Validate(\.items, label: "items") {
        ValidationRule.notEmpty(message: "Order must have at least one item")
        ValidationRule.maxLength(100, message: "Maximum 100 items per order")
    }

    ValidateEach(\.items, label: "items") {
        ValidationRule.custom(message: "Invalid quantity") { $0.quantity > 0 && $0.quantity <= 999 }
        ValidationRule.custom(message: "Invalid price") { $0.price > 0 }
    }

    Validate(\.shippingAddress, label: "shippingAddress", validator: addressValidator)

    ValidateIf({ $0.billingAddress != nil }) {
        Validate(\.billingAddress!, label: "billingAddress", validator: addressValidator)
    }

    ValidateIf({ $0.couponCode != nil }) {
        Validate(\.couponCode!, label: "couponCode") {
            ValidationRule.pattern(#"^[A-Z0-9]{4,12}$"#, message: "Invalid coupon format")
        }
    }

    ValidateIf({ $0.notes != nil }) {
        Validate(\.notes!, label: "notes") {
            ValidationRule.maxLength(500, message: "Notes too long")
        }
    }
}
```

---

## Fiber Interceptor Integration

`ValidationInterceptor` automatically validates request bodies before they reach the network:

```swift
import Fiber
import FiberValidation

let createUserValidator = Validator<CreateUserRequest> {
    Validate(\.name, label: "name") {
        ValidationRule.notEmpty()
        ValidationRule.minLength(2)
    }
    Validate(\.email, label: "email") {
        ValidationRule.email()
    }
}

let api = Fiber("https://api.example.com") {
    $0.interceptors = [
        ValidationInterceptor<CreateUserRequest>(
            validator: createUserValidator,
            for: [.post, .put, .patch],    // which methods to validate (default)
            failOnWarnings: false           // default
        ),
        auth,
        retry,
        logging,
    ]
}
```

**When validation fails:**

```swift
do {
    try await api.post("/users", body: invalidUser)
} catch let error as FiberError {
    if case .interceptor(let name, let underlying) = error,
       let failure = underlying as? ValidationFailure {
        for item in failure.result.errorItems {
            print("\(item.path): \(item.message)")
        }
    }
}
```

The request **never leaves the device** when validation fails — saving bandwidth and providing instant feedback.

---

<p align="center">
  <a href="WebSocket.md">&larr; WebSocket</a> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching &rarr;</a>
</p>
