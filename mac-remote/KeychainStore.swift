import Foundation
import Security

/// Stores each Mac's PIN in the Keychain, keyed by the Mac's Bonjour name.
enum KeychainStore {
    private static let service = "zade.mac-remote.pin"

    static func pin(for server: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPIN(_ pin: String, for server: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server,
        ]
        let data = Data(pin.utf8)
        // AfterFirstUnlock so the app can reconnect right after a Face ID unlock.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(match as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(match.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func removePIN(for server: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server,
        ]
        SecItemDelete(match as CFDictionary)
    }
}
