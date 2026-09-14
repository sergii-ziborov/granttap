import StoreKit
import SwiftUI

@MainActor
struct SubscriptionView: View {
    @ObservedObject var store: SubscriptionStore
    private let offersOverride: [SubscriptionOffer]?

    init(store: SubscriptionStore? = nil, offers: [SubscriptionOffer]? = nil) {
        self.store = store ?? .shared
        offersOverride = offers
    }

    private var offers: [SubscriptionOffer] { offersForDisplay }

    /// Smallest tier first, whether the tiers came from the store or a test.
    var offersForDisplay: [SubscriptionOffer] {
        (offersOverride ?? store.offers).sorted { $0.seatLimit < $1.seatLimit }
    }

    var body: some View {
        List {
            Section {
                statusRow
            } header: {
                Text(L("Remote service"))
            } footer: {
                Text(L("Local agent history and on-device encrypted data stay available if the subscription ends. Remote relay, background wake, and the bounded server queue require an active entitlement after the trial."))
            }

            Section {
                if offers.isEmpty {
                    unavailableRow
                } else {
                    ForEach(offers) { offer in
                        productRow(offer)
                    }
                }
            } header: {
                Text(L("Personal"))
            } footer: {
                Text(L("Tiers differ only by how many computers you link. Every computer runs as many coding agents as it can — agents are never counted or charged for."))
            }

            Section(L("Manage")) {
                Button(L("Restore purchases")) { Task { await store.restore() } }
                Button(L("Manage subscription")) { Task { await store.manage() } }
                Link("Terms of Use", destination: URL(string: "https://granttap.com/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://granttap.com/privacy")!)
            }

        }
        .navigationTitle(L("Subscription"))
        .task { await store.start() }
        .overlay {
            if store.purchaseInProgress { ProgressView().controlSize(.large) }
        }
        .alert("Subscription", isPresented: Binding(
            get: { store.lastError != nil },
            set: { visible in if !visible { store.clearError() } }
        )) {
            Button(L("OK"), role: .cancel) { store.clearError() }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    @ViewBuilder var statusRow: some View {
        switch store.entitlement.state {
        case .trial(let expiry):
            Label("Free trial until \(expiry.formatted(date: .abbreviated, time: .omitted))",
                  systemImage: "clock.badge.checkmark")
        case .active(let expiry):
            Label(expiry.map { "Active until \($0.formatted(date: .abbreviated, time: .omitted))" }
                  ?? "Active", systemImage: "checkmark.seal.fill")
        case .gracePeriod:
            Label(L("Billing grace period"), systemImage: "exclamationmark.circle")
        case .billingRetry:
            Label(L("Payment needs attention"), systemImage: "creditcard.trianglebadge.exclamationmark")
        case .expired:
            Label(L("Expired"), systemImage: "xmark.circle")
        case .revoked:
            Label(L("Revoked or refunded"), systemImage: "xmark.shield")
        case .unavailable:
            Label(L("Not subscribed"), systemImage: "circle.dashed")
        }
    }

    @ViewBuilder var unavailableRow: some View {
        switch store.availability {
        case .loading:
            ProgressView("Loading App Store pricing…")
        case .notConfigured:
            Text(L("The subscription is not available in this App Store storefront yet."))
                .foregroundStyle(Theme.muted)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Could not load App Store pricing"))
                Text(error).font(.caption).foregroundStyle(Theme.muted)
            }
        case .ready:
            EmptyView()
        }
    }

    /// Whether this tier is the one currently paid for.
    func isCurrent(_ offer: SubscriptionOffer) -> Bool {
        store.entitlement.product?.rawValue == offer.id
    }

    /// The smallest tier that still covers the computers already linked.
    func isRecommended(_ offer: SubscriptionOffer) -> Bool {
        guard !offers.contains(where: isCurrent) else { return false }
        let linked = max(1, AppModel.shared.connectionRegistry.connections.count)
        return offers.first { $0.seatLimit >= linked }?.id == offer.id
    }

    func productRow(_ offer: SubscriptionOffer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: offer.seatLimit == 1 ? "desktopcomputer" : "macpro.gen3")
                    .foregroundStyle(Theme.claude)
                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.summary).font(.headline)
                    Text(L("Unlimited agents on each"))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(offer.displayPrice).font(.headline).monospacedDigit()
                    Text(L("per month")).font(.caption2).foregroundStyle(Theme.muted)
                }
            }

            if isCurrent(offer) {
                Label(L("Your plan"), systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(Theme.ok)
            } else if isRecommended(offer) {
                Label(L("Covers the computers you have linked"), systemImage: "sparkles")
                    .font(.caption).foregroundStyle(Theme.claude)
            }

            Text("7-day free trial for eligible new subscribers; then \(offer.displayPrice) per month. Renews automatically until cancelled.")
                .font(.caption).foregroundStyle(Theme.muted)

            Button(isCurrent(offer) ? "Manage" : "Subscribe") {
                if isCurrent(offer) { Task { await store.manage() } } else { subscribe(offer) }
            }
            .buttonStyle(.borderedProminent)
            .tint(isCurrent(offer) ? Theme.muted : Theme.claude)
            .accessibilityIdentifier("subscription.\(offer.id)")
        }
        .padding(.vertical, 5)
    }

    func subscribe(_ offer: SubscriptionOffer) {
        Task { await store.purchase(offerID: offer.id) }
    }
}
