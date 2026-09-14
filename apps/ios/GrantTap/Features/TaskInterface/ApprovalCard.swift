import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ApprovalCard: View {
    let req: ApprovalRequest
    var isWaiting = false
    let onApprove: () -> Void
    let onDeny: () -> Void

    private var accent: Color { Theme.accent(for: req.agent) }

    var body: some View {
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

            // Card body is not tappable for dismiss — only Deny/Allow buttons decide.
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
            .contentShape(Rectangle())
            .onTapGesture { /* absorb body taps — never dismiss */ }

            if isWaiting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("Decision sent · waiting for the computer to confirm…"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                HStack(spacing: 9) {
                    Button(L("Deny"), action: onDeny)
                        .buttonStyle(OutlineButton(tint: Theme.riskHigh))
                    Button(L("Allow"), action: onApprove)
                        .buttonStyle(FilledButton(tint: accent, textColor: Theme.glyphInk(for: req.agent)))
                }
            }
        }
        .card()
    }
}

// MARK: - pairing
