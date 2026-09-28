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
    case checking, purchased, evaluation, notPurchased

    var permitsLocalControl: Bool { self == .purchased || self == .evaluation }
    var permitsOwnRelay: Bool { self == .purchased }

    static func resolve(_ evidence: [DesktopPurchaseEvidence],
                        distribution: DesktopLicenseDistribution,
                        bundleID: String, evaluationAllowed: Bool) -> Self {
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
        return evaluationAllowed ? .evaluation : .notPurchased
    }
}
