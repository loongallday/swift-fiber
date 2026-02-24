import Foundation
import CryptoKit

// MARK: - EncryptionProvider Protocol

/// Pluggable encryption for request/response bodies.
///
/// ```swift
/// // Use built-in AES-GCM:
/// let provider = AESGCMEncryptionProvider(key: myKey)
///
/// // Or your own:
/// struct CustomEncryption: EncryptionProvider {
///     func encrypt(_ data: Data) throws -> Data { ... }
///     func decrypt(_ data: Data) throws -> Data { ... }
/// }
/// ```
public protocol EncryptionProvider: Sendable {
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ data: Data) throws -> Data
}

// MARK: - AES-GCM Default

/// Built-in AES-GCM encryption using Apple CryptoKit.
///
/// ```swift
/// let key = SymmetricKey(size: .bits256)
/// let provider = AESGCMEncryptionProvider(key: key)
/// let encrypted = try provider.encrypt(plaintext)
/// let decrypted = try provider.decrypt(encrypted)
/// ```
public struct AESGCMEncryptionProvider: EncryptionProvider {
    private let key: SymmetricKey

    public init(key: SymmetricKey) { self.key = key }
    public init(keyData: Data) { self.key = SymmetricKey(data: keyData) }

    public func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw EncryptionError.encryptionFailed }
        return combined
    }

    public func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}

public enum EncryptionError: Error, Sendable {
    case encryptionFailed
    case decryptionFailed
}

// MARK: - EncryptionInterceptor

/// Encrypts request bodies and decrypts response bodies.
///
/// ```swift
/// let fiber = Fiber("https://api.example.com") {
///     $0.interceptors = [EncryptionInterceptor(provider: AESGCMEncryptionProvider(key: myKey))]
/// }
/// ```
public struct EncryptionInterceptor: Interceptor {
    public let name = "encryption"
    private let provider: any EncryptionProvider
    private let encryptRequest: Bool
    private let decryptResponse: Bool

    public init(provider: any EncryptionProvider, encryptRequest: Bool = true, decryptResponse: Bool = true) {
        self.provider = provider; self.encryptRequest = encryptRequest; self.decryptResponse = decryptResponse
    }

    public func intercept(
        _ request: FiberRequest,
        next: @Sendable (FiberRequest) async throws -> FiberResponse
    ) async throws -> FiberResponse {
        var outgoing = request
        if encryptRequest, let body = request.body {
            do { outgoing = outgoing.body(try provider.encrypt(body)) }
            catch { throw FiberError.interceptor(name: name, underlying: error) }
        }

        var response = try await next(outgoing)

        if decryptResponse, !response.data.isEmpty {
            do {
                let decrypted = try provider.decrypt(response.data)
                response = FiberResponse(
                    data: decrypted, statusCode: response.statusCode, headers: response.headers,
                    request: response.request, duration: response.duration, traceID: response.traceID
                )
            } catch { throw FiberError.interceptor(name: name, underlying: error) }
        }

        return response
    }
}
