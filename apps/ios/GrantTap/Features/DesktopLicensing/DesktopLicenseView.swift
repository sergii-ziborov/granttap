#if targetEnvironment(macCatalyst)
import StoreKit
import SwiftUI

struct DesktopLicenseView: View {
    @ObservedObject var store: DesktopLicenseStore = .shared

    var body: some View {
        List {
            Section(L("Mac license")) {
                switch store.license {
                case .checking: ProgressView(L("Checking purchase…"))
                case .purchased:
                    Label(L("Purchased"), systemImage: "checkmark.seal.fill")
                case .evaluation:
                    Label(L("Development evaluation"), systemImage: "hammer")
                    Text(L("This development build is for evaluation. It is not a production purchase."))
                case .notPurchased:
                    Text(L("A Mac license unlocks local agent control and your own relay. A hosted-service subscription is optional."))
                }
                if store.distribution == .inAppUnlock, store.license != .purchased {
                    if let product = store.product {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            HStack {
                                Text(L("Buy Mac license"))
                                Spacer()
                                Text(product.displayPrice)
                            }
                        }
                        .accessibilityIdentifier("license.purchase")
                        Text(L("One-time purchase. No automatic renewal. Apple shows the final price before payment."))
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        Text(L("The Mac license is not available in this storefront yet."))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Button(L("Restore purchases")) { Task { await store.restore() } }
                    .accessibilityIdentifier("license.restore")
            }
            Section(L("Optional hosted service")) {
                Text(L("Personal pays for hosted encrypted delivery, its server queue and background notifications. Your Mac license does not expire when a subscription ends."))
                NavigationLink(L("Manage subscription")) { SubscriptionView() }
            }
            Section(L("Legal")) {
                ProductInformationLinks()
            }
            if let error = store.lastError {
                Section { Text(error).foregroundStyle(Theme.riskHigh) }
            }
        }
        .pageNavigationTitle(L("Mac license"))
        .accessibilityIdentifier("license.page")
        .disabled(store.purchasing)
        .overlay { if store.purchasing { ProgressView() } }
        .task { await store.start() }
    }
}
#endif
