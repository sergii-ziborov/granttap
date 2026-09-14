import SwiftUI

/// Where a figure on the Usage screen opens.
///
/// A number on its own is a claim about something that happened. Every row of
/// the overview is that claim, and touching it shows the thing itself: the
/// chats it counted, the calls it added up, what is still waiting, which
/// computers were awake.
enum UsageChatOrder {
    case activity
    case tokens
}

/// The chats a figure counted, newest first, or heaviest first when the
/// figure was tokens.
struct UsageChatsView: View {
    let title: String
    let sessions: [SessionInfo]
    var order: UsageChatOrder = .activity
    @ObservedObject private var model = AppModel.shared

    private var ordered: [SessionInfo] {
        switch order {
        case .activity: return sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
        case .tokens: return sessions.sorted { $0.tokensSession > $1.tokensSession }
        }
    }

    var body: some View {
        List {
            if ordered.isEmpty {
                CompatEmptyState(title: "No chats in this period", systemImage: "bubble.left.and.bubble.right")
            } else {
                ForEach(ordered) { session in
                    NavigationLink {
                        TaskChatView(session: session).environmentObject(model)
                    } label: {
                        row(session)
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    private func row(_ session: SessionInfo) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text([AgentIdentity.displayName(session.agent), session.computerId]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.tokens(session.tokensSession)).font(Theme.mono(13, .bold))
                // The context figure only earns a line when it is worth acting on.
                if let percent = contextPercent(session), percent >= 65 {
                    Text("\(percent)%")
                        .font(.caption2)
                        .foregroundStyle(percent >= 85 ? Theme.riskMed : Theme.muted)
                }
            }
        }
    }

    private func contextPercent(_ session: SessionInfo) -> Int? {
        guard let used = session.contextTokensUsed, let window = session.contextWindow,
              window > 0 else { return nil }
        return Int((Double(used) / Double(window) * 100).rounded())
    }
}

/// The calls a figure added up: every tool, or every skill, most used first,
/// each opening the calls it stands for.
struct UsageToolListView: View {
    let title: String
    let summaries: [OperationalToolSummary]
    var agent: String?

    private var ordered: [OperationalToolSummary] {
        // What failed is what a person came here to find, so it sorts first.
        summaries.sorted {
            ($0.failures > 0 ? 1 : 0, $0.count) > ($1.failures > 0 ? 1 : 0, $1.count)
        }
    }

    var body: some View {
        List {
            if ordered.isEmpty {
                CompatEmptyState(title: "Nothing ran in this period", systemImage: "wrench.and.screwdriver")
            } else {
                ForEach(ordered) { summary in
                    NavigationLink {
                        CapabilityUsageHistoryView(
                            kind: summary.kind, name: summary.name, agent: agent,
                            modelName: nil, outcome: nil
                        )
                    } label: {
                        UsageToolRow(summary: summary)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}
