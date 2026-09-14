import Foundation

/// Where secret snippet text lives. Implementations hold every secret in one
/// place so a single read serves all of them.
public protocol SecretStore {
    /// All stored secrets keyed by snippet id. Empty when nothing has been stored yet.
    func read() throws -> [UUID: String]
    /// Replaces all stored secrets.
    func write(_ secrets: [UUID: String]) throws
}

public enum SecretStoreError: Error, Equatable {
    /// The user denied the Keychain prompt, or the keychain is locked.
    case accessDenied
    /// Any other Keychain failure, with its status code.
    case failure(OSStatus)
}

/// Dictionary-backed store for tests and previews.
public final class InMemorySecretStore: SecretStore {
    public private(set) var secrets: [UUID: String]

    public init(secrets: [UUID: String] = [:]) {
        self.secrets = secrets
    }

    public func read() throws -> [UUID: String] {
        secrets
    }

    public func write(_ secrets: [UUID: String]) throws {
        self.secrets = secrets
    }
}
