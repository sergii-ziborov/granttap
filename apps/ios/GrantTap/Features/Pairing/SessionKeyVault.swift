import Foundation
import Security

enum SessionKeyVault {
    private static func service(_ room: String) -> String {
        "com.ziborov.granttap.session-keys.\(room)"
    }

    static func load(room: String) -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(room),
            kSecAttrAccount as String: "task-keys",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let keys = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return keys
    }

    @discardableResult
    static func save(_ keys: [String: String], room: String) -> Bool {
        guard let data = try? JSONEncoder().encode(keys) else { return false }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(room),
            kSecAttrAccount as String: "task-keys",
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = identity
        attributes.forEach { item[$0.key] = $0.value }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove(room: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(room),
            kSecAttrAccount as String: "task-keys",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
