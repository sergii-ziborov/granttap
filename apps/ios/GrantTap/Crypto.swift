import Foundation
import TweetNacl // SwiftPM: https://github.com/bitmark-inc/tweetnacl-swiftwrap

// NaCl public-key authenticated encryption, wire-compatible with the Node side
// (tweetnacl `nacl.box`). Each device holds only its own secret key and the
// peer's public key; the relay can never open these.

enum Crypto {
    struct SealResult: Codable { let nonce: String; let box: String }

    static func seal(_ jsonData: Data, theirPublicKeyB64: String, mySecretKeyB64: String) throws -> SealResult {
        guard let their = Data(base64Encoded: theirPublicKeyB64),
              let mine = Data(base64Encoded: mySecretKeyB64) else {
            throw CryptoError.badKey
        }
        let nonce = randomBytes(24)
        let boxed = try NaclBox.box(message: jsonData, nonce: nonce, publicKey: their, secretKey: mine)
        return SealResult(nonce: nonce.base64EncodedString(), box: boxed.base64EncodedString())
    }

    static func open(nonceB64: String, boxB64: String, theirPublicKeyB64: String, mySecretKeyB64: String) -> Data? {
        guard let nonce = Data(base64Encoded: nonceB64),
              let boxed = Data(base64Encoded: boxB64),
              let their = Data(base64Encoded: theirPublicKeyB64),
              let mine = Data(base64Encoded: mySecretKeyB64) else { return nil }
        return try? NaclBox.open(message: boxed, nonce: nonce, publicKey: their, secretKey: mine)
    }

    static func transferKeyData(_ key: String) -> Data? {
        var base64 = key.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), data.count == 32 else { return nil }
        return data
    }

    static func isValidTransferKey(_ key: String) -> Bool { transferKeyData(key) != nil }

    static func openableSeal(_ data: Data, key: String) -> SealResult? {
        guard let keyData = transferKeyData(key) else { return nil }
        let nonce = randomBytes(24)
        guard let box = try? NaclSecretBox.secretBox(message: data, nonce: nonce, key: keyData) else {
            return nil
        }
        return SealResult(nonce: nonce.base64EncodedString(), box: box.base64EncodedString())
    }

    /// Opens a pairing blob with the independent 256-bit key from the QR/token.
    static func openWithTransferKey(nonceB64: String, boxB64: String, key: String) -> Data? {
        guard let keyData = transferKeyData(key),
              let nonce = Data(base64Encoded: nonceB64),
              let box = Data(base64Encoded: boxB64) else { return nil }
        return try? NaclSecretBox.open(box: box, nonce: nonce, key: keyData)
    }

    static func randomBytes(_ count: Int) -> Data {
        var d = Data(count: count)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return d
    }

    enum CryptoError: Error { case badKey }
}
