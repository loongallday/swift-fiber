import Foundation
import Fiber
import Sharing

// MARK: - FiberConfiguration SharedKey

extension SharedReaderKey where Self == InMemoryKey<FiberConfiguration>.Default {
    /// Shared key for Fiber configuration.
    ///
    /// ```swift
    /// @Shared(.fiberConfiguration) var config
    /// config.baseURL = "https://api.example.com"
    /// ```
    public static var fiberConfiguration: Self {
        Self[.inMemory("fiberConfiguration"), default: FiberConfiguration()]
    }
}
