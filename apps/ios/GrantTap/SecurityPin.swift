import CryptoKit
import Foundation
import Security

/// First-party 6-digit GrantTap PIN (Keychain). Required whenever app lock is on.
enum AppPinStore {
    private static let service = "com.ziborov.granttap.pin"
    private static let account = "app-lock-pin"
    private static let saltAccount = "app-lock-pin-salt"
    static let length = 6

    static var isSet: Bool { loadHash() != nil }

    static func isValidFormat(_ pin: String) -> Bool {
        SecurityLockPolicy.isValidPinFormat(pin)
    }

    @discardableResult
    static func save(_ pin: String) -> Bool {
        guard isValidFormat(pin) else { return false }
        let salt = loadOrCreateSalt()
        let digest = hash(pin, salt: salt)
        return saveData(digest, account: account)
    }

    static func verify(_ pin: String) -> Bool {
        guard isValidFormat(pin), let expected = loadHash() else { return false }
        let salt = loadOrCreateSalt()
        return hash(pin, salt: salt) == expected
    }

    static func clear() {
        delete(account: account)
        delete(account: saltAccount)
    }

    private static func hash(_ pin: String, salt: Data) -> Data {
        var data = Data(pin.utf8)
        data.append(salt)
        return Data(SHA256.hash(data: data))
    }

    private static func loadHash() -> Data? { loadData(account: account) }

    private static func loadOrCreateSalt() -> Data {
        if let existing = loadData(account: saltAccount) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let salt = Data(bytes)
        _ = saveData(salt, account: saltAccount)
        return salt
    }

    private static func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    private static func saveData(_ data: Data, account: String) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let update = SecItemUpdate(identity as CFDictionary, attrs as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = identity
        attrs.forEach { item[$0.key] = $0.value }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
