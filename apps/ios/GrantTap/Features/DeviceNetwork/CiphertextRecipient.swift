import CryptoKit
import Foundation

/// A public routing hint only. Every accepted payload still needs box authentication.
enum CiphertextRecipient {
    static func identifier(publicKey: String) -> String? {
        guard let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func accepts(_ recipient: String?, publicKey: String) -> Bool {
        guard let recipient else { return true }
        return identifier(publicKey: publicKey) == recipient
    }
}
