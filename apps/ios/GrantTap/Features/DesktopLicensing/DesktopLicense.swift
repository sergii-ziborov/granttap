import Foundation

enum DesktopLicenseDistribution: String, Sendable {
    case inAppUnlock = "app-store-unlock"
    case paidDownload = "paid-download"
}

struct DesktopPurchaseEvidence: Equatable, Sendable {
    let identifier: String
    let verified: Bool
    let revoked: Bool
    let nonConsumable: Bool
}

enum DesktopLicense: Equatable, Sendable {
    static let productID = "com.ziborov.granttap.mac.license"
    static let paidBundleID = "com.ziborov.granttap.mac"
    case checking, purchased, evaluation, testFlight, notPurchased

    var permitsLocalControl: Bool {
        switch self {
        case .purchased, .evaluation, .testFlight: true
        case .checking, .notPurchased: false
        }
    }

    var permitsOwnRelay: Bool {
        switch self {
        case .purchased, .testFlight: true
        case .checking, .evaluation, .notPurchased: false
        }
    }

    /// Viewing paired data does not buy a local license or renew remote authorization.
    func permitsRelayCompanionInspection(linkedAccountID: String?, currentAccountID: String?) -> Bool {
        guard let linkedAccountID, linkedAccountID == currentAccountID else { return false }
        return true
    }

    static func resolve(_ evidence: [DesktopPurchaseEvidence],
                        distribution: DesktopLicenseDistribution,
                        bundleID: String, evaluationAllowed: Bool,
                        testFlightVerified: Bool = false) -> Self {
        let purchased = evidence.contains { purchase in
            guard purchase.verified, !purchase.revoked else { return false }
            switch distribution {
            case .inAppUnlock:
                return purchase.identifier == Self.productID && purchase.nonConsumable
            case .paidDownload:
                return bundleID == Self.paidBundleID && purchase.identifier == bundleID
            }
        }
        if purchased { return .purchased }
        if testFlightVerified { return .testFlight }
        return evaluationAllowed ? .evaluation : .notPurchased
    }
}
