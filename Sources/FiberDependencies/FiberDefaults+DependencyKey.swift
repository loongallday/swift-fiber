import Foundation
import Fiber
import Dependencies

// MARK: - FiberDefaults + DependencyKey

private enum FiberDefaultsKey: DependencyKey {
    static let liveValue: FiberDefaults = .shared
    static let testValue: FiberDefaults = FiberDefaults()
    static let previewValue: FiberDefaults = FiberDefaults()
}

extension DependencyValues {
    /// Access `FiberDefaults` via `@Dependency(\.fiberDefaults)`.
    ///
    /// ```swift
    /// @Dependency(\.fiberDefaults) var defaults
    ///
    /// // Override in tests:
    /// withDependencies {
    ///     $0.fiberDefaults = FiberDefaults(
    ///         traceIDGenerator: { "fixed-trace-id" }
    ///     )
    /// } operation: { ... }
    /// ```
    public var fiberDefaults: FiberDefaults {
        get { self[FiberDefaultsKey.self] }
        set { self[FiberDefaultsKey.self] = newValue }
    }
}
