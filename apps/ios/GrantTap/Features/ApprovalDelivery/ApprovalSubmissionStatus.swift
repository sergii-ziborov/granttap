import SwiftUI

struct ApprovalSubmissionStatus: View {
    let saved: Bool
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            if saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok) }
            else { ProgressView().controlSize(.small) }
            Text(message).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(saved ? "approval.relay-saved" : "approval.relay-saving")
    }
}
