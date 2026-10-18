import Foundation
import Security

enum CredentialStore {
    private static let service = "com.h200.openchat"
    private static let account = "api-key"

    static func loadAPIKey() -> String {
        loadAPIKey(account: account)
    }

    static func saveAPIKey(_ value: String) {
        saveAPIKey(value, account: account)
    }

    // Per-connection
    static func loadAPIKey(for connectionID: UUID) -> String {
        loadAPIKey(account: account(for: connectionID))
    }

    static func saveAPIKey(_ value: String, for connectionID: UUID) {
        saveAPIKey(value, account: account(for: connectionID))
    }

    static func deleteAPIKey(for connectionID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: connectionID)
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func migrateFromUserDefaults() -> String {
        let defaults = UserDefaults.standard
        let oldValue = defaults.string(forKey: "apiKey") ?? ""
        guard !oldValue.isEmpty else { return loadAPIKey() }
        saveAPIKey(oldValue)
        defaults.removeObject(forKey: "apiKey")
        return oldValue
    }

    // MARK: - private

    private static func account(for id: UUID) -> String {
        "\(account)-\(id.uuidString)"
    }

    private static func loadAPIKey(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    private static func saveAPIKey(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
