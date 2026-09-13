import Foundation
import Security

/// Keeps all secrets in one generic-password item in the login Keychain.
///
/// One item rather than one per snippet: Keychain access grants are per item
/// and per code signature, and ad-hoc-signed builds change signature on every
/// update. One item means the user is asked once per update, not once per
/// secret snippet.
public final class KeychainSecretStore: SecretStore {
    public static let service = "com.ozanalbayrak.CopyStack"
    public static let defaultAccount = "secrets"

    private let account: String

    public init(account: String = KeychainSecretStore.defaultAccount) {
        self.account = account
    }

    public func read() throws -> [UUID: String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return [:] }
            return try Self.decode(data)
        case errSecItemNotFound:
            return [:]
        default:
            throw Self.error(for: status)
        }
    }

    public func write(_ secrets: [UUID: String]) throws {
        if secrets.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Self.error(for: status)
            }
            return
        }
        let data = try Self.encode(secrets)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "CopyStack secret snippets"
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Self.error(for: status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static func error(for status: OSStatus) -> SecretStoreError {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .accessDenied
        default:
            return .failure(status)
        }
    }

    // Stored as a JSON object keyed by UUID string; `[UUID: String]` itself
    // would encode as a flat array.
    private static func encode(_ secrets: [UUID: String]) throws -> Data {
        let keyed = Dictionary(uniqueKeysWithValues: secrets.map { ($0.key.uuidString, $0.value) })
        return try JSONEncoder().encode(keyed)
    }

    private static func decode(_ data: Data) throws -> [UUID: String] {
        let keyed = try JSONDecoder().decode([String: String].self, from: data)
        var result: [UUID: String] = [:]
        for (key, value) in keyed {
            if let id = UUID(uuidString: key) {
                result[id] = value
            }
        }
        return result
    }
}
