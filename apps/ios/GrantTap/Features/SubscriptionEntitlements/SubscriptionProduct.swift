import Foundation

/// The Personal subscription, priced by how many computers a person links.
///
/// Agents are never counted: a computer runs as many coding agents as it can,
/// and charging per agent would price the product against the thing it exists
/// to make easy. Only the remote service — relay, background wake, and the
/// bounded server queue — is subscribed; local use is unaffected.
enum SubscriptionProduct: String, CaseIterable, Sendable {
    case solo = "com.ziborov.granttap.personal.solo.monthly"
    case personal = "com.ziborov.granttap.personal.monthly"
    case fleet = "com.ziborov.granttap.personal.fleet.monthly"

    /// Linked computers this tier allows. Agents per computer are unlimited.
    var seatLimit: Int {
        switch self {
        case .solo: 1
        case .personal: 5
        case .fleet: 10
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

    var product: SubscriptionProduct? { SubscriptionProduct(rawValue: id) }
    var seatLimit: Int { product?.seatLimit ?? 0 }
    var summary: String { product?.summary ?? "" }
}
