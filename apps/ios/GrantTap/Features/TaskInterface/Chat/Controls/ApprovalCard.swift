import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ApprovalCard: View {
    let req: ApprovalRequest
    var isWaiting = false
    var isStoredOnRelay = false
    var waitingMessage: String? = nil
    let onApprove: () -> Void
    let onDeny: () -> Void
    @State private var showingDetails = false

    private var accent: Color { Theme.accent(for: req.agent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showingDetails = true } label: { requestSummary }
                .pointerButtonStyle()
                .accessibilityIdentifier("approval.details.\(req.requestId)")

            if isWaiting {
                ApprovalSubmissionStatus(saved: isStoredOnRelay,
                    message: waitingMessage ?? L("Saving decision on relay…"))
            } else {
                HStack(spacing: 9) {
                    #if targetEnvironment(macCatalyst)
                    Spacer(minLength: 0)
                    #endif
                    DecisionActionButton(title: L("Deny"), tint: Theme.riskHigh,
                                         filled: false, action: onDeny)
                    DecisionActionButton(title: req.kind == "question" ? L("Reply") : L("Allow"), tint: accent,
                                         textColor: Theme.glyphInk(for: req.agent), action: {
                        if req.kind == "question" { showingDetails = true } else { onApprove() }
                    })
                }
            }
        }
        .card()
        .sheet(isPresented: $showingDetails) {
            ApprovalDetailSheet(request: req)
        }
    }
    private var requestSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentGlyph(agent: req.agent, size: 28)
                Text(req.agent.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(accent)
                Spacer()
                Pill(text: Theme.riskLabel(req.risk), color: Theme.risk(req.risk))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(req.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let command = req.command, !command.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Text("$")
                            .font(Theme.mono(12.5, .bold))
                            .foregroundStyle(accent)
                        Text(command)
                            .font(Theme.mono(12.5))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(11)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }

                if let cwd = req.cwd {
                    Text(cwd)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

        }.frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

}

// MARK: - pairing
