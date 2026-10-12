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
    case checking, purchased, evaluation, betaTrial(expiresAt: Date), notPurchased

    var permitsLocalControl: Bool {
        switch self {
        case .purchased, .evaluation, .betaTrial: true
        case .checking, .notPurchased: false
        }
    }

    var permitsOwnRelay: Bool {
        switch self {
        case .purchased, .betaTrial: true
        case .checking, .evaluation, .notPurchased: false
        }
    }

    static func resolve(_ evidence: [DesktopPurchaseEvidence],
                        distribution: DesktopLicenseDistribution,
                        bundleID: String, evaluationAllowed: Bool,
                        betaExpiresAt: Date? = nil, now: Date = Date()) -> Self {
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
        if distribution == .inAppUnlock, let betaExpiresAt, betaExpiresAt > now {
            return .betaTrial(expiresAt: betaExpiresAt)
        }
        return evaluationAllowed ? .evaluation : .notPurchased
    }
}
