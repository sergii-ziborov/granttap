import SwiftUI
import WatchKit

struct UnifiedTaskPage: View {
    @StateObject private var bridge = WatchBridge.shared

    private var sessions: [WatchSession] {
        bridge.state.sessions.sorted(by: sessionFeedOrder)
    }

    private var activeSessions: [WatchSession] {
        sessions.filter { $0.state == "working" || $0.state == "waiting" }
    }

    private var recentSessions: [WatchSession] {
        sessions.filter { $0.state != "working" && $0.state != "waiting" }
    }

    private var attention: [HumanAttentionItem] { bridge.state.humanAttention }

    private var connectionSummary: String {
        if bridge.state.connected {
            return bridge.state.machine.isEmpty
                ? L("Connected through iPhone")
                : String(format: L("Connected to %@ through iPhone"), bridge.state.machine)
        }
        return L("Latest synchronized data · computer offline")
    }

    var body: some View {
        List {
            needsYouSection
            taskSection(L("Active"), sessions: activeSessions)
            taskSection(L("Recent"), sessions: Array(recentSessions.prefix(3)))

            if sessions.isEmpty && attention.isEmpty {
                Section {
                    Text(L("No active tasks"))
                        .font(.system(size: pt(12), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                NavigationLink {
                    NewVoiceTaskView()
                } label: {
                    Label(L("New voice task"), systemImage: "mic.badge.plus")
                }
            }

            Section {
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label(bridge.state.connected ? L("Settings") : L("Connection issue"),
                          systemImage: bridge.state.connected ? "gearshape" : "exclamationmark.circle")
                }
            } footer: {
                Text(connectionSummary)
            }
        }
        .refreshable { bridge.requestRefresh() }
    }

    @ViewBuilder
    private var needsYouSection: some View {
        if !attention.isEmpty {
            Section(L("Needs You")) {
                ForEach(attention) { item in
                    NavigationLink {
                        ChatScreen(chat: WatchChat(from: item))
                    } label: {
                        HumanAttentionRow(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskSection(_ title: String, sessions: [WatchSession]) -> some View {
        if !sessions.isEmpty {
            Section(title) {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionActivityView(session: session)
                    } label: {
                        TaskPreviewRow(session: session)
                    }
                }
            }
        }
    }
}

func sessionFeedOrder(_ lhs: WatchSession, _ rhs: WatchSession) -> Bool {
    let left = sessionStateRank(lhs.state)
    let right = sessionStateRank(rhs.state)
    if left != right { return left < right }
    let leftActivity = lhs.lastActivityAt ?? 0
    let rightActivity = rhs.lastActivityAt ?? 0
    if leftActivity != rightActivity { return leftActivity > rightActivity }
    let leftAgent = AgentIdentity.normalize(lhs.agent)
    let rightAgent = AgentIdentity.normalize(rhs.agent)
    if leftAgent != rightAgent { return leftAgent < rightAgent }
    if lhs.title != rhs.title { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
    return lhs.id < rhs.id
}

func sessionStateRank(_ state: String) -> Int {
    switch state {
    case "working": return 0
    case "waiting": return 1
    default: return 2
    }
}
