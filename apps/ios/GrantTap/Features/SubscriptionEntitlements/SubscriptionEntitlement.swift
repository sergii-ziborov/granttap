import Foundation

enum SubscriptionAccessState: Equatable, Sendable {
    case trial(expiresAt: Date)
    case active(expiresAt: Date?)
    case gracePeriod(expiresAt: Date?)
    case billingRetry(expiresAt: Date?)
    case expired
    case revoked
    case unavailable

    var allowsRemoteInfrastructure: Bool {
        switch self {
        case .trial, .active, .gracePeriod: true
        case .billingRetry, .expired, .revoked, .unavailable: false
        }
    }
}

struct SubscriptionStatusSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case subscribed, gracePeriod, billingRetry, expired, revoked
    }

    let product: SubscriptionProduct
    let state: State
    let expirationDate: Date?
    let isTrial: Bool
    let verified: Bool
}

struct SubscriptionEntitlement: Equatable, Sendable {
    let state: SubscriptionAccessState
    let product: SubscriptionProduct?
    let seatLimit: Int

    static let unavailable = SubscriptionEntitlement(
        state: .unavailable,
        product: nil,
        seatLimit: 0
    )

    static func reduce(_ snapshots: [SubscriptionStatusSnapshot], now: Date) -> Self {
        let verified = snapshots.filter(\.verified)
        guard !verified.isEmpty else { return .unavailable }

        let ranked = verified.sorted { priority($0, now: now) > priority($1, now: now) }
        guard let selected = ranked.first else { return .unavailable }
        let expiration = selected.expirationDate

        let state: SubscriptionAccessState
        switch selected.state {
        case .subscribed where selected.isTrial && expiration.map { $0 > now } == true:
            state = .trial(expiresAt: expiration!)
        case .subscribed where expiration.map { $0 <= now } == true:
            state = .expired
        case .subscribed:
            state = .active(expiresAt: expiration)
        case .gracePeriod:
            state = .gracePeriod(expiresAt: expiration)
        case .billingRetry:
            state = .billingRetry(expiresAt: expiration)
        case .expired:
            state = .expired
        case .revoked:
            state = .revoked
        }
        return Self(state: state, product: selected.product,
                    seatLimit: selected.product.seatLimit)
    }

    private static func priority(_ snapshot: SubscriptionStatusSnapshot, now: Date) -> Int {
        switch snapshot.state {
        case .subscribed where snapshot.expirationDate.map { $0 > now } != false: 6
        case .gracePeriod: 5
        case .billingRetry: 4
        case .subscribed: 3
        case .expired: 2
        case .revoked: 1
        }
    }
}
