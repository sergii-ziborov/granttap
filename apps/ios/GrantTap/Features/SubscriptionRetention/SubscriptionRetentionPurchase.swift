import Foundation
import StoreKit

struct SubscriptionRetentionPrice {
    let product: Product
    let promotion: Product.SubscriptionOffer

    init?(offer: SubscriptionRetentionOffer, products: [Product], now: Date = Date()) {
        guard offer.expiresAt > now,
              let product = products.first(where: { $0.id == offer.productID }),
              let promotion = product.subscription?.promotionalOffers.first(where: { $0.id == offer.offerID }),
              promotion.period.unit == .month, promotion.period.value == 1,
              promotion.periodCount == 1, promotion.price > 0, promotion.price < product.price else { return nil }
        self.product = product
        self.promotion = promotion
    }
}

@MainActor
extension SubscriptionStore {
    func purchaseRetention(_ offer: SubscriptionRetentionOffer) async {
        guard !hasTestingAccess, currentAccountID() != nil,
              let price = SubscriptionRetentionPrice(offer: offer, products: products) else {
            lastError = L("This offer is no longer available. You can still manage or cancel with Apple.")
            return
        }
        await purchase(price.product, additionalOptions: [.promotionalOffer(offerID: offer.offerID,
            keyID: offer.keyID, nonce: offer.nonce, signature: offer.signature, timestamp: offer.timestamp)])
    }
}
