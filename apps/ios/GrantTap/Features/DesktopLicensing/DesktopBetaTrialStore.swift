import CryptoKit
import Foundation
import StoreKit

/// TestFlight evaluation is scoped to an Apple app transaction and build.
/// A new build starts a fresh week; a production App Store receipt never does.
enum DesktopBetaTrialStore {
    static let duration: TimeInterval = 7 * 24 * 60 * 60

    static func expiry(verifiedSandbox: Bool, bundleID: String, accountID: String,
                       build: String, now: Date, defaults: UserDefaults) -> Date? {
        guard verifiedSandbox, !bundleID.isEmpty, !accountID.isEmpty, !build.isEmpty else {
            return nil
        }
        let identity = "\(bundleID):\(accountID):\(build)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let firstKey = "granttap.mac.beta.\(digest).first"
        let lastKey = "granttap.mac.beta.\(digest).last"
        let first = defaults.object(forKey: firstKey) as? Date ?? now
        if defaults.object(forKey: firstKey) == nil { defaults.set(first, forKey: firstKey) }
        let observed = max(now, defaults.object(forKey: lastKey) as? Date ?? now)
        defaults.set(observed, forKey: lastKey)
        let expiration = first.addingTimeInterval(duration)
        return observed < expiration ? expiration : nil
    }

    @MainActor
    static func currentExpiry() async -> Date? {
        guard #available(iOS 16.0, macCatalyst 16.0, *),
              let result = try? await AppTransaction.shared else { return nil }
        return verifiedExpiry(result)
    }

    @MainActor
    static func refreshedExpiry() async throws -> Date? {
        guard #available(iOS 16.0, macCatalyst 16.0, *) else { return nil }
        return verifiedExpiry(try await AppTransaction.refresh())
    }

    @MainActor
    @available(iOS 16.0, macCatalyst 16.0, *)
    private static func verifiedExpiry(_ result: VerificationResult<AppTransaction>) -> Date? {
        guard case .verified(let transaction) = result,
              transaction.environment == .sandbox,
              transaction.bundleID == Bundle.main.bundleIdentifier,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else { return nil }
        return expiry(verifiedSandbox: true, bundleID: transaction.bundleID,
                      accountID: transaction.appTransactionID, build: build,
                      now: Date(), defaults: .standard)
    }
}
