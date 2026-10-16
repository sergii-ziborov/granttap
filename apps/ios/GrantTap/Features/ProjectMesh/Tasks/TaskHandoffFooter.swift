import SwiftUI

extension TaskHandoffSheet {
    /// What the move leaves behind, said next to the action and never instead of it.
    var transferWarning: String? {
        readinessChecks.first { $0.id == "workingTree" && $0.ready && $0.warning }?.detail
    }

    /// The action and its blocking reason remain visible while the form scrolls.
    var transferFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reason = handoffError ?? TaskHandoffReadiness.blockedReason(readinessChecks) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Theme.riskHigh)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("handoff.blockedReason")
            } else if let warning = transferWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(Theme.riskMed)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("handoff.warning")
            }
            if awaitingConfirmation && !submitting {
                Button(L("Check again"), action: checkHandoffConfirmation)
                    .accessibilityIdentifier("handoff.checkConfirmation")
            }
            Button(action: submitHandoff) {
                HStack(spacing: 10) {
                    if submitting || awaitingConfirmation { ProgressView() }
                    Label(L(submitting ? "Preparing transfer…" : "Prepare transfer"),
                          systemImage: "arrow.up.right.square")
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReady || sameAgentHere || userComment.count > 1_000 || submitting || awaitingConfirmation)
            .accessibilityIdentifier("handoff.submit")
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(Divider(), alignment: .top)
    }
}
