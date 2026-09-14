import Foundation
import Security

/// The Keychain copy of the install id. It deliberately outlives app deletion:
/// finding it without the container copy is what identifies a reinstall.
enum InstallIdentityRecord {
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: InstallIdentity.service,
            kSecAttrAccount as String: InstallIdentity.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func save(_ id: String) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: InstallIdentity.service,
            kSecAttrAccount as String: InstallIdentity.account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(id.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = identity
        attributes.forEach { item[$0.key] = $0.value }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// Every Keychain service this app owns. Per-room session keys carry the room
/// id inside the service name, so the set can only be found by prefix.
enum OwnedKeychainItems {
    static let servicePrefix = "com.ziborov.granttap."

    static func services(prefix: String = servicePrefix) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let rows = items as? [[String: Any]] else { return [] }
        let names = rows.compactMap { $0[kSecAttrService as String] as? String }
        return Set(names.filter { $0.hasPrefix(prefix) }).sorted()
    }

    /// Deletes every account under every owned service, including the install
    /// record itself, which `reconcile` immediately rewrites for the new install.
    static func removeAll(prefix: String = servicePrefix) {
        for service in services(prefix: prefix) {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ] as CFDictionary)
        }
    }
}
