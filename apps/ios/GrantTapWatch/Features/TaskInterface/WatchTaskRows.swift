import SwiftUI
import WatchKit

struct AgentConnectionNotice: View {
    let color: Color
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: pt(4)) {
            Label(title, systemImage: icon)
                .font(.system(size: pt(11), weight: .semibold))
                .foregroundStyle(color)
            Text(detail)
                .font(.system(size: pt(10)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DecisionRow: View {
    let approval: WatchApproval

    var body: some View {
        VStack(alignment: .leading, spacing: pt(3)) {
            Text(approval.title)
                .font(.system(size: pt(12), weight: .semibold))
                .lineLimit(2)
            HStack {
                Text(approval.agent.uppercased())
                    .font(.system(size: pt(8), weight: .heavy))
                    .foregroundStyle(accentFor(approval.agent))
                Spacer()
                if approval.waitingForMachine == true {
                    ProgressView()
                        .controlSize(.mini)
                    Text(L("Waiting for Mac…"))
                        .font(.system(size: pt(8), weight: .bold))
                        .foregroundStyle(.secondary)
                } else if !["safe", "low"].contains(approval.risk.lowercased()) {
                    Text(L(approval.risk))
                        .font(.system(size: pt(8), weight: .bold))
                        .foregroundStyle(approval.risk == "high" ? denyRed : .orange)
                }
            }
            if let command = approval.command, !command.isEmpty {
                Text(command)
                    .font(.system(size: pt(9), design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct HumanAttentionRow: View {
    let item: HumanAttentionItem

    private var color: Color {
        switch item.kind {
        case .approval: return accentFor(item.agent ?? "claude")
        case .question, .meshQuestion, .meshHandoff: return .orange
        case .deliveryFailure, .meshConflict, .meshFailure: return denyRed
        }
    }

    private var icon: String {
        switch item.action {
        case .decision, .meshDecision: return "checkmark.circle"
        case .reply, .meshReply: return "questionmark.bubble.fill"
        case .retryOnPhone, .openPhone: return "iphone"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: pt(3)) {
            Label(item.title, systemImage: icon)
                .font(.system(size: pt(12), weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(2)
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: pt(9)))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(attentionAgentName(item.agent).uppercased())
                .font(.system(size: pt(8), weight: .heavy))
                .foregroundStyle(accentFor(item.agent ?? "claude"))
        }
    }
}

struct TaskPreviewRow: View {
    let session: WatchSession

    var body: some View {
        HStack(spacing: pt(7)) {
            Text(agentGlyph(session.agent))
                .font(.system(size: pt(10), weight: .black, design: .monospaced))
                .foregroundStyle(glyphInkFor(session.agent))
                .frame(width: pt(19), height: pt(19))
                .background(accentFor(session.agent), in: RoundedRectangle(cornerRadius: pt(5)))
            VStack(alignment: .leading, spacing: pt(2)) {
                Text(session.title)
                    .font(.system(size: pt(15), weight: .bold))
                    .lineLimit(1)
                Text(stateWord(session.state))
                    .font(.system(size: pt(13), weight: .bold))
                    .foregroundStyle(session.state == "working" ? .green :
                                        (session.state == "waiting" ? .orange : .secondary))
            }
        }
        .padding(.vertical, pt(2))
    }
}

/// Honest first-launch state. The watch asks the paired iPhone for a current
/// snapshot and never substitutes sample tasks while that request is pending.
