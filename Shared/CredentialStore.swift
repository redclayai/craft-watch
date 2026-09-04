import Foundation
import Security

/// Keychain-backed storage for `CraftCredentials`.
///
/// `kSecAttrAccessibleAfterFirstUnlock` matters here: the Watch refreshes tokens from
/// background refresh and from complication taps, when the device may be locked.
nonisolated struct CredentialStore: Sendable {
    static let shared = CredentialStore()

    private let service = "ai.redclay.craftwatch.credentials"
    private let account = "craft-mcp"

    func load() -> CraftCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CraftCredentials.self, from: data)
    }

    func save(_ credentials: CraftCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CraftError.keychain(addStatus) }
        default:
            throw CraftError.keychain(status)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
