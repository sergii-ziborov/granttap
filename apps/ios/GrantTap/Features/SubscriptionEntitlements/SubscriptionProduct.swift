import Foundation

/// Managed plans count publishing computers, not agents or Tasks.
/// Local control and own-relay use have separate Mac Local rights.
enum SubscriptionProduct: String, CaseIterable, Sendable {
    case solo = "com.ziborov.granttap.personal.solo.monthly"
    case personal = "com.ziborov.granttap.personal.monthly"
    case studio = "com.ziborov.granttap.personal.studio.monthly"

    var label: String {
        switch self {
        case .solo: "Personal"
        case .personal: "Personal Plus"
        case .studio: "Fleet"
        }
    }

    /// Stable computers enabled to publish through the managed service.
    var seatLimit: Int {
        switch self {
        case .solo: 2
        case .personal: 5
        case .studio: 15
        }
    }

    /// Ordering for the paywall: the smallest tier first.
    static var ordered: [SubscriptionProduct] {
        allCases.sorted { $0.seatLimit < $1.seatLimit }
    }

    var summary: String {
        seatLimit == 1
            ? L("1 computer")
            : String(format: L("Up to %d computers"), seatLimit)
    }
}

struct SubscriptionOffer: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String
    var hasSevenDayTrial = false

    var product: SubscriptionProduct? { SubscriptionProduct(rawValue: id) }
    var seatLimit: Int { product?.seatLimit ?? 0 }
    var summary: String { product?.summary ?? "" }
}
