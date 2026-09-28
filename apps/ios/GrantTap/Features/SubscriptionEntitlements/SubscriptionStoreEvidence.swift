import Foundation
import StoreKit

@MainActor
enum SubscriptionStoreEvidence {
    static func merge(_ statuses: [SubscriptionStatusSnapshot],
                      authoritative: Set<SubscriptionProduct>,
                      receipts: [SubscriptionStatusSnapshot]) -> [SubscriptionStatusSnapshot] {
        statuses + receipts.filter { !authoritative.contains($0.product) }
    }

    static func load(_ products: [Product]) async -> [SubscriptionStatusSnapshot] {
        var statuses: [SubscriptionStatusSnapshot] = []
        var authoritative: Set<SubscriptionProduct> = []
        for product in products {
            guard let selected = SubscriptionProduct(rawValue: product.id),
                  let subscription = product.subscription,
                  let reported = try? await subscription.status else { continue }
            authoritative.insert(selected)
            for status in reported {
                let actual: SubscriptionProduct
                if case .verified(let transaction) = status.transaction {
                    guard let known = SubscriptionProduct(rawValue: transaction.productID) else { continue }
                    actual = known
                } else { actual = selected }
                authoritative.insert(actual)
                statuses.append(SubscriptionStore.snapshot(status, product: actual))
            }
        }
        var receipts: [SubscriptionStatusSnapshot] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable,
                  let product = SubscriptionProduct(rawValue: transaction.productID),
                  let expiration = transaction.expirationDate else { continue }
            receipts.append(.init(product: product,
                state: transaction.revocationDate == nil ? .subscribed : .revoked,
                expirationDate: expiration,
                isTrial: transaction.offerType == .introductory
                    && transaction.offerPaymentModeStringRepresentation == "FREE_TRIAL",
                verified: true))
        }
        return merge(statuses, authoritative: authoritative, receipts: receipts)
    }
}
