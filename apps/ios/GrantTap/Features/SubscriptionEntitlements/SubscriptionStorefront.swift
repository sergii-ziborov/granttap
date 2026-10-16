import StoreKit

@MainActor
extension SubscriptionStore {
    /// Tiers the store returned, smallest first, so the paywall reads as a ladder.
    var offers: [SubscriptionOffer] {
        products
            .map {
                SubscriptionOffer(
                    id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice,
                    hasSevenDayTrial: trialEligibleProductIDs.contains($0.id)
                )
            }
            .sorted { $0.seatLimit < $1.seatLimit }
    }

    func loadProducts() async {
        availability = .loading
        do {
            products = try await productLoader()
                .filter { SubscriptionProduct(rawValue: $0.id) != nil }
            trialEligibleProductIDs = []
            for product in products {
                guard let info = product.subscription, let intro = info.introductoryOffer,
                      intro.paymentMode == .freeTrial,
                      (intro.period.unit == .day && intro.period.value == 7)
                        || (intro.period.unit == .week && intro.period.value == 1),
                      await info.isEligibleForIntroOffer else { continue }
                trialEligibleProductIDs.insert(product.id)
            }
            availability = products.isEmpty ? .notConfigured : .ready
            lastError = nil
        } catch {
            products = []
            trialEligibleProductIDs = []
            availability = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

}
