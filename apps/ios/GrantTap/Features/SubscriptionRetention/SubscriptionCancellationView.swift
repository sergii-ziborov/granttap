import SwiftUI

@MainActor
struct SubscriptionCancellationView: View {
    @ObservedObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var offer: SubscriptionRetentionOffer?
    @State private var loading = true
    @State private var reason = ""
    @State private var comment = ""
    @State private var feedbackID = UUID()
    @State private var saved = false
    @State private var saving = false
    @State private var attempted = false
    @State private var error: String?
    private let reasons = ["price", "technical_problem", "missing_feature", "not_using", "other"]
    private let titles = ["Price", "Technical problem", "Missing a feature", "Not using it", "Other"]
    private let apple = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    Link(L("Continue to Apple's subscription settings"), destination: apple)
                        .accessibilityIdentifier("subscription.cancel-with-apple")
                    Text(L("Apple manages cancellation. Access continues until the current period ends. Cancel a free trial at least 24 hours before it ends to avoid renewal."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if !store.hasTestingAccess {
                    Section(L("One discounted month")) {
                        if let offer, let price = SubscriptionRetentionPrice(offer: offer, products: store.products) {
                            Text(String(format: L("%@ for one month, then %@ per month until cancelled."),
                                price.promotion.displayPrice, price.product.displayPrice))
                            Text(L("Available once per GrantTap account. Apple confirms the price and renewal before purchase."))
                                .font(.caption).foregroundStyle(Theme.muted)
                            Button(L("Use this offer")) { Task { await store.purchaseRetention(offer) } }
                                .disabled(store.purchaseInProgress)
                                .accessibilityIdentifier("subscription.retention-purchase")
                        } else if loading {
                            ProgressView(L("Checking your offer…"))
                        } else {
                            Text(L("There is no eligible offer for this account right now."))
                                .foregroundStyle(Theme.muted)
                        }
                        if let message = store.lastError { Text(message).foregroundStyle(Theme.riskHigh) }
                    }
                }
                Section {
                    if saved {
                        Label(L("Thank you. Your feedback was saved."), systemImage: "checkmark.circle")
                    } else {
                        Picker(L("Reason (optional)"), selection: $reason) {
                            Text(L("Choose a reason")).tag("")
                            ForEach(Array(reasons.enumerated()), id: \.element) { index, value in
                                Text(L(titles[index])).tag(value)
                            }
                        }
                        .disabled(attempted)
                        Text(L("Comment (optional)"))
                        TextEditor(text: $comment)
                            .frame(minHeight: 88)
                            .disabled(attempted)
                            .accessibilityLabel(L("Comment (optional)"))
                            .onChange(of: comment) { value in
                                if value.count > 2_000 { comment = String(value.prefix(2_000)) }
                            }
                        Button(L(attempted ? "Retry saving feedback" : "Send feedback")) { Task { await saveFeedback() } }
                            .disabled((reason.isEmpty && comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || saving)
                        Text(L("Feedback is optional and is sent to GrantTap support. Comments are encrypted at rest and kept for up to 90 days. It does not cancel or change your subscription."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let error { Text(error).foregroundStyle(Theme.riskHigh) }
                } header: { Text(L("Help us improve")) }
            }
            .pageNavigationTitle(L("Manage or cancel"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
            .task {
                defer { loading = false }
                guard !store.hasTestingAccess, store.currentAccountID() != nil else { return }
                do { offer = try await SubscriptionRetentionAPI.offer() }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func saveFeedback() async {
        saving = true; attempted = true; error = nil
        defer { saving = false }
        do {
            try await SubscriptionRetentionAPI.feedback(id: feedbackID, reason: reason.isEmpty ? "other" : reason, comment: comment)
            saved = true
        } catch { self.error = error.localizedDescription }
    }
}
